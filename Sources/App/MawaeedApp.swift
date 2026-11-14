import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The delegate must be in place before launch finishes so a notification tap opens its appointment.
        NotificationManager.shared.setUp()
        // The intro asks for notifications the first time; after that, keep the authorization fresh.
        if AppSettings.shared.onboarded && !UITestSupport.isActive { NotificationManager.shared.requestAuthorization() }
        // Right-to-left is set for SwiftUI with .appEnvironment() at the root and in every sheet.
        // UIKit views are not forced (UIView.appearance) — that drew pages mirrored while animating.
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.backgroundColor = Theme.uiBackground
        bar.titleTextAttributes = [.font: AppFont.ui(17, .bold), .foregroundColor: Theme.uiInk]
        bar.largeTitleTextAttributes = [.font: AppFont.ui(32, .bold), .foregroundColor: Theme.uiInk]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: AppFont.ui(17, .medium)]
        bar.buttonAppearance = button
        bar.doneButtonAppearance = button
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

    init() {
        UITestSupport.prepare()   // no-op outside automated UI tests
        // Before any screen: iOS runs the app in the chosen language and region (Arabic: ar-SA with
        // Arabic digits), which also makes the Arabic keyboard come up first.
        AppSettings.shared.syncSystemLanguage()
    }

    var body: some Scene {
        WindowGroup {
            AppEntry()
                .id(settings.language)   // rebuild every screen in the new language
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(sync)
                .appEnvironment()
                .font(.app(.body))
                .accentColor(.brand)
        }
    }
}
