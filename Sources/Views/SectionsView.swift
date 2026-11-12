import SwiftUI

enum MainSection: Int, CaseIterable, Identifiable {
    case appointments = 1, tasks, finance
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .appointments: return "مواعيدي"
        case .tasks: return "مهامي"
        case .finance: return "فواتير وتقارير"
        }
    }
    var icon: String {
        switch self {
        case .appointments: return "calendar"
        case .tasks: return "checkmark.circle.fill"
        case .finance: return "doc.text.fill"
        }
    }
    var summary: String {
        switch self {
        case .appointments: return "التقويم، المواعيد، الصيانة والتجديد"
        case .tasks: return "مهام اليوم والقادمة والمتأخرة"
        case .finance: return "فواتير الأجهزة والسيارات ومصاريفك"
        }
    }
    var color: Color {
        switch self {
        case .appointments: return Theme.dyn(0x14627A, 0x80D3ED)
        case .tasks: return Theme.dyn(0x276548, 0x91D7A9)
        case .finance: return Theme.dyn(0x915014, 0xF7C282)
        }
    }
    var surface: Color {
        switch self {
        case .appointments: return Theme.dyn(0xE3F2F7, 0x14323C)
        case .tasks: return Theme.dyn(0xE5F2E7, 0x21392A)
        case .finance: return Theme.dyn(0xFAECDB, 0x42301E)
        }
    }
    func includes(_ item: Item) -> Bool {
        switch item.category {
        case .task: return self == .tasks
        case .bill, .subscription, .warranty: return self == .finance
        default: return self == .appointments
        }
    }
}

