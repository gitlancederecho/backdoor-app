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

    /// Realtime plumbing — covers `venue_settings`, `venue_schedule`,
    /// and `venue_schedule_override`. Any change refreshes the whole
    /// VM via `load`. Topic includes a UUID for the same channel-
    /// caching reason as `AdminViewModel.startRealtime`.
    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?

    init() {
        Task {
            await load()
            await startRealtime()
        }
    }

    private func startRealtime() async {
        await stopRealtime()
        let channel = supabase.channel("venue_observer_\(UUID().uuidString.prefix(8))")
        let settingsStream  = channel.postgresChange(AnyAction.self, schema: "public", table: "venue_settings")
        let scheduleStream  = channel.postgresChange(AnyAction.self, schema: "public", table: "venue_schedule")
        let overridesStream = channel.postgresChange(AnyAction.self, schema: "public", table: "venue_schedule_override")
        try? await channel.subscribeWithError()
        realtimeChannel = channel
        realtimeTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in settingsStream {
                        guard !Task.isCancelled else { break }
                        await self?.load()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in scheduleStream {
                        guard !Task.isCancelled else { break }
                        await self?.load()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in overridesStream {
                        guard !Task.isCancelled else { break }
                        await self?.fetchOverrides()
                    }
                }
            }
        }
    }

    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            await supabase.removeChannel(ch)
            realtimeChannel = nil
        }
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
        // Optimistic: drop locally so the row vanishes the instant
        // the user confirms. The realtime subscription on
        // `venue_schedule_override` (wired in init) will refresh
        // ~200ms later. On server reject we put it back.
        let prior = overrides.first { $0.date == date }
        let priorIndex = overrides.firstIndex { $0.date == date }
        if let pi = priorIndex {
            overrides.remove(at: pi)
        }

        do {
            try await supabase
                .from("venue_schedule_override")
                .delete()
                .eq("date", value: date)
                .execute()
        } catch {
            if let pi = priorIndex, let ov = prior {
                overrides.insert(ov, at: min(pi, overrides.count))
            }
            throw error
        }
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
