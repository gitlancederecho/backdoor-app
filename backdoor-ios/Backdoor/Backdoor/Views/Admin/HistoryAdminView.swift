import SwiftUI

/// Admin-facing audit log. Shows every task_event in a chosen date
/// range, filterable by event type and actor. Grouped by calendar date.
struct HistoryAdminView: View {
    @Environment(AdminViewModel.self) private var adminVM
    @Environment(LanguageManager.self) private var lang
    @State private var vm = HistoryViewModel()
    @State private var selectedTask: DailyTask?

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                Divider().background(Color.bdBorder)

                if vm.isLoading && vm.events.isEmpty {
                    loadingState
                } else if let err = vm.error {
                    errorState(err)
                } else if vm.events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .sheet(item: $selectedTask) { task in
            TaskCompletionSheet(task: task, isPresented: .init(
                get: { selectedTask != nil },
                set: { if !$0 { selectedTask = nil } }
            ))
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Date range pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HistoryDateRange.allCases) { r in
                        Button(rangeLabel(r)) { vm.dateRange = r }
                            .font(.caption.weight(vm.dateRange == r ? .semibold : .regular))
                            .foregroundColor(vm.dateRange == r ? .black : .gray)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(vm.dateRange == r ? Color.bdAccent : Color.bgElevated)
                            .clipShape(Capsule())
                    }
                }
            }

            // Event type + actor menus on one row
            HStack(spacing: 8) {
                eventTypeMenu
                actorMenu
                Spacer()
                if vm.isLoading { ProgressView().scaleEffect(0.75) }
            }
        }
    }

    private var eventTypeMenu: some View {
        Menu {
            Button(tr("history_events_all")) { vm.selectedEventTypes = [] }
            Divider()
            ForEach(TaskEventType.allCases, id: \.rawValue) { t in
                Button {
                    if vm.selectedEventTypes.contains(t) {
                        vm.selectedEventTypes.remove(t)
                    } else {
                        vm.selectedEventTypes.insert(t)
                    }
                } label: {
                    HStack {
                        Text(verb(for: t))
                        if vm.selectedEventTypes.contains(t) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterPill(
                label: tr("history_filter_events"),
                value: eventTypesSummary
            )
        }
    }

    private var actorMenu: some View {
        Menu {
            Button(tr("history_actor_all")) { vm.selectedActorId = nil }
            Divider()
            ForEach(adminVM.allStaff) { s in
                Button {
                    vm.selectedActorId = s.id
                } label: {
                    HStack {
                        Text(s.name)
                        if vm.selectedActorId == s.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            filterPill(
                label: tr("history_filter_actor"),
                value: actorSummary
            )
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

    private var eventTypesSummary: String {
        if vm.selectedEventTypes.isEmpty { return tr("history_events_all") }
        if vm.selectedEventTypes.count == 1 {
            return verb(for: vm.selectedEventTypes.first!)
        }
        return String(format: tr("history_events_selected"), vm.selectedEventTypes.count)
    }

    private var actorSummary: String {
        if let id = vm.selectedActorId,
           let s = adminVM.allStaff.first(where: { $0.id == id }) {
            return s.name
        }
        return tr("history_actor_all")
    }

    // MARK: - Empty / loading / error

    private var loadingState: some View {
        VStack { Spacer(); ProgressView(); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.6))
            Text(tr("no_history"))
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.statusPending)
            Text(tr("history_error")).font(.subheadline).foregroundColor(.white)
            Text(message).font(.caption2).foregroundColor(.gray).multilineTextAlignment(.center)
            Button(tr("save")) { Task { await vm.refresh() } } // reuse "Save" as Retry? no — use plain text
                .buttonStyle(.borderless)
                .foregroundColor(.bdAccent)
                .hidden() // (button intentionally hidden — refresh handled by pull-to-refresh)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Event list

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: .sectionHeaders) {
                ForEach(vm.groupedByDate, id: \.date) { group in
                    Section {
                        VStack(spacing: 8) {
                            ForEach(group.events) { e in
                                eventRow(e)
                                    .padding(.horizontal, 16)
                            }
                        }
                    } header: {
                        dateHeader(for: group.date)
                    }
                }
                Spacer(minLength: 24)
            }
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func dateHeader(for iso: String) -> some View {
        HStack {
            Text(friendlyDateLabel(iso))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgPrimary)
    }

    @ViewBuilder
    private func eventRow(_ e: TaskEvent) -> some View {
        let canOpen = e.dailyTask != nil
        Button {
            if let dt = e.dailyTask { selectedTask = dt }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(initials: e.actor?.initials ?? "?", url: e.actor?.avatarUrl, size: 32)

                VStack(alignment: .leading, spacing: 4) {
                    // Title line: actor, verb, task title
                    HStack(spacing: 6) {
                        Text(e.actor?.name ?? "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        verbBadge(e.eventType)
                    }

                    if let taskTitle = e.dailyTask?.task?.title, !taskTitle.isEmpty {
                        Text(taskTitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // from → to for reassignments
                    if e.eventType == .reassigned,
                       let toId = e.toValue, let toUUID = UUID(uuidString: toId) {
                        let toName = adminVM.allStaff.first(where: { $0.id == toUUID })?.name ?? "—"
                        Text("→ \(toName)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Optional note preview
                    if let note = e.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(timeString(e.createdAt))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.gray)
                    if canOpen {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }
            .padding(12)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }

    private func verbBadge(_ type: TaskEventType) -> some View {
        let color: Color = {
            switch type {
            case .completed:    return .statusDone
            case .started:      return .statusProgress
            case .undone:       return .statusPending
            case .reassigned:   return .bdAccent
            case .deleted:      return .statusPending
            case .created, .note_added, .note_updated, .photo_added: return .gray
            }
        }()
        return Text(verb(for: type))
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Formatting helpers

    private func rangeLabel(_ r: HistoryDateRange) -> String {
        switch r {
        case .today:  return tr("history_range_today")
        case .last7:  return tr("history_range_7d")
        case .last30: return tr("history_range_30d")
        case .all:    return tr("history_range_all")
        }
    }

    private func verb(for type: TaskEventType) -> String {
        switch type {
        case .created:      return tr("event_created")
        case .started:      return tr("event_started")
        case .completed:    return tr("event_completed")
        case .undone:       return tr("event_undone")
        case .reassigned:   return tr("event_reassigned")
        case .note_added:   return tr("event_note_added")
        case .note_updated: return tr("event_note_updated")
        case .photo_added:  return tr("event_photo_added")
        case .deleted:      return tr("event_deleted")
        }
    }

    private func friendlyDateLabel(_ iso: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let date = df.date(from: iso) else { return iso }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return tr("history_date_today") }
        if cal.isDateInYesterday(date) { return tr("history_date_yesterday") }
        let pretty = DateFormatter()
        pretty.dateStyle = .medium
        pretty.locale = Locale.current
        return pretty.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
