import Foundation

/// Business-day logic: a "business day" is identified by the calendar date
/// of the day a venue's shift opens. A shift that opens at 17:00 Monday
/// and closes at 03:00 Tuesday is one continuous business day = "Monday".
///
/// Rules:
///  - If we're still inside yesterday's shift (before today's close_time), we're on yesterday's business day.
///  - If we're within `prepBufferMinutes` before today's open_time (or after), we're on today's business day.
///  - Otherwise (between shifts, bar is "dark"), business day = the most recently completed open day.
enum BusinessDay {

    /// The calendar of the venue timezone.
    private static func cal(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }

    /// Returns isodow (1=Mon..7=Sun) for a calendar date in the given timezone.
    private static func isodow(_ date: Date, tz: TimeZone) -> Int16 {
        // Calendar.component(.weekday) returns 1=Sun..7=Sat. Convert to ISO.
        let sun1 = cal(tz).component(.weekday, from: date)
        return Int16(((sun1 + 5) % 7) + 1)
    }

    /// Format a date as "yyyy-MM-dd" in the venue timezone.
    static func iso(_ date: Date, tz: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = cal(tz)
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Parse "yyyy-MM-dd" to a Date at noon in the venue timezone (avoids DST edge cases).
    static func parse(_ iso: String, tz: TimeZone) -> Date? {
        let f = DateFormatter()
        f.calendar = cal(tz)
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: "\(iso) 12:00")
    }

    /// Clock time (hour, minute) in the given timezone.
    static func clock(_ date: Date, tz: TimeZone) -> (hour: Int, minute: Int, totalMinutes: Int) {
        let comps = cal(tz).dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return (h, m, h * 60 + m)
    }

