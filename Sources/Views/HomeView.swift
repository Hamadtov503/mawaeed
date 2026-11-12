import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var settings: AppSettings
    let onAdd: () -> Void
    @State private var alertDismissed: UUID? = nil
    @State private var shareText: String? = nil

    var body: some View {
        let upcoming = store.upcoming()
        let today = upcoming.filter { $0.status() == .today }
        let soon = upcoming.filter { $0.status() != .today }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(todayCount: today.count)
                HStack(alignment: .top, spacing: 12) {
                    DateCard { shareText = $0 }
                    StatsCard(today: today.count,
                              week: upcoming.filter { $0.status() != .later }.count,
                              onToday: { router.tab = 1 })
                }
                .fixedSize(horizontal: false, vertical: true)

                SectionHeader(title: "موعدك الجاي", detail: upcoming.first.map { "· \(Fmt.dayTitle($0.date))" },
                              actionIcon: upcoming.isEmpty ? nil : "square.and.arrow.up",
                              onAction: { shareText = summary(upcoming) })
                VStack(spacing: 0) {
                    CountdownHero(items: upcoming, onOpen: { router.openID = AppointmentRef(id: $0) }, onAdd: onAdd)
                    if let soonest = upcoming.first, soonest.id != alertDismissed, let alert = alertCard(for: soonest) {
                        alert
                            .padding(.top, -26)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }

                if !today.isEmpty {
                    SectionHeader(title: "مواعيد اليوم", detail: "\(today.count)")
                    ForEach(today) { AppointmentCard(item: $0) }
                }
                if !soon.isEmpty {
                    SectionHeader(title: "القادمة", detail: "\(soon.count)")
                    ForEach(soon.prefix(5)) { AppointmentCard(item: $0, showDate: true) }
                    if soon.count > 5 {
                        Button { router.tab = 1 } label: {
                            Text("عرض كل المواعيد (\(upcoming.count))")
                                .font(.app(.subheadline, .semibold)).foregroundColor(.brand)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .card(padding: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            ShareSheet(items: [shareText ?? ""])
        }
    }

    private func header(todayCount: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(greeting).font(.app(.title2, .bold)).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "sparkles").foregroundColor(Theme.burgundy)
            }
            Spacer(minLength: 8)
            Button { router.present(notifications: true) } label: {
                Image(systemName: router.deliveredCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if router.deliveredCount > 0 {
                            Text("\(router.deliveredCount)")
                                .font(.app(.caption2, .bold)).foregroundColor(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Color.red))
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("التنبيهات")
            Button { router.present(notifications: false) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.burgundy))
                    .shadow(color: Theme.burgundy.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("الإعدادات")
        }
    }

    private var greeting: String {
        let h = Fmt.greg.component(.hour, from: Date())
        let g = (4..<12).contains(h) ? "صباح الخير" : "مساء الخير"
        let name = settings.userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? g : "\(g) يا \(name)"
    }

    private func summary(_ list: [Appointment]) -> String {
        var lines = ["📅 مواعيدي"]
        for a in list.prefix(5) { lines.append("• \(a.title) — \(Fmt.dateText(a.date, hasTime: a.hasTime))") }
        return lines.joined(separator: "\n")
    }

    /// A warm card over the countdown when the next appointment is today.
    private func alertCard(for a: Appointment) -> AlertCard? {
        guard a.status() == .today else { return nil }
        var pill = a.hasTime ? "الساعة \(Fmt.timeText(a.date))" : "اليوم"
        if !a.location.isEmpty { pill += " · \(a.location)" }
        return AlertCard(
            icon: "bell.badge.fill",
            title: "لا تنسى موعدك اليوم: \(a.title)",
            pill: pill,
            button: a.location.isEmpty ? "افتح الموعد" : "افتح الموقع في الخرائط",
            action: {
                if a.location.isEmpty {
                    router.openID = AppointmentRef(id: a.id)
                } else {
                    openMaps(a.location)
                }
            },
            onClose: { withAnimation { alertDismissed = a.id } })
    }
}

func openMaps(_ place: String) {
    let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
    if let url = URL(string: place.hasPrefix("http") ? place : "http://maps.apple.com/?q=\(q)") {
        UIApplication.shared.open(url)
    }
}

/// Today's date: weekday, Hijri day/month/year (Umm al-Qura) and the Gregorian date.
struct DateCard: View {
    let onShare: (String) -> Void

    var body: some View {
        let now = Date()
        let hc = Fmt.hijriCalendar
        VStack(spacing: 4) {
            HStack {
                Spacer()
                Button {
                    onShare("اليوم \(Fmt.weekday.string(from: now)) \(Fmt.hijriText(now)) — \(Fmt.dateText(now, hasTime: false, long: true))")
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.app(.subheadline)).foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            Text(Fmt.weekday.string(from: now))
                .font(.ruqaa(size: 38))
                .foregroundColor(Theme.burgundy)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(hc.component(.day, from: now))")
                .font(.app(size: 44, .bold))
                .foregroundColor(Theme.navy)
            Text("\(Fmt.hijriMonth.string(from: now)) (\(hc.component(.month, from: now)))")
                .font(.app(.headline)).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(hc.component(.year, from: now)) هـ").font(.app(.subheadline, .bold)).foregroundColor(Theme.ink)
            Text(Fmt.dateText(now, hasTime: false))
                .font(.app(.caption)).foregroundColor(Theme.forest).padding(.top, 4)
            Text("تقويم أم القرى").font(.app(.caption2)).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Two rows: today's appointments and this week's.
struct StatsCard: View {
    let today: Int
    let week: Int
    let onToday: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToday) {
                row(caption: "مواعيد اليوم", title: today == 0 ? "يومك فاضي" : Fmt.count(today, one: "موعد واحد", two: "موعدين", few: "مواعيد", many: "موعد"),
                    icon: "sun.max.fill", color: Theme.burgundy)
            }
            .buttonStyle(.plain)
            Divider().padding(.vertical, 14)
            Button(action: onToday) {
                row(caption: "خلال أسبوع", title: week == 0 ? "ما فيه شي" : Fmt.count(week, one: "موعد واحد", two: "موعدين", few: "مواعيد", many: "موعد"),
                    icon: "calendar", color: Theme.forest)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func row(caption: String, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .frame(width: 50, height: 50)
                .overlay(Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(caption).font(.app(.caption)).foregroundColor(color)
                Text(title).font(.app(.subheadline, .bold)).foregroundColor(Theme.ink).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Dark card with a live, second-by-second countdown to the next appointment.
struct CountdownHero: View {
    let items: [Appointment]
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void

    private let gold = Color(red: 0.91, green: 0.85, blue: 0.74)   // warm sand on navy

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.22), Color(red: 0.14, green: 0.21, blue: 0.34)],
                           startPoint: .top, endPoint: .bottom)
            stars
            if let item = items.first {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    content(item, now: ctx.date)
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpen(item.id) }
            } else {
                VStack(spacing: 12) {
                    Text("ما عندك مواعيد جاية").font(.app(.title3, .bold)).foregroundColor(.white)
                    Text("سجّل موعدك وأحسب لك الوقت المتبقي ثانية بثانية، وأذكّرك قبله.")
                        .font(.app(.subheadline)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button(action: onAdd) {
                        Label("أضف موعد", systemImage: "plus").font(.app(.headline)).foregroundColor(.black)
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                }
                .padding(28)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var stars: some View {
        GeometryReader { g in
            ZStack {
                Image(systemName: "moon.fill").font(.system(size: 34)).foregroundColor(.white.opacity(0.85))
                    .rotationEffect(.degrees(-25))
                    .position(x: g.size.width * 0.82, y: 42)
                ForEach(0..<14, id: \.self) { i in
                    Circle().fill(Color.white.opacity(i % 3 == 0 ? 0.55 : 0.3))
                        .frame(width: i % 4 == 0 ? 2.5 : 1.5, height: i % 4 == 0 ? 2.5 : 1.5)
                        .position(x: g.size.width * CGFloat(i * 37 % 97) / 97, y: CGFloat(12 + (i * 53 % 150)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func content(_ item: Appointment, now: Date) -> some View {
        let target = item.hasTime ? item.date : Fmt.greg.startOfDay(for: item.date)
        let left = max(0, Int(target.timeIntervalSince(now)))
        let days = left / 86400
        let clock = String(format: "%02d:%02d:%02d", (left % 86400) / 3600, (left % 3600) / 60, left % 60)
        let start = min(item.createdAt, target.addingTimeInterval(-3600))
        let progress = min(1, max(0, now.timeIntervalSince(start) / max(1, target.timeIntervalSince(start))))
        return VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: item.displayIcon)
                    Text(Fmt.dayTitle(item.date)).lineLimit(1)
                }
                .font(.app(.caption, .bold)).foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
                Spacer()
            }
            .padding(.top, 2)
            Text(left == 0 ? "حان وقت \(item.title)" : "باقي على \(item.title)")
                .font(.app(.title3, .bold)).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            if days > 0 {
                Text(Fmt.days(days))
                    .font(.app(size: 40, .bold)).foregroundColor(gold)
                Text("و \(clock)")
                    .font(.app(size: 20, .semibold)).monospacedDigit()
                    .foregroundColor(gold.opacity(0.85))
            } else {
                Text(clock)
                    .font(.app(size: 46, .bold)).monospacedDigit()
                    .foregroundColor(gold)
            }
            if items.count > 1 {
                let second = items[1]
                Text("بعده: \(second.title) \(Fmt.countdown(to: second.date, hasTime: second.hasTime, now: now))")
                    .font(.app(.subheadline)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [gold, Color(red: 0.79, green: 0.43, blue: 0.47)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, g.size.width * CGFloat(progress)), height: 10)
                    // An HStack (not .offset) so the knob follows the right-to-left direction like the fill.
                    HStack(spacing: 0) {
                        Color.clear.frame(width: max(0, min(g.size.width - 24, g.size.width * CGFloat(progress) - 12)))
                        Circle().fill(Color(red: 0.09, green: 0.13, blue: 0.22))
                            .overlay(Circle().stroke(gold, lineWidth: 3))
                            .frame(width: 24, height: 24)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 26)
            .padding(.top, 6)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("سجّلته").font(.app(.subheadline, .bold))
                    Text(Fmt.dateText(start, hasTime: false)).font(.app(.caption))
                }
                .foregroundColor(.white.opacity(0.75))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("الموعد").font(.app(.subheadline, .bold))
                    Text(Fmt.dateText(item.date, hasTime: item.hasTime)).font(.app(.caption))
                }
                .foregroundColor(gold)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 44)
    }
}

/// Warm card that overlaps the bottom of the countdown, with a pill and a big white button.
struct AlertCard: View {
    let icon: String
    let title: String
    let pill: String
    let button: String
    let action: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.app(.title3))
                Text(title).font(.app(.headline)).lineLimit(2)
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.app(.body, .semibold)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إغلاق")
            }
            .foregroundColor(.white)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.app(.caption))
                Text(pill).font(.app(.subheadline, .bold)).lineLimit(1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color(red: 0.12, green: 0.30, blue: 0.23)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25)))
            Button(action: action) {
                Text(button)
                    .font(.app(.headline))
                    .foregroundColor(Color(red: 0.48, green: 0.12, blue: 0.18))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.56, green: 0.16, blue: 0.23), Color(red: 0.40, green: 0.10, blue: 0.16)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