struct StartDashboard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    let onAdd: () -> Void
    let onSettings: () -> Void
    @State private var alertDismissed = false
    @State private var shareText: String? = nil

    private static let gold = Theme.dyn(0xA8782E, 0xE2B66A)
    private static let goldSoft = Theme.dyn(0xF6EEDD, 0x2E2719)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                HStack(alignment: .top, spacing: 12) {
                    dateCard
                    shortcutsCard
                }
                .fixedSize(horizontal: false, vertical: true)
                sectionHeader("الجاي", trailing: nextUp.first.map { "· \($0.category.title)" }) {
                    shareText = shareSummary
                }
                VStack(spacing: 0) {
                    CountdownHero(items: nextUp, onOpen: { router.openItem = ItemRef(id: $0) }, onAdd: onAdd)
                    if let alert = alertCard, !alertDismissed {
                        alert
                            .padding(.top, -26)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                sectionHeader("أقسامك", trailing: nil, onShare: nil)
                ForEach(MainSection.allCases) { section in
                    Button { router.tab = section.rawValue } label: { sectionCard(section) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(
            ZStack(alignment: .topLeading) {
                Theme.background
                Image(systemName: "seal")
                    .font(.system(size: 320, weight: .ultraLight))
                    .foregroundColor(Self.gold.opacity(0.06))
                    .offset(x: -90, y: -70)
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: Binding(get: { shareText != nil }, set: { if !$0 { shareText = nil } })) {
            ShareSheet(items: [shareText ?? ""])
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(greeting).font(.title2.bold()).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "sparkles").foregroundColor(Self.gold)
            }
            Spacer(minLength: 8)
            Button { router.tab = MainSection.appointments.rawValue } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.card))
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if store.badgeCount > 0 {
                            Text("\(store.badgeCount)")
                                .font(.caption2.bold()).foregroundColor(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(Capsule().fill(Color.red))
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("التنبيهات")
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Color.brand))
                    .shadow(color: Color.brand.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("الإعدادات")
        }
    }

    private var greeting: String {
        let h = Fmt.greg.component(.hour, from: Date())
        if h < 5 { return "تصبح على خير" }
        if h < 12 { return "صباح الخير" }
        if h < 18 { return "يومك سعيد" }
        return "مساء الخير"
    }

    // MARK: Two cards

    private var dateCard: some View {
        let now = Date()
        let hc = Fmt.hijriCalendar
        let hDay = hc.component(.day, from: now)
        let hMonth = hc.component(.month, from: now)
        let monthName = formatted(now, "MMMM", hijri: true)
        let hYear = hc.component(.year, from: now)
        return VStack(spacing: 4) {
            HStack {
                Spacer()
                Button { shareText = "اليوم \(formatted(now, "EEEE", hijri: false)) \(Fmt.hijriText(now)) — \(Fmt.dateText(now, hasTime: false, long: true))" } label: {
                    Image(systemName: "square.and.arrow.up").font(.subheadline).foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            Text(formatted(now, "EEEE", hijri: false))
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundColor(Self.gold)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text("\(hDay)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(Theme.ink)
            Text("\(monthName) (\(hMonth))")
                .font(.headline).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(hYear) هـ").font(.subheadline.bold()).foregroundColor(Theme.ink)
            Text(Fmt.dateText(now, hasTime: false))
                .font(.caption).foregroundColor(Self.gold).padding(.top, 4)
            Text("تقويم أم القرى").font(.caption2).foregroundColor(Self.gold.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Self.goldSoft))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Self.gold.opacity(0.25), lineWidth: 1))
    }

    private var shortcutsCard: some View {
        let tasks = store.activeSorted.filter { $0.category == .task && $0.urgency() <= .today }
        let doses = store.doses()
        let pending = doses.filter { !$0.taken }.count
        return VStack(spacing: 0) {
            Button { router.tab = MainSection.tasks.rawValue } label: {
                shortcutRow(caption: "قبل لا يفوتك",
                            title: tasks.isEmpty ? "مهامي" : "مهام اليوم (\(tasks.count))",
                            icon: "checklist")
            }
            .buttonStyle(.plain)
            Divider().padding(.vertical, 14)
            if doses.isEmpty {
                Button { router.tab = MainSection.finance.rawValue } label: {
                    shortcutRow(caption: "مصاريفك", title: "فواتيري", icon: "doc.text.fill")
                }
                .buttonStyle(.plain)
            } else {
                Button { router.tab = MainSection.appointments.rawValue } label: {
                    shortcutRow(caption: "أدوية اليوم",
                                title: pending == 0 ? "أخذتها كلها ✓" : "باقي \(pending) جرعة",
                                icon: "pills.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Self.goldSoft))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Self.gold.opacity(0.25), lineWidth: 1))
    }

    private func shortcutRow(caption: String, title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Self.gold, Self.gold.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .frame(width: 50, height: 50)
                .overlay(Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(caption).font(.caption).foregroundColor(Self.gold)
                Text(title).font(.subheadline.bold()).foregroundColor(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: Section header

    private func sectionHeader(_ title: String, trailing: String?, onShare: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(Self.gold).frame(width: 5, height: 24)
            Text(title).font(.title3.bold()).foregroundColor(Theme.ink)
            if let t = trailing {
                Text(t).font(.subheadline).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer()
            if let onShare = onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up").font(.body).foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Data

    private var nextUp: [Item] {
        let now = Date()
        return store.activeSorted.filter {
            !$0.isMedicine && $0.dueMoment(reminderMinutes: AppSettings.shared.reminderMinutes) > now
        }
    }

    private var shareSummary: String {
        var lines = ["📅 مواعيدي — \(Fmt.dateText(Date(), hasTime: false, long: true))"]
        for it in nextUp.prefix(5) {
            lines.append("• \(it.title) — \(Fmt.countdown(to: it.date, hasTime: it.hasTime))")
        }
        return lines.joined(separator: "\n")
    }

    /// The card that overlaps the bottom of the countdown: overdue first, then a pending dose.
    private var alertCard: AnyView? {
        let overdue = store.active(.overdue)
        if let first = overdue.first {
            return AnyView(AlertCard(
                icon: "exclamationmark.triangle.fill",
                title: overdue.count == 1 ? "عندك شي متأخر" : "عندك \(overdue.count) أشياء متأخرة",
                pill: "\(first.title) — \(first.pillText)",
                button: "افتحه وخلّصه",
                action: { router.openItem = ItemRef(id: first.id) },
                onClose: { withAnimation { alertDismissed = true } }))
        }
        let now = Date()
        let start = Fmt.greg.startOfDay(for: now)
        if let dose = store.doses().first(where: { !$0.taken && start.addingTimeInterval(TimeInterval($0.minutes * 60)) <= now }) {
            return AnyView(AlertCard(
                icon: "pills.fill",
                title: "وقت جرعة \(dose.item.title)",
                pill: [dose.item.dosage, Fmt.timeText(start.addingTimeInterval(TimeInterval(dose.minutes * 60)))]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                button: "أخذتها ✅",
                action: { withAnimation { store.toggleDose(dose.item.id, day: now, minutes: dose.minutes) } },
                onClose: { withAnimation { alertDismissed = true } }))
        }
        return nil
    }

    private func formatted(_ d: Date, _ format: String, hijri: Bool) -> String {
        let f = DateFormatter()
        f.calendar = hijri ? Fmt.hijriCalendar : Fmt.greg
        f.locale = hijri ? Fmt.hijriLocale : Fmt.locale
        f.dateFormat = format
        return f.string(from: d)
    }

    private func sectionCard(_ section: MainSection) -> some View {
        HStack(spacing: 14) {
            Tile(icon: section.icon, color: section.color, size: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(section.title).font(.title3.bold()).foregroundColor(Theme.ink)
                Text(section.summary).font(.subheadline).foregroundColor(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.subheadline.bold()).foregroundColor(section.color)
                .accessibilityHidden(true)
        }.padding(16).frame(minHeight: 88)
            .background(RoundedRectangle(cornerRadius: 24).fill(section.surface))
    }
}

/// Dark card with a live countdown to the next item and a progress bar from when it was added.
struct CountdownHero: View {
    let items: [Item]
    let onOpen: (UUID) -> Void
    let onAdd: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.20), Color(red: 0.10, green: 0.23, blue: 0.27)],
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
                    Text("ما عندك شي جاي").font(.title3.bold()).foregroundColor(.white)
                    Text("سجّل موعد أو تجديد وأحسب لك الوقت المتبقي ثانية بثانية.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                    Button(action: onAdd) {
                        Label("إضافة", systemImage: "plus").font(.headline).foregroundColor(.black)
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
                        .position(x: g.size.width * CGFloat((i * 37 % 97)) / 97, y: CGFloat(12 + (i * 53 % 150)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func content(_ item: Item, now: Date) -> some View {
        let due = item.dueMoment(reminderMinutes: AppSettings.shared.reminderMinutes)
        let left = max(0, Int(due.timeIntervalSince(now)))
        let days = left / 86400
        let clock = String(format: "%02d:%02d:%02d", (left % 86400) / 3600, (left % 3600) / 60, left % 60)
        let start = min(item.createdAt, due.addingTimeInterval(-3600))
        let total = max(1, due.timeIntervalSince(start))
        let progress = min(1, max(0, now.timeIntervalSince(start) / total))
        return VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: item.displayIcon)
                    Text(item.category.title).lineLimit(1)
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15)))
                Spacer()
            }
            .padding(.top, 2)
            Text("باقي على \(item.title)")
                .font(.title3.bold()).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            if days > 0 {
                Text(Fmt.days(days))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.93, green: 0.78, blue: 0.48))
                Text("و \(clock)")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundColor(Color(red: 0.93, green: 0.78, blue: 0.48).opacity(0.85))
            } else {
                Text(clock)
                    .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundColor(Color(red: 0.93, green: 0.78, blue: 0.48))
            }
            if items.count > 1 {
                let second = items[1]
                Text("بعده: \(second.title) \(Fmt.countdown(to: second.date, hasTime: second.hasTime, now: now))")
                    .font(.subheadline).foregroundColor(.white.opacity(0.75)).lineLimit(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)).frame(height: 10)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.48), Color(red: 0.80, green: 0.62, blue: 0.32)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, g.size.width * CGFloat(progress)), height: 10)
                    // An HStack (not .offset) so the knob follows the right-to-left direction like the fill.
                    HStack(spacing: 0) {
                        Color.clear.frame(width: max(0, min(g.size.width - 24, g.size.width * CGFloat(progress) - 12)))
                        Circle().fill(Color(red: 0.12, green: 0.15, blue: 0.20))
                            .overlay(Circle().stroke(Color(red: 0.93, green: 0.78, blue: 0.48), lineWidth: 3))
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
                    Text("أضفته").font(.subheadline.bold())
                    Text(Fmt.dateText(start, hasTime: false)).font(.caption)
                }
                .foregroundColor(.white.opacity(0.75))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("الموعد").font(.subheadline.bold())
                    Text(Fmt.dateText(item.date, hasTime: item.hasTime)).font(.caption)
                }
                .foregroundColor(Color(red: 0.93, green: 0.78, blue: 0.48))
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
                Image(systemName: icon).font(.title3)
                Text(title).font(.headline).lineLimit(2)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إغلاق")
            }
            .foregroundColor(.white)
            if !pill.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").font(.caption)
                    Text(pill).font(.subheadline.bold()).lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color(red: 0.16, green: 0.45, blue: 0.38)))
                .overlay(Capsule().stroke(Color.white.opacity(0.25)))
            }
            Button(action: action) {
                Text(button)
                    .font(.headline)
                    .foregroundColor(Color(red: 0.55, green: 0.38, blue: 0.13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.78, green: 0.62, blue: 0.33), Color(red: 0.62, green: 0.44, blue: 0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

struct ScheduleSection: View {
    let section: MainSection
    @EnvironmentObject private var store: Store
    @State private var filter: Period = .upcoming
    @State private var selectedDate = Date()
    @State private var query = ""

    enum Period: String, CaseIterable, Identifiable {
        case upcoming = "القادمة", today = "اليوم", late = "المتأخرة", completed = "المنجزة", calendar = "التقويم"
        var id: Self { self }
    }

    private var visible: [Item] {
        let base = filter == .completed ? store.doneSorted : store.activeSorted
        let matching = base.filter {
            guard section.includes($0), query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) else { return false }
            if $0.isMedicine { return filter == .completed || (filter == .upcoming && !query.isEmpty) }
            switch filter {
            case .upcoming: return $0.urgency() != .overdue
            case .today: return $0.urgency() == .today
            case .late: return $0.urgency() == .overdue
            case .calendar: return Fmt.greg.isDate($0.date, inSameDayAs: selectedDate)
            case .completed: return true
            }
        }
        guard section == .tasks, filter != .completed else { return matching }
        return matching.sorted {
            if $0.isHighPriority != $1.isHighPriority { return $0.isHighPriority }
            return $0.date < $1.date
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                PageHeader(title: section.title, subtitle: section.summary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Period.allCases.filter { $0 != .calendar || section == .appointments }) { p in
                            Chip(title: p.rawValue, selected: p == filter) { filter = p }
                        }
                    }
                }
                if filter == .calendar {
                    DatePicker("اختر التاريخ", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).card()
                }
                if section == .appointments, filter == .today, query.isEmpty, !store.doses().isEmpty {
                    SectionBlock(title: "جرعات اليوم", icon: "pills.fill", color: .pink, count: store.doses().count) {
                        VStack(spacing: 8) { ForEach(store.doses()) { DoseRow(dose: $0) } }.card()
                    }
                }
                if section == .appointments, filter == .upcoming, query.isEmpty {
                    let medicines = store.activeSorted.filter { $0.isMedicine }
                    if !medicines.isEmpty {
                        SectionBlock(title: "الأدوية", icon: "pills.fill", color: .pink, count: medicines.count) {
                            VStack(spacing: 10) {
                                ForEach(medicines) { ItemCard(item: $0) }
                            }
                        }
                    }
                }
                if visible.isEmpty {
                    EmptyStateView(icon: section.icon, title: "ما فيه عناصر هنا", message: "غيّر الفلتر أو أضف عنصر من زر +.").card()
                }
                ForEach(visible) { ItemCard(item: $0) }
            }.padding(16)
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "ابحث بالعنوان")
    }
}

