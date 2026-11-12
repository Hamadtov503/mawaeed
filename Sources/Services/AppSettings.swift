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

/// Tabs, plus which appointment is open (a notification tap opens one too).
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab = 0
    @Published var openID: AppointmentRef? = nil
    @Published var showSettings = false
    @Published var showNotifications = false
    /// Notifications sitting in Notification Center, shown as the bell's badge.
    @Published var deliveredCount = 0

    /// Slides the notifications or settings page in over the home screen.
    func present(notifications: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            if notifications { showNotifications = true } else { showSettings = true }
        }
    }

    func closePages() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.95)) {
            showNotifications = false
            showSettings = false
        }
    }

    /// Opens an appointment's sheet; a page that is slid in stays underneath.
    func open(_ id: UUID) {
        openID = AppointmentRef(id: id)
    }
}

struct AppointmentRef: Identifiable, Hashable {
    let id: UUID
}
