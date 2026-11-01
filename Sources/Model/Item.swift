import Foundation
import SwiftUI

enum Category: String, Codable, CaseIterable, Identifiable {
    case appointment, document, subscription, bill, warranty, maintenance, task, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appointment: return "موعد"
        case .document: return "وثيقة / تجديد"
        case .subscription: return "اشتراك / باقة"
        case .bill: return "فاتورة / قسط"
        case .warranty: return "ضمان"
        case .maintenance: return "صيانة"
        case .task: return "مهمة"
        case .other: return "أخرى"
        }
    }

    var icon: String {
        switch self {
        case .appointment: return "calendar.badge.clock"
        case .document: return "doc.text.fill"
        case .subscription: return "arrow.triangle.2.circlepath"
        case .bill: return "creditcard.fill"
        case .warranty: return "checkmark.shield.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .task: return "checklist"
        case .other: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .appointment: return .blue
        case .document: return .indigo
        case .subscription: return .purple
        case .bill: return .pink
        case .warranty: return .green
        case .maintenance: return .orange
        case .task: return .teal
        case .other: return .gray
        }
    }
}

enum RepeatUnit: String, Codable, CaseIterable, Identifiable {
    case none, day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "لا يتكرر"
        case .day: return "يومي"
        case .week: return "أسبوعي"
        case .month: return "شهري"
        case .year: return "سنوي"
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .none: return nil
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// Reminder offsets are minutes before the due date. For items without a time,
/// the "due moment" is the user's default reminder time on that day.
enum ReminderOption {
    static let all: [Int] = [0, 15, 30, 60, 120, 180, 1440, 2880, 4320, 10080, 20160, 43200, 86400, 129600, 259200]

    static func options(hasTime: Bool) -> [Int] {
        hasTime ? all : all.filter { $0 == 0 || $0 >= 1440 }
    }

    static func label(_ m: Int, hasTime: Bool) -> String {
        switch m {
        case 0: return hasTime ? "في وقت الموعد" : "في نفس اليوم"
        case ..<60: return "قبل \(Fmt.minutes(m))"
        case ..<1440: return "قبل \(Fmt.hours(m / 60))"
        case ..<10080: return "قبل \(Fmt.days(m / 1440))"
        case ..<43200: return "قبل \(Fmt.weeks(m / 10080))"
        default: return "قبل \(Fmt.months(m / 43200))"
        }
    }

    static func summary(_ list: [Int], hasTime: Bool) -> String {
        if list.isEmpty { return "بدون تنبيه" }
        return list.sorted(by: >).map { label($0, hasTime: hasTime) }.joined(separator: "، ")
    }
}

enum Urgency: Int, Comparable {
    case overdue, today, week, month, later, done

    static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .week: return Color(red: 0.85, green: 0.6, blue: 0.0)
        case .month: return .blue
        case .later: return .secondary
        case .done: return .green
        }
    }
}

