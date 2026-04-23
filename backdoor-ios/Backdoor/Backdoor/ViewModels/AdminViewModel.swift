import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AdminViewModel {
    var allStaff: [Staff] = []
    var taskTemplates: [TaskTemplate] = []
    var isLoading = false

    init() {
        Task { await fetchAll() }
    }

    func fetchAll() async {
        isLoading = true
        async let staffResult: [Staff] = (try? supabase
            .from("staff")
            .select()
            .order("name")
            .execute()
            .value) ?? []
        async let tasksResult: [TaskTemplate] = (try? supabase
            .from("tasks")
            .select()
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
        allStaff = await staffResult
        taskTemplates = await tasksResult
        isLoading = false
    }

    // MARK: - Task CRUD

    /// Create a new task template. For recurring templates the
    /// generate_daily_tasks RPC materializes any matching rows for today;
    /// non-recurring templates are ignored by that RPC (it filters to
    /// is_recurring=true) so we materialize a daily_task directly for the
    /// caller's business day. Without this second write, non-recurring
    /// tasks would never appear on anyone's board.
    func createTask(_ task: NewTask, businessDay: String) async throws {
        let inserted: TaskTemplate = try await supabase
            .from("tasks")
            .insert(task)
            .select()
            .single()
            .execute()
            .value

        if !task.isRecurring {
            let ad = NewDailyTask(
                taskId: inserted.id,
                date: businessDay,
                assignedTo: task.assignedTo,
                status: TaskStatus.pending.rawValue,
                startTime: task.startTime,
                endTime: task.endTime
            )
            // Best-effort. If this fails the admin can re-save — the unique
            // (task_id, date) constraint will make it safely idempotent.
            _ = try? await supabase.from("daily_tasks").insert(ad).execute()
        }

        try? await supabase.rpc("generate_daily_tasks").execute()
        await fetchAll()
    }

    func updateTask(id: UUID, _ task: NewTask, businessDay: String) async throws {
        try await supabase.from("tasks").update(task).eq("id", value: id).execute()

        // Propagate assignment + start/end changes to today's un-completed
        // daily_tasks so the admin's edit feels immediate.
        let existing: [DailyTask] = (try? await supabase
            .from("daily_tasks")
            .select()
            .eq("task_id", value: id)
            .eq("date", value: businessDay)
            .neq("status", value: TaskStatus.completed.rawValue)
            .execute()
            .value) ?? []

        struct PropagatePatch: Encodable {
            var assignedTo: UUID?
            var startTime: String?
            var endTime: String?
        }
        try? await supabase
            .from("daily_tasks")
            .update(PropagatePatch(
                assignedTo: task.assignedTo,
                startTime: task.startTime,
                endTime: task.endTime
            ))
            .eq("task_id", value: id)
            .eq("date", value: businessDay)
            .neq("status", value: TaskStatus.completed.rawValue)
            .execute()

        // Log reassignment events
        let actor = await currentStaffId()
        for dt in existing where dt.assignedTo != task.assignedTo {
            let event = NewTaskEvent(
                dailyTaskId: dt.id,
                actorId: actor,
                eventType: TaskEventType.reassigned.rawValue,
                fromValue: dt.assignedTo?.uuidString,
                toValue: task.assignedTo?.uuidString
            )
            _ = try? await supabase.from("task_events").insert(event).execute()
        }

        try? await supabase.rpc("generate_daily_tasks").execute()
        await fetchAll()
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

    /// Soft-delete a task template + log one template-level `deleted`
    /// event so the History tab surfaces the action regardless of
    /// whether any daily_tasks had been materialized yet.
    ///
    /// The event uses `daily_task_id = null`, `from_value = templateId`,
    /// and `note = templateTitle` so History can render without needing
    /// to join back through a (now potentially missing) daily_task.
    func deleteTask(_ template: TaskTemplate) async throws {
        let actor = await currentStaffId()

        let event = NewTaskEvent(
            dailyTaskId: nil,
            actorId: actor,
            eventType: TaskEventType.deleted.rawValue,
            fromValue: template.id.uuidString,
            toValue: nil,
            note: template.title,
            photoUrl: nil
        )
        _ = try? await supabase.from("task_events").insert(event).execute()

        try await supabase
            .from("tasks")
            .update(["is_active": false])
            .eq("id", value: template.id)
            .execute()
        await fetchAll()
    }

    /// Reverse a soft-delete. Sets `is_active = true` and logs a
    /// matching `undone` template-level event.
    func undoDeleteTask(_ template: TaskTemplate) async throws {
        let actor = await currentStaffId()

        try await supabase
            .from("tasks")
            .update(["is_active": true])
            .eq("id", value: template.id)
            .execute()

        let event = NewTaskEvent(
            dailyTaskId: nil,
            actorId: actor,
            eventType: TaskEventType.undone.rawValue,
            fromValue: nil,
            toValue: template.id.uuidString,
            note: template.title,
            photoUrl: nil
        )
        _ = try? await supabase.from("task_events").insert(event).execute()

        await fetchAll()
    }

    // MARK: - Staff

    func setRole(_ staff: Staff, role: UserRole) async throws {
        try await supabase
            .from("staff")
            .update(["role": role.rawValue])
            .eq("id", value: staff.id)
            .execute()
        await fetchAll()
    }

    func toggleActive(_ staff: Staff) async throws {
        try await supabase
            .from("staff")
            .update(["is_active": !staff.isActive])
            .eq("id", value: staff.id)
            .execute()
        await fetchAll()
    }

    func updateStaffName(_ staff: Staff, name: String) async throws {
        try await supabase
            .from("staff")
            .update(["name": name])
            .eq("id", value: staff.id)
            .execute()
        await fetchAll()
    }
}
