import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var store: Store
    @State private var tab: Tab = .general
    @State private var months = 12

    enum Tab: String, CaseIterable, Identifiable {
        case general, spending, documents, medicines
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "عام"
            case .spending: return "المصاريف"
            case .documents: return "الوثائق والضمانات"
            case .medicines: return "الأدوية"
            }
        }
    }

    private var periodStart: Date {
        let cal = Fmt.greg
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return cal.date(byAdding: .month, value: -(months - 1), to: startOfMonth) ?? Date()
    }

    private var logs: [(item: Item, entry: LogEntry)] {
        let start = periodStart
        return store.allLogs.filter { $0.entry.date >= start }
    }

    private var spent: Double { logs.compactMap { $0.entry.cost }.reduce(0, +) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Tab.allCases) { t in
                                Chip(title: t.title, selected: tab == t) { withAnimation { tab = t } }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    periodCard

                    switch tab {
                    case .general: general
                    case .spending: spending
                    case .documents: documents
                    case .medicines: medicines
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("التقارير")
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Period

    private var periodCard: some View {
        HStack {
            Image(systemName: "calendar").foregroundColor(.brand)
            Menu {
                ForEach([1, 3, 6, 12, 24], id: \.self) { m in
                    Button(periodTitle(m)) { months = m }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(periodTitle(months)).font(.subheadline.weight(.bold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .foregroundColor(Theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().stroke(Theme.border))
            }
            Spacer()
            Text("\(monthName(periodStart)) – \(monthName(Date()))")
                .font(.caption).foregroundColor(Theme.muted)
        }
        .card(padding: 14)
    }

    private func periodTitle(_ m: Int) -> String {
        m == 1 ? "هالشهر" : "آخر \(Fmt.months(m))"
    }

    private func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Fmt.greg
        f.locale = Fmt.locale
        f.dateFormat = "MMM y"
        return f.string(from: d)
    }

    // MARK: General

    private var general: some View {
        let docs = documentStatus
        let doneCount = logs.count + store.items.filter { !$0.isRecurring && ($0.doneAt ?? .distantPast) >= periodStart && $0.logs.isEmpty }.count
        let active = store.items.filter { !$0.isDone }
        let next30 = store.activeSorted.filter {
            !$0.isMedicine && $0.date >= Fmt.greg.startOfDay(for: Date()) && $0.date <= Date().addingTimeInterval(30 * 86400)
        }
        let expected = next30.compactMap { $0.amount }.reduce(0, +)
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "الصرف", icon: "creditcard.fill", value: Fmt.money(spent),
                         lines: ["بالشهر \(Fmt.money(spent / Double(months)))", "\(logs.filter { $0.entry.cost != nil }.count) عملية"])
                StatCard(title: "المنجز", icon: "checkmark.seal.fill", value: "\(doneCount)",
                         lines: ["دفعات \(logs.filter { $0.entry.kind == .payment }.count)",
                                 "صيانة وتصليح \(logs.filter { $0.entry.kind == .maintenance || $0.entry.kind == .repair }.count)"])
            }
            HStack(spacing: 12) {
                StatCard(title: "أشيائي", icon: "square.stack.fill", value: "\(active.count)",
                         lines: ["أنواع \(Set(active.map { $0.category }).count)",
                                 "متأخرة \(store.active(.overdue).count)"])
                StatCard(title: "الوثائق والضمانات", icon: "checkmark.shield.fill", value: "\(docs.valid) سارية",
                         lines: ["تنتهي قريب \(docs.soon)", "منتهية \(docs.expired)"])
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("الجاي خلال 30 يوم", systemImage: "calendar.badge.clock").font(.headline).foregroundColor(Theme.ink)
                Text(next30.isEmpty ? "ما فيه شي" : "\(next30.count) شي" + (expected > 0 ? " · متوقع تدفع \(Fmt.money(expected))" : ""))
                    .font(.subheadline).foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            MonthlyChart(logs: logs, start: periodStart, months: min(months, 12))
        }
    }

    // MARK: Spending

    private var spending: some View {
        let byCategory = Dictionary(grouping: logs.filter { $0.entry.cost != nil }, by: { $0.item.category })
            .map { (cat: $0.key, total: $0.value.compactMap { $0.entry.cost }.reduce(0, +)) }
            .sorted { $0.total > $1.total }
        let top = byCategory.first?.total ?? 1
        return VStack(spacing: 12) {
            MonthlyChart(logs: logs, start: periodStart, months: min(months, 12))
            VStack(alignment: .leading, spacing: 12) {
                Text("حسب النوع").font(.headline).foregroundColor(Theme.ink)
                if byCategory.isEmpty {
                    Text("ما فيه مصاريف مسجّلة بالفترة. لما تعلّم دفعة أو تجديد «تم» وله مبلغ، أو تضيف مصروف من صفحة العنصر، يطلع هنا.")
                        .font(.subheadline).foregroundColor(Theme.muted)
                }
                ForEach(byCategory, id: \.cat) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(row.cat.title, systemImage: row.cat.icon).foregroundColor(Theme.ink)
                            Spacer()
                            Text(Fmt.money(row.total)).bold().foregroundColor(Theme.ink)
                        }
                        .font(.subheadline)
                        GeometryReader { g in
                            Capsule().fill(row.cat.color.opacity(0.8))
                                .frame(width: max(6, g.size.width * CGFloat(row.total / top)))
                        }
                        .frame(height: 6)
                    }
                }
            }
            .card()
            if !logs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("السجل").font(.headline).foregroundColor(Theme.ink)
                    ForEach(logs.prefix(30), id: \.entry.id) { row in
                        HStack(spacing: 10) {
                            Tile(icon: row.entry.kind.icon, color: row.item.category.color, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.item.title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.ink).lineLimit(1)
                                Text("\(row.entry.kind.title) · \(Fmt.dateText(row.entry.date, hasTime: false))")
                                    .font(.caption).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            if let c = row.entry.cost { Text(Fmt.money(c)).font(.subheadline.bold()).foregroundColor(Theme.ink) }
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: Documents

    private var documentStatus: (valid: Int, soon: Int, expired: Int) {
        let docs = store.items.filter { !$0.isDone && ($0.category == .document || $0.category == .warranty) }
        let today = Fmt.greg.startOfDay(for: Date())
        let soonLimit = today.addingTimeInterval(30 * 86400)
        let expired = docs.filter { $0.date < today }.count
        let soon = docs.filter { $0.date >= today && $0.date <= soonLimit }.count
        return (docs.count - expired - soon, soon, expired)
    }

    private var documents: some View {
        let docs = store.items.filter { !$0.isDone && ($0.category == .document || $0.category == .warranty) }
            .sorted { $0.date < $1.date }
        let s = documentStatus
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "سارية", icon: "checkmark.circle.fill", value: "\(s.valid)", lines: [], tint: .green)
                StatCard(title: "تنتهي قريب", icon: "clock.fill", value: "\(s.soon)", lines: [], tint: .orange)
                StatCard(title: "منتهية", icon: "xmark.octagon.fill", value: "\(s.expired)", lines: [], tint: .red)
            }
            if docs.isEmpty {
                EmptyStateView(icon: "doc.text", title: "ما فيه وثائق", message: "أضف الاستمارة، الرخصة، الهوية، الجواز، أو ضمان جهاز.")
                    .card()
            }
            ForEach(docs) { ItemCard(item: $0) }
        }
    }

    // MARK: Medicines

    private var medicines: some View {
        let meds = store.items.filter { $0.isMedicine }
        return VStack(spacing: 12) {
            if meds.isEmpty {
                EmptyStateView(icon: "pills", title: "ما فيه أدوية", message: "أضف دواء من ➕ وحدد أوقات الجرعات.")
                    .card()
            }
            ForEach(meds) { m in
                let week = m.adherence(days: 7)
                let month = m.adherence(days: 30)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Tile(icon: m.displayIcon, color: .red, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.headline).foregroundColor(Theme.ink)
                            Text(m.isDone ? "متوقف" : m.doseTimesLabel).font(.caption).foregroundColor(Theme.muted)
                        }
                    }
                    adherenceBar("آخر 7 أيام", week)
                    adherenceBar("آخر 30 يوم", month)
                }
                .card()
            }
        }
    }

    private func adherenceBar(_ title: String, _ a: (taken: Int, due: Int)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundColor(Theme.muted)
                Spacer()
                Text(a.due == 0 ? "—" : "\(a.taken) من \(a.due) (\(Int((Double(a.taken) / Double(a.due) * 100).rounded()))٪)")
                    .font(.subheadline.bold()).foregroundColor(Theme.ink)
            }
            ProgressView(value: Double(a.taken), total: Double(max(1, a.due)))
                .tint(a.due > 0 && Double(a.taken) / Double(a.due) < 0.8 ? .orange : .green)
        }
    }
}

