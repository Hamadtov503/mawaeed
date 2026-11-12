import SwiftUI
import UserNotifications

/// Opened from the bell: notifications already received, and the reminders still to come.
struct NotificationsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var settings: AppSettings
    @State private var delivered: [UNNotification] = []

    private struct Upcoming: Identifiable {
        let appointment: Appointment
        let offset: Int
        let fire: Date
        var id: String { "\(appointment.id.uuidString)|\(offset)" }
    }

    /// Every reminder still to fire, soonest first.
    private var upcoming: [Upcoming] {
        let now = Date()
        var out: [Upcoming] = []
        for a in store.upcoming(now: now) {
            let due = a.dueMoment(reminderMinutes: settings.reminderMinutes)
            for m in Set(a.reminders) {
                let fire = due.addingTimeInterval(TimeInterval(-m * 60))
                if fire > now { out.append(Upcoming(appointment: a, offset: m, fire: fire)) }
            }
        }
        return Array(out.sorted { $0.fire < $1.fire }.prefix(40))
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !delivered.isEmpty {
                        HStack {
                            SectionHeader(title: "وصلتك", detail: "\(delivered.count)")
                            Button("مسح الكل") {
                                NotificationManager.shared.clearDelivered()
                                withAnimation { delivered = [] }
                            }
                            .font(.app(.subheadline, .semibold))
                            .foregroundColor(Theme.burgundy)
                        }
                        VStack(spacing: 0) {
                            ForEach(delivered, id: \.request.identifier) { n in
                                deliveredRow(n)
                                if n.request.identifier != delivered.last?.request.identifier { Divider().padding(.vertical, 10) }
                            }
                        }
                        .card()
                    }

                    let list = upcoming
                    SectionHeader(title: "التنبيهات الجاية", detail: list.isEmpty ? nil : "\(list.count)")
                    if list.isEmpty {
                        EmptyState(icon: "bell.slash", title: "ما فيه تنبيهات جاية",
                                   message: "لما تضيف موعد، تنبيهاته تطلع هنا مع وقت وصول كل تنبيه.")
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(list) { u in
                                upcomingRow(u)
                                if u.id != list.last?.id { Divider().padding(.vertical, 10) }
                            }
                        }
                        .card()
                    }
                }
                .padding(18)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .onAppear { NotificationManager.shared.delivered { delivered = $0 } }
    }

    private func upcomingRow(_ u: Upcoming) -> some View {
        Button { router.open(u.appointment.id) } label: {
            HStack(spacing: 12) {
                Tile(icon: "bell.fill", color: Theme.burgundy, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(u.appointment.title).font(.app(.subheadline, .bold)).foregroundColor(Theme.ink).lineLimit(1)
                    Text("\(ReminderOption.label(u.offset, hasTime: u.appointment.hasTime)) · يوصلك \(Fmt.dateText(u.fire, hasTime: true))")
                        .font(.app(.caption)).foregroundColor(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(Fmt.countdown(to: u.fire, hasTime: true))
                    .font(.app(.caption, .bold)).foregroundColor(Theme.burgundy).lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deliveredRow(_ n: UNNotification) -> some View {
        let id = (n.request.content.userInfo["id"] as? String).flatMap(UUID.init(uuidString:))
        return Button {
            if let id = id, store.item(id) != nil { router.open(id) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Tile(icon: "bell.badge.fill", color: .brand, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.request.content.title).font(.app(.subheadline, .bold)).foregroundColor(Theme.ink).lineLimit(1)
                    Text(n.request.content.body).font(.app(.caption)).foregroundColor(Theme.muted).lineLimit(3)
                }
                Spacer(minLength: 6)
                Text(Fmt.countdown(to: n.date, hasTime: true))
                    .font(.app(.caption2)).foregroundColor(Theme.muted).lineLimit(1).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
