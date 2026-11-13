import SwiftUI
import PhotosUI

/// A centred card over a dimmed background. Tapping anywhere outside the card closes it.
struct PopupModifier<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    /// nil: centred. Otherwise the card's distance from the top.
    var top: CGFloat? = nil
    /// true: the popup draws its own box (menus), so no card is drawn around it.
    var bare = false
    let popup: () -> Popup

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .zIndex(10)
                popup()
                    .padding(bare ? 0 : 14)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(bare ? Color.clear : Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(bare ? Color.clear : Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(bare ? 0 : 0.18), radius: 24, y: 10)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 460)
                    .padding(.top, top ?? 0)
                    .frame(maxHeight: .infinity, alignment: top == nil ? .center : .top)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(11)
            }
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { isPresented = false }
    }
}

extension View {
    /// Shows `content` as a popup card; an outside tap closes it.
    func popup<P: View>(isPresented: Binding<Bool>, top: CGFloat? = nil, bare: Bool = false, @ViewBuilder content: @escaping () -> P) -> some View {
        modifier(PopupModifier(isPresented: isPresented, top: top, bare: bare, popup: content))
    }
}

/// A row that shows a value and opens a popup when tapped.
struct PickerRow: View {
    let title: String
    let value: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(Theme.burgundy).frame(width: 22)
                Text(title).foregroundColor(Theme.ink)
                Spacer()
                Text(value)
                    .font(.app(.body, .semibold))
                    .foregroundColor(Theme.navy)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.sand))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Calendar popup content, drawn entirely in SwiftUI (the system date picker rendered its
/// numbers mirrored in right-to-left). Hijri or Gregorian; the other calendar's day is shown small
/// under each day. Picking a day closes it right away; the time of day is kept.
struct DayPickerPopup: View {
    @Binding var date: Date
    let hijri: Bool
    let onDone: () -> Void
    @State private var year: Int
    @State private var month: Int

    init(date: Binding<Date>, hijri: Bool, onDone: @escaping () -> Void) {
        _date = date
        self.hijri = hijri
        self.onDone = onDone
        let c = (hijri ? Fmt.hijriCalendar : Fmt.greg).dateComponents([.year, .month], from: date.wrappedValue)
        _year = State(initialValue: c.year ?? 1448)
        _month = State(initialValue: c.month ?? 1)
    }

    private var cal: Calendar { hijri ? Fmt.hijriCalendar : Fmt.greg }
    private var other: Calendar { hijri ? Fmt.greg : Fmt.hijriCalendar }

    private struct Cell: Identifiable {
        let date: Date
        let day: Int
        let otherDay: Int
        let inMonth: Bool
        var id: Date { date }
    }

    private var firstDay: Date {
        cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
    }

    private var cells: [Cell] {
        let first = firstDay
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = Fmt.greg.component(.weekday, from: first) - 1
        let rows = Int(ceil(Double(lead + days) / 7))
        return (0..<(rows * 7)).compactMap { i in
            guard let d = Fmt.greg.date(byAdding: .day, value: i - lead, to: Fmt.greg.startOfDay(for: first)) else { return nil }
            return Cell(date: d, day: cal.component(.day, from: d), otherDay: other.component(.day, from: d),
                        inMonth: cal.component(.month, from: d) == month)
        }
    }

    private var weekdays: [String] {
        [L("أحد", "Sun"), L("إثنين", "Mon"), L("ثلاثاء", "Tue"), L("أربعاء", "Wed"), L("خميس", "Thu"), L("جمعة", "Fri"), L("سبت", "Sat")]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(Fmt.formatter("MMMM", hijri: hijri).string(from: firstDay)) \(Fmt.num(year))")
                    .font(.app(.headline, .bold)).foregroundColor(Theme.burgundy)
                Spacer()
                arrow("chevron.backward") { shift(-1) }
                arrow("chevron.forward") { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(w).font(.app(size: 10, .semibold)).foregroundColor(Theme.muted).frame(maxWidth: .infinity)
                }
            }
            let all = cells
            VStack(spacing: 2) {
                ForEach(Array(stride(from: 0, to: all.count, by: 7)), id: \.self) { start in
                    HStack(spacing: 0) {
                        ForEach(all[start..<min(start + 7, all.count)]) { cell in dayButton(cell) }
                    }
                }
            }
            .id("\(year)-\(month)")
            .transition(.opacity)
        }
    }

    private func dayButton(_ cell: Cell) -> some View {
        let selected = Fmt.greg.isDate(cell.date, inSameDayAs: date)
        let today = Fmt.greg.isDateInToday(cell.date)
        return Button { pick(cell.date) } label: {
            VStack(spacing: 0) {
                Text(Fmt.num(cell.day))
                    .font(.app(size: 15, .bold))
                    .foregroundColor(selected ? .white : (cell.inMonth ? (today ? Theme.navy : Theme.ink) : Theme.muted.opacity(0.5)))
                Text(Fmt.num(cell.otherDay))
                    .font(.app(size: 9))
                    .foregroundColor(selected ? .white.opacity(0.85) : Theme.muted.opacity(cell.inMonth ? 1 : 0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Circle().fill(selected ? Theme.burgundy : Color.clear).frame(width: 38, height: 38))
            .overlay(Circle().stroke(today && !selected ? Theme.burgundy : Color.clear, lineWidth: 1.2).frame(width: 38, height: 38))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("day.\(Fmt.fileStamp.string(from: cell.date))")
    }

    private func arrow(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.ink)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.sand))
        }
        .buttonStyle(.plain)
    }

    private func shift(_ by: Int) {
        var m = month + by, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        withAnimation(.easeInOut(duration: 0.2)) { month = m; year = y }
    }

    private func pick(_ day: Date) {
        let t = Fmt.greg.dateComponents([.hour, .minute], from: date)
        date = Fmt.greg.date(bySettingHour: t.hour ?? 10, minute: t.minute ?? 0, second: 0, of: day) ?? day
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onDone() }
    }
}

