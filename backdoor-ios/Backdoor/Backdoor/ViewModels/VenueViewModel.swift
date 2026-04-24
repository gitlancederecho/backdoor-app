import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class VenueViewModel {
    var settings: VenueSettings = .fallback
    /// Indexed by weekday (1..7). Always exactly 7 entries after load.
    var schedule: [VenueDay] = VenueViewModel.defaultSchedule()
    /// All per-date overrides, sorted by date ascending. Includes past
    /// rows so the admin can see history; the UI filters to upcoming.
    var overrides: [VenueScheduleOverride] = []
    var isLoaded = false

    init() {
        Task { await load() }
    }

    func load() async {
        let settingsRows: [VenueSettings] = (try? await supabase
            .from("venue_settings")
            .select()
            .eq("id", value: 1)
            .limit(1)
            .execute()
            .value) ?? []
        if let s = settingsRows.first { settings = s }

        let days: [VenueDay] = (try? await supabase
            .from("venue_schedule")
            .select()
            .order("weekday")
            .execute()
            .value) ?? []
        if !days.isEmpty {
            var byDay: [Int16: VenueDay] = Dictionary(uniqueKeysWithValues: days.map { ($0.weekday, $0) })
            for wd in Int16(1)...Int16(7) where byDay[wd] == nil {
                byDay[wd] = VenueDay(weekday: wd, isClosed: false,
                                     openTime: "17:00:00", closeTime: "03:00:00")
            }
            schedule = (Int16(1)...Int16(7)).map { byDay[$0]! }
        }

        await fetchOverrides()

        isLoaded = true
    }

    func fetchOverrides() async {
        let ovs: [VenueScheduleOverride] = (try? await supabase
            .from("venue_schedule_override")
            .select()
            .order("date")
            .execute()
            .value) ?? []
        overrides = ovs
    }

    /// Upcoming overrides including today, sorted ascending.
    var upcomingOverrides: [VenueScheduleOverride] {
        let today = VenueViewModel.isoToday()
        return overrides.filter { $0.date >= today }
    }

    /// Look up an override for a specific ISO date, if any.
    func override(for date: String) -> VenueScheduleOverride? {
        overrides.first { $0.date == date }
    }

    func day(for weekday: Int16) -> VenueDay? {
        schedule.first { $0.weekday == weekday }
    }

    // MARK: - Admin mutations

    func updateSettings(timezone: String? = nil,
                        prepBufferMinutes: Int16? = nil,
                        gracePeriodMinutes: Int16? = nil) async throws {
        try await supabase
            .from("venue_settings")
            .update(VenueSettingsPatch(
                timezone: timezone,
                prepBufferMinutes: prepBufferMinutes,
                gracePeriodMinutes: gracePeriodMinutes
            ))
            .eq("id", value: 1)
            .execute()
        await load()
    }

    func upsertDay(_ day: VenueDayUpsert) async throws {
        try await supabase
            .from("venue_schedule")
            .upsert(day, onConflict: "weekday")
            .execute()
        await load()
    }

    // MARK: - Overrides

    func upsertOverride(_ override: VenueScheduleOverrideUpsert) async throws {
        try await supabase
            .from("venue_schedule_override")
            .upsert(override, onConflict: "date")
            .execute()
        await fetchOverrides()
    }

    func deleteOverride(date: String) async throws {
        try await supabase
            .from("venue_schedule_override")
            .delete()
            .eq("date", value: date)
            .execute()
        await fetchOverrides()
    }

    // MARK: - Defaults

    private static func defaultSchedule() -> [VenueDay] {
        (Int16(1)...Int16(7)).map { wd in
            VenueDay(weekday: wd,
                     isClosed: wd == 7,
                     openTime: "17:00:00",
                     closeTime: "03:00:00")
        }
    }

    nonisolated static func isoToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