struct FinanceSection: View {
    let onAddInvoice: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                PageHeader(title: "فواتير وتقارير", subtitle: "فواتيرك وضماناتك ومصاريفك في مكان واحد")
                Button(action: onAddInvoice) {
                    Label("إضافة فاتورة شراء", systemImage: "plus.circle.fill")
                        .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity)
                        .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Color.brand))
                }.buttonStyle(.plain)
                ForEach(InvoiceGroup.allCases) { group in
                    NavigationLink(destination: InvoiceList(group: group)) {
                        SettingsTile(title: group.title, subtitle: group.subtitle, icon: group.icon, tint: MainSection.finance.color)
                    }.buttonStyle(.plain)
                }
                NavigationLink(destination: AssetsView()) {
                    SettingsTile(title: "ملفات الأجهزة والسيارات", subtitle: "الفواتير والضمان والصيانة لكل ممتلك", icon: "archivebox.fill", tint: .teal)
                }.buttonStyle(.plain)
                NavigationLink(destination: ReportsView()) {
                    SettingsTile(title: "التقارير", subtitle: "راجع المصاريف حسب الفترة والنوع", icon: "chart.bar.fill", tint: .indigo)
                }.buttonStyle(.plain)
            }.padding(16)
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle("فواتير وتقارير").navigationBarTitleDisplayMode(.inline)
    }
}

