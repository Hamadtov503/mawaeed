import Foundation
import Combine
import UIKit
import UserNotifications

/// Holds every item, saves them as JSON on the device, and after each change refreshes
/// notifications, the iCloud calendar / reminders and the iCloud Drive backup.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var items: [Item] = [] {
        didSet {
            save()
            if !applyingLinks { scheduleSideEffects() }
        }
    }

    private var applyingLinks = false
    private let sideEffects = PassthroughSubject<Void, Never>()
    private var bag = Set<AnyCancellable>()

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("items.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? Self.decoder.decode([Item].self, from: data) {
            items = decoded
        }
        sideEffects
            .debounce(for: .milliseconds(700), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.runSideEffects() }
            .store(in: &bag)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func save() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Queries

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    var activeSorted: [Item] {
        items.filter { !$0.isDone }.sorted { $0.date < $1.date }
    }

    var doneSorted: [Item] {
        items.filter { $0.isDone }.sorted { ($0.doneAt ?? $0.date) > ($1.doneAt ?? $1.date) }
    }

    func active(_ u: Urgency) -> [Item] {
        let now = Date()
        return activeSorted.filter { !$0.isMedicine && $0.urgency(now: now) == u }
    }

    struct Dose: Identifiable {
        let item: Item
        let minutes: Int
        let taken: Bool
        var id: String { "\(item.id.uuidString)|\(minutes)" }
    }

    /// Today's medicine doses in time order.
    func doses(on day: Date = Date()) -> [Dose] {
        let d = Fmt.greg.startOfDay(for: day)
        return items.filter { $0.isMedicine && $0.takesDoses(on: d) }
            .flatMap { it in it.doseTimes.map { Dose(item: it, minutes: $0, taken: it.isTaken(day: d, minutes: $0)) } }
            .sorted { $0.minutes < $1.minutes }
    }

    func toggleDose(_ id: UUID, day: Date, minutes: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let key = Item.doseKey(day: Fmt.greg.startOfDay(for: day), minutes: minutes)
        if let k = items[i].takenDoses.firstIndex(of: key) {
            items[i].takenDoses.remove(at: k)
        } else {
            items[i].takenDoses.append(key)
            // Keep the log small: the last ~90 days are enough.
            if items[i].takenDoses.count > 400 { items[i].takenDoses.removeFirst(items[i].takenDoses.count - 400) }
        }
    }

    func markDoseTaken(_ id: UUID, day: Date, minutes: Int) {
        guard let it = item(id), !it.isTaken(day: day, minutes: minutes) else { return }
        toggleDose(id, day: day, minutes: minutes)
    }

    var monthlyTotal: Double {
        items.filter { !$0.isDone }.compactMap { $0.monthlyCost }.reduce(0, +)
    }

    var badgeCount: Int {
        let now = Date()
        let pendingDoses = doses(on: now).filter { d in
            !d.taken && Fmt.greg.startOfDay(for: now).addingTimeInterval(TimeInterval(d.minutes * 60)) <= now
        }.count
        return items.filter { !$0.isDone && !$0.isMedicine && $0.urgency(now: now) <= .today }.count + pendingDoses
    }

    // MARK: Mutations

    func upsert(_ item: Item) {
        var it = item
        if !it.hasTime { it.date = Fmt.greg.startOfDay(for: it.date) }
        if let i = items.firstIndex(where: { $0.id == it.id }) { items[i] = it } else { items.append(it) }
    }

    /// Marks an item done. Recurring items roll forward to their next date instead (renewal).
    func complete(_ id: UUID, newDate: Date? = nil) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var it = items[i]
        it.snoozeUntil = nil
        if it.isMedicine {
            it.isDone = true
            it.doneAt = Date()
        } else if it.isRecurring {
            it.history.append(it.date)
            if it.hasInstallments && it.installmentsLeft == 0 {
                // Last installment paid.
                it.isDone = true
                it.doneAt = Date()
                items[i] = it
                return
            }
            var next = newDate ?? (it.hasInstallments ? it.advanced(it.date) : it.nextOccurrence())
            if !it.hasTime { next = Fmt.greg.startOfDay(for: next) }
            it.date = next
            it.isDone = false
            it.doneAt = nil
        } else {
            it.isDone = true
            it.doneAt = Date()
        }
        items[i] = it
    }

    func reopen(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isDone = false
        items[i].doneAt = nil
        if items[i].isMedicine, let e = items[i].endDate, e < Fmt.greg.startOfDay(for: Date()) {
            items[i].endDate = nil
        }
    }

    func snooze(_ id: UUID, until date: Date) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].snoozeUntil = date
    }

    func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let it = items[i]
        it.photos.forEach(PhotoStore.delete)
        CalendarSync.shared.removeLinks(of: it)
        items.remove(at: i)
    }

    func duplicate(_ id: UUID) -> Item? {
        guard var it = item(id) else { return nil }
        it.id = UUID()
        it.title += " (نسخة)"
        it.calendarEventID = nil
        it.reminderItemID = nil
        it.history = []
        it.takenDoses = []
        it.isDone = false
        it.doneAt = nil
        it.createdAt = Date()
        it.photos = it.photos.compactMap { name in
            PhotoStore.data(name).flatMap { PhotoStore.write($0) }
        }
        items.append(it)
        return it
    }

    /// Restores a backup: `replace` wipes current data, otherwise items are merged by id.
    func restore(_ backup: Backup, replace: Bool) {
        for (name, data) in backup.photos where PhotoStore.data(name) == nil {
            PhotoStore.write(data, name: name)
        }
        var incoming = backup.items
        for i in incoming.indices {
            incoming[i].calendarEventID = nil
            incoming[i].reminderItemID = nil
        }
        if replace {
            items.forEach { CalendarSync.shared.removeLinks(of: $0) }
            items = incoming
        } else {
            var merged = items
            for it in incoming {
                if let i = merged.firstIndex(where: { $0.id == it.id }) {
                    var copy = it
                    copy.calendarEventID = merged[i].calendarEventID
                    copy.reminderItemID = merged[i].reminderItemID
                    merged[i] = copy
                } else {
                    merged.append(it)
                }
            }
            items = merged
        }
    }

    // MARK: Side effects

    func scheduleSideEffects() { sideEffects.send() }

    func runSideEffects() {
        let settings = AppSettings.shared
        NotificationManager.shared.reschedule(items: items, settings: settings)
        updateBadge()

        let links = CalendarSync.shared.sync(items: items, calendar: settings.calendarSync, reminders: settings.remindersSync)
        if !links.isEmpty {
            applyingLinks = true
            var copy = items
            for link in links {
                guard let i = copy.firstIndex(where: { $0.id == link.id }) else { continue }
                copy[i].calendarEventID = link.eventID
                copy[i].reminderItemID = link.reminderID
            }
            items = copy
            applyingLinks = false
        }

        BackupManager.shared.autoBackup(items: items)
    }

    /// Called when the app comes to the foreground.
    func refresh() {
        // Tasks ticked off in Apple's Reminders app (on any device) are completed here too.
        if AppSettings.shared.remindersSync {
            for id in CalendarSync.shared.completedInReminders(items: items) { complete(id) }
        }
        // Clear snoozes that have already fired.
        let now = Date()
        if items.contains(where: { ($0.snoozeUntil ?? .distantFuture) < now }) {
            items = items.map { var it = $0; if let s = it.snoozeUntil, s < now { it.snoozeUntil = nil }; return it }
        }
        scheduleSideEffects()
        objectWillChange.send()
    }

    func updateBadge() {
        let n = badgeCount
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(n)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = n
        }
    }
}
