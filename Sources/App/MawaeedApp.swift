import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be in place before launch finishes so a notification tap opens its appointment.
        NotificationManager.shared.setUp()
        NotificationManager.shared.requestAuthorization()
        // Right-to-left is set for SwiftUI with .appEnvironment() at the root and in every sheet.
        // UIKit views are not forced (UIView.appearance) — that drew pages mirrored while animating.
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.backgroundColor = Theme.uiBackground
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UITableView.appearance().backgroundColor = .clear
        _ = Store.shared
        return true
    }
}

@main
struct MawaeedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = Store.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = Router.shared
    @StateObject private var sync = SyncManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(sync)
                .appEnvironment()
                .accentColor(.brand)
        }
    }
}
