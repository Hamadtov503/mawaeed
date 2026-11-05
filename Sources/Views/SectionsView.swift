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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("مواعيدي", systemImage: "calendar.badge.clock")
                        .font(.title2.bold()).foregroundColor(Theme.ink)
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape").font(.title3)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(Theme.card))
                    }.buttonStyle(.plain).accessibilityLabel("الإعدادات")
                }
                todayCard
                Text("أقسامك").font(.headline).foregroundColor(Theme.ink)
                    .padding(.top, 4).accessibilityAddTraits(.isHeader)
                ForEach(MainSection.allCases) { section in
                    Button { router.tab = section.rawValue } label: { sectionCard(section) }
                        .buttonStyle(.plain)
                }
                Button(action: onAdd) {
                    Label("إضافة جديدة", systemImage: "plus.circle.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(14)
                        .foregroundColor(Color.brand)
                }.buttonStyle(.plain)
            }.padding(18).frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
        }.background(Theme.background.ignoresSafeArea())
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Fmt.dateText(Date(), hasTime: false, long: true))
                .font(.subheadline).foregroundColor(.white.opacity(0.85))
            Text("نظرة على يومك").font(.largeTitle.bold()).foregroundColor(.white)
            HStack(spacing: 12) {
                summary("اليوم", store.active(.today).count, "sun.max.fill")
                summary("متأخر", store.active(.overdue).count, "clock.fill")
                summary("هذا الأسبوع", store.active(.week).count, "calendar")
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28).fill(
                LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.25), Color(red: 0.09, green: 0.36, blue: 0.34)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            ))
    }

    private func summary(_ label: String, _ count: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("\(count)", systemImage: icon).font(.headline)
            Text(label).font(.caption)
        }.foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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

