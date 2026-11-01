import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be in place before launch finishes so notification actions are handled.
        NotificationManager.shared.setUp()
        NotificationManager.shared.requestAuthorization()
        UIView.appearance().semanticContentAttribute = .forceRightToLeft
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
    @StateObject private var backup = BackupManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(lock)
                .environmentObject(backup)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Fmt.locale)
                .environment(\.calendar, Fmt.greg)
                .accentColor(.brand)
        }
    }
}
