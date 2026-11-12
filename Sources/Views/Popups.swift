import SwiftUI

/// A centred card over a dimmed background. Tapping anywhere outside the card closes it.
struct PopupModifier<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
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
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 460)
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
    func popup<P: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> P) -> some View {
        modifier(PopupModifier(isPresented: isPresented, popup: content))
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

/// Calendar popup content: picking a day closes it right away; the time of day is kept.
struct DayPickerPopup: View {
    @Binding var date: Date
    let hijri: Bool
    let onDone: () -> Void

    var body: some View {
        DatePicker("", selection: Binding(
            get: { date },
            set: { newDay in
                let cal = Fmt.greg
                let t = cal.dateComponents([.hour, .minute], from: date)
                date = cal.date(bySettingHour: t.hour ?? 10, minute: t.minute ?? 0, second: 0, of: newDay) ?? newDay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onDone() }
            }), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .environment(\.calendar, hijri ? Fmt.hijriCalendar : Fmt.greg)
            .environment(\.locale, hijri ? Fmt.hijriLocale : Fmt.locale)
            .tint(Theme.burgundy)
    }
}

/// Time popup content: a wheel and a Done button (an outside tap also closes it).
struct TimePickerPopup: View {
    @Binding var date: Date
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Fmt.locale)
            Button(action: onDone) {
                Text(L("تم", "Done"))
                    .font(.app(.headline, .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.burgundy))
            }
            .buttonStyle(.plain)
        }
    }
}
