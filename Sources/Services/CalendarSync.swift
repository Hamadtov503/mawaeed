import Foundation
import EventKit
import UIKit

/// Mirrors appointments into a «مواعيدي» calendar in the iCloud account, so they show in the
/// Calendar app on the iPhone, iPad, Mac and Watch.
final class CalendarSync {
    static let shared = CalendarSync()
    let store = EKEventStore()
    static let calendarName = "مواعيدي"

    /// What was last written this session, to skip unchanged appointments.
    private var written: [UUID: Int] = [:]

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event).rawValue == 3   // .authorized / .fullAccess
    }

    func requestAccess(_ done: @escaping (Bool) -> Void) {
        let finish: (Bool, Error?) -> Void = { ok, _ in DispatchQueue.main.async { done(ok) } }
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents(completion: finish)
        } else {
            store.requestAccess(to: .event, completion: finish)
        }
    }

    private func appCalendar() -> EKCalendar? {
        let key = "appCalendarID"
        if let id = UserDefaults.standard.string(forKey: key), let cal = store.calendar(withIdentifier: id) { return cal }
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarName && $0.allowsContentModifications }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: key)
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = Self.calendarName
        cal.cgColor = UIColor(red: 0.05, green: 0.49, blue: 0.48, alpha: 1).cgColor
        let iCloud = store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        guard let source = iCloud ?? store.defaultCalendarForNewEvents?.source else { return nil }
        cal.source = source
        do {
            try store.saveCalendar(cal, commit: true)
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: key)
            return cal
        } catch {
            return store.defaultCalendarForNewEvents
        }
    }

    var accountName: String? { hasAccess ? appCalendar()?.source.title : nil }

    /// Returns new event ids to store (id → event id, or nil when an event was removed).
    func sync(items: [Appointment], enabled: Bool) -> [UUID: String?] {
        guard hasAccess else { return [:] }
        var changes: [UUID: String?] = [:]
        let cal = enabled ? appCalendar() : nil
        for a in items {
            if let cal = cal {
                let id = upsert(a, in: cal)
                if id != a.calendarEventID { changes[a.id] = .some(id) }
            } else if let eid = a.calendarEventID {
                if let ev = store.event(withIdentifier: eid) { try? store.remove(ev, span: .thisEvent, commit: true) }
                written[a.id] = nil
                changes[a.id] = .some(nil)
            }
        }
        return changes
    }

    private func signature(_ a: Appointment) -> Int {
        var h = Hasher()
        h.combine(a.title); h.combine(a.date); h.combine(a.hasTime); h.combine(a.location); h.combine(a.notes)
        return h.finalize()
    }

    private func upsert(_ a: Appointment, in cal: EKCalendar) -> String? {
        let sig = signature(a)
        let existing = a.calendarEventID.flatMap { store.event(withIdentifier: $0) }
        if existing != nil, written[a.id] == sig { return a.calendarEventID }
        // Another phone on the same iCloud account may already have added this appointment.
        let ev = existing ?? findEvent(for: a, in: cal) ?? EKEvent(eventStore: store)
        if ev.calendar == nil { ev.calendar = cal }
        ev.title = a.title
        ev.isAllDay = !a.hasTime
        ev.startDate = a.date
        ev.endDate = a.hasTime ? a.date.addingTimeInterval(3600) : a.date
        ev.location = a.location.isEmpty ? nil : a.location
        ev.notes = a.notes.isEmpty ? nil : a.notes
        ev.url = URL(string: "mawaeed://appointment/\(a.id.uuidString)")
        do {
            try store.save(ev, span: .thisEvent, commit: true)
            written[a.id] = sig
            return ev.eventIdentifier
        } catch {
            return a.calendarEventID
        }
    }

    private func findEvent(for a: Appointment, in cal: EKCalendar) -> EKEvent? {
        let url = URL(string: "mawaeed://appointment/\(a.id.uuidString)")
        let start = a.date.addingTimeInterval(-40 * 86400), end = a.date.addingTimeInterval(40 * 86400)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
        return store.events(matching: pred).first { $0.url == url }
    }

    func removeEvent(of a: Appointment) {
        guard hasAccess else { return }
        if let eid = a.calendarEventID, let ev = store.event(withIdentifier: eid) {
            try? store.remove(ev, span: .thisEvent, commit: true)
        }
        written[a.id] = nil
    }
}