struct Item: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var category: Category = .other
    var icon: String? = nil
    var date = Date()
    var hasTime = false
    var reminders: [Int] = [1440]
    var repeatUnit: RepeatUnit = .none
    var repeatEvery = 1
    var notes = ""
    var location = ""
    var amount: Double? = nil
    var purchaseDate: Date? = nil
    var warrantyMonths: Int? = nil
    var photos: [String] = []
    var isDone = false
    var doneAt: Date? = nil
    var snoozeUntil: Date? = nil
    var history: [Date] = []
    var createdAt = Date()
    var calendarEventID: String? = nil
    var reminderItemID: String? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, title, category, icon, date, hasTime, reminders, repeatUnit, repeatEvery, notes, location, amount,
             purchaseDate, warrantyMonths, photos, isDone, doneAt, snoozeUntil, history, createdAt,
             calendarEventID, reminderItemID
    }

    /// Tolerant decoding: missing or unknown fields fall back to defaults so old backups keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        category = (try? c.decodeIfPresent(Category.self, forKey: .category)) ?? .other
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
        reminders = (try? c.decodeIfPresent([Int].self, forKey: .reminders)) ?? [1440]
        repeatUnit = (try? c.decodeIfPresent(RepeatUnit.self, forKey: .repeatUnit)) ?? .none
        repeatEvery = max(1, (try? c.decodeIfPresent(Int.self, forKey: .repeatEvery)) ?? 1)
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        location = (try? c.decodeIfPresent(String.self, forKey: .location)) ?? ""
        amount = try? c.decodeIfPresent(Double.self, forKey: .amount)
        purchaseDate = try? c.decodeIfPresent(Date.self, forKey: .purchaseDate)
        warrantyMonths = try? c.decodeIfPresent(Int.self, forKey: .warrantyMonths)
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? []
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        doneAt = try? c.decodeIfPresent(Date.self, forKey: .doneAt)
        snoozeUntil = try? c.decodeIfPresent(Date.self, forKey: .snoozeUntil)
        history = (try? c.decodeIfPresent([Date].self, forKey: .history)) ?? []
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        calendarEventID = try? c.decodeIfPresent(String.self, forKey: .calendarEventID)
        reminderItemID = try? c.decodeIfPresent(String.self, forKey: .reminderItemID)
    }

    // MARK: Derived

    var displayIcon: String { icon ?? category.icon }
    var isRecurring: Bool { repeatUnit != .none }

    var repeatLabel: String {
        guard repeatUnit != .none else { return "لا يتكرر" }
        if repeatEvery == 1 {
            switch repeatUnit {
            case .day: return "كل يوم"
            case .week: return "كل أسبوع"
            case .month: return "كل شهر"
            case .year: return "كل سنة"
            case .none: return ""
            }
        }
        switch repeatUnit {
        case .day: return "كل \(Fmt.days(repeatEvery))"
        case .week: return "كل \(Fmt.weeks(repeatEvery))"
        case .month: return "كل \(Fmt.months(repeatEvery))"
        case .year: return "كل \(Fmt.years(repeatEvery))"
        case .none: return ""
        }
    }

    func urgency(now: Date = Date()) -> Urgency {
        if isDone { return .done }
        let cal = Fmt.greg
        let today = cal.startOfDay(for: now)
        let day = cal.startOfDay(for: date)
        if day < today { return .overdue }
        let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
        if diff == 0 { return .today }
        if diff <= 7 { return .week }
        if diff <= 30 { return .month }
        return .later
    }

    /// The moment the "due" reminder fires: the exact time, or the default reminder time on the day.
    func dueMoment(reminderMinutes: Int) -> Date {
        if hasTime { return date }
        return Fmt.greg.startOfDay(for: date).addingTimeInterval(TimeInterval(reminderMinutes * 60))
    }

    func fireDate(offset: Int, reminderMinutes: Int) -> Date {
        dueMoment(reminderMinutes: reminderMinutes).addingTimeInterval(TimeInterval(-offset * 60))
    }

    func advanced(_ d: Date, by steps: Int = 1) -> Date {
        guard let comp = repeatUnit.component else { return d }
        return Fmt.greg.date(byAdding: comp, value: repeatEvery * steps, to: d) ?? d
    }

    /// The next due date after completing this occurrence: at least one period ahead and not in the past.
    func nextOccurrence(now: Date = Date()) -> Date {
        guard isRecurring else { return date }
        var d = advanced(date)
        let floor = hasTime ? now : Fmt.greg.startOfDay(for: now)
        var guardCount = 0
        while d < floor && guardCount < 2000 {
            d = advanced(d)
            guardCount += 1
        }
        return d
    }

    /// Normalised monthly cost for subscriptions and bills.
    var monthlyCost: Double? {
        guard let a = amount, a > 0 else { return nil }
        let n = Double(max(1, repeatEvery))
        switch repeatUnit {
        case .none: return nil
        case .day: return a * 30 / n
        case .week: return a * 52 / 12 / n
        case .month: return a / n
        case .year: return a / 12 / n
        }
    }

    var warrantyEnd: Date? {
        guard let p = purchaseDate, let m = warrantyMonths else { return nil }
        return Fmt.greg.date(byAdding: .month, value: m, to: Fmt.greg.startOfDay(for: p))
    }

    var shareText: String {
        var lines = ["📌 \(title)", "📅 \(Fmt.dateText(date, hasTime: hasTime, long: true))", "🌙 \(Fmt.hijriText(date))"]
        if !isDone { lines.append("⏳ \(Fmt.countdown(to: date, hasTime: hasTime))") }
        if isRecurring { lines.append("🔁 \(repeatLabel)") }
        if let a = amount { lines.append("💰 \(Fmt.money(a))") }
        if !location.isEmpty { lines.append("📍 \(location)") }
        if !notes.isEmpty { lines.append("📝 \(notes)") }
        return lines.joined(separator: "\n")
    }
}
