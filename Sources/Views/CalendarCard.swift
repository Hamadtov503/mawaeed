import SwiftUI

/// A Hijri month (Umm al-Qura) with the Gregorian day under each Hijri day, a dot on days that
/// have appointments or tasks, today framed, and the selected day highlighted.
struct CalendarCard: View {
    @EnvironmentObject var store: Store
    @Binding var selection: Date
    @State private var year: Int
    @State private var month: Int
    @State private var direction: Edge = .leading

    private let hc = Fmt.hijriCalendar
    private let weekdays = ["أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]

    init(selection: Binding<Date>) {
        _selection = selection
        let c = Fmt.hijriCalendar.dateComponents([.year, .month], from: selection.wrappedValue)
        _year = State(initialValue: c.year ?? 1448)
        _month = State(initialValue: c.month ?? 1)
    }

    private struct Cell: Identifiable {
        let date: Date
        let hijriDay: Int
        let gregDay: Int
        let inMonth: Bool
        var id: Date { date }
    }

    private var firstDay: Date {
        hc.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private var cells: [Cell] {
        let first = firstDay
        let days = hc.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = Fmt.greg.component(.weekday, from: first) - 1          // Sunday = 0
        let rows = Int(ceil(Double(lead + days) / 7))
        return (0..<(rows * 7)).compactMap { i in
            guard let d = Fmt.greg.date(byAdding: .day, value: i - lead, to: Fmt.greg.startOfDay(for: first)) else { return nil }
            return Cell(date: d,
                        hijriDay: hc.component(.day, from: d),
                        gregDay: Fmt.greg.component(.day, from: d),
                        inMonth: hc.component(.month, from: d) == month)
        }
    }

    private var gregorianSpan: String {
        let inMonth = cells.filter { $0.inMonth }
        guard let a = inMonth.first?.date, let b = inMonth.last?.date else { return "" }
        let m = Fmt.formatter("MMMM"), my = Fmt.formatter("MMMM y")
        if Fmt.greg.isDate(a, equalTo: b, toGranularity: .month) { return my.string(from: a) }
        if Fmt.greg.isDate(a, equalTo: b, toGranularity: .year) { return "\(m.string(from: a)) – \(my.string(from: b))" }
        return "\(my.string(from: a)) – \(my.string(from: b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            grid
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button { goToToday() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Fmt.hijriMonth.string(from: firstDay)) \(String(year))")
                        .font(.app(size: 26, .bold))
                        .foregroundColor(Theme.burgundy)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 14)).foregroundColor(Theme.forest)
                        Text(gregorianSpan).font(.app(.subheadline)).foregroundColor(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 10) {
                arrow("chevron.backward") { shift(-1) }
                arrow("chevron.forward") { shift(1) }
            }
        }
    }

    private func arrow(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.ink)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let all = cells
        let rows = stride(from: 0, to: all.count, by: 7).map { Array(all[$0..<min($0 + 7, all.count)]) }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.app(.caption, .semibold)).foregroundColor(Theme.burgundy.opacity(0.85))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .background(Theme.sand)

            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r]) { cell in dayCell(cell) }
                    }
                    .padding(.vertical, 4)
                    .background(r % 2 == 0 ? Theme.card.opacity(0.55) : Theme.card)
                }
            }
            .id("\(year)-\(month)")
            .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                    removal: .opacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 25).onEnded { v in
            guard abs(v.translation.width) > abs(v.translation.height), abs(v.translation.width) > 50 else { return }
            // Right-to-left: swiping right goes forward in time, left goes back.
            shift(v.translation.width > 0 ? 1 : -1)
        })
    }

    private func dayCell(_ cell: Cell) -> some View {
        let isToday = Fmt.greg.isDateInToday(cell.date)
        let isSelected = Fmt.greg.isDate(cell.date, inSameDayAs: selection)
        let busy = store.hasAnything(on: cell.date)
        return Button {
            withAnimation(Router.soft) {
                selection = cell.date
                if !cell.inMonth { jump(to: cell.date) }
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(cell.hijriDay)")
                    .font(.app(size: 19, .bold))
                    .foregroundColor(cell.inMonth ? (isToday ? Theme.burgundy : Theme.ink) : Theme.muted.opacity(0.7))
                Text("\(cell.gregDay)")
                    .font(.app(size: 12))
                    .foregroundColor(cell.inMonth ? Theme.muted : Theme.muted.opacity(0.6))
                Circle()
                    .fill(busy ? Theme.forest : Color.clear)
                    .frame(width: 6, height: 6)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.sand : Color.clear)
                    .padding(.horizontal, 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isToday ? Theme.burgundy : (isSelected ? Theme.border : Color.clear), lineWidth: isToday ? 2 : 1)
                    .padding(.horizontal, 3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Navigation

    private func shift(_ by: Int) {
        var m = month + by, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        direction = by > 0 ? .trailing : .leading
        withAnimation(Router.soft) {
            month = m
            year = y
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func jump(to d: Date) {
        let c = hc.dateComponents([.year, .month], from: d)
        let forward = (c.year ?? year, c.month ?? month) > (year, month)
        direction = forward ? .trailing : .leading
        year = c.year ?? year
        month = c.month ?? month
    }

    private func goToToday() {
        withAnimation(Router.soft) {
            jump(to: Date())
            selection = Date()
        }
    }
}