struct StatCard: View {
    let title: String
    let icon: String
    let value: String
    let lines: [String]
    var tint: Color = .brand

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundColor(tint)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(0.12)))
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.muted).lineLimit(1)
            }
            Text(value).font(.title2.bold()).foregroundColor(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
            if !lines.isEmpty {
                Divider()
                ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundColor(Theme.muted).lineLimit(1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

/// Spending per month as simple bars (works on iOS 15, no Charts framework needed).
struct MonthlyChart: View {
    let logs: [(item: Item, entry: LogEntry)]
    let start: Date
    let months: Int

    private var buckets: [(label: String, total: Double)] {
        let cal = Fmt.greg
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Fmt.locale
        f.dateFormat = "MMM"
        let firstShown = cal.date(byAdding: .month, value: -(months - 1),
                                  to: cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()) ?? start
        return (0..<months).map { i in
            let m = cal.date(byAdding: .month, value: i, to: firstShown) ?? firstShown
            let next = cal.date(byAdding: .month, value: 1, to: m) ?? m
            let total = logs.filter { $0.entry.date >= m && $0.entry.date < next }.compactMap { $0.entry.cost }.reduce(0, +)
            return (f.string(from: m), total)
        }
    }

    var body: some View {
        let data = buckets
        let top = max(1, data.map { $0.total }.max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("الصرف بالشهر", systemImage: "chart.bar.fill").font(.headline).foregroundColor(Theme.ink)
                Spacer()
            }
            if data.allSatisfy({ $0.total == 0 }) {
                Text("ما فيه صرف بالفترة.").font(.subheadline).foregroundColor(Theme.muted)
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, b in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(b.total > 0 ? Color.brand : Theme.border)
                                .frame(height: max(4, CGFloat(b.total / top) * 120))
                            Text(b.label).font(.system(size: 9)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 140, alignment: .bottom)
            }
        }
        .card()
    }
}
