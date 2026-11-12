import SwiftUI

/// A card: icon tile, title, time · place, and a countdown pill. Tapping opens the details sheet.
struct AppointmentCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let item: Appointment
    var showDate = false

    var body: some View {
        let status = item.status()
        Button { router.openID = AppointmentRef(id: item.id) } label: {
            HStack(spacing: 14) {
                Tile(icon: item.displayIcon, color: status == .past ? Theme.muted : .brand)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "بدون عنوان" : item.title)
                        .font(.headline)
                        .foregroundColor(status == .past ? Theme.muted : Theme.ink)
                        .lineLimit(1)
                    Text(showDate ? "\(Fmt.dateText(item.date, hasTime: false)) · \(item.subtitle)" : item.subtitle)
                        .font(.subheadline).foregroundColor(Theme.muted).lineLimit(1)
                    StatusPill(text: Fmt.countdown(to: item.date, hasTime: item.hasTime), status: status)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.duplicate(item.id) } label: { Label("نسخة مكررة", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { withAnimation { store.delete(item.id) } } label: {
                Label("حذف", systemImage: "trash")
            }
        }
    }
}
