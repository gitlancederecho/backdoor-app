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
