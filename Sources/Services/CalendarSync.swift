import Foundation
import EventKit
import UIKit

/// Mirrors items into a «مواعيدي» calendar and tasks into a «مواعيدي» Reminders list,
/// created in the iCloud account when there is one — so they show on every Apple device.
final class CalendarSync {
    static let shared = CalendarSync()
    let store = EKEventStore()
    static let listName = "مواعيدي"

    struct Link {
        let id: UUID
        let eventID: String?
        let reminderID: String?
    }

    /// Signatures of what was last written this session, to skip unchanged items.
    private var eventSig: [UUID: Int] = [:]
    private var reminderSig: [UUID: Int] = [:]

    // MARK: Access

    func hasAccess(_ type: EKEntityType) -> Bool {
        let s = EKEventStore.authorizationStatus(for: type)
        if #available(iOS 17.0, *) {
            return s == .fullAccess || s.rawValue == 3
        }
        return s.rawValue == 3   // .authorized
    }

    func requestAccess(_ type: EKEntityType, _ done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(iOS 17.0, *) {
            if type == .event { store.requestFullAccessToEvents(completion: finish) }
            else { store.requestFullAccessToReminders(completion: finish) }
        } else {
            store.requestAccess(to: type, completion: finish)
        }
    }

    // MARK: Calendars

    private func appCalendar(_ type: EKEntityType) -> EKCalendar? {
        let key = type == .event ? "appCalendarID" : "appReminderListID"
        if let id = UserDefaults.standard.string(forKey: key), let cal = store.calendar(withIdentifier: id) {
            return cal
        }
        if let existing = store.calendars(for: type).first(where: { $0.title == Self.listName && $0.allowsContentModifications }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: key)
            return existing
        }
        let cal = EKCalendar(for: type, eventStore: store)
        cal.title = Self.listName
        cal.cgColor = UIColor(red: 0.05, green: 0.49, blue: 0.48, alpha: 1).cgColor
        let iCloud = store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        let fallback = type == .event ? store.defaultCalendarForNewEvents?.source : store.defaultCalendarForNewReminders()?.source
        guard let source = iCloud ?? fallback ?? store.sources.first(where: { $0.sourceType == .local }) else { return nil }
        cal.source = source
        do {
            try store.saveCalendar(cal, commit: true)
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: key)
            return cal
        } catch {
            // iCloud may refuse a new list in rare setups; fall back to the default calendar.
            return type == .event ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()
        }
    }

    var calendarAccountName: String? {
        guard hasAccess(.event) else { return nil }
        return appCalendar(.event)?.source.title
    }

    // MARK: Sync

    func sync(items: [Item], calendar: Bool, reminders: Bool) -> [Link] {
        var links: [UUID: (String?, String?)] = [:]
        func link(_ it: Item) -> (String?, String?) { links[it.id] ?? (it.calendarEventID, it.reminderItemID) }

        if hasAccess(.event) {
            let cal = calendar ? appCalendar(.event) : nil
            for it in items {
                if calendar, let cal = cal, !it.isMedicine {
                    if let newID = upsertEvent(it, in: cal), newID != it.calendarEventID {
                        links[it.id] = (newID, link(it).1)
                    }
                } else if let eid = it.calendarEventID {
                    if let ev = store.event(withIdentifier: eid) { try? store.remove(ev, span: .thisEvent, commit: false) }
                    links[it.id] = (nil, link(it).1)
                    eventSig[it.id] = nil
                }
            }
            try? store.commit()
        }

        if hasAccess(.reminder) {
            let list = reminders ? appCalendar(.reminder) : nil
            for it in items {
                if reminders, let list = list, it.category == .task {
                    if let newID = upsertReminder(it, in: list), newID != it.reminderItemID {
                        links[it.id] = (link(it).0, newID)
                    }
                } else if let rid = it.reminderItemID {
                    if let r = store.calendarItem(withIdentifier: rid) as? EKReminder { try? store.remove(r, commit: false) }
                    links[it.id] = (link(it).0, nil)
                    reminderSig[it.id] = nil
                }
            }
            try? store.commit()
        }

        return links.map { Link(id: $0.key, eventID: $0.value.0, reminderID: $0.value.1) }
    }

    private func signature(_ it: Item) -> Int {
        var h = Hasher()
        h.combine(it.title); h.combine(it.date); h.combine(it.hasTime); h.combine(it.notes)
        h.combine(it.location); h.combine(it.isDone); h.combine(it.category.rawValue)
        return h.finalize()
    }

    private func upsertEvent(_ it: Item, in cal: EKCalendar) -> String? {
        let sig = signature(it)
        let existing = it.calendarEventID.flatMap { store.event(withIdentifier: $0) }
        if existing != nil, eventSig[it.id] == sig { return it.calendarEventID }

        let ev = existing ?? EKEvent(eventStore: store)
        if existing == nil { ev.calendar = cal }
        ev.title = it.isDone ? "✓ \(it.title)" : it.title
        ev.isAllDay = !it.hasTime
        ev.startDate = it.date
        ev.endDate = it.hasTime ? it.date.addingTimeInterval(3600) : it.date
        ev.location = it.location.isEmpty ? nil : it.location
        ev.notes = [it.category.title, it.notes].filter { !$0.isEmpty }.joined(separator: "\n")
        do {
            try store.save(ev, span: .thisEvent, commit: true)
            eventSig[it.id] = sig
            return ev.eventIdentifier
        } catch {
            return it.calendarEventID
        }
    }

    private func upsertReminder(_ it: Item, in list: EKCalendar) -> String? {
        let sig = signature(it)
        let existing = it.reminderItemID.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
        if existing != nil, reminderSig[it.id] == sig { return it.reminderItemID }

        let r = existing ?? EKReminder(eventStore: store)
        if existing == nil { r.calendar = list }
        r.title = it.title
        r.notes = it.notes.isEmpty ? nil : it.notes
        var comps = Fmt.greg.dateComponents(it.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: it.date)
        comps.calendar = Fmt.greg
        r.dueDateComponents = comps
        r.isCompleted = it.isDone
        do {
            try store.save(r, commit: true)
            reminderSig[it.id] = sig
            return r.calendarItemIdentifier
        } catch {
            return it.reminderItemID
        }
    }

    /// Tasks the user ticked off in Apple's Reminders app.
    func completedInReminders(items: [Item]) -> [UUID] {
        guard hasAccess(.reminder) else { return [] }
        store.refreshSourcesIfNecessary()
        return items.compactMap { it in
            guard !it.isDone, let rid = it.reminderItemID,
                  let r = store.calendarItem(withIdentifier: rid) as? EKReminder, r.isCompleted else { return nil }
            reminderSig[it.id] = nil
            return it.id
        }
    }

    func removeLinks(of it: Item) {
        if let eid = it.calendarEventID, hasAccess(.event), let ev = store.event(withIdentifier: eid) {
            try? store.remove(ev, span: .thisEvent, commit: true)
        }
        if let rid = it.reminderItemID, hasAccess(.reminder), let r = store.calendarItem(withIdentifier: rid) as? EKReminder {
            try? store.remove(r, commit: true)
        }
        eventSig[it.id] = nil
        reminderSig[it.id] = nil
    }
}
