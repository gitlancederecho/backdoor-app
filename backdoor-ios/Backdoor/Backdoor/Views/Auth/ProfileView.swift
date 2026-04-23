import SwiftUI
import Supabase

// MARK: - Shared stat payload

struct ProfileStats: Decodable {
    var today_assigned: Int
    var today_completed: Int
    var week_completed: Int
    var all_time_completed: Int
    var in_progress_now: Int

    static let empty = ProfileStats(
        today_assigned: 0, today_completed: 0,
        week_completed: 0, all_time_completed: 0,
        in_progress_now: 0
    )
}

/// Params struct so a nil `target` omits the key (Supabase/PostgREST
/// picks up the function's default NULL → caller's own row).
private struct ProfileStatsParams: Encodable {
    let target: UUID?
}

// MARK: - ProfileView (self)

/// Personal profile page — same layout for admin and staff, with one
/// role-specific insight card sandwiched between identity and stats.
/// Accessed by tapping the top-right avatar on the Today tab.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingSignOutConfirm = false
    @State private var stats = ProfileStats.empty
    @State private var recentEvents: [TaskEvent] = []
    @State private var isLoading = false

    // Role-specific insight state
    @State private var activeStaffCount: Int = 0
    @State private var templatesCreated: Int = 0
    @State private var reassignmentsByMe: Int = 0
    @State private var nextPending: DailyTask? = nil

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identityCard
                        insightCard
                        statsGrid
                        recentActivitySection
                        preferencesSection
                        signOutButton
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .refreshable { await load() }
            }
            .navigationTitle(tr("profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("close")) { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .sheet(isPresented: $showingEdit) {
            ProfileEditSheet().environment(auth).environment(lang)
        }
        .confirmationDialog(tr("sign_out_confirm"), isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
            Button(tr("sign_out"), role: .destructive) {
                Task { await auth.signOut() }
            }
            Button(tr("cancel"), role: .cancel) {}
        }
    }

    private var identityCard: some View {
        ProfileIdentityCard(
            staff: auth.staff,
            trailingAction: { showingEdit = true },
            trailingLabel: tr("edit")
        )
    }

    // MARK: - Role-specific insight

    @ViewBuilder
    private var insightCard: some View {
        if auth.isAdmin {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("profile_admin_insight_header"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
                    .tracking(1.2)
                VStack(alignment: .leading, spacing: 8) {
                    insightRow(icon: "person.3", label: tr("insight_active_staff"), value: "\(activeStaffCount)")
                    insightRow(icon: "list.bullet.rectangle", label: tr("insight_templates_created"), value: "\(templatesCreated)")
                    insightRow(icon: "arrow.left.arrow.right", label: tr("insight_reassignments"), value: "\(reassignmentsByMe)")
                }
                .padding(14)
                .cardStyle()
            }
        } else if let next = nextPending {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("profile_staff_insight_header"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
                    .tracking(1.2)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundColor(.bdAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.task?.title ?? "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let window = timeWindowLabel(next) {
                            Text(window).font(.caption).foregroundColor(.gray)
                        }
                    }
                    Spacer()
                }
                .padding(14)
                .cardStyle()
            }
        }
    }

    private func insightRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.bdAccent).frame(width: 20)
            Text(label).font(.subheadline).foregroundColor(.white)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold)).foregroundColor(.white)
        }
    }

    // MARK: - Stats grid (shared with StaffProfileView)

    private var statsGrid: some View { ProfileStatsGrid(stats: stats) }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_activity_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)
            if recentEvents.isEmpty && !isLoading {
                Text(tr("no_history"))
                    .font(.subheadline).foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).cardStyle()
            } else {
                VStack(spacing: 8) {
                    ForEach(recentEvents) { ProfileActivityRow(event: $0) }
                }
            }
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_preferences_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)
            HStack(spacing: 8) {
                Text(tr("language")).font(.subheadline).foregroundColor(.white)
                Spacer()
                ForEach(AppLanguage.allCases) { l in
                    Button(l.label) { lang.current = l }
                        .font(.caption.weight(lang.current == l ? .semibold : .regular))
                        .foregroundColor(lang.current == l ? .black : .gray)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(lang.current == l ? Color.bdAccent : Color.bgElevated)
                        .clipShape(Capsule())
                }
            }
            .padding(12).cardStyle()
        }
    }

    private var signOutButton: some View {
        Button { showingSignOutConfirm = true } label: {
            Label(tr("sign_out"), systemImage: "rectangle.portrait.and.arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.statusPending)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color.bgCard)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.statusPending.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Data load

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Stats for self.
        if let result: ProfileStats = try? await supabase
            .rpc("profile_stats", params: ProfileStatsParams(target: nil))
            .execute()
            .value {
            stats = result
        }

        guard let me = auth.staff?.id else { return }

        async let events: [TaskEvent] = (try? await supabase
            .from("task_events")
            .select("*, dailyTask:daily_tasks(*, task:tasks(*))")
            .eq("actor_id", value: me)
            .order("created_at", ascending: false)
            .limit(15)
            .execute()
            .value) ?? []

        if auth.isAdmin {
            async let staffCount: [Staff] = (try? await supabase
                .from("staff").select().eq("is_active", value: true).execute().value) ?? []
            async let templates: [TaskTemplate] = (try? await supabase
                .from("tasks").select().eq("created_by", value: me).execute().value) ?? []
            async let reassigns: [TaskEvent] = (try? await supabase
                .from("task_events").select("*")
                .eq("actor_id", value: me)
                .eq("event_type", value: TaskEventType.reassigned.rawValue)
                .execute().value) ?? []
            activeStaffCount = await staffCount.count
            templatesCreated = await templates.count
            reassignmentsByMe = await reassigns.count
        } else {
            // Staff insight: next pending task assigned to me for today,
            // sorted by start_time (nulls last).
            let pending: [DailyTask] = (try? await supabase
                .from("daily_tasks")
                .select("*, task:tasks(*)")
                .eq("assigned_to", value: me)
                .eq("date", value: todayISO())
                .eq("status", value: TaskStatus.pending.rawValue)
                .order("start_time", ascending: true, nullsFirst: false)
                .limit(1)
                .execute()
                .value) ?? []
            nextPending = pending.first
        }

        recentEvents = await events
    }

    private func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private func timeWindowLabel(_ dt: DailyTask) -> String? {
        switch (dt.startTime, dt.endTime) {
        case let (.some(s), .some(e)): return "\(TimeOfDay.displayString(from: s)) – \(TimeOfDay.displayString(from: e))"
        case let (.some(s), nil):      return TimeOfDay.displayString(from: s)
        case let (nil, .some(e)):      return TimeOfDay.displayString(from: e)
        default: return nil
        }
    }
}

// MARK: - StaffProfileView (read-only peer profile)

/// Read-only profile for another staff member, reached from the People
/// search sheet. No edit, no sign-out, no preferences — just identity,
/// their stats, and their recent public activity.
struct StaffProfileView: View {
    let staff: Staff
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var stats = ProfileStats.empty
    @State private var recentEvents: [TaskEvent] = []

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ProfileIdentityCard(staff: staff, trailingAction: nil, trailingLabel: nil)
                        ProfileStatsGrid(stats: stats)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("profile_activity_header"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                                .tracking(1.2)
                            if recentEvents.isEmpty {
                                Text(tr("no_history"))
                                    .font(.subheadline).foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16).cardStyle()
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(recentEvents) { ProfileActivityRow(event: $0) }
                                }
                            }
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .refreshable { await load() }
            }
            .navigationTitle(staff.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("close")) { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func load() async {
        if let result: ProfileStats = try? await supabase
            .rpc("profile_stats", params: ProfileStatsParams(target: staff.id))
            .execute()
            .value {
            stats = result
        }
        let events: [TaskEvent] = (try? await supabase
            .from("task_events")
            .select("*, dailyTask:daily_tasks(*, task:tasks(*))")
            .eq("actor_id", value: staff.id)
            .order("created_at", ascending: false)
            .limit(15)
            .execute()
            .value) ?? []
        recentEvents = events
    }
}

