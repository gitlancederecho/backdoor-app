import SwiftUI

struct TasksAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var editingTask: TaskTemplate?
    @State private var showingNew = false

    /// Undo state. When a delete lands, we stash the template + a
    /// short dismiss timer; tapping Undo within the window fires the
    /// restore. Only one delete can be undone at a time — starting a
    /// second delete dismisses the first toast.
    @State private var pendingUndo: TaskTemplate?
    @State private var undoDismissTask: Task<Void, Never>?
    private let undoWindow: Duration = .seconds(5)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(adminVM.taskTemplates) { task in
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
