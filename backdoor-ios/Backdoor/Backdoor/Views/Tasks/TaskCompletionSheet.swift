import SwiftUI
import PhotosUI
import Supabase

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

    // Reassign — fetched on-demand, admin-only.
    @State private var reassignableStaff: [Staff] = []
    @State private var showingReassignPicker = false

    // Comments
    @State private var comments: [TaskComment] = []
    @State private var commentDraft: String = ""
    @State private var isPostingComment = false
    @State private var commentsRealtimeTask: Task<Void, Never>?
    @State private var commentsRealtimeChannel: RealtimeChannelV2?

    /// Live view of the task — re-reads from the VM each access so
    /// optimistic updates (reassign, complete, undo, note edits)
    /// surface in the sheet without closing and re-opening. Falls
    /// back to the original snapshot if the row has disappeared
    /// (shouldn't happen while the sheet is live).
    private var currentTask: DailyTask {
        taskVM.tasks.first(where: { $0.id == task.id }) ?? task
    }

    /// Assignee that reflects the latest assignedTo, even if the VM's
    /// joined `assignee` hasn't been replaced yet after an optimistic
    /// reassign. Checks the cached staff list as a fallback.
    private var displayAssignee: Staff? {
        let ct = currentTask
        if let a = ct.assignee, a.id == ct.assignedTo { return a }
        if let id = ct.assignedTo {
            return reassignableStaff.first(where: { $0.id == id })
        }
        return nil
    }

    private var isDone: Bool { currentTask.status == .completed }
    private var canUndo: Bool {
        isDone && (auth.isAdmin || currentTask.completedBy == auth.staff?.id)
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

                    // Pills — category / priority (only if not normal) / status
                    pillsRow

                    // Meta — assignment (with inline Reassign menu for
                    // admins). Reassign only changes the assigned_to of
                    // this daily_task, not the template.
                    HStack(spacing: 6) {
                        Text("\(tr("assign_to")):").foregroundColor(.gray)
                        if let a = displayAssignee {
                            AvatarView(initials: a.initials, url: a.avatarUrl, size: 20)
                            Text(a.name).foregroundColor(.white)
                        } else {
                            Text(tr("assign_anyone")).foregroundColor(.gray)
                        }
                        Spacer()
                        if auth.isAdmin {
                            reassignMenu
                        }
                    }
                    .font(.subheadline)

                    // Expected time window, if the template specified one
                    if let windowText = expectedWindowText {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.caption).foregroundColor(.gray)
                            Text(windowText).font(.subheadline).foregroundColor(.gray)
                        }
                    }

                    // Trail — started / completed with duration
                    if currentTask.startedAt != nil || currentTask.completedAt != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            if let startedAt = currentTask.startedAt {
                                trailRow(
                                    color: .statusPending,
                                    label: tr("started_label"),
                                    actor: currentTask.starter?.name,
                                    time: startedAt
                                )
                            }
                            if let completedAt = currentTask.completedAt {
                                trailRow(
                                    color: .statusDone,
                                    label: tr("completed_label"),
                                    actor: currentTask.completer?.name,
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

                    // Note — editable before AND after completion so
                    // someone can correct or append context post-hoc
                    // (logs note_added / note_updated events).
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("add_note")).font(.caption).foregroundColor(.gray)
                        TextField(tr("add_note"), text: $note, axis: .vertical)
                            .lineLimit(3...5)
                            .inputStyle()
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
                        } else if let existingUrl = currentTask.photoUrl, let url = URL(string: existingUrl) {
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: { Color.bgElevated }
                                    .frame(maxWidth: .infinity).frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                let replaceLabel = tr("replace_photo")
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label(replaceLabel, systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(.black.opacity(0.6))
                                        .clipShape(Capsule())
                                }
                                .padding(8)
                            }
                        } else {
                            let chooseLabel = tr("choose_photo")
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label(chooseLabel, systemImage: "camera")
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
                            if hasPostCompletionEdits {
                                Button {
                                    Task { await savePostCompletionEdits() }
                                } label: {
                                    if isSaving { ProgressView().tint(.black) }
                                    else { Text(tr("save")) }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(isSaving)
                            }
                            if canUndo {
                                Button(tr("undo")) {
                                    Task { await undoTask() }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        } else {
                            if currentTask.status == .pending {
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

                    // Comments — free-text thread per daily_task
                    Divider().background(Color.bdBorder)
                    commentsSection
                }
                .padding(20)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            note = task.note ?? ""
            Task { await loadHistory() }
            Task { await loadReassignableStaffIfNeeded() }
            Task { await loadComments() }
            Task { await subscribeToComments() }
        }
        .onDisappear {
            Task { await unsubscribeFromComments() }
        }
        .sheet(isPresented: $showingReassignPicker) {
            SearchablePickerSheet<String>(
                title: tr("reassign"),
                rows: reassignPickerRows,
                selectedID: currentTask.assignedTo?.uuidString ?? "__none__",
                onPick: { id in
                    if id == "__none__" {
                        Task { await performReassign(to: nil) }
                    } else if let uuid = UUID(uuidString: id),
                              let staff = reassignableStaff.first(where: { $0.id == uuid }) {
                        Task { await performReassign(to: staff) }
                    }
                }
            )
            .environment(lang)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Reassign (admin-only inline menu)

    private var reassignMenu: some View {
        Button {
            showingReassignPicker = true
        } label: {
            Text(tr("reassign"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.bdAccent)
        }
        .buttonStyle(.plain)
    }

    private func loadReassignableStaffIfNeeded() async {
        guard auth.isAdmin, reassignableStaff.isEmpty else { return }
        let rows: [Staff] = (try? await supabase
            .from("staff")
            .select()
            .eq("is_active", value: true)
            .order("name")
            .execute()
            .value) ?? []
        reassignableStaff = rows
    }

    private func performReassign(to newStaff: Staff?) async {
        guard let actor = auth.staff?.id else { return }
        do {
            try await taskVM.reassign(task: currentTask, to: newStaff, actorId: actor)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rows for the reassign picker: "Anyone" pseudo-row + one row per
    /// active staff. Uses uuidString as the RowID so we can round-trip
    /// through the generic picker's String key and map back in onPick.
    private var reassignPickerRows: [PickerRow<String>] {
        var rows: [PickerRow<String>] = [
            PickerRow<String>(id: "__none__", label: tr("assign_anyone"), isSpecial: true)
        ]
        rows.append(contentsOf: reassignableStaff.map { s in
            PickerRow<String>(
                id: s.id.uuidString,
                label: s.name,
                sublabel: s.email,
                avatar: (s.initials, s.avatarUrl)
            )
        })
        return rows
    }

    // MARK: - Comments

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(tr("comments"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
                    .tracking(1.2)
                Spacer()
                if !comments.isEmpty {
                    Text("\(comments.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            if comments.isEmpty {
                Text(tr("no_comments_yet"))
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                VStack(spacing: 8) {
                    ForEach(comments) { commentRow($0) }
                }
            }

            // Composer pinned at the bottom.
            HStack(alignment: .bottom, spacing: 8) {
                TextField(tr("add_comment"), text: $commentDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .inputStyle()
                Button {
                    Task { await postDraft() }
                } label: {
                    if isPostingComment {
                        ProgressView().tint(.bdAccent)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundColor(canPost ? .bdAccent : .gray.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canPost)
            }
        }
    }

    private var canPost: Bool {
        !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isPostingComment
    }

    @ViewBuilder
    private func commentRow(_ c: TaskComment) -> some View {
        let isOwn = c.authorId != nil && c.authorId == auth.staff?.id
        HStack(alignment: .top, spacing: 10) {
            AvatarView(initials: c.author?.initials ?? "?", url: c.author?.avatarUrl, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.author?.name ?? "—")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Text(formattedTime(c.createdAt))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    if c.editedAt != nil {
                        Text(tr("edited"))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    if isOwn || auth.isAdmin {
                        Menu {
                            Button(role: .destructive) {
                                Task { await deleteComment(c) }
                            } label: {
                                Label(tr("delete"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(c.body)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.bgElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func loadComments() async {
        comments = await taskVM.fetchComments(for: task.id)
    }

    /// Supabase caches channels by topic — re-opening the sheet for
    /// the same task would hit the already-subscribed instance and
    /// throw when we add a `postgresChange` callback. Teardown must
    /// `removeChannel` so the next subscribe gets a fresh binding.
    private func subscribeToComments() async {
        await unsubscribeFromComments()
        let channel = supabase.channel("task_comments_\(task.id)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "task_comments",
            filter: .eq("daily_task_id", value: task.id)
        )
        try? await channel.subscribeWithError()
        commentsRealtimeChannel = channel
        commentsRealtimeTask = Task {
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await loadComments()
            }
        }
    }

    private func unsubscribeFromComments() async {
        commentsRealtimeTask?.cancel()
        commentsRealtimeTask = nil
        if let ch = commentsRealtimeChannel {
            await supabase.removeChannel(ch)
            commentsRealtimeChannel = nil
        }
    }

    private func postDraft() async {
        guard let authorId = auth.staff?.id else { return }
        let body = commentDraft
        isPostingComment = true
        do {
            let created = try await taskVM.postComment(
                dailyTaskId: task.id, authorId: authorId, body: body
            )
            // Optimistic append so the UI feels instant — realtime
            // might deliver the same row a moment later; dedupe by id.
            if !comments.contains(where: { $0.id == created.id }) {
                comments.append(created)
            }
            commentDraft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isPostingComment = false
    }

    private func deleteComment(_ c: TaskComment) async {
        do {
            try await taskVM.deleteComment(id: c.id)
            comments.removeAll { $0.id == c.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Pills + time window

    @ViewBuilder
    private var pillsRow: some View {
        HStack(spacing: 6) {
            if let key = task.task?.category {
                pill(
                    text: CategoryDisplay.localized(key),
                    fg: .gray,
                    bg: Color.bgElevated
                )
            }
            if let prio = task.task?.priority, prio == .high {
                pill(
                    text: tr("priority_high"),
                    fg: .statusPending,
                    bg: Color.statusPending.opacity(0.15)
                )
            }
            pill(
                text: statusLabel,
                fg: statusColor,
                bg: statusColor.opacity(0.15)
            )
        }
    }

    private func pill(text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg)
            .clipShape(Capsule())
    }

    private var statusLabel: String {
        switch task.status {
        case .pending:     return tr("status_pending")
        case .in_progress: return tr("status_in_progress")
        case .completed:   return tr("status_completed")
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .pending:     return .gray
        case .in_progress: return .statusProgress
        case .completed:   return .statusDone
        }
    }

    /// "Expected 17:00 – 17:30" etc. Nil when the template didn't
    /// specify either bound.
    private var expectedWindowText: String? {
        switch (task.startTime, task.endTime) {
        case let (.some(s), .some(e)):
            return String(format: tr("expected_window"),
                          TimeOfDay.displayString(from: s),
                          TimeOfDay.displayString(from: e))
        case let (.some(s), nil):
            return String(format: tr("expected_from"),
                          TimeOfDay.displayString(from: s))
        case let (nil, .some(e)):
            return String(format: tr("expected_by"),
                          TimeOfDay.displayString(from: e))
        default:
            return nil
        }
    }

    // MARK: - Post-completion edits

    private var hasPostCompletionEdits: Bool {
        guard isDone else { return false }
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        let existingNote = currentTask.note ?? ""
        let noteChanged = trimmed != existingNote
        let photoChanged = photoData != nil
        return noteChanged || photoChanged
    }

    private func savePostCompletionEdits() async {
        guard let staffId = auth.staff?.id else { return }
        isSaving = true
        errorMessage = nil
        do {
            var newPhotoUrl: String? = currentTask.photoUrl
            if let data = photoData {
                let mime = data.first == 0x89 ? "image/png" : "image/jpeg"
                newPhotoUrl = try await uploadTaskPhoto(
                    taskId: task.id, date: task.date, imageData: data, mimeType: mime
                )
            }
            try await taskVM.updateNoteAndPhoto(
                task: currentTask,
                actorId: staffId,
                note: note.trimmingCharacters(in: .whitespaces),
                photoUrl: newPhotoUrl
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
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
