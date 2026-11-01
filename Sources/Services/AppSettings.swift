import Foundation
import Combine

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Minutes after midnight for reminders of items without a time.
    @Published var reminderMinutes: Int { didSet { d.set(reminderMinutes, forKey: "reminderMinutes"); changed() } }
    @Published var digestEnabled: Bool { didSet { d.set(digestEnabled, forKey: "digestEnabled"); changed() } }
    @Published var digestMinutes: Int { didSet { d.set(digestMinutes, forKey: "digestMinutes"); changed() } }
    @Published var calendarSync: Bool { didSet { d.set(calendarSync, forKey: "calendarSync"); changed() } }
    @Published var remindersSync: Bool { didSet { d.set(remindersSync, forKey: "remindersSync"); changed() } }
    @Published var lockEnabled: Bool { didSet { d.set(lockEnabled, forKey: "lockEnabled") } }
    @Published var overdueNag: Bool { didSet { d.set(overdueNag, forKey: "overdueNag"); changed() } }
    @Published var currency: String { didSet { d.set(currency, forKey: "currency") } }
    static let currencies = ["ر.س", "د.ك", "د.إ", "ر.ق", "د.ب", "ر.ع"]

    private init() {
        d.register(defaults: [
            "reminderMinutes": 9 * 60,
            "digestEnabled": true,
            "digestMinutes": 7 * 60 + 30,
            "calendarSync": false,
            "remindersSync": false,
            "lockEnabled": false,
            "overdueNag": true,
            "currency": "ر.س",
        ])
        reminderMinutes = d.integer(forKey: "reminderMinutes")
        digestEnabled = d.bool(forKey: "digestEnabled")
        digestMinutes = d.integer(forKey: "digestMinutes")
        calendarSync = d.bool(forKey: "calendarSync")
        remindersSync = d.bool(forKey: "remindersSync")
        lockEnabled = d.bool(forKey: "lockEnabled")
        overdueNag = d.bool(forKey: "overdueNag")
        currency = d.string(forKey: "currency") ?? "ر.س"
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

/// Lets a notification tap open an item, and lets views switch tabs.
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab = 0
    @Published var openItem: ItemRef? = nil
}

struct ItemRef: Identifiable, Hashable {
    let id: UUID
}
