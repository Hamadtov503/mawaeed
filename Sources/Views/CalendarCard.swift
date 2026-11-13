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
    private let weekdays = [L("أحد", "Sun"), L("إثنين", "Mon"), L("ثلاثاء", "Tue"), L("أربعاء", "Wed"), L("خميس", "Thu"), L("جمعة", "Fri"), L("سبت", "Sat")]

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
        VStack(alignment: .leading, spacing: 10) {
            header
            grid
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button { goToToday() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Fmt.hijriMonth.string(from: firstDay)) \(Fmt.num(year))")
                        .font(.app(size: 19, .bold))
                        .foregroundColor(Theme.burgundy)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 11)).foregroundColor(Theme.forest)
                        Text(gregorianSpan).font(.app(.caption)).foregroundColor(Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cal.title")
            Spacer()
            // Back to today (the month arrows sit on the calendar's sides).
            Button { goToToday() } label: {
                Text(L("اليوم", "Today"))
                    .font(.app(.footnote, .semibold))
                    .foregroundColor(Theme.burgundy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.burgundy.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cal.today")
        }
    }

    /// The month arrows, half outside the calendar, at the middle of its sides: the previous month on
    /// the right and the next on the left in Arabic (the other way round in English).
    private var sideArrows: some View {
        let prevOnRight = Fmt.isArabic
        return HStack {
            arrow("chevron.left", id: prevOnRight ? "cal.next" : "cal.prev") { shift(prevOnRight ? 1 : -1) }
            Spacer()
            arrow("chevron.right", id: prevOnRight ? "cal.prev" : "cal.next") { shift(prevOnRight ? -1 : 1) }
        }
        .padding(.horizontal, -13)
        .environment(\.layoutDirection, .leftToRight)   // pinned to the screen's sides
    }

    private func arrow(_ icon: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.burgundy)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .frame(width: 40, height: 52)          // a bigger area to tap
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var grid: some View {
        let all = cells
        let rows = stride(from: 0, to: all.count, by: 7).map { Array(all[$0..<min($0 + 7, all.count)]) }
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.app(size: 10, .semibold)).foregroundColor(Theme.burgundy.opacity(0.85))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 5)
            .background(Theme.sand)

            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(rows[r]) { cell in dayCell(cell) }
                    }
                    .background(r % 2 == 0 ? Theme.card.opacity(0.55) : Theme.card)
                }
            }
            .id("\(year)-\(month)")
            .transition(.asymmetric(insertion: .move(edge: direction).combined(with: .opacity),
                                    removal: .opacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .overlay(sideArrows)
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
            VStack(spacing: -2) {
                Text("\(cell.hijriDay)")
                    .font(.app(size: 15, .bold))
                    .foregroundColor(cell.inMonth ? (isToday ? Theme.navy : Theme.ink) : Theme.muted.opacity(0.7))
                Text("\(cell.gregDay)")
                    .font(.app(size: 9.5))
                    .foregroundColor(cell.inMonth ? Theme.muted : Theme.muted.opacity(0.6))
                Circle()
                    .fill(busy ? Theme.forest : Color.clear)
                    .frame(width: 4, height: 4)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(
                Circle()
                    .fill(isSelected ? Theme.sand : Color.clear)
                    .frame(width: 36, height: 36)
            )
            .overlay(
                Circle()
                    .stroke(isToday ? Theme.burgundy : (isSelected ? Theme.border : Color.clear), lineWidth: isToday ? 1.5 : 1)
                    .frame(width: 36, height: 36)
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
