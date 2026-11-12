import SwiftUI

/// Three tabs and a floating bar with a centre add button. Details and the form open as sheets.
struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var phase
    @State private var adding = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Group {
                switch router.tab {
                case 1: AppointmentsView()
                case 2: SettingsView()
                default: HomeView(onAdd: { adding = true })
                }
            }
            .safeAreaInset(edge: .bottom) {
                FloatingTabBar(selection: $router.tab) { adding = true }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
        }
        .sheet(isPresented: $adding) {
            AppointmentEditor(appointment: AppointmentEditor.blank(), isNew: true) { adding = false }
                .environmentObject(store)
        }
        .sheet(item: $router.openID) { ref in
            AppointmentDetail(id: ref.id) { router.openID = nil }
                .environmentObject(store)
                .environmentObject(router)
        }
        .onChange(of: phase) { p in
            switch p {
            case .active:
                store.refresh()
                SyncManager.shared.startAutoSync()
            case .background:
                SyncManager.shared.stopAutoSync()
                SyncManager.shared.sync()
            default:
                break
            }
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(0, "الرئيسية", "house.fill")
            tab(1, "مواعيدي", "calendar")
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.gold))
                    .shadow(color: Theme.gold.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("موعد جديد")
            tab(2, "الإعدادات", "gearshape.fill")
        }
        .padding(6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }

    private func tab(_ i: Int, _ title: String, _ icon: String) -> some View {
        let on = selection == i
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selection = i }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(on ? Theme.gold : Theme.ink.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(on ? Theme.barSelected : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
