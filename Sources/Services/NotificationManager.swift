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

    /// Notifications already shown (still in Notification Center).
    func delivered(_ done: @escaping ([UNNotification]) -> Void) {
        center.getDeliveredNotifications { list in
            DispatchQueue.main.async {
                let sorted = list.sorted { $0.date > $1.date }
                Router.shared.deliveredCount = sorted.count
                done(sorted)
            }
        }
    }

    func refreshDeliveredCount() { delivered { _ in } }

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        Router.shared.deliveredCount = 0
    }

    func status(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { s in DispatchQueue.main.async { done(s.authorizationStatus) } }
    }

    func reschedule(store: Store, settings: AppSettings) {
        let items = store.items
        let tasks = store.tasks
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

        for t in tasks where !t.isDone && t.remind {
            guard let fire = t.reminderMoment(reminderMinutes: settings.reminderMinutes), fire > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "✅ \(t.title)"
            c.body = t.hasTime ? L("حان موعد المهمة", "Task due now") : L("مهمة اليوم، فلا تنسَها", "Today's task — don't forget it")
            if !t.notes.isEmpty { c.body += "\n\(t.notes)" }
            c.sound = .default
            c.threadIdentifier = t.id.uuidString
            c.userInfo = ["task": t.id.uuidString]
            reminders.append((fire, UNNotificationRequest(identifier: "task|\(t.id.uuidString)", content: c, trigger: trigger(fire))))
        }

        var digests: [UNNotificationRequest] = []
        if settings.digestEnabled {
            for day in 0..<7 {
                guard let start = Fmt.greg.date(byAdding: .day, value: day, to: Fmt.greg.startOfDay(for: now)) else { continue }
                let fire = start.addingTimeInterval(TimeInterval(settings.digestMinutes * 60))
                guard fire > now, let r = digest(items: items, tasks: tasks, day: start, fire: fire) else { continue }
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

    private func digest(items: [Appointment], tasks: [TaskItem], day: Date, fire: Date) -> UNNotificationRequest? {
        let today = items.filter { Fmt.greg.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
        let todayTasks = tasks.filter { !$0.isDone && $0.isDue(on: day) }
        guard !today.isEmpty || !todayTasks.isEmpty else { return nil }
        let c = UNMutableNotificationContent()
        var parts: [String] = []
        if !today.isEmpty { parts.append(Fmt.appointments(today.count)) }
        if !todayTasks.isEmpty { parts.append(Fmt.tasks(todayTasks.count)) }
        c.title = L("☀️ صباح الخير، لديك اليوم ", "☀️ Good morning — today you have ") + parts.joined(separator: L(" و", " and "))
        var lines = today.prefix(4).map { $0.hasTime ? "• \($0.title) \(Fmt.timeText($0.date))" : "• \($0.title)" }
        lines += todayTasks.prefix(3).map { "✓ \($0.title)" }
        c.body = lines.joined(separator: "\n")
        c.sound = .default
        c.threadIdentifier = "digest"
        return UNNotificationRequest(identifier: "digest|\(Fmt.fileStamp.string(from: day))", content: c, trigger: trigger(fire))
    }

    func sendTest() {
        let c = UNMutableNotificationContent()
        c.title = L("📌 تجربة التنبيه", "📌 Test reminder")
        c.body = L("تم! التنبيهات تعمل 👍", "All set! Reminders work 👍")
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "test", content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshDeliveredCount() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = (info["id"] as? String).flatMap(UUID.init(uuidString:))
        let isTask = info["task"] != nil
        DispatchQueue.main.async {
            if let id = id, Store.shared.item(id) != nil {
                Router.shared.open(id)
            } else {
                Router.shared.go(isTask ? .tasks : .home)
            }
            NotificationManager.shared.refreshDeliveredCount()
            completionHandler()
        }
    }
}
