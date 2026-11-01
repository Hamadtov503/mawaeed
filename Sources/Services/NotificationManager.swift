import Foundation
import UserNotifications

/// iOS keeps at most 64 pending local notifications per app, so after every change
/// the nearest ones are rebuilt from scratch.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    static let itemCategory = "ITEM"
    static let doneAction = "DONE"
    static let snoozeHourAction = "SNOOZE_HOUR"
    static let snoozeTomorrowAction = "SNOOZE_TOMORROW"

    func setUp() {
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.doneAction, title: "✅ تم", options: [])
        let hour = UNNotificationAction(identifier: Self.snoozeHourAction, title: "⏰ ذكّرني بعد ساعة", options: [])
        let tomorrow = UNNotificationAction(identifier: Self.snoozeTomorrowAction, title: "📅 ذكّرني بكرة", options: [])
        let cat = UNNotificationCategory(identifier: Self.itemCategory, actions: [done, hour, tomorrow],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
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

    // MARK: Scheduling

    private struct Pending {
        let date: Date
        let request: UNNotificationRequest
    }

    func reschedule(items: [Item], settings: AppSettings) {
        let now = Date()
        var list: [Pending] = []

        for item in items where !item.isDone {
            for offset in Set(item.reminders) {
                let fire = item.fireDate(offset: offset, reminderMinutes: settings.reminderMinutes)
                guard fire > now else { continue }
                list.append(Pending(date: fire, request: request(for: item, at: fire, id: "\(item.id.uuidString)|\(offset)")))
            }
            if let s = item.snoozeUntil, s > now {
                list.append(Pending(date: s, request: request(for: item, at: s, id: "\(item.id.uuidString)|snooze")))
            }
            // Gentle daily nudge while something stays overdue (for the next 3 days).
            let due = item.dueMoment(reminderMinutes: settings.reminderMinutes)
            if settings.overdueNag, due < now, item.category != .appointment {
                for day in 0..<3 {
                    let base = Fmt.greg.date(byAdding: .day, value: day, to: Fmt.greg.startOfDay(for: now)) ?? now
                    let fire = base.addingTimeInterval(19 * 60 * 60)   // 7 PM
                    guard fire > now, fire > due else { continue }
                    let content = baseContent(for: item)
                    content.title = "⚠️ \(item.title)"
                    content.body = "\(Fmt.countdown(to: item.date, hasTime: item.hasTime, now: fire)) — خلّصه وعلّمه منجز"
                    list.append(Pending(date: fire, request: UNNotificationRequest(
                        identifier: "\(item.id.uuidString)|nag\(day)", content: content, trigger: trigger(fire))))
                }
            }
        }

        var digests: [Pending] = []
        if settings.digestEnabled {
            for day in 0..<7 {
                guard let base = Fmt.greg.date(byAdding: .day, value: day, to: Fmt.greg.startOfDay(for: now)) else { continue }
                let fire = base.addingTimeInterval(TimeInterval(settings.digestMinutes * 60))
                guard fire > now, let req = digest(items: items, dayStart: base, fire: fire) else { continue }
                digests.append(Pending(date: fire, request: req))
            }
        }

        list.sort { $0.date < $1.date }
        let room = max(0, 63 - digests.count)
        let final = Array(list.prefix(room)) + digests

        center.removeAllPendingNotificationRequests()
        for p in final { center.add(p.request) }
    }

    private func trigger(_ date: Date) -> UNCalendarNotificationTrigger {
        var comps = Fmt.greg.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        comps.calendar = Fmt.greg
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func baseContent(for item: Item) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.sound = .default
        c.categoryIdentifier = Self.itemCategory
        c.threadIdentifier = item.id.uuidString
        c.userInfo = ["itemID": item.id.uuidString]
        return c
    }

    private func request(for item: Item, at fire: Date, id: String) -> UNNotificationRequest {
        let c = baseContent(for: item)
        c.title = "📌 \(item.title)"
        var body = Fmt.countdown(to: item.date, hasTime: item.hasTime, now: fire)
        body += " — \(Fmt.dateText(item.date, hasTime: item.hasTime))"
        if !item.location.isEmpty { body += "\n📍 \(item.location)" }
        if let a = item.amount { body += "\n💰 \(Fmt.money(a))" }
        c.body = body
        c.subtitle = item.category.title
        return UNNotificationRequest(identifier: id, content: c, trigger: trigger(fire))
    }

    /// A morning summary: what's due today, plus anything overdue.
    private func digest(items: [Item], dayStart: Date, fire: Date) -> UNNotificationRequest? {
        let cal = Fmt.greg
        let open = items.filter { !$0.isDone }
        let today = open.filter { cal.isDate($0.date, inSameDayAs: dayStart) }.sorted { $0.date < $1.date }
        let overdue = open.filter { cal.startOfDay(for: $0.date) < dayStart }
        let soon = open.filter {
            let d = cal.dateComponents([.day], from: dayStart, to: cal.startOfDay(for: $0.date)).day ?? 99
            return d >= 1 && d <= 3
        }
        guard !today.isEmpty || !overdue.isEmpty else { return nil }

        let c = UNMutableNotificationContent()
        c.sound = .default
        c.title = today.isEmpty ? "☀️ صباح الخير" : "☀️ صباح الخير — عندك اليوم \(Fmt.count(today.count, one: "شي واحد", two: "شيئين", few: "أشياء", many: "شي"))"
        var lines: [String] = today.prefix(4).map { $0.hasTime ? "• \($0.title) \(Fmt.timeText($0.date))" : "• \($0.title)" }
        if today.count > 4 { lines.append("• و\(today.count - 4) غيرها") }
        if !overdue.isEmpty { lines.append("⚠️ متأخر: \(overdue.count)") }
        if !soon.isEmpty { lines.append("🔜 خلال 3 أيام: \(soon.count)") }
        c.body = lines.joined(separator: "\n")
        c.threadIdentifier = "digest"
        return UNNotificationRequest(identifier: "digest|\(Fmt.fileStamp.string(from: dayStart))", content: c, trigger: trigger(fire))
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
        let info = response.notification.request.content.userInfo
        let id = (info["itemID"] as? String).flatMap(UUID.init(uuidString:))
        DispatchQueue.main.async {
            let store = Store.shared
            if let id = id {
                switch response.actionIdentifier {
                case Self.doneAction:
                    store.complete(id)
                case Self.snoozeHourAction:
                    store.snooze(id, until: Date().addingTimeInterval(3600))
                case Self.snoozeTomorrowAction:
                    let tomorrow = Fmt.greg.date(byAdding: .day, value: 1, to: Fmt.greg.startOfDay(for: Date())) ?? Date()
                    store.snooze(id, until: tomorrow.addingTimeInterval(TimeInterval(AppSettings.shared.reminderMinutes * 60)))
                default:
                    Router.shared.tab = 0
                    Router.shared.openItem = ItemRef(id: id)
                }
            }
            if response.actionIdentifier != UNNotificationDefaultActionIdentifier {
                store.runSideEffects()
            }
            completionHandler()
        }
    }
}
