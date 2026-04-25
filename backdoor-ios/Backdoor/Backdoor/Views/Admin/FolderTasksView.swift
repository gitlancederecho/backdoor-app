import SwiftUI

/// The folder-detail view — pushed when an admin taps a folder row in
/// `TasksAdminView`. Renders the subset of templates whose
/// `folder_id == folder.id`, with its own edit / bulk-action /
/// filter state (so navigating out and back doesn't leak selection).
struct FolderTasksView: View {
    let folder: TaskFolder
    @Bindable var adminVM: AdminViewModel
    let onBack: () -> Void

    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue

    @State private var editingTask: TaskTemplate?
    @State private var showingNew = false
    @State private var showingRename = false
    @State private var showingDeleteConfirm = false

    // Filters — same shape as TasksAdminView, scoped to this folder.
    @State private var searchText: String = ""
    @State private var recurrenceFilter: TasksRecurrenceFilter = .all
    @State private var categoryFilter: String? = nil
    @State private var assigneeFilter: TasksAssigneeFilter = .all
    @State private var showingCategoryPicker = false
    @State private var showingAssigneePicker = false

    // Edit mode + selection
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showingMoveTarget = false
    @State private var showingSingleMoveTarget = false
    @State private var singleMoveTask: TaskTemplate?

    /// Single-row soft-delete undo state — mirrors the pattern on
    /// the `TasksAdminView` root so folder-scoped deletes are just
    /// as forgiving.
    @State private var pendingUndo: TaskTemplate?
    @State private var undoDismissTask: Task<Void, Never>?
    private let undoWindow: Duration = .seconds(5)

    private var folderTasks: [TaskTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return adminVM.taskTemplates
            .filter { $0.folderId == folder.id }
            .filter { t in
                switch recurrenceFilter {
                case .all: break
                case .recurring: if !t.isRecurring { return false }
                case .oneOff:    if t.isRecurring  { return false }
                }
                if let c = categoryFilter, t.category != c { return false }
                switch assigneeFilter {
                case .all: break
                case .anyone: if t.assignedTo != nil { return false }
                case .staff(let id): if t.assignedTo != id { return false }
                }
                if !q.isEmpty {
                    let en = t.title.localizedCaseInsensitiveContains(q)
                    let ja = t.titleJa?.localizedCaseInsensitiveContains(q) ?? false
                    if !en && !ja { return false }
                }
                return true
            }
    }

    var body: some View {
        let _ = lang.current
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                folderHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                Divider().background(Color.bdBorder)
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider().background(Color.bdBorder)
                tasksList
                if editMode.isEditing, !selectedIds.isEmpty {
                    bulkActionBar
                }
            }
            if !editMode.isEditing {
                FloatingAddButton { showingNew = true }
            }

