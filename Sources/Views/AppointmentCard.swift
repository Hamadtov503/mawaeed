import SwiftUI

/// A card: icon tile, the title with its countdown on the same line, and the time and place under it. Tapping opens the details sheet.
struct AppointmentCard: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    let item: Appointment
    var showDate = false

    var body: some View {
        let status = item.status()
        // A tap gesture, not a Button: a Button also fired at the end of a sideways swipe that started
        // on the card, opening it instead of going back home.
        Group {
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
        .onTapGesture { router.openID = AppointmentRef(id: item.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("card.\(item.title)")
        .onLongPress {
            let id = item.id
            router.menu = MenuRequest(title: item.title, actions: [
                MenuAction(title: L("نسخة مكررة", "Duplicate"), icon: "plus.square.on.square") { store.duplicate(id) },
                MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) { withAnimation { store.delete(id) } },
            ])
        }
    }
}
