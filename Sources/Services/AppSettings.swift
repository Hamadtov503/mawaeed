import Foundation
import Combine
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Minutes after midnight when reminders for all-day appointments fire.
    @Published var reminderMinutes: Int { didSet { d.set(reminderMinutes, forKey: "reminderMinutes"); changed() } }
    @Published var digestEnabled: Bool { didSet { d.set(digestEnabled, forKey: "digestEnabled"); changed() } }
    @Published var digestMinutes: Int { didSet { d.set(digestMinutes, forKey: "digestMinutes"); changed() } }
    @Published var calendarSync: Bool { didSet { d.set(calendarSync, forKey: "calendarSync"); changed() } }
    /// The name the greeting uses ("صباح الخير يا …").
    @Published var userName: String { didSet { d.set(userName, forKey: "userName") } }
    /// Your profile picture: a small square JPEG, or nil for the initial / person mark.
    @Published var profileImage: Data? { didSet { d.set(profileImage, forKey: "profileImage") } }
    /// The app's language (Arabic by default). Changing it rebuilds the screens and reschedules reminders.
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language"); syncSystemLanguage(); changed() } }

    /// iOS runs the app in the first of these languages from the next launch on, so the parts iOS
    /// draws (menus, pickers, dialogs) follow the app's own language and direction.
    /// Also sets the region to Saudi Arabia with Arabic digits, so iOS offers the Arabic keyboard first.
    func syncSystemLanguage() {
        let languages = language == .ar ? ["ar-SA"] : ["en"]
        let locale = language == .ar ? "ar_SA@numbers=arab" : "en_US"
        if d.stringArray(forKey: "AppleLanguages")?.first != languages[0] { d.set(languages, forKey: "AppleLanguages") }
        if d.string(forKey: "AppleLocale") != locale { d.set(locale, forKey: "AppleLocale") }
    }
    /// Set once the intro has been completed.
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }

    private init() {
        d.register(defaults: [
            "reminderMinutes": 9 * 60,
            "digestEnabled": true,
            "digestMinutes": 7 * 60 + 30,
            "calendarSync": false,
        ])
        reminderMinutes = d.integer(forKey: "reminderMinutes")
        digestEnabled = d.bool(forKey: "digestEnabled")
        digestMinutes = d.integer(forKey: "digestMinutes")
        calendarSync = d.bool(forKey: "calendarSync")
        userName = d.string(forKey: "userName") ?? ""
        profileImage = d.data(forKey: "profileImage")
        onboarded = d.bool(forKey: "onboarded")
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "ar") ?? .ar
        syncSystemLanguage()
    }

    private func changed() {
        DispatchQueue.main.async { Store.shared.scheduleSideEffects() }
    }

    static func date(fromMinutes m: Int) -> Date {
        Fmt.greg.startOfDay(for: Date()).addingTimeInterval(TimeInterval(m * 60))
    }

    static func minutes(from date: Date) -> Int {
        let c = Fmt.greg.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

enum Page: Int, CaseIterable, Identifiable {
    case home, appointments, tasks
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .home: return L("الرئيسية", "Home")
        case .appointments: return L("مواعيدي", "Appointments")
        case .tasks: return L("مهامي", "Tasks")
        }
    }
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .appointments: return "calendar"
        case .tasks: return "checklist"
        }
    }
}

/// Which page shows, the side menu, the slide-in pages and the sheets.
final class Router: ObservableObject {
    static let shared = Router()
    @Published var page: Page = .home
    @Published var menuOpen = false
    @Published var openID: AppointmentRef? = nil
    @Published var addingAppointment = false
    @Published var editingTask: TaskItem? = nil
    @Published var showSettings = false
    @Published var showProfile = false
    /// An app-drawn menu or question over the pages (long press on a card, a task row…).
    @Published var menu: MenuRequest? = nil
    /// Notifications sitting in Notification Center, shown as the bell's badge.
    @Published var deliveredCount = 0
    /// Where the home page's day line ("اليوم") is on screen; the menu tab sits beside it.
    @Published var dayLineY: CGFloat = 0

    static let soft = Animation.spring(response: 0.42, dampingFraction: 0.9)

    func go(_ p: Page) {
        withAnimation(Self.glide) {
            page = p
            menuOpen = false
            showSettings = false
            showProfile = false
        }
    }

    /// A gentle spring for the menu and page changes: a soft glide with only a hint of settle.
    static let glide = Animation.spring(response: 0.5, dampingFraction: 0.88)

    func toggleMenu(_ open: Bool? = nil) {
        withAnimation(Self.glide) { menuOpen = open ?? !menuOpen }
    }

    /// Slides the profile or settings page in over the current page.
    func present(profile: Bool) {
        withAnimation(Self.soft) {
            menuOpen = false
            if profile { showProfile = true } else { showSettings = true }
        }
    }

    func closePages() {
        withAnimation(Self.soft) {
            showProfile = false
            showSettings = false
        }
    }

    func open(_ id: UUID) {
        openID = AppointmentRef(id: id)
    }

    func newTask(due: Date? = nil) {
        var t = TaskItem()
        t.due = due
        editingTask = t
    }
}

struct AppointmentRef: Identifiable, Hashable {
    let id: UUID
}
