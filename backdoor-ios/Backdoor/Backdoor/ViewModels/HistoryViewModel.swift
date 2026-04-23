import Foundation
import Observation
import Supabase

enum HistoryDateRange: CaseIterable, Identifiable {
    case today, last7, last30, all
    var id: Self { self }

    /// Inclusive lower bound — nil for `.all`.
    func startDate(now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .today:
            return cal.startOfDay(for: now)
        case .last7:
            return cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))
        case .last30:
            return cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now))
        case .all:
            return nil
        }
    }
}

@Observable
@MainActor
final class HistoryViewModel {
    var events: [TaskEvent] = []
    var isLoading = false
    var error: String?

    // Filters
    var dateRange: HistoryDateRange = .last7 {
        didSet { if dateRange != oldValue { Task { await load() } } }
    }
    /// Empty set means "all types". Populated set applies an `in` filter.
    var selectedEventTypes: Set<TaskEventType> = [] {
        didSet { if selectedEventTypes != oldValue { Task { await load() } } }
    }
    /// nil = any actor. UUID = specific actor.
    var selectedActorId: UUID? = nil {
        didSet { if selectedActorId != oldValue { Task { await load() } } }
    }
    /// Free-text search — filtered client-side over already-fetched
    /// events (server-side would need a view or RPC since we'd match
    /// through the joined daily_task → task title).
    var searchText: String = ""

    /// Cap the result size so the list stays snappy on "all" + busy projects.
    /// 500 events ≈ a month of moderate activity.
    private let fetchLimit = 500

    init() { Task { await load() } }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Build the query. PostgREST chaining returns a new builder each
        // step, so we hold it in a single variable and overwrite.
        // The nested embeds on daily_tasks mirror TaskViewModel.fetchTasks
        // so the TaskCompletionSheet (opened on row tap) renders without
        // a second round-trip for assignee / starter / completer.
        var q = supabase
            .from("task_events")
            .select(
                """
                *,
                actor:staff!task_events_actor_id_fkey(*),
                dailyTask:daily_tasks(
                    *,
                    task:tasks(*),
                    assignee:staff!daily_tasks_assigned_to_fkey(*),
                    starter:staff!daily_tasks_started_by_fkey(*),
                    completer:staff!daily_tasks_completed_by_fkey(*)
                )
                """
            )

        if let start = dateRange.startDate() {
            let iso = ISO8601DateFormatter().string(from: start)
            q = q.gte("created_at", value: iso)
        }

        if !selectedEventTypes.isEmpty {
            q = q.in("event_type", values: selectedEventTypes.map(\.rawValue))
        }

        if let actor = selectedActorId {
            q = q.eq("actor_id", value: actor)
        }

        do {
            let result: [TaskEvent] = try await q
                .order("created_at", ascending: false)
                .limit(fetchLimit)
                .execute()
                .value
            // A fresh refresh could have been fired while we were
            // awaiting — don't clobber the newer result with ours.
            guard !Task.isCancelled else { return }
            events = result
        } catch is CancellationError {
            // SwiftUI may cancel the .refreshable task when the view
            // re-renders (filter change, observable mutation, parent
            // invalidation). Leave existing state alone — another load
            // will follow.
            return
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            // URLSession reports cancellation via URLError; same
            // semantics as Swift's CancellationError for our purposes.
            return
        } catch {
            self.error = error.localizedDescription
            // Keep the previous events so pull-to-refresh doesn't blank
            // the list on a transient failure.
        }
    }

    func refresh() async { await load() }

    // MARK: - Search + Grouping

    /// Events narrowed by the free-text search. If `searchText` is
    /// empty returns the full list.
    var filteredEvents: [TaskEvent] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return events }
        return events.filter { e in
            if let n = e.note, n.localizedCaseInsensitiveContains(q) { return true }
            if let t = e.dailyTask?.task?.title, t.localizedCaseInsensitiveContains(q) { return true }
            if let t = e.dailyTask?.task?.titleJa, t.localizedCaseInsensitiveContains(q) { return true }
            if let name = e.actor?.name, name.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    /// Grouped by the ISO date of `created_at` (venue-agnostic calendar
    /// date in the user's local tz). Sorted descending (newest day first).
    var groupedByDate: [(date: String, events: [TaskEvent])] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        var buckets: [String: [TaskEvent]] = [:]
        for e in filteredEvents {
            let key = df.string(from: e.createdAt)
            buckets[key, default: []].append(e)
        }
        return buckets
            .map { (date: $0.key, events: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }
}
