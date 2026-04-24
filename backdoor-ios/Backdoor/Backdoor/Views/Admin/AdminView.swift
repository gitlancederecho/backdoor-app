import SwiftUI

enum AdminTab: String, CaseIterable {
    case overview, tasks, categories, staff

    var localized: String {
        switch self {
        case .overview:   return tr("admin_overview")
        case .tasks:      return tr("admin_tasks")
        case .categories: return tr("admin_categories")
        case .staff:      return tr("admin_staff")
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

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
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

                        Spacer()

                        Text(tr("tab_admin"))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }

                    // Segment tabs — four entries, no scroll needed.
                    HStack(spacing: 8) {
                        ForEach(AdminTab.allCases, id: \.self) { t in
                            Button(t.localized) { tab = t }
                                .font(.subheadline.weight(tab == t ? .semibold : .regular))
                                .foregroundColor(tab == t ? .black : .gray)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(tab == t ? Color.bdAccent : Color.bgElevated)
                                .clipShape(Capsule())
                                .frame(maxWidth: .infinity)
                        }
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
                case .staff:      StaffAdminView(adminVM: adminVM)
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
    }
}
