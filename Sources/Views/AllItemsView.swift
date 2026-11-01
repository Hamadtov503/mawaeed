import SwiftUI

struct AllItemsView: View {
    @EnvironmentObject var store: Store
    @State private var filter: Category? = nil
    @State private var showDone = false
    @State private var query = ""
    @State private var showAdd = false

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
        NavigationView {
            List {
                Section {
                    Picker("", selection: $showDone) {
                        Text("النشطة").tag(false)
                        Text("المنجزة").tag(true)
                    }
                    .pickerStyle(.segmented)
                    chips
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)

                if list.isEmpty {
                    EmptyStateView(icon: showDone ? "checkmark.seal" : "tray",
                                   title: showDone ? "ما فيه شي منجز" : "ما فيه شي هنا",
                                   message: query.isEmpty ? "" : "جرّب كلمة بحث ثانية")
                        .listRowBackground(Color.clear)
                } else if showDone {
                    Section { ForEach(list) { ItemLink(item: $0) } }
                } else {
                    ForEach(monthGroups, id: \.0) { group in
                        Section(header: Text(group.0).font(.subheadline.bold())) {
                            ForEach(group.1) { ItemLink(item: $0) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "ابحث")
            .navigationTitle("الكل")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFlowView(isPresented: $showAdd)
                    .environmentObject(store)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Fmt.locale)
                    .environment(\.calendar, Fmt.greg)
            }
        }
        .navigationViewStyle(.stack)
    }

    /// Active items grouped by month ("متأخرة" first).
    private var monthGroups: [(String, [Item])] {
        let f = DateFormatter()
        f.calendar = Fmt.greg
        f.locale = Fmt.locale
        f.dateFormat = "MMMM y"
        var groups: [(String, [Item])] = []
        let today = Fmt.greg.startOfDay(for: Date())
        for it in list {
            let key = it.date < today ? "متأخرة" : f.string(from: it.date)
            if let i = groups.firstIndex(where: { $0.0 == key }) { groups[i].1.append(it) } else { groups.append((key, [it])) }
        }
        return groups
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "الكل", "square.grid.2x2.fill", .brand)
                ForEach(Category.allCases) { c in
                    chip(c, c.title, c.icon, c.color)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(_ c: Category?, _ title: String, _ icon: String, _ color: Color) -> some View {
        let selected = filter == c
        return Button {
            withAnimation { filter = c }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? color : color.opacity(0.12)))
                .foregroundColor(selected ? .white : color)
        }
        .buttonStyle(.plain)
    }
}
