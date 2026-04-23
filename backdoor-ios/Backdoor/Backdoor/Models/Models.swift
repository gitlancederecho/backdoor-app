import Foundation

// MARK: - Enums

enum UserRole: String, Codable {
    case admin, staff
}

enum Category: String, Codable, CaseIterable {
    case opening, closing, bar, cleaning, weekly, other

    var label: String {
        switch self {
        case .opening:  return "Opening"
        case .closing:  return "Closing"
        case .bar:      return "Bar"
        case .cleaning: return "Cleaning"
        case .weekly:   return "Weekly"
        case .other:    return "Other"
        }
    }

    var labelJa: String {
        switch self {
        case .opening:  return "オープン"
        case .closing:  return "クローズ"
        case .bar:      return "バー"
        case .cleaning: return "清掃"
        case .weekly:   return "週次"
        case .other:    return "その他"
        }
    }

    /// Localized label based on the user's selected app language.
    @MainActor
    var localized: String {
        switch self {
        case .opening:  return tr("cat_opening")
        case .closing:  return tr("cat_closing")
        case .bar:      return tr("cat_bar")
        case .cleaning: return tr("cat_cleaning")
        case .weekly:   return tr("cat_weekly")
        case .other:    return tr("cat_other")
        }
    }

    static var displayOrder: [Category] {
        [.opening, .bar, .cleaning, .closing, .weekly, .other]
    }
}

enum Priority: String, Codable, CaseIterable {
    case low, normal, high
}

enum TaskStatus: String, Codable {
    case pending, in_progress, completed

    var label: String {
        switch self {
        case .pending:     return "Pending"
        case .in_progress: return "In Progress"
        case .completed:   return "Done"
        }
    }
}

enum RecurrenceType: String, Codable, CaseIterable {
    case daily, weekly, monthly
}

// MARK: - Models

struct Staff: Codable, Identifiable {
    let id: UUID
    var name: String
    var role: UserRole
    var email: String
    var avatarUrl: String?
    var isActive: Bool
    let createdAt: Date

    var initials: String {
        name.split(separator: " ")
            .compactMap(\.first)
            .prefix(2)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct TaskTemplate: Codable, Identifiable {
    let id: UUID
    var title: String
    var titleJa: String?
    var category: Category
    var assignedTo: UUID?
    var isRecurring: Bool
    var recurrenceType: RecurrenceType?
    var recurrenceDays: [Int]?
    var priority: Priority
    var createdBy: UUID?
    var isActive: Bool
    /// "HH:mm:ss" — earliest time this task should start. Optional.
    var startTime: String?
    /// "HH:mm:ss" — latest time (deadline). Optional.
    var endTime: String?
    let createdAt: Date
}

struct DailyTask: Codable, Identifiable {
    let id: UUID
    let taskId: UUID?
    var date: String
    var assignedTo: UUID?
    var status: TaskStatus
    var startedBy: UUID?
    var startedAt: Date?
    var completedBy: UUID?
    var completedAt: Date?
    var note: String?
    var photoUrl: String?
    /// "HH:mm:ss" — copied from template when the daily_task was generated.
    var startTime: String?
    /// "HH:mm:ss" — deadline, copied from template.
    var endTime: String?
    let createdAt: Date

    // Joined relations
    var task: TaskTemplate?
    var assignee: Staff?
    var starter: Staff?
    var completer: Staff?
}

// MARK: - Audit log

enum TaskEventType: String, Codable, CaseIterable {
    case created, started, completed, undone, reassigned
    case note_added, note_updated, photo_added
}

struct TaskEvent: Codable, Identifiable {
    let id: UUID
    let dailyTaskId: UUID
    let actorId: UUID?
    let eventType: TaskEventType
    let fromValue: String?
    let toValue: String?
    let note: String?
    let photoUrl: String?
    let createdAt: Date

    // Joined
    var actor: Staff?
    /// Populated when the query embeds daily_tasks (and its task template).
    /// Lets the History view render task title + business day without
    /// a second lookup.
    var dailyTask: DailyTask?
}

struct NewTaskEvent: Encodable {
    var dailyTaskId: UUID
    var actorId: UUID?
    var eventType: String
    var fromValue: String?
    var toValue: String?
    var note: String?
    var photoUrl: String?
}

// MARK: - Time helpers

enum TimeOfDay {
    /// Parse "HH:mm:ss" or "HH:mm" into (hour, minute) — today's date at that time.
    static func parse(_ timeString: String) -> (hour: Int, minute: Int)? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// Format a Date into "HH:mm:ss" (DB format).
    static func dbString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    /// Format "HH:mm:ss" into a user-facing "17:00" (locale-respecting).
    static func displayString(from timeString: String) -> String {
        guard let (h, m) = parse(timeString) else { return timeString }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        var comps = DateComponents()
        comps.hour = h
        comps.minute = m
        return Calendar.current.date(from: comps).map { f.string(from: $0) } ?? "\(h):\(m)"
    }

    /// Minutes from midnight.
    static func minutesFromMidnight(_ timeString: String) -> Int? {
        guard let (h, m) = parse(timeString) else { return nil }
        return h * 60 + m
    }

    /// Minutes from midnight for Date.now (user's local tz).
    static var nowMinutes: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}

// MARK: - Insertable types (no id / createdAt — DB sets these)

struct NewTask: Encodable {
    var title: String
    var titleJa: String?
    var category: Category
    var assignedTo: UUID?
    var isRecurring: Bool
    var recurrenceType: RecurrenceType?
    var recurrenceDays: [Int]?
    var priority: Priority
    var createdBy: UUID?
    var isActive: Bool = true
    /// "HH:mm:ss" or nil.
    var startTime: String?
    /// "HH:mm:ss" or nil.
    var endTime: String?
}

/// Row-level insert for daily_tasks. Used when we need to materialize a
/// daily_task outside of the generate_daily_tasks RPC — specifically,
/// when an admin creates a non-recurring template that the generator
/// won't pick up.
struct NewDailyTask: Encodable {
    var taskId: UUID
    var date: String
    var assignedTo: UUID?
    var status: String
    var startTime: String?
    var endTime: String?
}

struct DailyTaskPatch: Encodable {
    var status: TaskStatus?
    var assignedTo: UUID?
    var startedBy: UUID?
    var startedAt: Date?
    var completedBy: UUID?
    var completedAt: Date?
    var note: String?
    var photoUrl: String?
}
