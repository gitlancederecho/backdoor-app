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
    private nonisolated(unsafe) var realtimeChannel: RealtimeChannelV2?

    init(date: String = todayISO()) {
        self.date = date
        Task { await start() }
    }

    private func start() async {
        isLoading = true
        await generateIfNeeded()
        await fetchTasks()
        await startRealtime()
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

    /// Swap the board to a different business-day ISO date. Tears down
    /// the existing realtime subscription (scoped to the previous
    /// date), re-runs generate_daily_tasks for the target, reloads,
    /// and resubscribes on the new date's channel.
    func setDate(_ newDate: String) async {
        guard newDate != date else { return }
        date = newDate
        tasks = []
        isLoading = true
        await generateIfNeeded()
        await fetchTasks()
        await startRealtime()
    }

    /// Supabase caches channels by topic, so calling `channel(topic)`
    /// a second time returns the *same* already-subscribed instance —
    /// and adding a new `postgresChange` callback to an already-
    /// subscribed channel throws. Explicitly `removeChannel` on
    /// teardown so the next `startRealtime` gets a fresh binding.
    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            await supabase.removeChannel(ch)
            realtimeChannel = nil
        }
    }

    private func startRealtime() async {
        await stopRealtime()
        let channel = supabase.channel("daily_tasks_ios_\(date)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "daily_tasks",
            filter: "date=eq.\(date)"
        )
        await channel.subscribe()
        realtimeChannel = channel
        realtimeTask = Task {
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

        // One-off templates are "done" once their last daily_task is
        // completed. Auto-soft-delete + log a template-level deleted
        // event so the History tab reflects the full lifecycle.
        await maybeAutoRetireOneOff(template: task.task, actorId: staffId)
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

    /// Reassign a single daily_task (not the template) to a specific
    /// staff member, or nil to clear. Writes the new assigned_to and
    /// logs a `reassigned` task_event so the change shows in History.
    /// No-op when the new assignee matches the old one.
    ///
    /// Custom encoding below so that `assigned_to = nil` goes on the
    /// wire as explicit `null` — Swift's default Encodable omits nil
    /// Optional keys, which Postgres would interpret as "leave column
    /// alone" and quietly fail to unassign.
    ///
    /// The caller passes the full `Staff` (not just the id) so we can
    /// populate the in-memory joined `assignee` alongside `assignedTo`
    /// for an immediate, correctly-labelled optimistic update.
    func reassign(task: DailyTask, to newStaff: Staff?, actorId: UUID) async throws {
        let newId = newStaff?.id
        guard task.assignedTo != newId else { return }

        struct Patch: Encodable {
            let assignedTo: UUID?
            enum CodingKeys: String, CodingKey { case assignedTo = "assigned_to" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(assignedTo, forKey: .assignedTo)  // emits null when nil
            }
        }

        // Optimistic local update so the UI reflects the change before
        // the round-trip finishes. Both fields get updated so the row's
        // display (which reads `assignee` for the joined name/avatar)
        // matches `assignedTo` immediately.
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].assignedTo = newId
            tasks[idx].assignee = newStaff
        }

        try await supabase
            .from("daily_tasks")
            .update(Patch(assignedTo: newId))
            .eq("id", value: task.id)
            .execute()

        let event = NewTaskEvent(
            dailyTaskId: task.id,
            actorId: actorId,
            eventType: TaskEventType.reassigned.rawValue,
            fromValue: task.assignedTo?.uuidString,
            toValue: newId?.uuidString
        )
        _ = try? await supabase.from("task_events").insert(event).execute()
    }

    /// Patch just the note and/or photo on a daily_task — used when an
    /// admin/staff edits these fields on an already-completed row.
    /// Logs either `note_added` (empty → non-empty), `note_updated`
    /// (non-empty → different non-empty), or `photo_added` when the
    /// photo URL changes. Multiple events may fire if both change.
    func updateNoteAndPhoto(
        task: DailyTask,
        actorId: UUID,
        note newNote: String?,
        photoUrl newPhoto: String?
    ) async throws {
        let cleanNew = (newNote?.isEmpty == true) ? nil : newNote
        let old = task.note?.isEmpty == true ? nil : task.note
        let noteChanged = cleanNew != old
        let photoChanged = newPhoto != task.photoUrl

        guard noteChanged || photoChanged else { return }

        let patch = DailyTaskPatch(note: cleanNew, photoUrl: newPhoto)
        try await applyPatch(id: task.id, patch: patch)

        if noteChanged {
            let type: TaskEventType = (old == nil) ? .note_added : .note_updated
            await logEvent(dailyTaskId: task.id, actorId: actorId, type: type, note: cleanNew)
        }
        if photoChanged, let url = newPhoto {
            await logEvent(dailyTaskId: task.id, actorId: actorId, type: .photo_added, photoUrl: url)
        }
    }

    func undo(task: DailyTask) async throws {
        let patch = DailyTaskPatch(status: .in_progress, completedBy: nil, completedAt: nil)
        try await applyPatch(id: task.id, patch: patch)
        // `actorId` here is whoever is logged in — not necessarily who originally completed.
        // This is why the audit log is useful: admins can see the undo.
        let actor = await currentStaffId()
        await logEvent(dailyTaskId: task.id, actorId: actor, type: .undone)

        // Symmetric to the auto-retire on complete: if this daily_task
        // belongs to an auto-retired one-off template, bring the
        // template back to active.
        await maybeRestoreRetiredOneOff(template: task.task, actorId: actor)
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

    // MARK: - Auto-retire one-off templates

    /// When the last non-completed daily_task of a non-recurring template
    /// flips to `completed`, soft-delete the template and log a
    /// template-level `deleted` event. No-op for recurring templates and
    /// when other non-completed rows still exist.
    private func maybeAutoRetireOneOff(template: TaskTemplate?, actorId: UUID?) async {
        guard let template, !template.isRecurring else { return }

        struct MiniDT: Decodable { let id: UUID }
        let remaining: [MiniDT] = (try? await supabase
            .from("daily_tasks")
            .select("id")
            .eq("task_id", value: template.id)
            .neq("status", value: TaskStatus.completed.rawValue)
            .execute()
            .value) ?? []
        guard remaining.isEmpty else { return }

        _ = try? await supabase
            .from("tasks")
            .update(["is_active": false])
            .eq("id", value: template.id)
            .execute()

        let event = NewTaskEvent(
            dailyTaskId: nil,
            actorId: actorId,
            eventType: TaskEventType.deleted.rawValue,
            fromValue: template.id.uuidString,
            toValue: nil,
            note: template.title,
            photoUrl: nil
        )
        _ = try? await supabase.from("task_events").insert(event).execute()
    }

    /// Symmetric restore for `undo` on a completion. Re-fetches the
    /// template's current is_active (the in-memory `task.task` snapshot
    /// may still read as active from the pre-completion fetch).
    private func maybeRestoreRetiredOneOff(template: TaskTemplate?, actorId: UUID?) async {
        guard let template, !template.isRecurring else { return }

        let current: TaskTemplate? = try? await supabase
            .from("tasks")
            .select()
            .eq("id", value: template.id)
            .single()
            .execute()
            .value
        guard let t = current, !t.isActive else { return }

        _ = try? await supabase
            .from("tasks")
            .update(["is_active": true])
            .eq("id", value: template.id)
            .execute()

        let event = NewTaskEvent(
            dailyTaskId: nil,
            actorId: actorId,
            eventType: TaskEventType.undone.rawValue,
            fromValue: nil,
            toValue: template.id.uuidString,
            note: template.title,
            photoUrl: nil
        )
        _ = try? await supabase.from("task_events").insert(event).execute()
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

    // MARK: - Comments

    /// Fetch the comment thread for a daily_task, oldest first so the
    /// UI can render like a chat (newest at bottom).
    func fetchComments(for dailyTaskId: UUID) async -> [TaskComment] {
        let result: [TaskComment] = (try? await supabase
            .from("task_comments")
            .select("*, author:staff!task_comments_author_id_fkey(*)")
            .eq("daily_task_id", value: dailyTaskId)
            .order("created_at", ascending: true)
            .execute()
            .value) ?? []
        return result
    }

    /// Post a new comment. Returns the row as the DB saw it so the
    /// caller can append it immediately (realtime will also deliver it,
    /// but we dedupe by id).
    @discardableResult
    func postComment(dailyTaskId: UUID, authorId: UUID, body: String) async throws -> TaskComment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "Backdoor.TaskViewModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Comment body is empty"]
            )
        }
        let new = NewTaskComment(
            dailyTaskId: dailyTaskId,
            authorId: authorId,
            body: trimmed
        )
        let inserted: TaskComment = try await supabase
            .from("task_comments")
            .insert(new)
            .select("*, author:staff!task_comments_author_id_fkey(*)")
            .single()
            .execute()
            .value
        return inserted
    }

    func deleteComment(id: UUID) async throws {
        try await supabase
            .from("task_comments")
            .delete()
            .eq("id", value: id)
            .execute()
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
