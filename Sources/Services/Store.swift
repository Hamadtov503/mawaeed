import Foundation
import Combine
import UIKit
import UserNotifications

/// Appointments and tasks, saved as JSON on the phone. After each change it refreshes the
/// notifications, the iCloud calendar and the iCloud Drive sync.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var items: [Appointment] = [] {
        didSet {
            save()
            if !quiet { scheduleSideEffects() }
        }
    }

    @Published var tasks: [TaskItem] = [] {
        didSet {
            saveTasks()
            if !quiet { scheduleSideEffects() }
        }
    }

    /// Deleted ids (appointments and tasks) with the deletion time, so deletions reach the other phones.
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
    private let tasksURL = Store.dir.appendingPathComponent("tasks.json")
    private let deletedURL = Store.dir.appendingPathComponent("deleted.json")
    /// Earlier versions kept everything in items.json; only appointments are carried over.
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
        if let data = try? Data(contentsOf: tasksURL), let list = try? Self.decoder.decode([TaskItem].self, from: data) {
            tasks = list
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

    private func saveTasks() {
        guard let data = try? Self.encoder.encode(tasks) else { return }
        try? data.write(to: tasksURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func saveDeleted() {
        let cutoff = Date().addingTimeInterval(-180 * 86400)
        deleted = deleted.filter { $0.value > cutoff }
        if let data = try? Self.encoder.encode(deleted) { try? data.write(to: deletedURL, options: .atomic) }
    }

    // MARK: Appointment queries

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

    // MARK: Task queries

    func task(_ id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    var openTasks: [TaskItem] {
        tasks.filter { !$0.isDone }.sorted {
            switch ($0.due, $1.due) {
            case let (a?, b?): return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.createdAt < $1.createdAt
            }
        }
    }

    var doneTasks: [TaskItem] {
        tasks.filter { $0.isDone }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    func tasks(on day: Date) -> [TaskItem] {
        tasks.filter { $0.isDue(on: day) }.sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }

    /// Whether anything (appointment or open task) falls on this day — for the calendar dots.
    func hasAnything(on day: Date) -> Bool {
        items.contains { Fmt.greg.isDate($0.date, inSameDayAs: day) }
            || tasks.contains { !$0.isDone && $0.isDue(on: day) }
    }

    // MARK: Appointment changes

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

    // MARK: Task changes

    func upsertTask(_ t: TaskItem) {
        var it = t
        if let d = it.due, !it.hasTime { it.due = Fmt.greg.startOfDay(for: d) }
        it.updatedAt = Date()
        if let i = tasks.firstIndex(where: { $0.id == it.id }) { tasks[i] = it } else { tasks.append(it) }
    }

    func toggleTask(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isDone.toggle()
        tasks[i].doneAt = tasks[i].isDone ? Date() : nil
        tasks[i].updatedAt = Date()
    }

    func deleteTask(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        deleted[id.uuidString] = Date()
        saveDeleted()
        tasks.remove(at: i)
    }

    // MARK: Backup

    /// Restores a backup file: replace wipes current data, otherwise it is merged by id.
    func restore(_ list: [Appointment], tasks incomingTasks: [TaskItem], replace: Bool) {
        let now = Date()
        var incoming = list.filter { $0.isAppointment }
        for i in incoming.indices {
            incoming[i].legacyCategory = nil
            incoming[i].calendarEventID = nil
            incoming[i].updatedAt = now
        }
        let newTasks = incomingTasks.map { t -> TaskItem in var c = t; c.updatedAt = now; return c }
        if replace {
            for a in items where !incoming.contains(where: { $0.id == a.id }) {
                CalendarSync.shared.removeEvent(of: a)
                deleted[a.id.uuidString] = now
            }
            for t in tasks where !newTasks.contains(where: { $0.id == t.id }) { deleted[t.id.uuidString] = now }
            saveDeleted()
            items = incoming
            tasks = newTasks
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
            var mergedTasks = tasks
            for t in newTasks {
                if let i = mergedTasks.firstIndex(where: { $0.id == t.id }) { mergedTasks[i] = t } else { mergedTasks.append(t) }
            }
            tasks = mergedTasks
        }
    }

    // MARK: Sync merge

    struct Merged {
        let items: [Appointment]
        let tasks: [TaskItem]
        let deleted: [String: Date]
    }

    /// Merges another phone's copy: per item the newest edit wins; deletions win over older edits.
    func merge(remote: [Appointment], remoteTasks: [TaskItem], remoteDeleted: [String: Date]) -> Merged {
        var allDeleted = deleted
        for (k, v) in remoteDeleted { allDeleted[k] = max(v, allDeleted[k] ?? .distantPast) }

        // Appointments
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
        // Tasks
        var taskByID: [UUID: TaskItem] = [:]
        for t in tasks { taskByID[t.id] = t }
        for r in remoteTasks {
            if let l = taskByID[r.id] {
                if r.updatedAt > l.updatedAt && !r.sameContent(as: l) { taskByID[r.id] = r }
            } else {
                taskByID[r.id] = r
            }
        }
        for (k, when) in allDeleted {
            guard let id = UUID(uuidString: k) else { continue }
            if let a = byID[id], a.updatedAt <= when {
                CalendarSync.shared.removeEvent(of: a)
                byID[id] = nil
            }
            if let t = taskByID[id], t.updatedAt <= when { taskByID[id] = nil }
        }

        var merged = items.compactMap { byID[$0.id] }
        let known = Set(merged.map { $0.id })
        merged += remote.compactMap { byID[$0.id] }.filter { !known.contains($0.id) }

        var mergedTasks = tasks.compactMap { taskByID[$0.id] }
        let knownTasks = Set(mergedTasks.map { $0.id })
        mergedTasks += remoteTasks.compactMap { taskByID[$0.id] }.filter { !knownTasks.contains($0.id) }

        if allDeleted != deleted {
            deleted = allDeleted
            saveDeleted()
        }
        if merged != items || mergedTasks != tasks {
            quiet = true
            if merged != items { items = merged }
            if mergedTasks != tasks { tasks = mergedTasks }
            quiet = false
            NotificationManager.shared.reschedule(store: self, settings: AppSettings.shared)
            updateBadge()
        }
        return Merged(items: merged, tasks: mergedTasks, deleted: allDeleted)
    }

    // MARK: Side effects

    func scheduleSideEffects() { sideEffects.send() }

    func runSideEffects() {
        let settings = AppSettings.shared
        NotificationManager.shared.reschedule(store: self, settings: settings)
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
        NotificationManager.shared.refreshDeliveredCount()
        objectWillChange.send()
    }

    /// The badge on the app icon: today's appointments still to come plus tasks due today or late.
    func updateBadge() {
        let now = Date()
        let n = items.filter { $0.status(now: now) == .today }.count
            + tasks.filter { !$0.isDone && ($0.isDue(on: now) || $0.isOverdue(now: now)) }.count
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(n)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = n
        }
    }
}
