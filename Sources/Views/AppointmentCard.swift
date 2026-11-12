import SwiftUI

/// A card: icon tile, the title with its countdown on the same line, and the time and place under it. Tapping opens the details sheet.
struct AppointmentCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let item: Appointment
    var showDate = false

    var body: some View {
        let status = item.status()
        Button { router.openID = AppointmentRef(id: item.id) } label: {
            HStack(spacing: 12) {
                Tile(icon: item.displayIcon, color: status == .past ? Theme.muted : .brand, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    // The countdown sits on the title's line (on the far side) to keep the card short.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title.isEmpty ? L("بدون عنوان", "Untitled") : item.title)
                            .font(.app(.headline))
                            .foregroundColor(status == .past ? Theme.muted : Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        StatusPill(text: Fmt.countdown(to: item.date, hasTime: item.hasTime), status: status)
                            .fixedSize()
                    }
                    Text(showDate ? Fmt.joined([Fmt.dateText(item.date, hasTime: false), item.subtitle]) : item.subtitle)
                        .font(.app(.subheadline)).foregroundColor(Theme.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.duplicate(item.id) } label: { Label(L("نسخة مكررة", "Duplicate"), systemImage: "plus.square.on.square") }
            Button(role: .destructive) { withAnimation { store.delete(item.id) } } label: {
                Label(L("حذف", "Delete"), systemImage: "trash")
            }
        }
    }
}
