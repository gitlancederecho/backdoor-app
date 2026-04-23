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

struct TaskBoardView: View {
    @Environment(TaskViewModel.self) private var vm
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var selectedTask: DailyTask?
    /// Refreshes the view every minute so time buckets stay accurate.
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var filterMine: Bool = false

    private var visibleTasks: [DailyTask] {
        guard filterMine, let id = auth.staff?.id else { return vm.tasks }
        return vm.tasks.filter { $0.assignedTo == id }
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
                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formattedDate(todayISO()))
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text(progressSummary)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            ProfileMenu()
                                .environment(auth)
                                .environment(lang)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        if visibleTasks.isEmpty {
                            Text(filterMine ? tr("no_tasks_mine") : tr("no_tasks_today"))
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
            }
        }
        .onReceive(ticker) { tick = $0 }
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
