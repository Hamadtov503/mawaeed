import SwiftUI

/// Opens as a sheet (no navigation push).
struct AppointmentDetail: View {
    let id: UUID
    let onClose: () -> Void
    @EnvironmentObject var store: Store
    @State private var editing = false
    @State private var menu: MenuRequest? = nil
    @State private var sharing = false

    var body: some View {
        AppNavigation {
            Group {
                if let a = store.item(id) {
                    content(a)
                } else {
                    EmptyState(icon: "trash", title: L("انحذف هذا الموعد", "This appointment was deleted"), message: "")
                        .frame(maxHeight: .infinity)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("الموعد", "Appointment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق", "Close"), action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    if store.item(id) != nil { Button(L("تعديل", "Edit")) { editing = true } }
                }
            }
        }
    }

    private func content(_ a: Appointment) -> some View {
        let status = a.status()
        return ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Tile(icon: a.displayIcon, color: .brand, size: 68)
                    Text(a.title).font(.app(.title2, .bold)).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                    StatusPill(text: Fmt.countdown(to: a.date, hasTime: a.hasTime), status: status)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                VStack(spacing: 14) {
                    row("calendar", L("التاريخ", "Date"), Fmt.dateText(a.date, hasTime: false, long: true))
                    Divider()
                    row("moon.fill", L("هجري", "Hijri"), Fmt.hijriText(a.date))
                    Divider()
                    row("clock", L("الوقت", "Time"), a.hasTime ? Fmt.timeText(a.date) : L("طوال اليوم", "All day"))
                    Divider()
                    row("bell.fill", L("التنبيه", "Reminder"), ReminderOption.summary(a.reminders, hasTime: a.hasTime))
                    if !a.location.isEmpty {
                        Divider()
                        Button { openMaps(a.location) } label: {
                            row("mappin.and.ellipse", L("المكان", "Place"), a.location, link: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()

                if !a.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L("ملاحظات", "Notes"), systemImage: "note.text").font(.app(.subheadline, .bold)).foregroundColor(Theme.muted)
                        Text(a.notes).foregroundColor(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()
                }

                VStack(spacing: 0) {
                    action(L("مشاركة", "Share"), "square.and.arrow.up") { sharing = true }
                    Divider().padding(.vertical, 12)
                    action(L("نسخة مكررة", "Duplicate"), "plus.square.on.square") { store.duplicate(a.id) }
                    Divider().padding(.vertical, 12)
                    action(L("حذف الموعد", "Delete appointment"), "trash", color: .red) {
                        menu = MenuRequest(title: L("تحذف «\(a.title)»؟", "Delete “\(a.title)”?"), actions: [
                            MenuAction(title: L("حذف", "Delete"), icon: "trash", destructive: true) {
                                onClose()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.delete(a.id) }
                            },
                            MenuAction(title: L("إلغاء", "Cancel"), icon: "xmark") {},
                        ])
                    }
                }
                .card()
            }
            .padding(18)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editing) {
            AppointmentEditor(appointment: a, isNew: false) { editing = false }
                .environmentObject(store)
                .appEnvironment()
        }
        .sheet(isPresented: $sharing) { ShareSheet(items: [a.shareText]) }
        .actionMenu($menu)
    }

    private func row(_ icon: String, _ title: String, _ value: String, link: Bool = false) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: icon).foregroundColor(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundColor(link ? .brand : Theme.ink).multilineTextAlignment(.trailing)
        }
        .font(.app(.subheadline))
    }

    private func action(_ title: String, _ icon: String, color: Color = .brand, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack {
                Label(title, systemImage: icon).foregroundColor(color)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
