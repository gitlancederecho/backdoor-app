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

    /// Soft-delete a task template. Also logs a `deleted` task_event
    /// against every un-completed daily_task for the current business
    /// day, so the History tab surfaces what the admin removed.
    ///
    /// Completed daily_tasks are left alone — their history shouldn't
    /// retroactively show a "deleted" marker for work that already
    /// happened.
    func deleteTask(id: UUID, businessDay: String) async throws {
        let actor = await currentStaffId()

        // Snapshot today's un-completed daily_tasks for this template so
        // we can log one event per affected instance.
        let affected: [DailyTask] = (try? await supabase
            .from("daily_tasks")
            .select()
            .eq("task_id", value: id)
            .eq("date", value: businessDay)
            .neq("status", value: TaskStatus.completed.rawValue)
            .execute()
            .value) ?? []

        for dt in affected {
            let event = NewTaskEvent(
                dailyTaskId: dt.id,
                actorId: actor,
                eventType: TaskEventType.deleted.rawValue,
                fromValue: id.uuidString,
                toValue: nil
            )
            _ = try? await supabase.from("task_events").insert(event).execute()
        }

        try await supabase
            .from("tasks")
            .update(["is_active": false])
            .eq("id", value: id)
            .execute()
        await fetchAll()
    }

    /// Reverse a soft-delete. Sets `is_active = true` and logs an
    /// `undone` event against the same un-completed daily_tasks so the
    /// History tab reflects the restore.
    func undoDeleteTask(id: UUID, businessDay: String) async throws {
        let actor = await currentStaffId()

        try await supabase
            .from("tasks")
            .update(["is_active": true])
            .eq("id", value: id)
            .execute()

        // Log undo events against the daily_tasks that received the
        // delete events. Completed rows were skipped on delete, so they
        // stay skipped here too.
        let affected: [DailyTask] = (try? await supabase
            .from("daily_tasks")
            .select()
            .eq("task_id", value: id)
            .eq("date", value: businessDay)
            .neq("status", value: TaskStatus.completed.rawValue)
            .execute()
            .value) ?? []

        for dt in affected {
            let event = NewTaskEvent(
                dailyTaskId: dt.id,
                actorId: actor,
                eventType: TaskEventType.undone.rawValue,
                fromValue: nil,
                toValue: id.uuidString
            )
            _ = try? await supabase.from("task_events").insert(event).execute()
        }

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
