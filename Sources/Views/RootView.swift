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
            .scaleEffect(pageOpen ? 0.95 : (router.menuOpen ? 0.985 : 1))
            .opacity(pageOpen ? 0.6 : 1)

            if !router.menuOpen && !pageOpen {
                MenuHandle { router.toggleMenu(true) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }

            if pageOpen || router.menuOpen {
                Color.black.opacity(router.menuOpen ? 0.12 : 0.18).ignoresSafeArea()
                    .onTapGesture {
                        if router.menuOpen { router.toggleMenu(false) } else { router.closePages() }
                    }
                    .transition(.opacity)
                    .zIndex(2)
            }
            if router.menuOpen {
                SideMenu()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(3)
            }
            if router.showNotifications {
                SlidePage(title: L("التنبيهات", "Notifications"), onBack: router.closePages) { NotificationsView() }
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }
            if router.showSettings {
                SlidePage(title: L("الإعدادات", "Settings"), onBack: router.closePages) { SettingsView() }
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
    @EnvironmentObject var router: Router
    let onOpen: () -> Void

    private let size = CGSize(width: 34, height: 118)

    var body: some View {
        GeometryReader { g in
            let top = g.frame(in: .global).minY
            // One fixed height on every page: level with the home page's day line.
            let wanted = router.dayLineY > 0 ? router.dayLineY - top : g.size.height * 0.55
            let y = min(max(wanted, size.height / 2 + 8), g.size.height - size.height / 2 - 8)
            Button(action: onOpen) {
                ZStack(alignment: .leading) {
                    WaveTab()
                        .fill(LinearGradient(colors: [Theme.menuTop, Theme.menuBottom], startPoint: .top, endPoint: .bottom))
                        .shadow(color: Theme.burgundy.opacity(0.28), radius: 6, x: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 9)
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("القائمة", "Menu"))
            .accessibilityIdentifier("menuHandle")
            .gesture(DragGesture(minimumDistance: 15).onEnded { v in
                if abs(v.translation.width) > 40 { onOpen() }
            })
            .position(x: size.width / 2, y: y)
        }
        // Measured against the whole screen, ignoring safe areas and the keyboard, so nothing
        // (a sheet, the keyboard, adding an item) can shift it.
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)   // always on the screen's left edge
    }
}

/// A smooth bump out of the screen's left edge, like a leaf tab: flat against the edge,
/// swelling to full width in the middle and tapering back at both ends.
struct WaveTab: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX + w, y: r.minY + h / 2),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.28),
                   control2: CGPoint(x: r.minX + w, y: r.minY + h * 0.22))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY),
                   control1: CGPoint(x: r.minX + w, y: r.minY + h * 0.78),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.72))
        p.closeSubpath()
        return p
    }
}

/// Rounded on the inner (right) side only, flat against the screen's left edge.
struct UnevenCapsule: Shape {
    var radius: CGFloat = 18

    func path(in r: CGRect) -> Path {
        let rad = min(r.width / 2, min(r.height / 2, radius))
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

/// A slim side menu on the left edge: the three pages as icons with a small label.
struct SideMenu: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                ForEach(Page.allCases) { p in item(p) }
            }
            .environment(\.layoutDirection, Fmt.isArabic ? .rightToLeft : .leftToRight)
            .padding(.vertical, 18)
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .background(
                // Semi-transparent: frosted glass with a light beige tint.
                ZStack {
                    UnevenCapsule(radius: 26).fill(.ultraThinMaterial)
                    UnevenCapsule(radius: 26).fill(Theme.background.opacity(0.45))
                }
                .shadow(color: .black.opacity(0.12), radius: 14, x: 3)
            )
            .overlay(UnevenCapsule(radius: 26).stroke(Color.white.opacity(0.6), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .leftToRight)   // pin the panel to the screen's left edge
        .frame(maxHeight: .infinity)
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            if abs(v.translation.width) > 50 { router.toggleMenu(false) }
        })
    }

    private func badge(for p: Page) -> Int {
        switch p {
        case .home: return 0
        case .appointments: return store.items.filter { $0.status() == .today }.count
        case .tasks: return store.tasks.filter { !$0.isDone && ($0.isDue(on: Date()) || $0.isOverdue()) }.count
        }
    }

    private func item(_ p: Page) -> some View {
        let selected = router.page == p
        let count = badge(for: p)
        return Button { router.go(p) } label: {
            VStack(spacing: 5) {
                Image(systemName: p.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(selected ? .white : Theme.burgundy)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(selected ? Theme.burgundy : Theme.burgundy.opacity(0.1)))
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)").font(.app(size: 10, .bold)).foregroundColor(.white)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Circle().fill(Theme.navy))
                                .offset(x: 5, y: -5)
                        }
                    }
                Text(p.title).font(.app(.caption2, selected ? .bold : .medium)).foregroundColor(Theme.ink)
            }
            .frame(width: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menu.\(p)")
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
                    .accessibilityLabel(L("رجوع", "Back"))
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
