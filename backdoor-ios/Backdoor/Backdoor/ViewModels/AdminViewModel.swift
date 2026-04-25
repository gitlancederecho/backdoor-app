import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AdminViewModel {
    var allStaff: [Staff] = []
    var taskTemplates: [TaskTemplate] = []
    var categories: [Category] = []
    /// Active folders, sorted by sort_order. Inactive (soft-deleted)
    /// folders are excluded — tasks that referenced them get their
    /// folder_id set NULL by `ON DELETE SET NULL`, so they fall back
    /// to Unfiled.
    var folders: [TaskFolder] = []
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
        // Non-recurring templates auto-soft-delete on final completion
        // (handled in TaskViewModel), so `is_active = true` alone now
        // gives us the set of "templates still worth managing."
        async let tasksResult: [TaskTemplate] = (try? supabase
            .from("tasks")
            .select()
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
        async let categoriesResult: [Category] = (try? supabase
            .from("categories")
            .select()
            .order("sort_order")
            .execute()
            .value) ?? []
        async let foldersResult: [TaskFolder] = (try? supabase
            .from("task_folders")
            .select()
            .eq("is_active", value: true)
            .order("sort_order")
            .execute()
            .value) ?? []
        allStaff = await staffResult
        taskTemplates = await tasksResult
        categories = await categoriesResult
        folders = await foldersResult
        isLoading = false
    }

    // MARK: - Folder CRUD

    private func fetchFolders() async {
        let rows: [TaskFolder] = (try? await supabase
            .from("task_folders")
            .select()
            .eq("is_active", value: true)
            .order("sort_order")
            .execute()
            .value) ?? []
        folders = rows
    }

    func createFolder(
        name: String,
        description: String? = nil,
        color: String? = nil
    ) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = Int16(clamping: (folders.map { Int($0.sortOrder) }.max() ?? 0) + 1)
        let cleanDescription: String? = {
            let t = description?.trimmingCharacters(in: .whitespaces) ?? ""
            return t.isEmpty ? nil : t
        }()
        let row = NewTaskFolder(
            name: trimmed,
            description: cleanDescription,
            color: color,
            sortOrder: nextOrder,
            createdBy: await currentStaffId()
        )
        try await supabase.from("task_folders").insert(row).execute()
        await fetchFolders()
    }

    func renameFolder(_ folder: TaskFolder, to newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        try await supabase
            .from("task_folders")
            .update(TaskFolderPatch(name: trimmed))
            .eq("id", value: folder.id)
            .execute()
        await fetchFolders()
    }

    /// Soft-delete a folder. Tasks that referenced it land in Unfiled
    /// via the `ON DELETE SET NULL` on tasks.folder_id — but we're
    /// doing a soft-delete (is_active=false), not a hard delete, so
    /// the FK doesn't fire. Instead, null out folder_id on all tasks
    /// currently in this folder so they surface under Unfiled.
    func deleteFolder(_ folder: TaskFolder) async throws {
        // Null folder_id on every task currently in this folder.
        struct Patch: Encodable {
            let folderId: UUID?
            enum CodingKeys: String, CodingKey { case folderId = "folder_id" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(folderId, forKey: .folderId)
            }
        }
        _ = try? await supabase
            .from("tasks")
            .update(Patch(folderId: nil))
            .eq("folder_id", value: folder.id)
            .execute()

        try await supabase
            .from("task_folders")
            .update(TaskFolderPatch(isActive: false))
            .eq("id", value: folder.id)
            .execute()
        await fetchFolders()
        await fetchAll()  // tasks' folder_id changed, reload
    }

    /// Soft-delete a folder *and* every template inside it. Preferred
    /// when an admin clears out an entire category of work. Each
    /// member template goes through `deleteTask` so `task_events`
    /// gets the usual `deleted` row per template (matches individual
    /// deletes — admins can still find + restore a specific one via
    /// the Deleted tasks sheet).
    func deleteFolderAndTasks(_ folder: TaskFolder) async throws {
        let members = taskTemplates.filter { $0.folderId == folder.id }
        for t in members {
            try? await deleteTask(t)
        }
        try await supabase
            .from("task_folders")
            .update(TaskFolderPatch(isActive: false))
            .eq("id", value: folder.id)
            .execute()
        await fetchFolders()
        await fetchAll()
    }

    /// Persist the current `folders` order.
    func persistFolderOrder() async {
        for (index, f) in folders.enumerated() {
            let desired = Int16(clamping: index + 1)
            if f.sortOrder != desired {
                _ = try? await supabase
                    .from("task_folders")
                    .update(TaskFolderPatch(sortOrder: desired))
                    .eq("id", value: f.id)
                    .execute()
            }
        }
        await fetchFolders()
    }

    /// Explicitly set (or clear) `recurrence_ends_on` on a single
    /// template. Uses a custom-encoded patch so that nil flows as JSON
    /// null — the default encoder would omit it and leave a stale
    /// cutoff in place.
    func setRecurrenceEnd(id: UUID, to iso: String?) async throws {
        struct Patch: Encodable {
            let recurrenceEndsOn: String?
            enum CodingKeys: String, CodingKey { case recurrenceEndsOn = "recurrence_ends_on" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(recurrenceEndsOn, forKey: .recurrenceEndsOn)
            }
        }
        try await supabase
            .from("tasks")
            .update(Patch(recurrenceEndsOn: iso))
            .eq("id", value: id)
            .execute()
        await fetchAll()
    }

    /// Move a single task to a folder (or to Unfiled when `folderId` is nil).
    func moveTask(_ task: TaskTemplate, toFolder folderId: UUID?) async throws {
        struct Patch: Encodable {
            let folderId: UUID?
            enum CodingKeys: String, CodingKey { case folderId = "folder_id" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(folderId, forKey: .folderId)
            }
        }
        try await supabase
            .from("tasks")
            .update(Patch(folderId: folderId))
            .eq("id", value: task.id)
            .execute()
        await fetchAll()
    }

    /// Bulk-move: reassign `folder_id` on every task in `ids` in a
    /// single request. nil folderId = move to Unfiled.
    func moveTasks(ids: [UUID], toFolder folderId: UUID?) async {
        struct Patch: Encodable {
            let folderId: UUID?
            enum CodingKeys: String, CodingKey { case folderId = "folder_id" }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(folderId, forKey: .folderId)
            }
        }
        _ = try? await supabase
            .from("tasks")
            .update(Patch(folderId: folderId))
            .in("id", values: ids)
            .execute()
        await fetchAll()
    }

    /// How many *active* templates currently live in a given folder.
    /// Used for the "5 tasks" count on the folder row in Admin → Tasks.
    func taskCount(inFolder folderId: UUID?) -> Int {
        taskTemplates.filter { $0.folderId == folderId }.count
    }

    // MARK: - Category CRUD

    func createCategory(_ row: NewCategory) async throws {
        try await supabase.from("categories").insert(row).execute()
        await fetchCategories()
    }

    func updateCategory(key: String, _ patch: CategoryPatch) async throws {
        try await supabase
            .from("categories")
            .update(patch)
            .eq("key", value: key)
            .execute()
        await fetchCategories()
    }

    func deleteCategory(key: String) async throws {
        // No FK cascade — tasks using this key keep it and render via
        // CategoryDisplay's humanize fallback until an admin repoints
        // them or re-creates the category.
        try await supabase
            .from("categories")
            .delete()
            .eq("key", value: key)
            .execute()
        await fetchCategories()
    }

    /// How many templates currently reference a given category key.
    /// Used by the delete-confirmation UI to warn about orphan tasks.
    func taskCountUsingCategory(_ key: String) -> Int {
        taskTemplates.filter { $0.category == key }.count
    }

    /// Persist the current order of `categories` — writes a new
    /// sort_order (1-based index) to any row whose position changed.
    /// Called after an .onMove so the DB matches what the UI shows.
    func persistCategoryOrder() async {
        for (index, cat) in categories.enumerated() {
            let desired = Int16(clamping: index + 1)
            if cat.sortOrder != desired {
                _ = try? await supabase
                    .from("categories")
                    .update(CategoryPatch(sortOrder: desired))
                    .eq("key", value: cat.key)
                    .execute()
            }
        }
        // Refresh so in-memory sort_orders reflect what landed in the
        // DB (timestamps, server-side validation, etc).
        await fetchCategories()
    }

    /// Delete multiple templates in one go. Each delete reuses the
    /// existing deleteTask path so event logging + cascade semantics
    /// stay consistent with single-row deletes.
    func deleteTaskTemplates(_ templates: [TaskTemplate]) async {
        for t in templates {
            try? await deleteTask(t)
        }
    }

    /// Restore multiple soft-deleted templates. Logs an `undone`
    /// event per template (matches `undoDeleteTask`).
    func restoreTaskTemplates(_ templates: [TaskTemplate]) async {
        for t in templates {
            try? await undoDeleteTask(t)
        }
    }

    /// Fetch soft-deleted templates on demand (not cached on the VM
    /// so the default list stays tight). The admin's "Show deleted"
    /// toggle calls this and filters against the result.
    func fetchDeletedTaskTemplates() async -> [TaskTemplate] {
        let rows: [TaskTemplate] = (try? await supabase
            .from("tasks")
            .select()
            .eq("is_active", value: false)
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
        return rows
    }

    /// Delete multiple categories (non-builtin only — the caller is
    /// expected to have filtered). Returns how many actually deleted.
    @discardableResult
    func deleteCategories(keys: [String]) async -> Int {
        var count = 0
        for k in keys {
            do {
                try await deleteCategory(key: k)
                count += 1
            } catch {}
        }
        return count
    }

    private func fetchCategories() async {
        let rows: [Category] = (try? await supabase
            .from("categories")
            .select()
            .order("sort_order")
            .execute()
            .value) ?? []
        categories = rows
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

        _ = try? await supabase.rpc("generate_daily_tasks").execute()
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
        _ = try? await supabase
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

        _ = try? await supabase.rpc("generate_daily_tasks").execute()
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

    /// Bulk set is_active on a list of staff. Skips the caller's own
    /// staff row so an admin can't accidentally lock themselves out
    /// via a multi-select.
    func bulkSetStaffActive(ids: [UUID], to isActive: Bool, excludingSelf selfId: UUID?) async {
        let targets = ids.filter { $0 != selfId }
        guard !targets.isEmpty else { return }
        for id in targets {
            _ = try? await supabase
                .from("staff")
                .update(["is_active": isActive])
                .eq("id", value: id)
                .execute()
        }
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
