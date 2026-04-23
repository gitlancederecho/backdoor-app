import SwiftUI
import Combine

enum TimeBucket: String, CaseIterable {
    case overdue, now, upcoming, anytime, done

    var titleKey: String {
        switch self {
        case .overdue:  return "time_overdue"
        case .now:      return "time_now"
        case .upcoming: return "time_upcoming"
        case .anytime:  return "time_anytime"
        case .done:     return "time_done"
        }
    }

    var accent: Color {
        switch self {
        case .overdue:  return .statusPending
        case .now:      return .bdAccent
        case .upcoming: return .gray
        case .anytime:  return .gray.opacity(0.7)
        case .done:     return .gray.opacity(0.5)
        }
    }
}

enum BoardFilter: Hashable { case everyone, mine }

struct TaskBoardView: View {
    @Environment(TaskViewModel.self) private var vm
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var selectedTask: DailyTask?
    @State private var filter: BoardFilter = .everyone
    @State private var showingDatePicker = false
    @State private var pickerDate: Date = Date()
    /// Refreshes the view every minute so time buckets stay accurate.
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var visibleTasks: [DailyTask] {
        guard filter == .mine, let id = auth.staff?.id else { return vm.tasks }
        // In Mine mode, include unassigned tasks too — they're fair
        // game for the current user to claim.
        return vm.tasks.filter { $0.assignedTo == id || $0.assignedTo == nil }
    }

    /// How close to the start time "upcoming" turns into "now", in minutes.
    private let nowWarmup = 30

    /// The schedule governing this task board's business day.
    private var boardDay: VenueDay? {
        BusinessDay.scheduleDay(for: vm.date, schedule: venue.schedule, tz: venue.settings.timeZone)
    }

    /// Convert a task's clock-time (HH:mm:ss) to minutes into the business day.
    private func taskMinutes(_ time: String) -> Int? {
        guard let day = boardDay else {
            return TimeOfDay.minutesFromMidnight(time)
        }
        return BusinessDay.minutesIntoBusinessDay(clockTimeHHmm: time, day: day, settings: venue.settings)
    }

    /// "Now" in minutes into the business day governing this board.
    private var nowInBusinessDay: Int {
        BusinessDay.nowInBusinessDay(schedule: venue.schedule, settings: venue.settings)
    }

    /// Classify a single task into a time bucket using business-day-relative minutes.
    private func bucket(for task: DailyTask) -> TimeBucket {
        if task.status == .completed { return .done }
        let now = nowInBusinessDay
        let start = task.startTime.flatMap(taskMinutes)
        let end = task.endTime.flatMap(taskMinutes)

        if start == nil && end == nil { return .anytime }
        if let e = end, now > e { return .overdue }

        if let s = start, end == nil {
            return now >= (s - nowWarmup) ? .now : .upcoming
        }
        if start == nil, let e = end {
            return now >= (e - nowWarmup) ? .now : .upcoming
        }
        if let s = start {
            if now < s - nowWarmup { return .upcoming }
            return .now
        }
        return .anytime
    }

    private var buckets: [(bucket: TimeBucket, tasks: [DailyTask])] {
        let grouped = Dictionary(grouping: visibleTasks, by: bucket(for:))
        return TimeBucket.allCases.compactMap { b in
            let list = grouped[b] ?? []
            guard !list.isEmpty else { return nil }
            return (b, sortTasks(list, bucket: b))
        }
    }

