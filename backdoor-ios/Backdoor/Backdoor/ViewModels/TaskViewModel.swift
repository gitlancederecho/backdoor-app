import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class TaskViewModel {
    var tasks: [DailyTask] = []
    var isLoading = true
    var isRefreshing = false
    var error: String?

    private(set) var date: String
    private nonisolated(unsafe) var realtimeTask: Task<Void, Never>?

    init(date: String = todayISO()) {
        self.date = date
        Task { await start() }
    }

    private func start() async {
        isLoading = true
        await generateIfNeeded()
        await fetchTasks()
        startRealtime()
    }

    private func generateIfNeeded() async {
        try? await supabase
            .rpc("generate_daily_tasks", params: ["target_date": date])
            .execute()
    }

    func fetchTasks() async {
        do {
            let result: [DailyTask] = try await supabase
                .from("daily_tasks")
                .select("""
                *,
                task:tasks(*),
                assignee:staff!daily_tasks_assigned_to_fkey(*),
                starter:staff!daily_tasks_started_by_fkey(*),
                completer:staff!daily_tasks_completed_by_fkey(*)
                """)
                .eq("date", value: date)
                .order("created_at")
                .execute()
                .value
            tasks = result
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
        isRefreshing = false
    }

    func pullRefresh() async {
        isRefreshing = true
        await fetchTasks()
    }

    private func startRealtime() {
        realtimeTask?.cancel()
        realtimeTask = Task {
            let channel = supabase.channel("daily_tasks_ios_\(date)")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "daily_tasks",
                filter: "date=eq.\(date)"
            )
            await channel.subscribe()
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await fetchTasks()
            }
        }
    }

    func complete(task: DailyTask, staffId: UUID, note: String?, photoUrl: String?) async throws {
        let now = Date()
        let cleanNote = (note?.isEmpty == true) ? nil : note
        let patch = DailyTaskPatch(
            status: .completed,
            assignedTo: task.assignedTo ?? staffId,
            completedBy: staffId,
            completedAt: now,
            note: cleanNote,
            photoUrl: photoUrl
        )
        try await applyPatch(id: task.id, patch: patch)
        await logEvent(dailyTaskId: task.id, actorId: staffId, type: .completed,
                       note: cleanNote, photoUrl: photoUrl)
    }

    func start(task: DailyTask, staffId: UUID) async throws {
        let patch = DailyTaskPatch(
            status: .in_progress,
            assignedTo: task.assignedTo ?? staffId,
            startedBy: staffId,
            startedAt: Date()
        )
        try await applyPatch(id: task.id, patch: patch)
        await logEvent(dailyTaskId: task.id, actorId: staffId, type: .started)
    }

    func undo(task: DailyTask) async throws {
        let patch = DailyTaskPatch(status: .in_progress, completedBy: nil, completedAt: nil)
        try await applyPatch(id: task.id, patch: patch)
        // `actorId` here is whoever is logged in — not necessarily who originally completed.
        // This is why the audit log is useful: admins can see the undo.
        let actor = await currentStaffId()
        await logEvent(dailyTaskId: task.id, actorId: actor, type: .undone)
    }

    private func applyPatch(id: UUID, patch: DailyTaskPatch) async throws {
        // Optimistic update
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            if let s = patch.status { tasks[idx].status = s }
            if let started = patch.startedAt { tasks[idx].startedAt = started }
            if let startedBy = patch.startedBy { tasks[idx].startedBy = startedBy }
            tasks[idx].completedBy = patch.completedBy
            tasks[idx].completedAt = patch.completedAt
            if let note = patch.note { tasks[idx].note = note }
            if let url = patch.photoUrl { tasks[idx].photoUrl = url }
        }
        try await supabase
            .from("daily_tasks")
            .update(patch)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Audit log

    private func logEvent(
        dailyTaskId: UUID,
        actorId: UUID?,
        type: TaskEventType,
        fromValue: String? = nil,
        toValue: String? = nil,
        note: String? = nil,
        photoUrl: String? = nil
    ) async {
        let event = NewTaskEvent(
            dailyTaskId: dailyTaskId,
            actorId: actorId,
            eventType: type.rawValue,
            fromValue: fromValue,
            toValue: toValue,
            note: note,
            photoUrl: photoUrl
        )
        _ = try? await supabase.from("task_events").insert(event).execute()
    }

    private func currentStaffId() async -> UUID? {
        guard let uid = try? await supabase.auth.session.user.id else { return nil }
        let rows: [Staff] = (try? await supabase
            .from("staff")
            .select()
            .eq("auth_user_id", value: uid)
            .limit(1)
            .execute()
            .value) ?? []
        return rows.first?.id
    }

    /// Fetch the full event history for a daily task, oldest first.
    func fetchEvents(for dailyTaskId: UUID) async -> [TaskEvent] {
        let result: [TaskEvent] = (try? await supabase
            .from("task_events")
            .select("*, actor:staff!task_events_actor_id_fkey(*)")
            .eq("daily_task_id", value: dailyTaskId)
            .order("created_at", ascending: true)
            .execute()
            .value) ?? []
        return result
    }

    deinit {
        realtimeTask?.cancel()
    }
}

// MARK: - Photo upload

func uploadTaskPhoto(taskId: UUID, date: String, imageData: Data, mimeType: String) async throws -> String {
    let ext = mimeType.contains("png") ? "png" : "jpg"
    let path = "\(date)/\(taskId)-\(Int(Date().timeIntervalSince1970)).\(ext)"
    try await supabase.storage
        .from(photoBucket)
        .upload(path, data: imageData, options: FileOptions(contentType: mimeType))
    let url = try supabase.storage.from(photoBucket).getPublicURL(path: path)
    return url.absoluteString
}

// MARK: - Helpers

func todayISO() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f.string(from: Date())
}

func formattedDate(_ iso: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    guard let d = f.date(from: iso) else { return iso }
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    out.doesRelativeDateFormatting = true
    return out.string(from: d)
}

func formattedTime(_ date: Date?) -> String {
    guard let date else { return "" }
    let f = DateFormatter()
    f.timeStyle = .short
    return f.string(from: date)
}
