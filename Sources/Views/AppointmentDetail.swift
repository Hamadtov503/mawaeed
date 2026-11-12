import SwiftUI

/// Opens as a sheet (no navigation push).
struct AppointmentDetail: View {
    let id: UUID
    let onClose: () -> Void
    @EnvironmentObject var store: Store
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var sharing = false

    var body: some View {
        AppNavigation {
            Group {
                if let a = store.item(id) {
                    content(a)
                } else {
                    EmptyState(icon: "trash", title: "انحذف هذا الموعد", message: "")
                        .frame(maxHeight: .infinity)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("الموعد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق", action: onClose) }
                ToolbarItem(placement: .primaryAction) {
                    if store.item(id) != nil { Button("تعديل") { editing = true } }
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
                    Text(a.title).font(.title2.bold()).foregroundColor(Theme.ink).multilineTextAlignment(.center)
                    StatusPill(text: Fmt.countdown(to: a.date, hasTime: a.hasTime), status: status)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                VStack(spacing: 14) {
                    row("calendar", "التاريخ", Fmt.dateText(a.date, hasTime: false, long: true))
                    Divider()
                    row("moon.fill", "هجري", Fmt.hijriText(a.date))
                    Divider()
                    row("clock", "الوقت", a.hasTime ? Fmt.timeText(a.date) : "طوال اليوم")
                    Divider()
                    row("bell.fill", "التنبيه", ReminderOption.summary(a.reminders, hasTime: a.hasTime))
                    if !a.location.isEmpty {
                        Divider()
                        Button { openMaps(a.location) } label: {
                            row("mappin.and.ellipse", "المكان", a.location, link: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()

                if !a.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("ملاحظات", systemImage: "note.text").font(.subheadline.bold()).foregroundColor(Theme.muted)
                        Text(a.notes).foregroundColor(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()
                }

                VStack(spacing: 0) {
                    action("مشاركة", "square.and.arrow.up") { sharing = true }
                    Divider().padding(.vertical, 12)
                    action("نسخة مكررة", "plus.square.on.square") { store.duplicate(a.id) }
                    Divider().padding(.vertical, 12)
                    action("حذف الموعد", "trash", color: .red) { confirmDelete = true }
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
        }
        .sheet(isPresented: $sharing) { ShareSheet(items: [a.shareText]) }
        .confirmationDialog("تحذف «\(a.title)»؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                onClose()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { store.delete(a.id) }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String, link: Bool = false) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: icon).foregroundColor(Theme.muted)
            Spacer(minLength: 12)
            Text(value).foregroundColor(link ? .brand : Theme.ink).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
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
