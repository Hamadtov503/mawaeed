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
        onboarded = d.bool(forKey: "onboarded")
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
        case .home: return "الرئيسية"
        case .appointments: return "مواعيدي"
        case .tasks: return "مهامي"
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
    @Published var showNotifications = false
    /// Notifications sitting in Notification Center, shown as the bell's badge.
    @Published var deliveredCount = 0

    static let soft = Animation.spring(response: 0.42, dampingFraction: 0.9)

    func go(_ p: Page) {
        withAnimation(Self.glide) {
            page = p
            menuOpen = false
            showSettings = false
            showNotifications = false
        }
    }

    /// A slower, fully damped spring so the menu glides in and out without a bounce.
    static let glide = Animation.spring(response: 0.55, dampingFraction: 1.0)

    func toggleMenu(_ open: Bool? = nil) {
        withAnimation(Self.glide) { menuOpen = open ?? !menuOpen }
    }

    /// Slides the notifications or settings page in over the current page.
    func present(notifications: Bool) {
        withAnimation(Self.soft) {
            menuOpen = false
            if notifications { showNotifications = true } else { showSettings = true }
        }
    }

    func closePages() {
        withAnimation(Self.soft) {
            showNotifications = false
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
