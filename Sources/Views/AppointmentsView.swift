import SwiftUI

/// All appointments: upcoming grouped by day, past ones, or a calendar to pick a day.
struct AppointmentsView: View {
    @EnvironmentObject var store: Store
    @State private var mode: Mode = .upcoming
    @State private var day = Date()
    @State private var query = ""

    enum Mode: String, CaseIterable, Identifiable {
        case upcoming = "القادمة", calendar = "التقويم", past = "السابقة"
        var id: Self { self }
    }

    private func matches(_ a: Appointment) -> Bool {
        query.isEmpty || a.title.localizedCaseInsensitiveContains(query)
            || a.location.localizedCaseInsensitiveContains(query) || a.notes.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("مواعيدي").font(.system(size: 32, weight: .bold)).foregroundColor(Theme.ink)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                    TextField("ابحث بالعنوان أو المكان", text: $query)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                            .buttonStyle(.plain)
                    }
                }
                .card(padding: 12, radius: 18)

                HStack(spacing: 8) {
                    ForEach(Mode.allCases) { m in
                        Chip(title: m.rawValue, selected: mode == m) { withAnimation { mode = m } }
                    }
                }

                switch mode {
                case .upcoming: grouped(store.upcoming().filter(matches), empty: "ما عندك مواعيد جاية")
                case .past: grouped(store.past().filter(matches), empty: "ما فيه مواعيد سابقة")
                case .calendar: calendar
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func grouped(_ list: [Appointment], empty: String) -> some View {
        if list.isEmpty {
            EmptyState(icon: "calendar", title: empty, message: query.isEmpty ? "اضغط ➕ تحت وأضف موعد." : "جرّب كلمة بحث ثانية").card()
        } else {
            ForEach(groups(list), id: \.0) { g in
                SectionHeader(title: g.0, detail: "\(g.1.count)")
                ForEach(g.1) { AppointmentCard(item: $0) }
            }
        }
    }

    private func groups(_ list: [Appointment]) -> [(String, [Appointment])] {
        var out: [(String, [Appointment])] = []
        for a in list {
            let key = Fmt.dayTitle(a.date)
            if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1.append(a) } else { out.append((key, [a])) }
        }
        return out
    }

    private var calendar: some View {
        let list = store.on(day: day).filter(matches)
        return VStack(alignment: .leading, spacing: 14) {
            DatePicker("اختر اليوم", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .card(padding: 10)
            SectionHeader(title: Fmt.dayTitle(day), detail: Fmt.hijriText(day))
            if list.isEmpty {
                EmptyState(icon: "calendar", title: "ما فيه مواعيد بهاليوم", message: "").card()
            }
            ForEach(list) { AppointmentCard(item: $0) }
        }
    }
}
