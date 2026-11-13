import SwiftUI

/// The home page: a greeting, the Hijri/Gregorian calendar, and the selected day's
/// appointments and tasks. Adding happens from the appointments and tasks pages.
struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var settings: AppSettings
    @State private var day = Date()
    @State private var lineInContent: CGFloat = 0
    @State private var scrollTop: CGFloat = 0

    var body: some View {
        let isToday = Fmt.greg.isDateInToday(day)
        // Today (the default): everything coming up and every open task.
        // Another day picked in the calendar: just that day's.
        let appointments = isToday ? store.upcoming() : store.on(day: day)
        let allTasks = isToday ? store.openTasks : store.tasks(on: day)
        VStack(spacing: 0) {
        // The greeting and its two buttons stay fixed above the scrolling content: a tap on them never
        // lands on a page that is still gliding after a scroll (that first tap would only stop it).
        header
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CalendarCard(selection: $day)

                SectionHeader(title: isToday ? L("اليوم", "Today") : Fmt.dayTitle(day), detail: Fmt.hijriText(day))
                    .accessibilityIdentifier("dayLine")
                    // Where this line sits inside the page content: unaffected by scrolling.
                    .background(GeometryReader { g in
                        let y = g.frame(in: .named("homeContent")).midY
                        Color.clear
                            .onAppear { lineInContent = y }
                            .onChange(of: y) { lineInContent = $0 }
                    })

                label(L("مواعيدي", "Appointments"), "calendar", appointments.count)
                if appointments.isEmpty {
                    emptyRow(L("ليس لديك مواعيد", "No appointments"))
                } else {
                    if isToday {
                        // Today: a "now" line among today's appointments, refreshed every minute.
                        TimelineView(.periodic(from: Date(), by: 60)) { ctx in
                            todayList(appointments, now: ctx.date)
                        }
                    } else {
                        ForEach(appointments) { AppointmentCard(item: $0, showDate: false) }
                    }
                }

                label(L("مهامي", "Tasks"), "checklist", allTasks.filter { !$0.isDone }.count)
                if allTasks.isEmpty {
                    emptyRow(L("ليس لديك مهام", "No tasks"))
                } else {
                    TaskList(tasks: allTasks, interactive: false, spacing: 18)   // opened to be marked done
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .animation(Router.soft, value: day)
            .coordinateSpace(name: "homeContent")
        }
        // Where the page starts on screen (after the status bar margin is applied): also unaffected by scrolling.
        .background(GeometryReader { g in
            let top = g.frame(in: .global).minY
            Color.clear
                .onAppear { scrollTop = top }
                .onChange(of: top) { scrollTop = $0 }
        })
        }
        // The menu tab sits level with the day line as the page lays out unscrolled. Both parts are measured
        // independently of scrolling, and only the settled layout is used (the very first pass, before the
        // status bar margin was applied, put the tab about 55 points too high).
        .onChange(of: scrollTop) { _ in publishLine() }
        .onChange(of: lineInContent) { _ in publishLine() }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { publishLine() } }
        .background(Theme.background.ignoresSafeArea())
    }

    private func publishLine() {
        // Only while home is the page on screen and nothing is drawn over it: switching pages, the menu and
        // slide-in pages scale or shift the home page, which would otherwise move the tab.
        guard lineInContent > 0, router.page == .home, !router.menuOpen,
              !router.showSettings, !router.showProfile else { return }
        let y = scrollTop + lineInContent
        if abs(router.dayLineY - y) > 0.5 { router.dayLineY = y }
    }

    private var header: some View {
        HStack(spacing: 10) {
            // Re-evaluated every minute, so the greeting follows the time of day.
            TimelineView(.periodic(from: Date(), by: 60)) { ctx in
                greetingView(now: ctx.date)
            }
            Spacer(minLength: 8)
            Button { router.present(profile: true) } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("الملف الشخصي", "Profile"))
            .accessibilityIdentifier("button.profile")
            Button { router.present(profile: false) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Theme.burgundy))
                    .shadow(color: Theme.burgundy.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("الإعدادات", "Settings"))
            .accessibilityIdentifier("button.settings")
        }
    }

    /// "صبآح الخير ❄︎ <name>" — the season's icon sits between the greeting and the name.
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

    /// Today's appointments that have already started, the "now" line, then the rest. The line only
    /// shows when there is something today to place it among.
    @ViewBuilder
    private func todayList(_ items: [Appointment], now: Date) -> some View {
        let todays = items.filter { Fmt.greg.isDate($0.date, inSameDayAs: now) }
        let started = items.filter { todays.contains($0) && ($0.hasTime ? $0.date <= now : true) }
        let rest = items.filter { !started.contains($0) }
        VStack(spacing: 18) {
            ForEach(started) { AppointmentCard(item: $0, showDate: true) }
            if !todays.isEmpty { NowLine(now: now) }
            ForEach(rest) { AppointmentCard(item: $0, showDate: true) }
        }
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

/// Winter (November–April): a snowman. Summer (May–October): an air conditioner.
struct SeasonIcon: View {
    let date: Date

    private var isSummer: Bool { (5...10).contains(Fmt.greg.component(.month, from: date)) }

    var body: some View {
        Group {
            if isSummer {
                Group {
                    if #available(iOS 16.0, *) {
                        Image(systemName: "air.conditioner.horizontal.fill")
                    } else {
                        Image(systemName: "wind")
                    }
                }
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.navy)
            } else {
                Image("Snowman")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
        }
        .accessibilityLabel(isSummer ? L("صيف", "Summer") : L("شتاء", "Winter"))
    }
}


/// "الآن · ٤:٣٧ م" with a thin line: where the present sits among today's appointments.
struct NowLine: View {
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.burgundy).frame(width: 8, height: 8)
            Text(Fmt.joined([L("الآن", "Now"), Fmt.timeText(now)]))
                .font(.app(.caption, .bold))
                .foregroundColor(Theme.burgundy)
                .fixedSize()
            Rectangle().fill(Theme.burgundy.opacity(0.45)).frame(height: 1)
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("nowLine")
    }
}