// MARK: - Shared pieces

/// Identity card reused on both own-profile and other-staff profile.
private struct ProfileIdentityCard: View {
    let staff: Staff?
    /// If provided, a trailing button appears (e.g. "Edit").
    let trailingAction: (() -> Void)?
    let trailingLabel: String?

    @Environment(LanguageManager.self) private var lang

    var body: some View {
        let _ = lang.current
        HStack(alignment: .top, spacing: 12) {
            AvatarView(initials: staff?.initials ?? "?", url: staff?.avatarUrl, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(staff?.name ?? "—")
                    .font(.title3.bold()).foregroundColor(.white)
                Text(staff?.email ?? "")
                    .font(.caption).foregroundColor(.gray).lineLimit(1)
                HStack(spacing: 6) {
                    roleBadge
                    if let created = staff?.createdAt {
                        Text("· \(memberSince(created))")
                            .font(.caption2).foregroundColor(.gray)
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
            if let trailingAction, let trailingLabel {
                Button(trailingLabel, action: trailingAction)
                    .font(.subheadline.weight(.medium)).foregroundColor(.bdAccent)
            }
        }
        .padding(16).cardStyle()
    }

    @ViewBuilder
    private var roleBadge: some View {
        if staff?.role == .admin {
            Text(tr("role_admin"))
                .font(.caption2.weight(.semibold)).foregroundColor(.bdAccent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.bdAccent.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Text(tr("role_staff"))
                .font(.caption2.weight(.medium)).foregroundColor(.gray)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.bgElevated)
                .clipShape(Capsule())
        }
    }

    private func memberSince(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale.current
        return String(format: tr("member_since"), f.string(from: date))
    }
}

private struct ProfileStatsGrid: View {
    let stats: ProfileStats
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        let _ = lang.current
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_stats_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                tile(title: tr("stat_today"),       primary: "\(stats.today_completed)/\(stats.today_assigned)", subtitle: tr("stat_today_subtitle"))
                tile(title: tr("stat_in_progress"), primary: "\(stats.in_progress_now)",                          subtitle: tr("stat_in_progress_subtitle"))
                tile(title: tr("stat_this_week"),   primary: "\(stats.week_completed)",                            subtitle: tr("stat_this_week_subtitle"))
                tile(title: tr("stat_all_time"),    primary: "\(stats.all_time_completed)",                        subtitle: tr("stat_all_time_subtitle"))
            }
        }
    }

