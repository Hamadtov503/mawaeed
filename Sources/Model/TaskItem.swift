import Foundation

/// A task: a title, an optional due date (with or without a time), a reminder, and done/undone.
struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var notes = ""
    var due: Date? = nil
    var hasTime = false
    /// Remind at the due time (or at the default reminder time on an all-day date).
    var remind = true
    var isDone = false
    var doneAt: Date? = nil
    var createdAt = Date()
    var updatedAt = Date()

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, title, notes, due, hasTime, remind, isDone, doneAt, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        due = try? c.decodeIfPresent(Date.self, forKey: .due)
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
        remind = (try? c.decodeIfPresent(Bool.self, forKey: .remind)) ?? true
        isDone = (try? c.decodeIfPresent(Bool.self, forKey: .isDone)) ?? false
        doneAt = try? c.decodeIfPresent(Date.self, forKey: .doneAt)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    func reminderMoment(reminderMinutes: Int) -> Date? {
        guard let d = due else { return nil }
        return hasTime ? d : Fmt.greg.startOfDay(for: d).addingTimeInterval(TimeInterval(reminderMinutes * 60))
    }

    func isOverdue(now: Date = Date()) -> Bool {
        guard !isDone, let d = due else { return false }
        return hasTime ? d < now : Fmt.greg.startOfDay(for: d) < Fmt.greg.startOfDay(for: now)
    }

    func isDue(on day: Date) -> Bool {
        guard let d = due else { return false }
        return Fmt.greg.isDate(d, inSameDayAs: day)
    }

    var dueText: String? {
        guard let d = due else { return nil }
        return Fmt.dateText(d, hasTime: hasTime)
    }

    func sameContent(as o: TaskItem) -> Bool {
        var a = self, b = o
        a.updatedAt = .distantPast; b.updatedAt = .distantPast
        return a == b
    }
}
