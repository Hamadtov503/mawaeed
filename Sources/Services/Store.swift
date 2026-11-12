import Foundation
import Combine
import UIKit
import UserNotifications

/// All appointments, saved as JSON on the phone. After each change it refreshes the
/// notifications, the iCloud calendar and the iCloud Drive sync.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var items: [Appointment] = [] {
        didSet {
            save()
            if !quiet { scheduleSideEffects() }
        }
    }

    /// Deleted ids with the deletion time, so deletions also reach the other phones.
    private(set) var deleted: [String: Date] = [:]
    private var quiet = false
    private let sideEffects = PassthroughSubject<Void, Never>()
    private var bag = Set<AnyCancellable>()

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let fileURL = Store.dir.appendingPathComponent("appointments.json")
    private let deletedURL = Store.dir.appendingPathComponent("deleted.json")
    /// Earlier versions kept everything (medicines, bills…) in items.json; only appointments are carried over.
    private let legacyURL = Store.dir.appendingPathComponent("items.json")

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

    private init() {
        if let data = try? Data(contentsOf: fileURL), let list = try? Self.decoder.decode([Appointment].self, from: data) {
            items = list
        } else if let data = try? Data(contentsOf: legacyURL), let list = try? Self.decoder.decode([Appointment].self, from: data) {
            items = list.filter { $0.isAppointment }.map { var a = $0; a.legacyCategory = nil; return a }
            save()
        }
        if let data = try? Data(contentsOf: deletedURL), let d = try? Self.decoder.decode([String: Date].self, from: data) {
            deleted = d
        }
        sideEffects
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.runSideEffects() }
            .store(in: &bag)
    }

    private func save() {
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func saveDeleted() {
        let cutoff = Date().addingTimeInterval(-180 * 86400)
        deleted = deleted.filter { $0.value > cutoff }
        if let data = try? Self.encoder.encode(deleted) { try? data.write(to: deletedURL, options: .atomic) }
    }

    // MARK: Queries

    func item(_ id: UUID) -> Appointment? { items.first { $0.id == id } }

    func upcoming(now: Date = Date()) -> [Appointment] {
        items.filter { !$0.isPast(now: now) }.sorted { $0.date < $1.date }
    }

    func past(now: Date = Date()) -> [Appointment] {
        items.filter { $0.isPast(now: now) }.sorted { $0.date > $1.date }
    }

    func on(day: Date) -> [Appointment] {
        items.filter { Fmt.greg.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    // MARK: Changes

    func upsert(_ a: Appointment) {
        var it = a
        if !it.hasTime { it.date = Fmt.greg.startOfDay(for: it.date) }
        it.updatedAt = Date()
        if let i = items.firstIndex(where: { $0.id == it.id }) { items[i] = it } else { items.append(it) }
    }

    func delete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        CalendarSync.shared.removeEvent(of: items[i])
        deleted[id.uuidString] = Date()
        saveDeleted()
        items.remove(at: i)
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Appointment? {
        guard var a = item(id) else { return nil }
        a.id = UUID()
        a.calendarEventID = nil
        a.createdAt = Date()
        upsert(a)
        return a
    }

    /// Restores a backup file: replace wipes current data, otherwise appointments are merged by id.
    func restore(_ list: [Appointment], replace: Bool) {
        let now = Date()
        var incoming = list.filter { $0.isAppointment }
        for i in incoming.indices {
            incoming[i].legacyCategory = nil
            incoming[i].calendarEventID = nil
            incoming[i].updatedAt = now
        }
        if replace {
            for a in items where !incoming.contains(where: { $0.id == a.id }) {
                CalendarSync.shared.removeEvent(of: a)
                deleted[a.id.uuidString] = now
            }
            saveDeleted()
            items = incoming
        } else {
            var merged = items
            for a in incoming {
                if let i = merged.firstIndex(where: { $0.id == a.id }) {
                    var copy = a
                    copy.calendarEventID = merged[i].calendarEventID
                    merged[i] = copy
                } else {
                    merged.append(a)
                }
            }
            items = merged
        }
    }

    // MARK: Sync merge

    /// Merges another phone's copy: per appointment the newest edit wins; deletions win over older edits.
    func merge(remote: [Appointment], remoteDeleted: [String: Date]) -> (items: [Appointment], deleted: [String: Date]) {
        var allDeleted = deleted
        for (k, v) in remoteDeleted { allDeleted[k] = max(v, allDeleted[k] ?? .distantPast) }

        var byID: [UUID: Appointment] = [:]
        for a in items { byID[a.id] = a }
        for r in remote where r.isAppointment {
            var copy = r
            copy.legacyCategory = nil
            if let l = byID[r.id] {
                if r.updatedAt > l.updatedAt && !r.sameContent(as: l) {
                    copy.calendarEventID = l.calendarEventID
                    byID[r.id] = copy
                }
            } else {
                copy.calendarEventID = nil
                byID[r.id] = copy
            }
        }
        for (k, when) in allDeleted {
            if let id = UUID(uuidString: k), let a = byID[id], a.updatedAt <= when {
                CalendarSync.shared.removeEvent(of: a)
                byID[id] = nil
            }
        }

        var merged = items.compactMap { byID[$0.id] }
        let known = Set(merged.map { $0.id })
        merged += remote.compactMap { byID[$0.id] }.filter { !known.contains($0.id) }

        if allDeleted != deleted {
            deleted = allDeleted
            saveDeleted()
        }
        if merged != items {
            quiet = true
            items = merged
            quiet = false
            NotificationManager.shared.reschedule(items: items, settings: AppSettings.shared)
            updateBadge()
        }
        return (merged, allDeleted)
    }

    // MARK: Side effects

    func scheduleSideEffects() { sideEffects.send() }

    func runSideEffects() {
        let settings = AppSettings.shared
        NotificationManager.shared.reschedule(items: items, settings: settings)
        updateBadge()

        let links = CalendarSync.shared.sync(items: items, enabled: settings.calendarSync)
        if !links.isEmpty {
            quiet = true
            var copy = items
            for (id, eventID) in links {
                if let i = copy.firstIndex(where: { $0.id == id }) { copy[i].calendarEventID = eventID }
            }
            items = copy
            quiet = false
        }
        SyncManager.shared.sync()
    }

    func refresh() {
        scheduleSideEffects()
        objectWillChange.send()
    }

    /// The badge on the app icon: today's appointments still to come.
    func updateBadge() {
        let now = Date()
        let n = items.filter { $0.status(now: now) == .today }.count
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(n)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = n
        }
    }
}
