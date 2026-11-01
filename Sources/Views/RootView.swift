import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var lock: AppLock
    @Environment(\.scenePhase) private var phase
    @State private var showAdd = false
    @State private var dismissedNext: UUID? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                switch router.tab {
                case 1: AllItemsView()
                case 2: ReportsView()
                case 3: SettingsView()
                default: HomeView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let next = nextItem, next.id != dismissedNext, router.tab != 3 {
                        NextBanner(item: next) {
                            router.openItem = ItemRef(id: next.id)
                        } onClose: {
                            withAnimation { dismissedNext = next.id }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    FloatingTabBar(selection: $router.tab) { showAdd = true }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 2)
            }

            if lock.isLocked {
                LockView().transition(.opacity)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddFlowView(isPresented: $showAdd)
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Fmt.locale)
                .environment(\.calendar, Fmt.greg)
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
        .onChange(of: phase) { p in
            switch p {
            case .active:
                store.refresh()
                lock.unlock()
                SyncManager.shared.startAutoSync()
            case .background:
                SyncManager.shared.stopAutoSync()
                SyncManager.shared.sync()
                lock.lock()
            default:
                break
            }
        }
    }

    /// The nearest thing coming up (not medicines, not overdue).
    private var nextItem: Item? {
        let now = Date()
        return store.activeSorted.first { !$0.isMedicine && $0.urgency(now: now) != .overdue }
    }
}

struct NextBanner: View {
    let item: Item
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Tile(icon: item.displayIcon, color: item.category.color, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("الجاي").font(.caption).foregroundColor(Theme.muted)
                        Text(item.title).font(.subheadline.weight(.bold)).foregroundColor(Theme.ink).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(Fmt.countdown(to: item.date, hasTime: item.hasTime))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Theme.pill(item.urgency()).fg)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundColor(Theme.muted)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

struct FloatingTabBar: View {
    @Binding var selection: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(0, "الرئيسية", "house.fill")
            tab(1, "أشيائي", "square.stack.fill")
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.brand))
                    .shadow(color: Color.brand.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("إضافة")
            tab(2, "التقارير", "chart.bar.fill")
            tab(3, "الإعدادات", "gearshape.fill")
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
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(on ? Color.brand : Theme.ink.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(on ? Theme.barSelected : Color.clear))
        }
        .buttonStyle(.plain)
    }
}

struct LockView: View {
    @EnvironmentObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Tile(icon: "lock.fill", size: 84)
                Text("مواعيدي").font(.largeTitle.bold()).foregroundColor(Theme.ink)
                Button {
                    lock.unlock()
                } label: {
                    Label("افتح بـ \(AppLock.biometryName)", systemImage: "faceid")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.brand))
                }
            }
        }
        .onAppear { lock.unlock() }
    }
}
