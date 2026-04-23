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

    // Filters
    @State private var recurrenceFilter: TasksRecurrenceFilter = .all
    @State private var categoryFilter: Category? = nil     // nil = all
    @State private var assigneeFilter: TasksAssigneeFilter = .all

    /// Undo state. When a delete lands, we stash the template + a
    /// short dismiss timer; tapping Undo within the window fires the
    /// restore. Only one delete can be undone at a time — starting a
    /// second delete dismisses the first toast.
    @State private var pendingUndo: TaskTemplate?
    @State private var undoDismissTask: Task<Void, Never>?
    private let undoWindow: Duration = .seconds(5)

    private var filteredTemplates: [TaskTemplate] {
        adminVM.taskTemplates.filter { t in
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
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider().background(Color.bdBorder)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredTemplates) { task in
                            TaskTemplateRow(task: task) {
                                editingTask = task
                            } onDelete: {
                                handleDelete(task)
                            }
                            .padding(.horizontal, 16)
                        }
                        Spacer().frame(height: 80)
                    }
                    .padding(.top, 12)
                }
            }

            Button {
                showingNew = true
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
        VStack(alignment: .leading, spacing: 8) {
            // Recurrence pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    recurrencePill(.all,       label: tr("history_range_all"))
                    recurrencePill(.recurring, label: tr("recurring"))
                    recurrencePill(.oneOff,    label: tr("filter_one_off"))
                }
            }

            // Category + assignee menus on one row
            HStack(spacing: 8) {
                categoryMenu
                assigneeMenu
                Spacer()
                if adminVM.isLoading { ProgressView().scaleEffect(0.75) }
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
        Menu {
            Button(tr("history_range_all")) { categoryFilter = nil }
            Divider()
            ForEach(Category.displayOrder, id: \.rawValue) { cat in
                Button {
                    categoryFilter = cat
                } label: {
                    HStack {
                        Text(cat.localized)
                        if categoryFilter == cat { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            filterPill(label: tr("tasks_filter_category"),
                       value: categoryFilter?.localized ?? tr("history_range_all"))
        }
    }

    private var assigneeMenu: some View {
        Menu {
            Button(tr("history_range_all"))  { assigneeFilter = .all }
            Button(tr("assign_anyone"))      { assigneeFilter = .anyone }
            Divider()
            ForEach(adminVM.allStaff) { s in
                Button {
                    assigneeFilter = .staff(s.id)
                } label: {
                    HStack {
                        Text(s.name)
                        if case .staff(let id) = assigneeFilter, id == s.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterPill(label: tr("tasks_filter_assignee"),
                       value: assigneeSummary)
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

private struct TaskTemplateRow: View {
    let task: TaskTemplate
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
                    Text(task.category.localized)
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
            HStack(spacing: 16) {
                Button(tr("edit"), action: onEdit).font(.subheadline).foregroundColor(.bdAccent)
                Button(tr("delete"), action: onDelete).font(.subheadline).foregroundColor(.statusPending)
            }
        }
        .padding(14)
        .cardStyle()
    }
}