            if let template = pendingUndo {
                UndoToast(labelKey: "task_deleted_toast") {
                    handleUndo(template)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pendingUndo?.id)
        .sheet(isPresented: $showingNew) {
            // New task seeded with this folder pre-selected.
            TaskEditorSheet(task: nil, adminVM: adminVM, initialFolderId: folder.id)
                .environment(auth)
                .environment(lang)
                .environment(venue)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, adminVM: adminVM)
                .environment(auth)
                .environment(lang)
                .environment(venue)
        }
        .sheet(isPresented: $showingRename) {
            FolderEditorSheet(folder: folder, adminVM: adminVM)
                .environment(lang)
        }
        .sheet(isPresented: $showingCategoryPicker) {
            SearchablePickerSheet<String>(
                title: tr("tasks_filter_category"),
                rows: categoryPickerRows,
                selectedID: categoryFilter ?? "__all__",
                onPick: { id in
                    categoryFilter = (id == "__all__") ? nil : id
                }
            )
            .environment(lang)
        }
        .sheet(isPresented: $showingAssigneePicker) {
            SearchablePickerSheet<String>(
                title: tr("tasks_filter_assignee"),
                rows: assigneePickerRows,
                selectedID: selectedAssigneeId,
                onPick: { id in
                    switch id {
                    case "__all__":    assigneeFilter = .all
                    case "__anyone__": assigneeFilter = .anyone
                    default:
                        if let uuid = UUID(uuidString: id) {
                            assigneeFilter = .staff(uuid)
                        }
                    }
                }
            )
            .environment(lang)
        }
        .sheet(isPresented: $showingMoveTarget) {
            MoveToFolderPicker(
                currentFolderId: folder.id,
                folders: adminVM.folders,
                onPick: { target in
                    let ids = Array(selectedIds)
                    Task {
                        await adminVM.moveTasks(ids: ids, toFolder: target)
                        selectedIds = []
                        editMode = .inactive
                    }
                }
            )
            .environment(lang)
        }
        .sheet(isPresented: $showingSingleMoveTarget) {
            MoveToFolderPicker(
                currentFolderId: folder.id,
                folders: adminVM.folders,
                onPick: { target in
                    guard let t = singleMoveTask else { return }
                    Task {
                        try? await adminVM.moveTask(t, toFolder: target)
                        singleMoveTask = nil
                    }
                }
            )
            .environment(lang)
        }
        .alert(
            tr("delete_n_tasks_confirm"),
            isPresented: $showBulkDeleteConfirm,
            presenting: Array(selectedIds)
        ) { ids in
            Button(String(format: tr("delete_n"), ids.count), role: .destructive) {
                let templates = adminVM.taskTemplates.filter { ids.contains($0.id) }
                Task {
                    await adminVM.deleteTaskTemplates(templates)
                    selectedIds = []
                    editMode = .inactive
                }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: { ids in
            Text(String(format: tr("delete_n_tasks_message"), ids.count))
        }
        .alert(
            tr("delete_folder_confirm"),
            isPresented: $showingDeleteConfirm
        ) {
            let count = adminVM.taskCount(inFolder: folder.id)
            // Option 1: nuke folder + every task inside. Shown first
            // because it's the more destructive choice — iOS alerts
            // render destructive actions at the top by role. Only
            // offered when the folder actually has tasks; otherwise
            // it's identical to option 2.
            if count > 0 {
                Button(
                    String(format: tr("delete_folder_and_n_tasks"), count),
                    role: .destructive
                ) {
                    Task {
                        try? await adminVM.deleteFolderAndTasks(folder)
                        onBack()
                    }
                }
            }
            // Option 2: delete folder only; tasks slide back to
            // Unfiled. Destructive role because the folder itself
            // is still gone, just the tasks survive.
            Button(
                count > 0 ? tr("delete_folder_keep_tasks") : tr("delete_folder"),
                role: .destructive
            ) {
                Task {
                    try? await adminVM.deleteFolder(folder)
                    onBack()
                }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: {
            let count = adminVM.taskCount(inFolder: folder.id)
            if count > 0 {
                Text(String(format: tr("delete_folder_choice_message"), count))
            } else {
                Text(tr("delete_folder_empty_message"))
            }
        }
    }

    // MARK: - Single-row delete / undo
    //
    // Mirrors the policy at the TasksAdminView root: single-row
    // soft-delete gets no confirm alert, but an undo toast covers the
    // next 5 seconds. Bulk delete keeps its own alert (handled by the
    // bulk bar + alert wiring below).

    private func handleDelete(_ task: TaskTemplate) {
        undoDismissTask?.cancel()
        // Show the toast first; fire the delete in the background so
        // swipe-delete feels instant. Mirrors the TasksAdminView root
        // pattern exactly.
        pendingUndo = task
        undoDismissTask = Task {
            try? await Task.sleep(for: undoWindow)
            guard !Task.isCancelled else { return }
            pendingUndo = nil
        }
        Task { try? await adminVM.deleteTask(task) }
    }

    private func handleUndo(_ task: TaskTemplate) {
        undoDismissTask?.cancel()
        pendingUndo = nil
        Task { try? await adminVM.undoDeleteTask(task) }
    }

    // MARK: - Folder header

    private var folderHeader: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.bgElevated)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Folder icon tinted to its stored color — matches the
            // root list's folder rows and the move-picker swatch.
            Image(systemName: "folder.fill")
                .foregroundColor(FolderTint.color(forStored: folder.color))
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                if let desc = folder.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                Button { showingRename = true } label: {
                    Label(tr("edit_folder"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label(tr("delete_folder"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.bgElevated)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(prompt: tr("search_tasks"), text: $searchText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterPill(label: tr("history_range_all"),
                               isSelected: recurrenceFilter == .all) {
                        recurrenceFilter = .all
                    }
                    FilterPill(label: tr("recurring"),
                               isSelected: recurrenceFilter == .recurring) {
                        recurrenceFilter = .recurring
                    }
                    FilterPill(label: tr("filter_one_off"),
                               isSelected: recurrenceFilter == .oneOff) {
                        recurrenceFilter = .oneOff
                    }
                }
            }

            HStack(spacing: 8) {
                LabeledFilterPill(
                    label: tr("tasks_filter_category"),
                    value: categoryFilter.map {
                        CategoryDisplay.localized($0, in: adminVM.categories)
                    } ?? tr("history_range_all")
                ) { showingCategoryPicker = true }
                LabeledFilterPill(
                    label: tr("tasks_filter_assignee"),
                    value: assigneeSummary
                ) { showingAssigneePicker = true }

                Spacer()
                if adminVM.isLoading { ProgressView().scaleEffect(0.75) }
                Button(editMode.isEditing ? tr("done") : tr("edit")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if editMode.isEditing {
                            editMode = .inactive
                            selectedIds = []
                        } else {
                            editMode = .active
                        }
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(.bdAccent)
            }
        }
    }

    // MARK: - Tasks list

    @ViewBuilder
    private var tasksList: some View {
        if folderTasks.isEmpty {
            VStack { Spacer(); Text(tr("no_tasks_in_folder")).foregroundColor(.gray); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedIds) {
                ForEach(folderTasks) { task in
                    TaskTemplateRow(
                        task: task,
                        categories: adminVM.categories,
                        allStaff: adminVM.allStaff,
                        isEditing: editMode.isEditing,
                        onEdit: { editingTask = task },
                        onDelete: { handleDelete(task) },
                        onMove: {
                            singleMoveTask = task
                            showingSingleMoveTarget = true
                        },
                        onLongPress: { enterEditMode(preselect: task.id) }
                    )
                    .tag(task.id)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    // Drag the row out of this folder. Drop targets:
                    // any folder row at the root, or another folder
                    // when sibling folders ever get inline dropzones.
                    // For now, dragging here is most useful when the
                    // admin wants to flick a task back to Unfiled —
                    // but the root folder list isn't visible from
                    // here, so this mostly mirrors the move-via-menu
                    // flow. Kept for symmetry with the root view.
                    .draggable(task.id.uuidString)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { try? await adminVM.deleteTask(task) }
                        } label: { Label(tr("delete"), systemImage: "trash") }
                    }
                }
                .onMove { offsets, destination in
                    var slice = folderTasks
                    slice.move(fromOffsets: offsets, toOffset: destination)
                    Task { await adminVM.persistTaskOrder(slice) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .environment(\.editMode, $editMode)
        }
    }

    /// Same hold-to-select gesture as `TasksAdminView`: long press
    /// pops into edit mode with that row preselected.
    private func enterEditMode(preselect id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            editMode = .active
            selectedIds = [id]
        }
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Button {
                if selectedIds.count == folderTasks.count {
                    selectedIds = []
                } else {
                    selectedIds = Set(folderTasks.map(\.id))
                }
            } label: {
                Text(selectedIds.count == folderTasks.count ? tr("deselect_all") : tr("select_all"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.bdAccent)
            }
            .buttonStyle(.plain)

            Text(String(format: tr("selected_count"), selectedIds.count))
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Button { showingMoveTarget = true } label: {
                Label(tr("move_to_folder"), systemImage: "folder")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bdAccent)
            }
            Button {
                showBulkDeleteConfirm = true
            } label: {
                Label(
                    String(format: tr("delete_n"), selectedIds.count),
                    systemImage: "trash"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.statusPending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.bdBorder), alignment: .top)
    }

    // MARK: - Picker rows (same shape as TasksAdminView)

    private var categoryPickerRows: [PickerRow<String>] {
        var rows: [PickerRow<String>] = [
            PickerRow<String>(id: "__all__", label: tr("history_range_all"), isSpecial: true)
        ]
        rows.append(contentsOf: CategoryDisplay.available(in: adminVM.categories).map {
            PickerRow<String>(id: $0, label: CategoryDisplay.localized($0, in: adminVM.categories))
        })
        return rows
    }

    private var assigneePickerRows: [PickerRow<String>] {
        var rows: [PickerRow<String>] = [
            PickerRow<String>(id: "__all__",   label: tr("history_range_all"), isSpecial: true),
            PickerRow<String>(id: "__anyone__", label: tr("assign_anyone"),     isSpecial: true)
        ]
        rows.append(contentsOf: adminVM.allStaff.map { s in
            PickerRow<String>(
                id: s.id.uuidString,
                label: s.name,
                sublabel: s.email,
                avatar: (s.initials, s.avatarUrl)
            )
        })
        return rows
    }

    private var selectedAssigneeId: String {
        switch assigneeFilter {
        case .all:           return "__all__"
        case .anyone:        return "__anyone__"
        case .staff(let id): return id.uuidString
        }
    }

    private var assigneeSummary: String {
        switch assigneeFilter {
        case .all:            return tr("history_range_all")
        case .anyone:         return tr("assign_anyone")
        case .staff(let id):  return adminVM.allStaff.first { $0.id == id }?.name ?? "—"
        }
    }
}
