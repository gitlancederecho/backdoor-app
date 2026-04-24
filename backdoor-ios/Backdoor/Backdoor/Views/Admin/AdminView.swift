import SwiftUI

enum AdminTab: String, CaseIterable {
    case overview, tasks, categories

    var localized: String {
        switch self {
        case .overview:   return tr("admin_overview")
        case .tasks:      return tr("admin_tasks")
        case .categories: return tr("admin_categories")
        }
    }
}

struct AdminView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(TaskViewModel.self) private var taskVM
    @Environment(LanguageManager.self) private var lang
    @Environment(VenueViewModel.self) private var venue
    @State private var adminVM = AdminViewModel()
    @State private var tab: AdminTab = .overview
    @State private var showingHours = false
    @State private var showingHistory = false
    @State private var showingStaff = false

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text(tr("tab_admin"))
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Spacer()

                        Button { showingStaff = true } label: {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.bgElevated)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(tr("admin_open_staff"))

                        Button { showingHours = true } label: {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.bgElevated)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(tr("admin_open_hours"))

                        Button { showingHistory = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.bgElevated)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(tr("admin_open_history"))
                    }

                    // Segmented pills — only the selected pill carries
                    // a background so the "you are here" signal isn't
                    // diluted by low-contrast neighbors.
                    HStack(spacing: 4) {
                        ForEach(AdminTab.allCases, id: \.self) { t in
                            Button {
                                tab = t
                            } label: {
                                Text(t.localized)
                                    .font(.subheadline.weight(tab == t ? .semibold : .regular))
                                    .foregroundColor(tab == t ? .black : .gray)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(tab == t ? Color.bdAccent : Color.clear)
                                    .clipShape(Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                Divider().background(Color.bdBorder)

                // Content
                switch tab {
                case .overview:   OverviewView(taskVM: taskVM, adminVM: adminVM)
                case .tasks:      TasksAdminView(adminVM: adminVM)
                case .categories: CategoriesAdminView(adminVM: adminVM)
                }
            }
        }
        .environment(adminVM)
        .sheet(isPresented: $showingHours) {
            HoursAdminView()
                .environment(adminVM)
                .environment(venue)
                .environment(lang)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryAdminView()
                .environment(adminVM)
                .environment(lang)
        }
        .sheet(isPresented: $showingStaff) {
            StaffAdminView(adminVM: adminVM)
                .environment(adminVM)
                .environment(auth)
                .environment(lang)
        }
    }
}
