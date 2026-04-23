import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class VenueViewModel {
    var settings: VenueSettings = .fallback
    /// Indexed by weekday (1..7). Always exactly 7 entries after load.
    var schedule: [VenueDay] = VenueViewModel.defaultSchedule()
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
        isLoaded = true
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

    // MARK: - Defaults

    private static func defaultSchedule() -> [VenueDay] {
        (Int16(1)...Int16(7)).map { wd in
            VenueDay(weekday: wd,
                     isClosed: wd == 7,
                     openTime: "17:00:00",
                     closeTime: "03:00:00")
        }
    }
}
