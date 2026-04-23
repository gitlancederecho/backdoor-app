import SwiftUI
import Supabase

/// Personal profile page available to every signed-in staff member
/// regardless of role. Shows identity + quick completion stats +
/// recent activity + preferences + sign out. Admins get the same page;
/// their admin-only affordances live on the Admin tab.
struct ProfileView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var showingSignOutConfirm = false
    @State private var stats = ProfileStats.empty
    @State private var recentEvents: [TaskEvent] = []
    @State private var isLoading = false

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

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identityCard
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
            ProfileEditSheet()
                .environment(auth)
                .environment(lang)
        }
        .confirmationDialog(tr("sign_out_confirm"), isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
            Button(tr("sign_out"), role: .destructive) {
                Task { await auth.signOut() }
            }
            Button(tr("cancel"), role: .cancel) {}
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                AvatarView(
                    initials: auth.staff?.initials ?? "?",
                    url: auth.staff?.avatarUrl,
                    size: 72
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.staff?.name ?? "—")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text(auth.staff?.email ?? "")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        roleBadge
                        if let created = auth.staff?.createdAt {
                            Text("· \(memberSince(created))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
                Button(tr("edit")) { showingEdit = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bdAccent)
            }
        }
        .padding(16)
        .cardStyle()
    }

    @ViewBuilder
    private var roleBadge: some View {
        if auth.staff?.role == .admin {
            Text(tr("role_admin"))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.bdAccent)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.bdAccent.opacity(0.15))
                .clipShape(Capsule())
        } else {
            Text(tr("role_staff"))
                .font(.caption2.weight(.medium))
                .foregroundColor(.gray)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Color.bgElevated)
                .clipShape(Capsule())
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_stats_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)

            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                statTile(
                    title: tr("stat_today"),
                    primary: "\(stats.today_completed)/\(stats.today_assigned)",
                    subtitle: tr("stat_today_subtitle")
                )
                statTile(
                    title: tr("stat_in_progress"),
                    primary: "\(stats.in_progress_now)",
                    subtitle: tr("stat_in_progress_subtitle")
                )
                statTile(
                    title: tr("stat_this_week"),
                    primary: "\(stats.week_completed)",
                    subtitle: tr("stat_this_week_subtitle")
                )
                statTile(
                    title: tr("stat_all_time"),
                    primary: "\(stats.all_time_completed)",
                    subtitle: tr("stat_all_time_subtitle")
                )
            }
        }
    }

    private func statTile(title: String, primary: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.gray)
            Text(primary)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundColor(.white)
            Text(subtitle).font(.caption2).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_activity_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)

            if recentEvents.isEmpty && !isLoading {
                Text(tr("no_history"))
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .cardStyle()
            } else {
                VStack(spacing: 8) {
                    ForEach(recentEvents) { event in
                        activityRow(event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ e: TaskEvent) -> some View {
        let title = e.dailyTask?.task?.title ?? e.note ?? "—"
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(verb(for: e))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
            Text(shortTime(e.createdAt))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.gray)
        }
        .padding(12)
        .cardStyle()
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("profile_preferences_header"))
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .tracking(1.2)
            HStack(spacing: 8) {
                Text(tr("language"))
                    .font(.subheadline)
                    .foregroundColor(.white)
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
            .padding(12)
            .cardStyle()
        }
    }

    // MARK: - Sign out

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

        // Stats via RPC (single round-trip, server-side counts).
        if let result: ProfileStats = try? await supabase
            .rpc("my_profile_stats")
            .execute()
            .value {
            stats = result
        }

        // Recent events authored by the caller.
        guard let me = auth.staff?.id else { return }
        let events: [TaskEvent] = (try? await supabase
            .from("task_events")
            .select("*, dailyTask:daily_tasks(*, task:tasks(*))")
            .eq("actor_id", value: me)
            .order("created_at", ascending: false)
            .limit(15)
            .execute()
            .value) ?? []
        recentEvents = events
    }

    // MARK: - Formatting

    private func memberSince(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale.current
        return String(format: tr("member_since"), f.string(from: date))
    }

    private func shortTime(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale.current
        if cal.isDateInToday(date) {
            f.dateStyle = .none
            f.timeStyle = .short
        } else if cal.isDateInYesterday(date) {
            return tr("history_date_yesterday")
        } else {
            f.dateStyle = .short
            f.timeStyle = .none
        }
        return f.string(from: date)
    }

    private func verb(for e: TaskEvent) -> String {
        switch e.eventType {
        case .created:      return tr("event_created")
        case .started:      return tr("event_started")
        case .completed:    return tr("event_completed")
        case .undone:       return e.dailyTaskId == nil ? tr("event_restored") : tr("event_undone")
        case .reassigned:   return tr("event_reassigned")
        case .note_added:   return tr("event_note_added")
        case .note_updated: return tr("event_note_updated")
        case .photo_added:  return tr("event_photo_added")
        case .deleted:      return tr("event_deleted")
        }
    }
}
