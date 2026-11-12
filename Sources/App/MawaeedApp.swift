import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be in place before launch finishes so notification actions are handled.
        NotificationManager.shared.setUp()
        // No UIView.appearance().semanticContentAttribute override: the app's only localization is Arabic,
        // so UIKit is already right-to-left, and forcing it again mirrors text during navigation transitions.
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
    @StateObject private var lock = AppLock.shared
    @StateObject private var backup = SyncManager.shared

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(lock)
                .environmentObject(backup)
                .environment(\.locale, Fmt.locale)
                .environment(\.calendar, Fmt.greg)
                .accentColor(.brand)
        }
    }
}


