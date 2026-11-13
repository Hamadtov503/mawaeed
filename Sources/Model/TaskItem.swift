import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low, medium, high, urgent
    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return L("منخفضة", "Low")
        case .medium: return L("متوسطة", "Medium")
        case .high: return L("عالية", "High")
        case .urgent: return L("قصوى", "Urgent")
        }
    }
}

/// A task: an icon, a priority, open-ended or scheduled (start and end), a reminder, done/undone.
struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var notes = ""
    var icon: String? = nil
    var priority: TaskPriority = .medium
    /// When a scheduled task starts (nil for an open task).
    var start: Date? = nil
    /// When a scheduled task ends — its due time (nil for an open task).
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
        case id, title, notes, icon, priority, start, due, hasTime, remind, isDone, doneAt, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        priority = (try? c.decodeIfPresent(TaskPriority.self, forKey: .priority)) ?? .medium
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
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

    /// On the calendar a scheduled task covers every day from its start to its end.
    func isDue(on day: Date) -> Bool {
        guard let d = due else { return false }
        let cal = Fmt.greg
        if let st = start, cal.startOfDay(for: st) <= cal.startOfDay(for: day), cal.startOfDay(for: day) <= cal.startOfDay(for: d) {
            return true
        }
        return cal.isDate(d, inSameDayAs: day)
    }

    var isScheduled: Bool { due != nil }
    var displayIcon: String { icon ?? "checklist" }

    /// "from … to …" for a scheduled task; nil for an open one.
    var dueText: String? {
        guard let d = due else { return nil }
        guard let st = start else { return Fmt.dateText(d, hasTime: hasTime) }
        let sameDay = Fmt.greg.isDate(st, inSameDayAs: d)
        let end = sameDay ? Fmt.timeText(d) : Fmt.dateText(d, hasTime: true)
        return L("من \(Fmt.dateText(st, hasTime: true)) إلى \(end)", "\(Fmt.dateText(st, hasTime: true)) – \(end)")
    }

    /// Icons to choose from when adding a task.
    static let icons = ["checklist", "cart.fill", "house.fill", "briefcase.fill", "book.fill", "phone.fill",
                        "envelope.fill", "car.fill", "cross.case.fill", "heart.fill", "creditcard.fill",
                        "doc.text.fill", "wrench.and.screwdriver.fill", "gift.fill", "airplane",
                        "graduationcap.fill", "person.2.fill", "leaf.fill", "fork.knife", "bag.fill",
                        "figure.walk", "star.fill"]

    func sameContent(as o: TaskItem) -> Bool {
        var a = self, b = o
        a.updatedAt = .distantPast; b.updatedAt = .distantPast
        return a == b
    }
}
