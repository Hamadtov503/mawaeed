import SwiftUI

struct AllItemsView: View {
    @EnvironmentObject var store: Store
    @State private var filter: Category? = nil
    @State private var showDone = false
    @State private var query = ""

    private var list: [Item] {
        let base = showDone ? store.doneSorted : store.activeSorted
        return base.filter { it in
            (filter == nil || it.category == filter)
                && (query.isEmpty
                    || it.title.localizedCaseInsensitiveContains(query)
                    || it.notes.localizedCaseInsensitiveContains(query)
                    || it.location.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        AppNavigation {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(subtitle).font(.subheadline).foregroundColor(Theme.muted)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                        TextField("ابحث", text: $query)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                                .buttonStyle(.plain)
                        }
                    }
                    .card(padding: 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(title: "الكل", selected: filter == nil && !showDone) { withAnimation { filter = nil; showDone = false } }
                            ForEach(usedCategories) { c in
                                Chip(title: c.title, icon: c.icon, selected: filter == c) { withAnimation { filter = filter == c ? nil : c } }
                            }
                            Chip(title: "المنجزة", icon: "checkmark", selected: showDone) { withAnimation { showDone.toggle() } }
                        }
                        .padding(.vertical, 2)
                    }

                    if list.isEmpty {
                        EmptyStateView(icon: showDone ? "checkmark.seal" : "tray",
                                       title: showDone ? "ما فيه شي منجز" : "ما فيه شي هنا",
                                       message: query.isEmpty ? "اضغط ➕ تحت وأضف." : "جرّب كلمة بحث ثانية")
                            .card()
                    } else if showDone {
                        VStack(spacing: 10) { ForEach(list) { ItemCard(item: $0) } }
                    } else {
                        ForEach(monthGroups, id: \.0) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.0).font(.headline).foregroundColor(Theme.ink).padding(.horizontal, 4)
                                ForEach(group.1) { ItemCard(item: $0) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("أشيائي")
        }
        .navigationViewStyle(.stack)
    }

    private var subtitle: String {
        let n = store.items.filter { !$0.isDone }.count
        return n == 0 ? "ما فيه شي مسجّل" : "مسجّل \(n) · منجز \(store.items.count - n)"
    }

    private var usedCategories: [Category] {
        let used = Set(store.items.map { $0.category })
        return Category.allCases.filter { used.contains($0) }
    }

    /// Active items grouped by month; medicines and overdue first.
    private var monthGroups: [(String, [Item])] {
        let f = DateFormatter()
        f.calendar = Fmt.greg
        f.locale = Fmt.locale
        f.dateFormat = "MMMM y"
        var groups: [(String, [Item])] = []
        let today = Fmt.greg.startOfDay(for: Date())
        for it in list {
            let key = it.isMedicine ? "💊 الأدوية" : (it.date < today ? "متأخرة" : f.string(from: it.date))
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(it) } else { groups.append((key, [it])) }
        }
        let order: (String) -> Int = { $0 == "💊 الأدوية" ? 0 : ($0 == "متأخرة" ? 1 : 2) }
        return groups.enumerated().sorted { a, b in
            (order(a.element.0), a.offset) < (order(b.element.0), b.offset)
        }.map { $0.element }
    }
}