/// Time popup content, drawn in SwiftUI: hour, minutes (every 5) and AM/PM, then Done.
struct TimePickerPopup: View {
    @Binding var date: Date
    let onDone: () -> Void

    private var hour24: Int { Fmt.greg.component(.hour, from: date) }
    private var minute: Int { Fmt.greg.component(.minute, from: date) }
    private var isPM: Bool { hour24 >= 12 }
    private var hour12: Int { hour24 % 12 == 0 ? 12 : hour24 % 12 }

    var body: some View {
        VStack(spacing: 14) {
            Text(Fmt.timeText(date))
                .font(.app(size: 30, .bold)).foregroundColor(Theme.burgundy)
                .accessibilityIdentifier("popup.time.value")
            HStack(spacing: 8) {
                choice(L("ص", "AM"), on: !isPM) { set(hour12: hour12, minute: minute, pm: false) }
                choice(L("م", "PM"), on: isPM) { set(hour12: hour12, minute: minute, pm: true) }
            }
            grid(title: L("الساعة", "Hour"), values: Array(1...12), columns: 6, selected: hour12) { h in
                set(hour12: h, minute: minute, pm: isPM)
            }
            grid(title: L("الدقائق", "Minutes"), values: Array(stride(from: 0, to: 60, by: 5)), columns: 6,
                 selected: minute - minute % 5, pad: true) { m in
                set(hour12: hour12, minute: m, pm: isPM)
            }
            Button(action: onDone) {
                Text(L("تم", "Done"))
                    .font(.app(.headline, .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.burgundy))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("popup.done")
        }
    }

    private func set(hour12: Int, minute: Int, pm: Bool) {
        let h = (hour12 % 12) + (pm ? 12 : 0)
        date = Fmt.greg.date(bySettingHour: h, minute: minute, second: 0, of: date) ?? date
    }

    private func choice(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.app(.subheadline, .bold))
                .foregroundColor(on ? .white : Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Capsule().fill(on ? Theme.burgundy : Theme.sand))
        }
        .buttonStyle(.plain)
    }

    private func grid(title: String, values: [Int], columns: Int, selected: Int, pad: Bool = false,
                      action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.app(.caption, .semibold)).foregroundColor(Theme.muted)
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: values.count, by: columns)), id: \.self) { start in
                    HStack(spacing: 6) {
                        ForEach(values[start..<min(start + columns, values.count)], id: \.self) { v in
                            Button { action(v) } label: {
                                Text(pad && v < 10 ? Fmt.num(0) + Fmt.num(v) : Fmt.num(v))
                                    .font(.app(.subheadline, .semibold))
                                    .foregroundColor(v == selected ? .white : Theme.ink)
                                    .frame(maxWidth: .infinity).frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(v == selected ? Theme.navy : Theme.sand))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// Pick one picture from Photos (no photo-library permission needed with PHPicker).
struct PhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.presentationMode) private var presentationMode

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let p = PHPickerViewController(configuration: config)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if let r = results.first, r.itemProvider.canLoadObject(ofClass: UIImage.self) {
                r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage { DispatchQueue.main.async { self.parent.onPick(img) } }
                }
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: Action menus

/// One choice in an `ActionMenu`.
struct MenuAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var destructive = false
    let run: () -> Void
}

/// What a long press or a "delete?" question shows: an optional title and message, then the choices.
struct MenuRequest: Identifiable {
    let id = UUID()
    var title: String? = nil
    var message: String? = nil
    let actions: [MenuAction]

    /// A short notice with one "OK" (replaces an alert).
    static func notice(_ title: String, message: String) -> MenuRequest {
        MenuRequest(title: title, message: message, actions: [MenuAction(title: L("تمام", "OK"), icon: "checkmark") {}])
    }
}

/// A menu drawn by the app (not by iOS), so it always reads in the app's direction: the text on the
/// leading side (right in Arabic) and the icon on the trailing side. Replaces long-press menus,
/// confirmation dialogs and alerts, which iOS drew mirrored.
struct ActionMenu: View {
    let request: MenuRequest
    let onClose: () -> Void

    var body: some View {
        // One box, like an iOS menu: an optional heading, then the choices separated by thin lines.
        VStack(spacing: 0) {
            if request.title != nil || request.message != nil {
                VStack(spacing: 4) {
                    if let t = request.title {
                        Text(t).font(.app(.subheadline, .bold)).foregroundColor(Theme.ink)
                    }
                    if let m = request.message {
                        Text(m).font(.app(.footnote)).foregroundColor(Theme.muted)
                    }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Divider().overlay(Theme.border)
            }
            ForEach(Array(request.actions.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Divider().overlay(Theme.border) }
                Button {
                    onClose()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { a.run() }
                } label: {
                    HStack(spacing: 12) {
                        Text(a.title).font(.app(.body, .semibold))
                        Spacer(minLength: 8)
                        Image(systemName: a.icon).font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(a.destructive ? Theme.burgundy : Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menuAction.\(a.title)")
            }
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}

extension View {
    /// Shows `request` as an app-drawn menu; an outside tap closes it.
    func actionMenu(_ request: Binding<MenuRequest?>, top: CGFloat? = nil) -> some View {
        popup(isPresented: Binding(get: { request.wrappedValue != nil },
                                   set: { if !$0 { request.wrappedValue = nil } }), top: top, bare: true) {
            if let r = request.wrappedValue {
                ActionMenu(request: r) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { request.wrappedValue = nil }
                }
            }
        }
    }

    /// A long press: a light tap of feedback, then `action`.
    func onLongPress(_ action: @escaping () -> Void) -> some View {
        onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { action() }
        }
    }
}
