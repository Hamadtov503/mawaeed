import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var lock: AppLock
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                HomeView()
                    .tabItem { Label("الرئيسية", systemImage: "house.fill") }
                    .tag(0)
                AllItemsView()
                    .tabItem { Label("الكل", systemImage: "list.bullet.rectangle") }
                    .tag(1)
                SettingsView()
                    .tabItem { Label("الإعدادات", systemImage: "gearshape.fill") }
                    .tag(2)
            }
            .sheet(item: $router.openItem) { ref in
                NavigationView {
                    ItemDetailView(itemID: ref.id)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("إغلاق") { router.openItem = nil }
                            }
                        }
                }
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Fmt.locale)
                .environment(\.calendar, Fmt.greg)
            }

            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            }
        }
        .onChange(of: phase) { p in
            switch p {
            case .active:
                store.refresh()
                lock.unlock()
            case .background:
                lock.lock()
            default:
                break
            }
        }
    }
}

struct LockView: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.brand, Color.brand.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 54))
                Text("مواعيدي")
                    .font(.largeTitle.bold())
                Button {
                    lock.unlock()
                } label: {
                    Label("افتح بـ \(AppLock.biometryName)", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
            }
            .foregroundColor(.white)
        }
        .onAppear { lock.unlock() }
    }
}