enum InvoiceGroup: CaseIterable, Identifiable {
    case devices, vehicles, other
    var id: Self { self }
    var title: String {
        switch self {
        case .devices: return "فواتير الأجهزة"
        case .vehicles: return "فواتير السيارات"
        case .other: return "الفواتير الأخرى"
        }
    }
    var subtitle: String {
        switch self {
        case .devices: return "المشتريات وضمانات الأجهزة المرتبطة"
        case .vehicles: return "الفواتير والضمانات المرتبطة بالسيارات"
        case .other: return "الفواتير العامة والأقساط والاشتراكات"
        }
    }
    var icon: String {
        switch self {
        case .devices: return "desktopcomputer"
        case .vehicles: return "car.fill"
        case .other: return "doc.on.doc.fill"
        }
    }
    func includes(_ kind: AssetKind?) -> Bool {
        switch self {
        case .devices: return kind == .device
        case .vehicles: return kind == .vehicle
        case .other: return kind == nil
        }
    }
}

struct InvoiceList: View {
    let group: InvoiceGroup
    @ObservedObject private var assets = AssetStore.shared
    @EnvironmentObject private var store: Store
    @State private var query = ""

    private var items: [Item] {
        store.items.filter { item in
            let asset = assets.asset(item.assetID)
            return MainSection.finance.includes(item) && group.includes(asset?.kind)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || asset?.name.localizedCaseInsensitiveContains(query) == true)
        }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if items.isEmpty {
                    EmptyStateView(icon: group.icon, title: "ما فيه فواتير هنا",
                                   message: "تقدر تضيف فاتورة وترتبط تلقائيًا بهذا القسم إذا اخترت جهازًا أو سيارة عند الحفظ.").card()
                }
                ForEach(items) { ItemCard(item: $0) }
            }.padding(16)
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle(group.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "ابحث بالفاتورة أو الممتلك")
    }
}

struct SettingsTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Tile(icon: icon, color: tint, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundColor(Theme.ink)
                Text(subtitle).font(.subheadline).foregroundColor(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.caption.bold()).foregroundColor(Theme.muted)
                .accessibilityHidden(true)
        }.card(padding: 14)
    }
}

