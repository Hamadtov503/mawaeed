import SwiftUI

/// Two tabs and a floating bar with a centre add button. Details and the form open as sheets.
struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var phase
    @State private var adding = false

    var body: some View {
        let pageOpen = router.showSettings || router.showNotifications
        ZStack {
            Theme.background.ignoresSafeArea()
            Group {
                if router.tab == 1 {
                    AppointmentsView()
                } else {
                    HomeView(onAdd: { adding = true })
                }
            }
            .safeAreaInset(edge: .bottom) {
                FloatingTabBar(selection: $router.tab) { adding = true }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }
            // The home screen eases back and dims while a page slides in over it.
            .scaleEffect(pageOpen ? 0.94 : 1)
            .opacity(pageOpen ? 0.6 : 1)

            if pageOpen {
                Color.black.opacity(0.18).ignoresSafeArea()
                    .onTapGesture { router.closePages() }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if router.showNotifications {
                SlidePage(title: "التنبيهات", onBack: router.closePages) {
                    NotificationsView()
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
            if router.showSettings {
                SlidePage(title: "الإعدادات", onBack: router.closePages) {
                    SettingsView()
                }
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $adding) {
            AppointmentEditor(appointment: AppointmentEditor.blank(), isNew: true) { adding = false }
                .environmentObject(store)
                .appEnvironment()
        }
        .sheet(item: $router.openID) { ref in
            AppointmentDetail(id: ref.id) { router.openID = nil }
                .environmentObject(store)
                .environmentObject(router)
                .appEnvironment()
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

/// A full-screen page that slides in from the side over the home screen, with its own header
/// and back button. Drawn by SwiftUI (not a navigation push, which rendered mirrored).
struct SlidePage<Content: View>: View {
    let title: String
    let onBack: () -> Void
    let content: Content

    init(title: String, onBack: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.app(.headline, .bold)).foregroundColor(Theme.ink)
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.card))
                            .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("رجوع")
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            content
        }
        .background(Theme.background.ignoresSafeArea())
        .shadow(color: .black.opacity(0.18), radius: 20)
        // Swipe sideways to go back.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    if abs(v.translation.width) > 90 && abs(v.translation.height) < 80 { onBack() }
                }
        )
    }
}

struct FloatingTabBar: View {
    @Binding var selection: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(0, "الرئيسية", "house.fill")
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.burgundy))
                    .shadow(color: Theme.burgundy.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("موعد جديد")
            tab(1, "مواعيدي", "calendar")
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
                Text(title).font(.app(size: 11, .semibold))
            }
            .foregroundColor(on ? Theme.burgundy : Theme.ink.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(on ? Theme.barSelected : Color.clear))
        }
        .buttonStyle(.plain)
    }
}
