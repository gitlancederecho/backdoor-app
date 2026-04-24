import Foundation

struct VenueSettings: Codable {
    var id: Int16
    var timezone: String
    var prepBufferMinutes: Int16
    /// How many minutes past close_time we still consider part of the same business day.
    /// Handles unforeseen overtime (bar stays open late).
    var gracePeriodMinutes: Int16
    var updatedAt: Date?

    static let fallback = VenueSettings(
        id: 1,
        timezone: "Asia/Tokyo",
        prepBufferMinutes: 240,
        gracePeriodMinutes: 120,
        updatedAt: nil
    )

    var timeZone: TimeZone {
        TimeZone(identifier: timezone) ?? TimeZone(identifier: "Asia/Tokyo") ?? .current
    }
}

struct VenueDay: Codable, Identifiable {
    /// 1=Mon..7=Sun (ISO weekday)
    var weekday: Int16
    var isClosed: Bool
    /// "HH:mm:ss" in venue timezone
    var openTime: String?
    /// "HH:mm:ss" in venue timezone; may be after midnight relative to openTime
    var closeTime: String?
    var updatedAt: Date?

    var id: Int16 { weekday }

    var closesNextCalendarDay: Bool {
        guard let open = openTime.flatMap(TimeOfDay.minutesFromMidnight),
              let close = closeTime.flatMap(TimeOfDay.minutesFromMidnight) else {
            return false
        }
        return close <= open
    }
}

/// For inserting / upserting venue_schedule rows.
struct VenueDayUpsert: Encodable {
    var weekday: Int16
    var isClosed: Bool
    var openTime: String?
    var closeTime: String?
}

/// For updating venue_settings.
struct VenueSettingsPatch: Encodable {
    var timezone: String?
    var prepBufferMinutes: Int16?
    var gracePeriodMinutes: Int16?
}

/// A per-date exception to the weekly schedule. Any nil field = "inherit
/// the weekday default." `reason` is a free-form label ("Staff training",
/// "Golden Week").
struct VenueScheduleOverride: Codable, Identifiable, Hashable {
    /// "yyyy-MM-dd" in venue timezone.
    var date: String
    var isClosed: Bool?
    /// "HH:mm:ss"
    var openTime: String?
    /// "HH:mm:ss"
    var closeTime: String?
    var reason: String?
    var updatedAt: Date?
    var createdAt: Date?

    var id: String { date }

    /// True when this override only sets a reason (no hours / closed
    /// flag change). Useful to flag "notes-only" rows in the UI.
    var isNotesOnly: Bool {
        isClosed == nil && openTime == nil && closeTime == nil && !(reason ?? "").isEmpty
    }
}

/// For upserting `venue_schedule_override`. Uses a custom encoder so that
/// nil fields are serialized as explicit JSON null (clearing the DB
/// column) rather than being omitted — same trap as `DailyTaskPatch`,
/// but here we actually want the null semantics.
struct VenueScheduleOverrideUpsert: Encodable {
    var date: String
    var isClosed: Bool?
    var openTime: String?
    var closeTime: String?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case date
        case isClosed = "is_closed"
        case openTime = "open_time"
        case closeTime = "close_time"
        case reason
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(isClosed, forKey: .isClosed)
        try c.encode(openTime, forKey: .openTime)
        try c.encode(closeTime, forKey: .closeTime)
        try c.encode(reason, forKey: .reason)
    }
}
