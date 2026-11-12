import Foundation
import UserNotifications

/// iOS keeps at most 64 pending notifications per app, so after every change the nearest
/// ones are rebuilt from scratch: each appointment's reminders plus a morning summary.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async {
                done?(ok)
                Store.shared.scheduleSideEffects()
            }
        }
    }

    func status(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { s in DispatchQueue.main.async { done(s.authorizationStatus) } }
    }

    func reschedule(items: [Appointment], settings: AppSettings) {
        let now = Date()
        var reminders: [(Date, UNNotificationRequest)] = []
        for a in items where !a.isPast(now: now) {
            let due = a.dueMoment(reminderMinutes: settings.reminderMinutes)
            for offset in Set(a.reminders) {
                let fire = due.addingTimeInterval(TimeInterval(-offset * 60))
                guard fire > now else { continue }
                reminders.append((fire, request(for: a, fire: fire, id: "\(a.id.uuidString)|\(offset)")))
            }
        }

        var digests: [UNNotificationRequest] = []
        if settings.digestEnabled {
            for day in 0..<7 {
                guard let start = Fmt.greg.date(byAdding: .day, value: day, to: Fmt.greg.startOfDay(for: now)) else { continue }
                let fire = start.addingTimeInterval(TimeInterval(settings.digestMinutes * 60))
                guard fire > now, let r = digest(items: items, day: start, fire: fire) else { continue }
                digests.append(r)
            }
        }

        reminders.sort { $0.0 < $1.0 }
        let room = max(0, 63 - digests.count)
        let final = reminders.prefix(room).map { $0.1 } + digests

        center.removeAllPendingNotificationRequests()
        for r in final { center.add(r) }
    }

    private func trigger(_ date: Date) -> UNCalendarNotificationTrigger {
        var comps = Fmt.greg.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        comps.calendar = Fmt.greg
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func request(for a: Appointment, fire: Date, id: String) -> UNNotificationRequest {
        let c = UNMutableNotificationContent()
        c.title = "📌 \(a.title)"
        var body = Fmt.countdown(to: a.date, hasTime: a.hasTime, now: fire)
        body += " — \(Fmt.dateText(a.date, hasTime: a.hasTime))"
        if !a.location.isEmpty { body += "\n📍 \(a.location)" }
        c.body = body
        c.sound = .default
        c.threadIdentifier = a.id.uuidString
        c.userInfo = ["id": a.id.uuidString]
        return UNNotificationRequest(identifier: id, content: c, trigger: trigger(fire))
    }

    private func digest(items: [Appointment], day: Date, fire: Date) -> UNNotificationRequest? {
        let today = items.filter { Fmt.greg.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        guard !today.isEmpty else { return nil }
        let c = UNMutableNotificationContent()
        c.title = "☀️ صباح الخير — عندك اليوم \(Fmt.count(today.count, one: "موعد واحد", two: "موعدين", few: "مواعيد", many: "موعد"))"
        var lines = today.prefix(4).map { $0.hasTime ? "• \($0.title) \(Fmt.timeText($0.date))" : "• \($0.title)" }
        if today.count > 4 { lines.append("• و\(today.count - 4) غيرها") }
        c.body = lines.joined(separator: "\n")
        c.sound = .default
        c.threadIdentifier = "digest"
        return UNNotificationRequest(identifier: "digest|\(Fmt.fileStamp.string(from: day))", content: c, trigger: trigger(fire))
    }

    func sendTest() {
        let c = UNMutableNotificationContent()
        c.title = "📌 تجربة التنبيه"
        c.body = "تمام! التنبيهات شغّالة 👍"
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "test", content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init(uuidString:))
        DispatchQueue.main.async {
            if let id = id, Store.shared.item(id) != nil {
                Router.shared.openID = AppointmentRef(id: id)
            } else {
                Router.shared.tab = 0
            }
            completionHandler()
        }
    }
}