    /// The effective `VenueDay` for a calendar date — the weekday default
    /// from `schedule` overlaid with that date's `venue_schedule_override`
    /// row (if any). Mirrors the SQL `effective_venue_hours(date)` so the
    /// client and server agree on what "open on date X" means.
    static func effectiveDay(
        for date: Date,
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride],
        tz: TimeZone
    ) -> VenueDay? {
        let wd = isodow(date, tz: tz)
        guard let base = schedule.first(where: { $0.weekday == wd }) else { return nil }
        guard let ov = overrides.first(where: { $0.date == iso(date, tz: tz) }) else { return base }
        return VenueDay(
            weekday: base.weekday,
            isClosed: ov.isClosed ?? base.isClosed,
            openTime: ov.openTime ?? base.openTime,
            closeTime: ov.closeTime ?? base.closeTime,
            updatedAt: base.updatedAt
        )
    }

    /// Calculate the current business-day ISO date for the given moment, schedule, and venue settings.
    /// Includes grace period handling for unforeseen overtime.
    static func currentBusinessDayISO(
        now: Date = Date(),
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride] = [],
        settings: VenueSettings
    ) -> String {
        let tz = settings.timeZone
        let nowClock = clock(now, tz: tz).totalMinutes
        let today = cal(tz).startOfDay(for: now)
        let yesterday = cal(tz).date(byAdding: .day, value: -1, to: today) ?? today

        let todayDay = effectiveDay(for: today, schedule: schedule, overrides: overrides, tz: tz)
        let yesterdayDay = effectiveDay(for: yesterday, schedule: schedule, overrides: overrides, tz: tz)

        let grace = Int(settings.gracePeriodMinutes)

        // Case 1a: yesterday's shift crosses midnight and we're still in it (with grace period)
        if let y = yesterdayDay,
           !y.isClosed,
           y.closesNextCalendarDay,
           let closeMins = y.closeTime.flatMap(TimeOfDay.minutesFromMidnight),
           nowClock < closeMins + grace {
            return iso(yesterday, tz: tz)
        }

        // Case 1b: yesterday's shift ended same-calendar-day but close+grace
        // extends past midnight into today. Put both sides of the comparison
        // in the same reference frame ("minutes past yesterday's midnight"):
        //   now side  = nowClock + 1440 (today's minutes + 24h)
        //   close side = closeMins + grace (same-calendar-day close + grace)
        //
        // Example: yesterday closed 18:00 (early-close shift), grace = 120.
        // True end of business day = 20:00 yesterday = 1200 min. At 01:30 today
        // now-side = 90 + 1440 = 1530 > 1200 → correctly returns false and we
        // fall through to Case 2/3 instead of erroneously returning yesterday.
        if let y = yesterdayDay,
           !y.isClosed,
           !y.closesNextCalendarDay, // Case 1a already handles midnight-crossing shifts
           let closeMins = y.closeTime.flatMap(TimeOfDay.minutesFromMidnight),
           (nowClock + 24 * 60) < (closeMins + grace) {
            return iso(yesterday, tz: tz)
        }

        // Case 2: today has an open shift and we're within prep window or past open
        if let t = todayDay, !t.isClosed,
           let openMins = t.openTime.flatMap(TimeOfDay.minutesFromMidnight) {
            let prepStart = openMins - Int(settings.prepBufferMinutes)
            if nowClock >= prepStart {
                return iso(today, tz: tz)
            }
        }

        // Case 3: we're between shifts. Walk back to find the most recent open day.
        for offset in 1...7 {
            guard let date = cal(tz).date(byAdding: .day, value: -offset, to: today) else { break }
            if let d = effectiveDay(for: date, schedule: schedule, overrides: overrides, tz: tz),
               !d.isClosed {
                return iso(date, tz: tz)
            }
        }

        // Fallback
        return iso(today, tz: tz)
    }

    /// Is the venue currently inside an active shift (open)?
    static func isCurrentlyOpen(
        now: Date = Date(),
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride] = [],
        settings: VenueSettings
    ) -> Bool {
        let tz = settings.timeZone
        let nowClock = clock(now, tz: tz).totalMinutes
        let today = cal(tz).startOfDay(for: now)
        let yesterday = cal(tz).date(byAdding: .day, value: -1, to: today) ?? today

        // Is yesterday's shift still running into today?
        if let y = effectiveDay(for: yesterday, schedule: schedule, overrides: overrides, tz: tz),
           !y.isClosed, y.closesNextCalendarDay,
           let close = y.closeTime.flatMap(TimeOfDay.minutesFromMidnight),
           nowClock < close {
            return true
        }

        // Is today's shift open now?
        if let t = effectiveDay(for: today, schedule: schedule, overrides: overrides, tz: tz),
           !t.isClosed,
           let open = t.openTime.flatMap(TimeOfDay.minutesFromMidnight),
           let close = t.closeTime.flatMap(TimeOfDay.minutesFromMidnight) {
            if t.closesNextCalendarDay {
                return nowClock >= open || nowClock < close  // wraps midnight
            } else {
                return nowClock >= open && nowClock < close
            }
        }
        return false
    }

    /// Is the given business-day ISO date a closed day?
    static func isClosed(
        dayISO: String,
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride] = [],
        tz: TimeZone
    ) -> Bool {
        guard let date = parse(dayISO, tz: tz) else { return false }
        return effectiveDay(for: date, schedule: schedule, overrides: overrides, tz: tz)?.isClosed ?? false
    }

    // MARK: - Minutes-since-business-day-start

    /// Given a clock-time "HH:mm:ss" and the schedule for a specific business day,
    /// returns how many minutes into that business day this clock time is.
    ///
    /// Example: business day schedule = open 17:00, close 03:00 (next day), prep = 240min (start = 13:00)
    ///  - 13:00 → 0 min
    ///  - 17:00 → 240 min
    ///  - 23:00 → 600 min
    ///  - 02:00 (next day) → 13 * 60 + 60 = 840 min
    static func minutesIntoBusinessDay(
        clockTimeHHmm: String,
        day: VenueDay,
        settings: VenueSettings
    ) -> Int? {
        guard let clockMins = TimeOfDay.minutesFromMidnight(clockTimeHHmm),
              let openMins = day.openTime.flatMap(TimeOfDay.minutesFromMidnight) else {
            return nil
        }
        let prepStart = openMins - Int(settings.prepBufferMinutes)
        // Business day starts at prepStart. Times before prepStart in the same calendar day
        // are considered "next day" wraparound.
        if clockMins >= prepStart {
            return clockMins - prepStart
        } else {
            // Clock is before prepStart, so it's either the morning after (closing hours)
            // or way before — we treat as "next day wraparound"
            return (clockMins + 24 * 60) - prepStart
        }
    }

    /// Minutes "now" is into the current business day.
    static func nowInBusinessDay(
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride] = [],
        settings: VenueSettings,
        now: Date = Date()
    ) -> Int {
        let tz = settings.timeZone
        let nowClockTime = clock(now, tz: tz)

        // Determine which day's schedule governs us (today's or yesterday's if we're in wraparound)
        let today = cal(tz).startOfDay(for: now)
        let yesterday = cal(tz).date(byAdding: .day, value: -1, to: today) ?? today

        // Check wraparound — are we still in yesterday's shift?
        if let y = effectiveDay(for: yesterday, schedule: schedule, overrides: overrides, tz: tz),
           !y.isClosed, y.closesNextCalendarDay,
           let close = y.closeTime.flatMap(TimeOfDay.minutesFromMidnight),
           nowClockTime.totalMinutes < close {
            // Use yesterday's schedule for calculation
            let hh = String(format: "%02d:%02d", nowClockTime.hour, nowClockTime.minute)
            return minutesIntoBusinessDay(clockTimeHHmm: hh, day: y, settings: settings) ?? 0
        }

        // Use today's schedule
        guard let todayDay = effectiveDay(for: today, schedule: schedule, overrides: overrides, tz: tz) else { return 0 }
        let hh = String(format: "%02d:%02d", nowClockTime.hour, nowClockTime.minute)
        return minutesIntoBusinessDay(clockTimeHHmm: hh, day: todayDay, settings: settings) ?? 0
    }

    /// Find the effective schedule entry for a given business-day ISO date,
    /// merging any per-date override into the weekday default.
    static func scheduleDay(
        for dayISO: String,
        schedule: [VenueDay],
        overrides: [VenueScheduleOverride] = [],
        tz: TimeZone
    ) -> VenueDay? {
        guard let date = parse(dayISO, tz: tz) else { return nil }
        return effectiveDay(for: date, schedule: schedule, overrides: overrides, tz: tz)
    }
}