    private func sortTasks(_ tasks: [DailyTask], bucket: TimeBucket) -> [DailyTask] {
        switch bucket {
        case .overdue, .now, .upcoming:
            return tasks.sorted {
                let a = $0.startTime.flatMap(taskMinutes)
                    ?? $0.endTime.flatMap(taskMinutes)
                    ?? .max
                let b = $1.startTime.flatMap(taskMinutes)
                    ?? $1.endTime.flatMap(taskMinutes)
                    ?? .max
                return a < b
            }
        case .anytime:
            return tasks.sorted { ($0.task?.category ?? "") < ($1.task?.category ?? "") }
        case .done:
            return tasks.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
    }

    private var doneCount: Int { visibleTasks.filter { $0.status == .completed }.count }
    private var total: Int { visibleTasks.count }

    private var progressSummary: String {
        if total == 0 { return tr("no_tasks") }
        let pct = Int(Double(doneCount) / Double(total) * 100)
        return "\(doneCount)/\(total) \(tr("stat_done").lowercased()) · \(pct)%"
    }

    var body: some View {
        let _ = lang.current
        let _ = tick
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            if vm.isLoading {
                ProgressView().tint(.bdAccent)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                        header
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        if visibleTasks.isEmpty {
                            Text(filter == .mine ? tr("no_tasks_mine") : tr("no_tasks_today"))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        ForEach(buckets, id: \.bucket) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    if group.bucket == .now {
                                        Circle()
                                            .fill(Color.bdAccent)
                                            .frame(width: 6, height: 6)
                                    }
                                    Text(tr(group.bucket.titleKey).uppercased())
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(group.bucket.accent)
                                        .tracking(1.2)
                                    Spacer()
                                    let done = group.tasks.filter { $0.status == .completed }.count
                                    Text("\(done)/\(group.tasks.count)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color.gray.opacity(0.5))
                                }
                                .padding(.horizontal, 16)

                                ForEach(group.tasks) { task in
                                    TaskCardView(task: task)
                                        .padding(.horizontal, 16)
                                        .onTapGesture { selectedTask = task }
                                }
                            }
                        }

                        Spacer().frame(height: 24)
                    }
                }
                .refreshable { await vm.pullRefresh() }
                .simultaneousGesture(
                    // Horizontal swipe to shift date by ±1 day. Used
                    // `simultaneousGesture` so normal vertical scroll
                    // still works; we filter to dominant-horizontal
                    // drags via the translation ratio.
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let h = value.translation.width
                            let v = value.translation.height
                            guard abs(h) > abs(v) * 1.5 else { return }
                            Task { await shiftDate(by: h < 0 ? 1 : -1) }
                        }
                )
            }
        }
        .onReceive(ticker) { tick = $0 }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(selection: $pickerDate) { iso in
                Task { await vm.setDate(iso) }
            }
            .environment(lang)
        }
        .sheet(item: $selectedTask) { task in
            TaskCompletionSheet(task: task, isPresented: .init(
                get: { selectedTask != nil },
                set: { if !$0 { selectedTask = nil } }
            ))
            .environment(auth)
            .environment(vm)
            .environment(lang)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: date navigator + trailing icons
            HStack(spacing: 12) {
                Button { Task { await shiftDate(by: -1) } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                        .background(Color.bgElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    pickerDate = BusinessDay.parse(vm.date, tz: venue.settings.timeZone) ?? Date()
                    showingDatePicker = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedDate(vm.date))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        if vm.date != todayISO() {
                            Text(businessDayHint)
                                .font(.caption2)
                                .foregroundColor(.bdAccent)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button { Task { await shiftDate(by: 1) } } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                        .background(Color.bgElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 12) {
                    PeopleSearchButton()
                        .environment(lang)
                    ProfileMenu()
                        .environment(auth)
                        .environment(lang)
                }
            }

            // Row 2: venue status + progress
            HStack(spacing: 8) {
                venueStatusPill
                Spacer()
                Text(progressSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)
            }

            // Row 3: Everyone / Mine filter pills
            HStack(spacing: 6) {
                filterPill(.everyone, label: tr("filter_everyone"))
                filterPill(.mine,     label: tr("filter_mine"))
                Spacer()
                if vm.date != todayISO() {
                    Button(tr("jump_to_today")) {
                        Task { await vm.setDate(todayISO()) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.bdAccent)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterPill(_ value: BoardFilter, label: String) -> some View {
        Button(label) { filter = value }
            .font(.caption.weight(filter == value ? .semibold : .regular))
            .foregroundColor(filter == value ? .black : .gray)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(filter == value ? Color.bdAccent : Color.bgElevated)
            .clipShape(Capsule())
            .buttonStyle(.plain)
    }

    // MARK: - Venue status

    @ViewBuilder
    private var venueStatusPill: some View {
        let (label, color) = venueStatus
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.bgElevated)
        .clipShape(Capsule())
    }

    /// Short label + a status tint. Looked up from the venue schedule
    /// row for TODAY'S weekday (not the board's date — status is an
    /// always-live reading of right-now).
    private var venueStatus: (String, Color) {
        let tz = venue.settings.timeZone
        guard let day = BusinessDay.scheduleDay(
            for: BusinessDay.iso(Date(), tz: tz),
            schedule: venue.schedule,
            tz: tz
        ) else {
            return (tr("status_unknown"), .gray)
        }
        if day.isClosed {
            return (tr("status_closed_today"), .statusPending)
        }
        let open = BusinessDay.isCurrentlyOpen(schedule: venue.schedule, settings: venue.settings)
        if open {
            if let close = day.closeTime {
                return (String(format: tr("status_open_closes"), TimeOfDay.displayString(from: close)), .statusDone)
            }
            return (tr("status_open"), .statusDone)
        } else {
            if let op = day.openTime {
                return (String(format: tr("status_opens"), TimeOfDay.displayString(from: op)), .statusProgress)
            }
            return (tr("status_between_shifts"), .gray)
        }
    }

    private var businessDayHint: String {
        // Shown under the date when the board is NOT on today's calendar
        // date — clarifies whether we're looking at past or future.
        let cal = Calendar.current
        guard let boardDate = BusinessDay.parse(vm.date, tz: venue.settings.timeZone) else {
            return tr("business_day_other")
        }
        let today = cal.startOfDay(for: Date())
        let bd = cal.startOfDay(for: boardDate)
        let days = cal.dateComponents([.day], from: today, to: bd).day ?? 0
        if days == -1 { return tr("business_day_yesterday") }
        if days ==  1 { return tr("business_day_tomorrow") }
        if days <  0  { return String(format: tr("business_day_days_ago"), -days) }
        return String(format: tr("business_day_days_ahead"), days)
    }

    // MARK: - Date navigation

    private func shiftDate(by days: Int) async {
        let tz = venue.settings.timeZone
        guard let current = BusinessDay.parse(vm.date, tz: tz) else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let next = cal.date(byAdding: .day, value: days, to: current) else { return }
        await vm.setDate(BusinessDay.iso(next, tz: tz))
    }
}

// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    @Binding var selection: Date
    let onCommit: (String) -> Void
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                DatePicker(
                    tr("go_to_date"),
                    selection: $selection,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(20)
                .tint(.bdAccent)
            }
            .navigationTitle(tr("go_to_date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("go")) {
                        onCommit(BusinessDay.iso(selection, tz: venue.settings.timeZone))
                        dismiss()
                    }
                    .foregroundColor(.bdAccent)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

/// People search entry — same visual weight as the avatar next to it.
/// Tap opens the PeopleSheet.
private struct PeopleSearchButton: View {
    @Environment(LanguageManager.self) private var lang
    @State private var showingPeople = false

    var body: some View {
        let _ = lang.current
        Button {
            showingPeople = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 36, height: 36)
                .background(Color.bgElevated)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.bdBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPeople) {
            PeopleSheet().environment(lang)
        }
    }
}

private struct ProfileMenu: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @State private var showingProfile = false

    var body: some View {
        let _ = lang.current
        // Tap the avatar → full Profile page. The profile page itself
        // hosts edit, language picker, and sign out, so the drop-down
        // menu we used to show here is gone.
        Button {
            showingProfile = true
        } label: {
            AvatarView(
                initials: auth.staff?.initials ?? "?",
                url: auth.staff?.avatarUrl,
                size: 36
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environment(auth)
                .environment(lang)
        }
    }
}
