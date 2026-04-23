import SwiftUI
import PhotosUI

struct TaskCompletionSheet: View {
    let task: DailyTask
    @Environment(AuthViewModel.self) private var auth
    @Environment(TaskViewModel.self) private var taskVM
    @Environment(LanguageManager.self) private var lang
    @Binding var isPresented: Bool

    @State private var note: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoPreview: Image?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showHistory = false
    @State private var events: [TaskEvent] = []
    @State private var isLoadingHistory = false

    private var isDone: Bool { task.status == .completed }
    private var canUndo: Bool {
        isDone && (auth.isAdmin || task.completedBy == auth.staff?.id)
    }

    private var displayTitle: String {
        lang.pick(en: task.task?.title ?? "Task", ja: task.task?.titleJa)
    }

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgCard.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Title
                    Text(displayTitle)
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    // Meta — assignment
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("\(tr("assign_to")):").foregroundColor(.gray)
                            if let a = task.assignee {
                                AvatarView(initials: a.initials, url: a.avatarUrl, size: 20)
                                Text(a.name).foregroundColor(.white)
                            } else {
                                Text(tr("assign_anyone")).foregroundColor(.gray)
                            }
                        }
                        .font(.subheadline)
                    }

                    // Trail — started / completed with duration
                    if task.startedAt != nil || task.completedAt != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            if let startedAt = task.startedAt {
                                trailRow(
                                    color: .statusPending,
                                    label: tr("started_label"),
                                    actor: task.starter?.name,
                                    time: startedAt
                                )
                            }
                            if let completedAt = task.completedAt {
                                trailRow(
                                    color: .statusDone,
                                    label: tr("completed_label"),
                                    actor: task.completer?.name,
                                    time: completedAt
                                )
                            }
                            if let d = duration {
                                HStack(spacing: 4) {
                                    Text("\(tr("duration")):")
                                        .foregroundColor(.gray)
                                    Text(d)
                                        .foregroundColor(.white)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Divider().background(Color.bdBorder)

                    // Note
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("add_note")).font(.caption).foregroundColor(.gray)
                        TextField(tr("add_note"), text: $note, axis: .vertical)
                            .lineLimit(3...5)
                            .inputStyle()
                            .disabled(isDone)
                    }

                    // Photo
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("completion_photo")).font(.caption).foregroundColor(.gray)
                        if let preview = photoPreview {
                            ZStack(alignment: .topTrailing) {
                                preview
                                    .resizable().scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                if !isDone {
                                    Button {
                                        selectedPhoto = nil
                                        photoData = nil
                                        photoPreview = nil
                                    } label: {
                                        Text(tr("delete"))
                                            .font(.caption.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(.black.opacity(0.6))
                                            .clipShape(Capsule())
                                    }
                                    .padding(8)
                                }
                            }
                        } else if let existingUrl = task.photoUrl, let url = URL(string: existingUrl) {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: { Color.bgElevated }
                                .frame(maxWidth: .infinity).frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if !isDone {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label(tr("choose_photo"), systemImage: "camera")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bdBorder))
                            }
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task {
                            guard let item else { return }
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                photoData = data
                                if let uiImage = UIImage(data: data) {
                                    photoPreview = Image(uiImage: uiImage)
                                }
                            }
                        }
                    }

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundColor(.statusPending)
                    }

                    // Actions
                    HStack(spacing: 12) {
                        if isDone {
                            if canUndo {
                                Button(tr("undo")) {
                                    Task { await undoTask() }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        } else {
                            if task.status == .pending {
                                Button(tr("start")) { Task { await startTask() } }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                            Button {
                                Task { await completeTask() }
                            } label: {
                                if isSaving { ProgressView().tint(.black) }
                                else { Text(tr("complete")) }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isSaving)
                        }
                    }

                    // History (audit log)
                    historySection
                }
                .padding(20)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            note = task.note ?? ""
            Task { await loadHistory() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Trail helpers

    @ViewBuilder
    private func trailRow(color: Color, label: String, actor: String?, time: Date) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundColor(.white).font(.caption.weight(.medium))
            if let actor {
                Text(actor).foregroundColor(.gray).font(.caption)
            }
            Spacer()
            Text(formattedTime(time)).foregroundColor(.gray).font(.caption)
        }
    }

    private var duration: String? {
        guard let start = task.startedAt, let end = task.completedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(start))
        guard seconds > 0 else { return nil }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showHistory.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text(tr("history"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if !events.isEmpty {
                        Text("\(events.count)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .foregroundColor(.gray)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showHistory {
                if isLoadingHistory {
                    HStack { ProgressView().tint(.gray); Spacer() }
                } else if events.isEmpty {
                    Text(tr("no_history"))
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: TaskEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(eventColor(event.eventType))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(eventLabel(event.eventType))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                    if let actor = event.actor?.name {
                        Text("· \(actor)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text(formattedTime(event.createdAt))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                if event.eventType == .reassigned {
                    let fromName = staffName(for: event.fromValue) ?? tr("assign_anyone")
                    let toName = staffName(for: event.toValue) ?? tr("assign_anyone")
                    Text("\(fromName) → \(toName)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func eventLabel(_ type: TaskEventType) -> String {
        switch type {
        case .created: return tr("event_created")
        case .started: return tr("event_started")
        case .completed: return tr("event_completed")
        case .undone: return tr("event_undone")
        case .reassigned: return tr("event_reassigned")
        case .note_added: return tr("event_note_added")
        case .note_updated: return tr("event_note_updated")
        case .photo_added: return tr("event_photo_added")
        case .deleted: return tr("event_deleted")
        }
    }

    private func eventColor(_ type: TaskEventType) -> Color {
        switch type {
        case .started: return .statusPending
        case .completed: return .statusDone
        case .undone: return .red
        case .reassigned: return .bdAccent
        default: return .gray
        }
    }

    private func staffName(for uuidString: String?) -> String? {
        guard let s = uuidString, let uuid = UUID(uuidString: s) else { return nil }
        // Look up in the event list's joined actors, plus fall back to the task's assignee/completer
        if let ev = events.first(where: { $0.fromValue == s || $0.toValue == s })?.actor, ev.id == uuid {
            return ev.name
        }
        if task.assignee?.id == uuid { return task.assignee?.name }
        if task.completer?.id == uuid { return task.completer?.name }
        if task.starter?.id == uuid { return task.starter?.name }
        return nil
    }

    private func loadHistory() async {
        isLoadingHistory = true
        events = await taskVM.fetchEvents(for: task.id)
        isLoadingHistory = false
    }

    // MARK: - Actions

    private func startTask() async {
        guard let staffId = auth.staff?.id else { return }
        isSaving = true
        do {
            try await taskVM.start(task: task, staffId: staffId)
            isPresented = false
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }

    private func completeTask() async {
        guard let staffId = auth.staff?.id else { return }
        isSaving = true
        errorMessage = nil
        do {
            var uploadedUrl: String? = task.photoUrl
            if let data = photoData {
                let mime = data.first == 0x89 ? "image/png" : "image/jpeg"
                uploadedUrl = try await uploadTaskPhoto(taskId: task.id, date: task.date, imageData: data, mimeType: mime)
            }
            try await taskVM.complete(
                task: task,
                staffId: staffId,
                note: note.trimmingCharacters(in: .whitespaces),
                photoUrl: uploadedUrl
            )
            isPresented = false
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }

    private func undoTask() async {
        isSaving = true
        do {
            try await taskVM.undo(task: task)
            isPresented = false
        } catch { errorMessage = error.localizedDescription }
        isSaving = false
    }
}
