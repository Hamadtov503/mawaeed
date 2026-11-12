import SwiftUI

/// مواعيدي: search, a centred plus, then «مواعيدك القادمة» and «مواعيدك السابقة»
/// (each only once it has something in it). Swiping right-to-left goes back home.
struct AppointmentsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @State private var query = ""

    private func matches(_ a: Appointment) -> Bool {
        query.isEmpty || a.title.localizedCaseInsensitiveContains(query)
            || a.location.localizedCaseInsensitiveContains(query) || a.notes.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let upcoming = store.upcoming().filter(matches)
        let past = store.past().filter(matches)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("مواعيدي", "Appointments")).font(.app(size: 26, .bold)).foregroundColor(Theme.ink).padding(.top, 2)
                SearchField(prompt: L("ابحث بالعنوان أو المكان", "Search by title or place"), text: $query)
                AddButton(label: L("موعد جديد", "New appointment"), hint: L("اضغط على علامة + لإضافة مواعيدك", "Tap + to add your appointments"), id: "addAppointment") { router.addingAppointment = true }

                if !upcoming.isEmpty {
                    BandHeader(title: L("مواعيدك القادمة", "Your upcoming appointments"), count: upcoming.count, color: Theme.navy)
                    ForEach(upcoming) { AppointmentCard(item: $0, showDate: true) }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !past.isEmpty {
                    BandHeader(title: L("مواعيدك السابقة", "Your past appointments"), count: past.count, color: Theme.slate)
                    ForEach(past) { AppointmentCard(item: $0, showDate: true) }
                        .transition(.opacity)
                }
                if upcoming.isEmpty && past.isEmpty && !query.isEmpty {
                    Text(L("ما فيه نتائج لـ«\(query)»", "No results for “\(query)”")).font(.app(.subheadline)).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
            .animation(Router.soft, value: upcoming.map(\.id))
            .animation(Router.soft, value: past.map(\.id))
        }
        .background(Theme.background.ignoresSafeArea())
        .swipeBackHome()
    }
}

/// The search bar used on the appointments and tasks pages.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
            TextField(prompt, text: $text).font(.app(.body))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .card(padding: 12, radius: 18)
    }
}

/// A box under the search bar: a green plus with a short hint beneath it. The whole box is tappable.
struct AddButton: View {
    let label: String
    let hint: String
    var id = "add"
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            action()
        }) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Theme.forest))
                    .shadow(color: Theme.forest.opacity(0.3), radius: 8, y: 4)
                Text(hint)
                    .font(.app(.subheadline, .medium))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.forest.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// A band-like section title: «مواعيدك القادمة», «مهامك المنجزة»…
struct BandHeader: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.app(.subheadline, .bold)).foregroundColor(.white)
            Spacer()
            Text("\(count)").font(.app(.caption, .bold)).foregroundColor(color)
                .frame(minWidth: 22, minHeight: 22)
                .background(Circle().fill(Color.white))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color))
        .padding(.top, 6)
    }
}

extension View {
    /// A right-to-left swipe (finger moving toward the left of the screen) goes back to the home page.
    /// Measured in global coordinates so the right-to-left layout does not flip it.
    func swipeBackHome() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    if dx < -80 && abs(dy) < abs(dx) * 0.6 { Router.shared.go(.home) }
                }
        )
    }
}
