import SwiftUI

/// The home page: a greeting, the Hijri/Gregorian calendar, and the selected day's
/// appointments and tasks. Adding happens from the appointments and tasks pages.
struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var settings: AppSettings
    @State private var day = Date()

    var body: some View {
        let appointments = store.on(day: day)
        let isToday = Fmt.greg.isDateInToday(day)
        let dayTasks = store.tasks(on: day).filter { !$0.isDone || isToday }
        let lateTasks = isToday ? store.openTasks.filter { $0.isOverdue() && !$0.isDue(on: day) } : []
        let undated = isToday ? store.openTasks.filter { $0.due == nil } : []
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                CalendarCard(selection: $day)

                SectionHeader(title: isToday ? L("اليوم", "Today") : Fmt.dayTitle(day), detail: Fmt.hijriText(day))
                    // Record where this line sits (unscrolled) once; the menu tab stays at that height
                    // on every page and does not move with scrolling.
                    .background(GeometryReader { g in
                        let y = g.frame(in: .global).midY
                        Color.clear
                            .onAppear { if router.dayLineY == 0 && y > 150 { router.dayLineY = y } }
                            .onChange(of: y) { v in if router.dayLineY == 0 && v > 150 { router.dayLineY = v } }
                    })

                let allTasks = lateTasks + dayTasks + undated

                label(L("مواعيدي", "Appointments"), "calendar", appointments.count)
                if appointments.isEmpty {
                    emptyRow(L("ليس لديك مواعيد", "No appointments"))
                } else {
                    ForEach(appointments) { AppointmentCard(item: $0) }
                }

                label(L("مهامي", "Tasks"), "checklist", allTasks.filter { !$0.isDone }.count)
                if allTasks.isEmpty {
                    emptyRow(L("ليس لديك مهام", "No tasks"))
                } else {
                    TaskList(tasks: allTasks)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .animation(Router.soft, value: day)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Re-evaluated every minute, so the greeting follows the time of day.
            TimelineView(.periodic(from: Date(), by: 60)) { ctx in
                greetingView(now: ctx.date)
            }
            Spacer(minLength: 8)
            Button { router.present(notifications: true) } label: {
                Image(systemName: router.deliveredCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if router.deliveredCount > 0 {
                            Text("\(router.deliveredCount)")
                                .font(.app(.caption2, .bold)).foregroundColor(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Theme.burgundy))
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("التنبيهات", "Notifications"))
            Button { router.present(notifications: false) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.burgundy))
                    .shadow(color: Theme.burgundy.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("الإعدادات", "Settings"))
        }
    }

    /// "صبآح الخير ❄︎ حمد" — the season's icon sits between the greeting and the name.
    private func greetingView(now: Date) -> some View {
        let h = Fmt.greg.component(.hour, from: now)
        let greeting = h < 12 ? L("صبآح الخير", "Good morning") : L("مسآء الخير", "Good evening")
        let name = settings.userName.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 7) {
            Text(greeting)
            SeasonIcon(date: now)
            if !name.isEmpty { Text(name).lineLimit(1) }
        }
        .font(.app(size: 21, .bold))
        .foregroundColor(Theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.app(.subheadline)).foregroundColor(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .card(padding: 0, radius: 18)
    }

    private func label(_ title: String, _ icon: String, _ count: Int, color: Color = Theme.navy) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
            Text(title).font(.app(.subheadline, .bold)).foregroundColor(color)
            if count > 0 {
                Text("\(count)").font(.app(.caption, .bold)).foregroundColor(color)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(color.opacity(0.1)))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

func openMaps(_ place: String) {
    let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
    if let url = URL(string: place.hasPrefix("http") ? place : "http://maps.apple.com/?q=\(q)") {
        UIApplication.shared.open(url)
    }
}

/// Winter (November–April): a snowflake. Summer (May–October): an air conditioner.
struct SeasonIcon: View {
    let date: Date

    private var isSummer: Bool { (5...10).contains(Fmt.greg.component(.month, from: date)) }

    var body: some View {
        Group {
            if isSummer {
                if #available(iOS 16.0, *) {
                    Image(systemName: "air.conditioner.horizontal.fill")
                } else {
                    Image(systemName: "wind")
                }
            } else {
                Image(systemName: "snowflake")
            }
        }
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(isSummer ? Theme.navy : Color.white)
        // A faint outline so white snow still reads on the beige background.
        .shadow(color: isSummer ? .clear : Color(red: 0.25, green: 0.38, blue: 0.55).opacity(0.55), radius: 0.8)
        .shadow(color: isSummer ? .clear : Color(red: 0.25, green: 0.38, blue: 0.55).opacity(0.35), radius: 2.5)
        .accessibilityLabel(isSummer ? L("صيف", "Summer") : L("شتاء", "Winter"))
    }
}
