import SwiftUI

enum TasksRecurrenceFilter: Hashable {
    case all, recurring, oneOff
}

enum TasksAssigneeFilter: Hashable {
    case all
    case anyone          // unassigned templates
    case staff(UUID)
}

struct TasksAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var editingTask: TaskTemplate?
    @State private var showingNew = false
    @State private var showingNewFolder = false

    /// Drill-in state. Non-nil = `FolderTasksView` for that folder is
    /// shown instead of the root (unfiled + folders). Embedded inside
    /// the Admin tab, so we can't rely on NavigationStack cleanly —
    /// just swap the view with a slide animation.
    @State private var currentFolder: TaskFolder?

    // Filters (scoped to the Unfiled section at the root view).
    @State private var searchText: String = ""
    @State private var recurrenceFilter: TasksRecurrenceFilter = .all
    @State private var categoryFilter: String? = nil       // nil = all; otherwise a category key
    @State private var assigneeFilter: TasksAssigneeFilter = .all
    @State private var showingCategoryPicker = false
    @State private var showingAssigneePicker = false

    /// Undo state. When a delete lands, we stash the template + a
    /// short dismiss timer; tapping Undo within the window fires the
    /// restore. Only one delete can be undone at a time — starting a
    /// second delete dismisses the first toast. Bulk deletions skip
    /// the undo toast (user confirms via alert first).
    @State private var pendingUndo: TaskTemplate?
    @State private var undoDismissTask: Task<Void, Never>?
    private let undoWindow: Duration = .seconds(5)

    // Edit mode + bulk selection (Unfiled scope only — folder rows
    // aren't selectable from the root).
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showingMoveTarget = false

    /// Filtered Unfiled templates (`folder_id IS NULL`). The root view's
    /// filter bar applies to this section only; folder rows are not
    /// touched by search or pills.
    private var filteredTemplates: [TaskTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return adminVM.taskTemplates
            .filter { $0.folderId == nil }
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
                    // Match either the English title or the Japanese title so
                    // the search works regardless of the active UI language.
                    let en = t.title.localizedCaseInsensitiveContains(q)
                    let ja = t.titleJa?.localizedCaseInsensitiveContains(q) ?? false
                    if !en && !ja { return false }
                }
                return true
            }
    }

    var body: some View {
        Group {
            if let folder = currentFolder {
                FolderTasksView(
                    folder: folder,
                    adminVM: adminVM,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentFolder = nil
                        }
                    }
                )
                .environment(auth)
                .environment(lang)
                .environment(venue)
                .transition(.move(edge: .trailing))
            } else {
                rootView
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentFolder?.id)
    }

    private var rootView: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider().background(Color.bdBorder)
                rootList
                if editMode.isEditing, !selectedIds.isEmpty {
                    bulkActionBar
                }
            }

            if !editMode.isEditing {
                Menu {
                    Button {
                        showingNew = true
                    } label: {
                        Label(tr("new_task"), systemImage: "plus.circle")
                    }
                    Button {
                        showingNewFolder = true
                    } label: {
                        Label(tr("new_folder"), systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.bdAccent)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }

            if let template = pendingUndo {
                undoToast(for: template)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pendingUndo?.id)
        .sheet(isPresented: $showingNew) {
            TaskEditorSheet(task: nil, adminVM: adminVM)
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
        .sheet(isPresented: $showingNewFolder) {
            FolderEditorSheet(folder: nil, adminVM: adminVM)
                .environment(lang)
        }
        .sheet(isPresented: $showingMoveTarget) {
            MoveToFolderPicker(
                currentFolderId: nil,  // root = Unfiled scope
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
        .sheet(isPresented: $showingCategoryPicker) {
            SearchablePickerSheet<String>(
                title: tr("tasks_filter_category"),
                rows: categoryPickerRows,
                selectedID: selectedCategoryId,
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
    }

    /// Root list: Unfiled tasks (section, filterable) at the top,
    /// Folders list beneath. Drill-in via tap → `currentFolder = folder`.
    private var rootList: some View {
        List(selection: $selectedIds) {
            if !filteredTemplates.isEmpty {
                Section {
                    ForEach(filteredTemplates) { task in
                        TaskTemplateRow(
                            task: task,
                            categories: adminVM.categories,
                            isEditing: editMode.isEditing,
                            onEdit: { editingTask = task },
                            onDelete: { handleDelete(task) }
                        )
                        .tag(task.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { handleDelete(task) } label: {
                                Label(tr("delete"), systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    sectionHeader(tr("unfiled"))
                }
            }

            if !adminVM.folders.isEmpty {
                Section {
                    ForEach(adminVM.folders) { folder in
                        folderRow(folder)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .selectionDisabled()
                    }
                } header: {
                    sectionHeader(tr("folders"))
                }
            }

            // Empty state — shown only when there's literally nothing
            // to see (no unfiled tasks AND no folders).
            if filteredTemplates.isEmpty && adminVM.folders.isEmpty {
                Text(tr("no_folders"))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .cardStyle()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .environment(\.editMode, $editMode)
    }

    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.gray)
            .tracking(1.2)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func folderRow(_ folder: TaskFolder) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentFolder = folder
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.bdAccent)
                    .font(.system(size: 18))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    Text(String(format: tr("tasks_count"), adminVM.taskCount(inFolder: folder.id)))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(14)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bulkActionBar: some View {
        HStack(spacing: 10) {
            Button {
                if selectedIds.count == filteredTemplates.count {
                    selectedIds = []
                } else {
                    selectedIds = Set(filteredTemplates.map(\.id))
                }
            } label: {
                Text(selectedIds.count == filteredTemplates.count ? tr("deselect_all") : tr("select_all"))
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

    // MARK: - Delete / undo wiring

    private func handleDelete(_ task: TaskTemplate) {
        // If another toast was up, dismiss its timer before firing a new delete.
        undoDismissTask?.cancel()

        Task {
            try? await adminVM.deleteTask(task)
            pendingUndo = task
            // Schedule auto-dismiss after the undo window.
            undoDismissTask = Task {
                try? await Task.sleep(for: undoWindow)
                guard !Task.isCancelled else { return }
                pendingUndo = nil
            }
        }
    }

    private func handleUndo(_ task: TaskTemplate) {
        undoDismissTask?.cancel()
        pendingUndo = nil
        Task { try? await adminVM.undoDeleteTask(task) }
    }

    @ViewBuilder
    private func undoToast(for task: TaskTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundColor(.statusPending)
            Text(tr("task_deleted_toast"))
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Button(tr("undo")) { handleUndo(task) }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.bdAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.bdBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchField(prompt: tr("search_tasks"), text: $searchText)

            // Recurrence pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    recurrencePill(.all,       label: tr("history_range_all"))
                    recurrencePill(.recurring, label: tr("recurring"))
                    recurrencePill(.oneOff,    label: tr("filter_one_off"))
                }
            }

            // Category + assignee menus on one row; edit toggle pinned right.
            HStack(spacing: 8) {
                categoryMenu
                assigneeMenu
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

    private func recurrencePill(_ value: TasksRecurrenceFilter, label: String) -> some View {
        Button(label) { recurrenceFilter = value }
            .font(.caption.weight(recurrenceFilter == value ? .semibold : .regular))
            .foregroundColor(recurrenceFilter == value ? .black : .gray)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(recurrenceFilter == value ? Color.bdAccent : Color.bgElevated)
            .clipShape(Capsule())
    }

    private var categoryMenu: some View {
        Button {
            showingCategoryPicker = true
        } label: {
            filterPill(label: tr("tasks_filter_category"),
                       value: categoryFilter.map { CategoryDisplay.localized($0, in: adminVM.categories) } ?? tr("history_range_all"))
        }
        .buttonStyle(.plain)
    }

    private var assigneeMenu: some View {
        Button {
            showingAssigneePicker = true
        } label: {
            filterPill(label: tr("tasks_filter_assignee"),
                       value: assigneeSummary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Picker rows

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

    private var selectedCategoryId: String {
        categoryFilter ?? "__all__"
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

    private func filterPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.gray)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.bgElevated)
        .clipShape(Capsule())
    }
}

/// Shared row used by both `TasksAdminView` (at the Unfiled section)
/// and `FolderTasksView` (inside a folder). File-scope visibility.
struct TaskTemplateRow: View {
    let task: TaskTemplate
    let categories: [Category]
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(LanguageManager.self) private var lang

    private var displayTitle: String {
        lang.pick(en: task.title, ja: task.titleJa)
    }

    private var priorityLabel: String {
        switch task.priority {
        case .low:    return tr("priority_low")
        case .normal: return tr("priority_normal")
        case .high:   return tr("priority_high")
        }
    }

    private var recurrenceLabel: String {
        guard task.isRecurring, let r = task.recurrenceType else { return "" }
        switch r {
        case .daily:   return tr("repeat_daily")
        case .weekly:  return tr("repeat_weekly")
        case .monthly: return tr("repeat_monthly")
        }
    }

    var body: some View {
        let _ = lang.current
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Text(CategoryDisplay.localized(task.category, in: categories))
                    Text("·")
                    Text(task.isRecurring ? recurrenceLabel : "—")
                    if task.priority != .normal {
                        Text("·")
                        Text(priorityLabel)
                            .foregroundColor(task.priority == .high ? .statusPending : .gray)
                    }
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            Spacer()
            if !isEditing {
                HStack(spacing: 16) {
                    Button(tr("edit"), action: onEdit)
                        .font(.subheadline)
                        .foregroundColor(.bdAccent)
                        .buttonStyle(.borderless)
                    Button(tr("delete"), action: onDelete)
                        .font(.subheadline)
                        .foregroundColor(.statusPending)
                        .buttonStyle(.borderless)
                }
            }
            // In edit mode, List renders the selection circle for us —
            // keep the row uncluttered so the selection affordance is
            // the primary action.
        }
        .padding(14)
        .cardStyle()
    }
}
