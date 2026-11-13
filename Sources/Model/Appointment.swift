import Foundation
import SwiftUI

struct Appointment: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var icon: String? = nil
    var date = Date()
    var hasTime = true
    var location = ""
    var notes = ""
    /// Minutes before the appointment. For all-day ones, before the default reminder time that day.
    var reminders: [Int] = [1440, 60]
    var createdAt = Date()
    /// Last edit; the newest copy wins when syncing between phones.
    var updatedAt = Date()
    /// This phone's event in the iCloud calendar (never synced).
    var calendarEventID: String? = nil
    /// Category from older versions of the app; anything but an appointment is dropped.
    var legacyCategory: String? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, title, icon, date, hasTime, location, notes, reminders, createdAt, updatedAt, calendarEventID
        case legacyCategory = "category"
    }

    /// Tolerant decoding so files from older versions (and other phones) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? Date()
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? true
        location = (try? c.decodeIfPresent(String.self, forKey: .location)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        reminders = (try? c.decodeIfPresent([Int].self, forKey: .reminders)) ?? [1440, 60]
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
        calendarEventID = try? c.decodeIfPresent(String.self, forKey: .calendarEventID)
        legacyCategory = try? c.decodeIfPresent(String.self, forKey: .legacyCategory)
    }

    var isAppointment: Bool { legacyCategory == nil || legacyCategory == "appointment" }

    var displayIcon: String { icon ?? "calendar.badge.clock" }

    /// The moment reminders count back from: the time, or the default reminder time on an all-day date.
    func dueMoment(reminderMinutes: Int) -> Date {
        hasTime ? date : Fmt.greg.startOfDay(for: date).addingTimeInterval(TimeInterval(reminderMinutes * 60))
    }

    /// When the appointment is over: one hour after a timed one, end of day for an all-day one.
    var endMoment: Date {
        hasTime ? date.addingTimeInterval(3600) : (Fmt.greg.date(byAdding: .day, value: 1, to: Fmt.greg.startOfDay(for: date)) ?? date)
    }

    func isPast(now: Date = Date()) -> Bool { endMoment <= now }

    func status(now: Date = Date()) -> Status {
        if isPast(now: now) { return .past }
        let cal = Fmt.greg
        let diff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if diff <= 0 { return .today }
        if diff == 1 { return .tomorrow }
        if diff <= 7 { return .week }
        return .later
    }

    enum Status { case today, tomorrow, week, later, past }

    var subtitle: String {
        var parts = [hasTime ? Fmt.timeText(date) : L("طوال اليوم", "All day")]
        if !location.isEmpty { parts.append(location) }
        return Fmt.joined(parts)
    }

    func sameContent(as o: Appointment) -> Bool {
        var a = self, b = o
        a.updatedAt = .distantPast; b.updatedAt = .distantPast
        a.calendarEventID = nil; b.calendarEventID = nil
        return a == b
    }

    var shareText: String {
        var lines = ["📌 \(title)", "📅 \(Fmt.dateText(date, hasTime: hasTime, long: true))", "🌙 \(Fmt.hijriText(date))"]
        if !location.isEmpty { lines.append("📍 \(location)") }
        if !notes.isEmpty { lines.append("📝 \(notes)") }
        return lines.joined(separator: "\n")
    }
}

/// Reminder offsets are minutes before the appointment.
enum ReminderOption {
    static let all: [Int] = [0, 15, 30, 60, 120, 180, 1440, 2880, 10080]

    static func options(hasTime: Bool) -> [Int] {
        hasTime ? all : all.filter { $0 == 0 || $0 >= 1440 }
    }

    static func label(_ m: Int, hasTime: Bool) -> String {
        switch m {
        case 0: return hasTime ? L("وقت الموعد", "At the time") : L("صباح اليوم نفسه", "Morning of the day")
        case ..<60: return L("قبل \(Fmt.minutes(m))", "\(Fmt.minutes(m)) before")
        case ..<1440: return L("قبل \(Fmt.hours(m / 60))", "\(Fmt.hours(m / 60)) before")
        case ..<10080: return L("قبل \(Fmt.days(m / 1440))", "\(Fmt.days(m / 1440)) before")
        default: return L("قبل \(Fmt.weeks(m / 10080))", "\(Fmt.weeks(m / 10080)) before")
        }
    }

    static func summary(_ list: [Int], hasTime: Bool) -> String {
        if list.isEmpty { return L("بدون تنبيه", "No reminder") }
        return list.sorted(by: >).map { label($0, hasTime: hasTime) }.joined(separator: L("، ", ", "))
    }
}

/// Quick titles with an icon, shown as chips when adding an appointment.
struct Suggestion: Identifiable {
    let title: String
    let icon: String
    var id: String { title }

    static var all: [Suggestion] { [
        Suggestion(title: L("موعد مستشفى", "Hospital"), icon: "stethoscope"),
        Suggestion(title: L("موعد أسنان", "Dentist"), icon: "mouth.fill"),
        Suggestion(title: L("مراجعة جهة حكومية", "Government office"), icon: "building.columns.fill"),
        Suggestion(title: L("اجتماع", "Meeting"), icon: "person.3.fill"),
        Suggestion(title: L("صيانة السيارة", "Car service"), icon: "car.fill"),
        Suggestion(title: L("مناسبة", "Occasion"), icon: "gift.fill"),
        Suggestion(title: L("سفر", "Travel"), icon: "airplane"),
        Suggestion(title: L("موعد", "Appointment"), icon: "calendar.badge.clock"),
    ] }
}
