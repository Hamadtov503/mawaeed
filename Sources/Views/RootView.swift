import SwiftUI

/// Home, appointments and tasks cross-fade in place; a side menu (opened from the handle on the
/// left edge) switches between them. Settings and notifications slide in as full pages; details
/// and forms open as sheets. Nothing uses a navigation push (pushed pages rendered mirrored).
struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let pageOpen = router.showSettings || router.showNotifications
        ZStack {
            Theme.background.ignoresSafeArea()

            ZStack {
                page(.home) { HomeView() }
                page(.appointments) { AppointmentsView() }
                page(.tasks) { TasksView() }
            }
            .scaleEffect(pageOpen || router.menuOpen ? 0.95 : 1)
            .opacity(pageOpen ? 0.6 : 1)

            if !router.menuOpen && !pageOpen {
                MenuHandle { router.toggleMenu(true) }
                    .transition(.opacity)
                    .zIndex(1)
            }

            if pageOpen || router.menuOpen {
                Color.black.opacity(router.menuOpen ? 0.25 : 0.18).ignoresSafeArea()
                    .onTapGesture {
                        if router.menuOpen { router.toggleMenu(false) } else { router.closePages() }
                    }
                    .transition(.opacity)
                    .zIndex(2)
            }
            if router.menuOpen {
                SideMenu()
                    .transition(.move(edge: .trailing))
                    .zIndex(3)
            }
            if router.showNotifications {
                SlidePage(title: "التنبيهات", onBack: router.closePages) { NotificationsView() }
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }
            if router.showSettings {
                SlidePage(title: "الإعدادات", onBack: router.closePages) { SettingsView() }
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }
        }
        .sheet(isPresented: $router.addingAppointment) {
            AppointmentEditor(appointment: AppointmentEditor.blank(), isNew: true) { router.addingAppointment = false }
                .environmentObject(store)
                .appEnvironment()
        }
        .sheet(item: $router.editingTask) { t in
            TaskEditor(task: t) { router.editingTask = nil }
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

    /// Every page stays alive; the visible one fades in with a slight drift.
    private func page<V: View>(_ p: Page, @ViewBuilder _ content: () -> V) -> some View {
        let on = router.page == p
        return content()
            .opacity(on ? 1 : 0)
            .scaleEffect(on ? 1 : 0.98)
            .offset(y: on ? 0 : 10)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
    }
}

/// The tab on the left edge that opens the side menu (also opens with a swipe from the edge).
struct MenuHandle: View {
    let onOpen: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpen) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 64)
                    .background(
                        UnevenCapsule()
                            .fill(LinearGradient(colors: [Theme.burgundy, Theme.burgundy.opacity(0.85)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: Theme.burgundy.opacity(0.3), radius: 6, x: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("القائمة")
            Spacer()
        }
        .environment(\.layoutDirection, .leftToRight)   // always on the screen's left edge
        .frame(maxHeight: .infinity)
        .offset(y: -60)
        .gesture(DragGesture(minimumDistance: 15).onEnded { v in
            if abs(v.translation.width) > 40 { onOpen() }
        })
    }
}

/// Rounded on the inner (right) side only, flat against the screen's left edge.
struct UnevenCapsule: Shape {
    func path(in r: CGRect) -> Path {
        let rad = min(r.width, 18)
        var p = Path()
        // Screen-left edge is flat; the right side is rounded.
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + rad), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.maxX - rad, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The side menu: the three pages, then notifications and settings.
struct SideMenu: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image("Logo").resizable().scaledToFit().frame(width: 44, height: 44)
                    Text("مواعيدي").font(.ruqaa(size: 30)).foregroundColor(Theme.burgundy)
                    Spacer()
                    Button { router.toggleMenu(false) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.muted)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.sand))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("إغلاق")
                }
                .padding(.bottom, 14)

                ForEach(Page.allCases) { p in
                    row(p.title, p.icon, badge: badge(for: p), selected: router.page == p) { router.go(p) }
                }

                Divider().padding(.vertical, 10)

                row("التنبيهات", "bell.fill", badge: router.deliveredCount, selected: false) { router.present(notifications: true) }
                row("الإعدادات", "gearshape.fill", badge: 0, selected: false) { router.present(notifications: false) }

                Spacer()
                Text("0.1 Beta").font(.app(.caption2)).foregroundColor(Theme.muted)
            }
            .environment(\.layoutDirection, .rightToLeft)   // the menu's content reads right-to-left
            .padding(20)
            .padding(.top, 30)
            .frame(width: 290)
            .frame(maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .overlay(Rectangle().fill(Theme.border).frame(width: 1).ignoresSafeArea(), alignment: .trailing)
            .shadow(color: .black.opacity(0.15), radius: 20)
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .leftToRight)   // pin the panel to the screen's left edge
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if abs(v.translation.width) > 60 { router.toggleMenu(false) }
        })
    }

    private func badge(for p: Page) -> Int {
        switch p {
        case .home: return 0
        case .appointments: return store.items.filter { $0.status() == .today }.count
        case .tasks: return store.tasks.filter { !$0.isDone && ($0.isDue(on: Date()) || $0.isOverdue()) }.count
        }
    }

    private func row(_ title: String, _ icon: String, badge: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(selected ? .white : Theme.burgundy)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.burgundy : Theme.burgundy.opacity(0.1)))
                Text(title).font(.app(.body, selected ? .bold : .medium)).foregroundColor(Theme.ink)
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.app(.caption, .bold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.burgundy))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Theme.sand : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A full-screen page that slides in from the side over the current page, with its own header
/// and back button. Drawn by SwiftUI (not a navigation push).
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
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    if abs(v.translation.width) > 90 && abs(v.translation.height) < 80 { onBack() }
                }
        )
    }
}
