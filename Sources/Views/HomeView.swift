import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var sync: SyncManager

    private let laterLimit = 6

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    dashboardHeader

                    HStack(spacing: 10) {
                        NavigationLink(destination: CategoryItemsView(category: .appointment)) {
                            shortcut("مواعيدي", "calendar", .blue)
                        }
                        NavigationLink(destination: CategoryItemsView(category: .task)) {
                            shortcut("مهامي", "checklist", .brand)
                        }
                        Button { router.tab = 2 } label: {
                            shortcut("ممتلكاتي", "car.fill", .orange)
                        }
                    }.buttonStyle(.plain)

                    SummaryRow()

                    let doses = store.doses()
                    if !doses.isEmpty {
                        SectionBlock(title: "أدوية اليوم", icon: "pills.fill", color: .red,
                                     count: doses.filter { !$0.taken }.count) {
                            VStack(spacing: 4) {
                                ForEach(doses) { d in
                                    DoseRow(dose: d)
                                    if d.id != doses.last?.id { Divider() }
                                }
                            }
                            .card(padding: 14)
                        }
                    }

                    group(.overdue, "متأخرة", "exclamationmark.triangle.fill")
                    group(.today, "اليوم", "sun.max.fill")
                    group(.week, "خلال أسبوع", "calendar")
                    group(.month, "خلال شهر", "calendar.circle")
                    laterSection

                    if store.activeSorted.isEmpty {
                        EmptyStateView(icon: "calendar.badge.plus",
                                       title: "ما عندك شي مسجّل",
                                       message: "اضغط ➕ تحت وسجّل موعد، دواء، اختبار، قسط، أو انتهاء استمارة… وأنا أذكّرك قبلها.")
                            .card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("مواعيدي")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if sync.isOn {
                        Image(systemName: sync.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                            .foregroundColor(sync.lastError == nil ? .brand : .orange)
                    }
                }
            }
            .refreshable {
                store.refresh()
                SyncManager.shared.sync()
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func group(_ u: Urgency, _ title: String, _ icon: String) -> some View {
        let list = store.active(u)
        if !list.isEmpty {
            SectionBlock(title: title, icon: icon, color: Theme.pill(u).fg, count: list.count) {
                VStack(spacing: 10) { ForEach(list) { ItemCard(item: $0) } }
            }
        }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(greeting).font(.caption).foregroundColor(.white.opacity(0.8))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("يومك أوضح،\nوبالك أهدأ.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("كل ما يحتاج انتباهك، تلقاه هنا.").font(.subheadline)
                }
                Spacer(minLength: 0)
                Image(systemName: "calendar.badge.clock").font(.system(size: 42, weight: .light))
                    .padding(14).background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.12)))
            }
            .foregroundColor(.white)
            HStack(spacing: 8) {
                Circle().fill(Color.white.opacity(0.9)).frame(width: 7, height: 7)
                Text(store.badgeCount == 0 ? "كل شيء تحت المتابعة" : "عندك \(store.badgeCount) تنبيه يحتاج متابعة")
                    .font(.caption.bold()).foregroundColor(.white)
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.08, green: 0.26, blue: 0.23), Color(red: 0.12, green: 0.39, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func shortcut(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 10) {
            Tile(icon: icon, color: color, size: 40)
            Text(title).font(.caption.bold()).foregroundColor(Theme.ink)
        }.frame(maxWidth: .infinity).card(padding: 14)
    }

    @ViewBuilder
    private var laterSection: some View {
        let list = store.active(.later)
        if !list.isEmpty {
            SectionBlock(title: "لاحقاً", icon: "clock", color: Theme.muted, count: list.count) {
                VStack(spacing: 10) {
                    ForEach(list.prefix(laterLimit)) { ItemCard(item: $0) }
                    if list.count > laterLimit {
                        Button { router.tab = 1 } label: {
                            Text("عرض الكل (\(list.count))")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .card(padding: 0)
                    }
                }
            }
        }
    }

    private var greeting: String {
        let h = Fmt.greg.component(.hour, from: Date())
        let g = h < 12 ? "صباح الخير ☀️" : "مساء الخير 🌙"
        return "\(g)  ·  \(Fmt.dateText(Date(), hasTime: false, long: true))  ·  \(Fmt.hijriText(Date()))"
    }
}

struct CategoryItemsView: View {
    let category: Category
    @EnvironmentObject private var store: Store
    var body: some View {
        ScrollView {
            let items = store.activeSorted.filter { $0.category == category }
            VStack(spacing: 12) {
                if items.isEmpty {
                    EmptyStateView(icon: category.icon, title: "ما فيه عناصر معلّقة", message: "أضف من زر + أسفل الشاشة.").card()
                }
                ForEach(items) { ItemCard(item: $0) }
            }.padding(16)
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle(category == .task ? "مهامي" : "مواعيدي")
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).foregroundColor(Theme.ink)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.12)))
            }
            .font(.headline)
            .padding(.horizontal, 4)
            content()
        }
    }
}

struct SummaryRow: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let overdue = store.active(.overdue).count
        let today = store.active(.today).count
        let week = store.active(.week).count
        let monthly = store.monthlyTotal
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                stat("متأخرة", overdue, "exclamationmark.triangle.fill", overdue > 0 ? .red : Theme.muted)
                stat("اليوم", today, "sun.max.fill", .orange)
                stat("هالأسبوع", week, "calendar", .brand)
            }
            if monthly > 0 {
                HStack(spacing: 10) {
                    Tile(icon: "creditcard.fill", color: .purple, size: 34)
                    Text("التزاماتك الشهرية تقريباً").font(.subheadline).foregroundColor(Theme.ink)
                    Spacer()
                    Text(Fmt.money(monthly)).font(.subheadline.bold()).foregroundColor(Theme.ink)
                }
                .card(padding: 12)
            }
        }
    }

    private func stat(_ title: String, _ value: Int, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text("\(value)").font(.title.bold()).monospacedDigit().foregroundColor(Theme.ink)
            Text(title).font(.caption).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}


