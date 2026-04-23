import SwiftUI

struct TasksAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var editingTask: TaskTemplate?
    @State private var showingNew = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(adminVM.taskTemplates) { task in
                        TaskTemplateRow(task: task) {
                            editingTask = task
                        } onDelete: {
                            Task { try? await adminVM.deleteTask(id: task.id) }
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
        }
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