    private func tile(title: String, primary: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.gray)
            Text(primary).font(.title2.weight(.semibold).monospacedDigit()).foregroundColor(.white)
            Text(subtitle).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).cardStyle()
    }
}

private struct ProfileActivityRow: View {
    let event: TaskEvent
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        let _ = lang.current
        let title = event.dailyTask?.task?.title ?? event.note ?? "—"
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.white).lineLimit(1)
                Text(verb).font(.caption2).foregroundColor(.gray)
            }
            Spacer()
            Text(shortTime(event.createdAt))
                .font(.caption2.monospacedDigit()).foregroundColor(.gray)
        }
        .padding(12).cardStyle()
    }

    private var verb: String {
        switch event.eventType {
        case .created:      return tr("event_created")
        case .started:      return tr("event_started")
        case .completed:    return tr("event_completed")
        case .undone:       return event.dailyTaskId == nil ? tr("event_restored") : tr("event_undone")
        case .reassigned:   return tr("event_reassigned")
        case .note_added:   return tr("event_note_added")
        case .note_updated: return tr("event_note_updated")
        case .photo_added:  return tr("event_photo_added")
        case .deleted:      return tr("event_deleted")
        }
    }

    private func shortTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale.current
        if cal.isDateInToday(date) { f.dateStyle = .none; f.timeStyle = .short }
        else if cal.isDateInYesterday(date) { return tr("history_date_yesterday") }
        else { f.dateStyle = .short; f.timeStyle = .none }
        return f.string(from: date)
    }
}
