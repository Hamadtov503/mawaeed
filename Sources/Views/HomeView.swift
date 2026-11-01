import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var showAdd = false

    private let laterLimit = 8

    var body: some View {
        NavigationView {
            List {
                Section {
                    SummaryCards(showAdd: $showAdd)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if store.activeSorted.isEmpty {
                    Section {
                        EmptyStateView(icon: "calendar.badge.plus",
                                       title: "ما عندك شي مسجّل",
                                       message: "اضغط + وسجّل أول موعد، أو انتهاء استمارة، أو باقة، أو ضمان… وأنا أذكّرك قبلها.")
                    }
                }

                group(.overdue, "متأخرة", "exclamationmark.triangle.fill")
                group(.today, "اليوم", "sun.max.fill")
                group(.week, "خلال أسبوع", "calendar")
                group(.month, "خلال شهر", "calendar.circle")
                laterSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("مواعيدي")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("إضافة")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFlowView(isPresented: $showAdd)
                    .environmentObject(store)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Fmt.locale)
                    .environment(\.calendar, Fmt.greg)
            }
            .refreshable { store.refresh() }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func group(_ u: Urgency, _ title: String, _ icon: String) -> some View {
        let list = store.active(u)
        if !list.isEmpty {
            Section(header: SectionTitle(title: title, icon: icon, color: u.color, count: list.count)) {
                ForEach(list) { ItemLink(item: $0) }
            }
        }
    }

    @ViewBuilder
    private var laterSection: some View {
        let list = store.active(.later)
        if !list.isEmpty {
            Section(header: SectionTitle(title: "لاحقاً", icon: "clock", color: .secondary, count: list.count)) {
                ForEach(list.prefix(laterLimit)) { ItemLink(item: $0) }
                if list.count > laterLimit {
                    Button("عرض الكل (\(list.count))") { router.tab = 1 }
                }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(title).foregroundColor(color)
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(color.opacity(0.15)))
                .foregroundColor(color)
        }
        .font(.subheadline.weight(.bold))
        .textCase(nil)
    }
}

struct SummaryCards: View {
    @EnvironmentObject var store: Store
    @Binding var showAdd: Bool

    var body: some View {
        let overdue = store.active(.overdue).count
        let today = store.active(.today).count
        let week = store.active(.week).count
        let monthly = store.monthlyTotal
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            HStack(spacing: 10) {
                card("متأخرة", "\(overdue)", "exclamationmark.triangle.fill", overdue > 0 ? .red : .gray)
                card("اليوم", "\(today)", "sun.max.fill", .orange)
                card("هالأسبوع", "\(week)", "calendar", .blue)
            }
            if monthly > 0 {
                HStack {
                    Image(systemName: "creditcard.fill").foregroundColor(.purple)
                    Text("اشتراكاتك وفواتيرك تقريباً")
                    Spacer()
                    Text(Fmt.money(monthly) + " / شهر").bold()
                }
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
        }
        .padding(.vertical, 6)
    }

    private var greeting: String {
        let h = Fmt.greg.component(.hour, from: Date())
        let g = h < 12 ? "صباح الخير ☀️" : (h < 18 ? "مساء الخير 🌤️" : "مساء الخير 🌙")
        return "\(g)  •  \(Fmt.dateText(Date(), hasTime: false, long: true))  •  \(Fmt.hijriText(Date()))"
    }

    private func card(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
