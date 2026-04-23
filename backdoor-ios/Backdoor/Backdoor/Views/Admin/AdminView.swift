import SwiftUI

enum AdminTab: String, CaseIterable {
    case overview, tasks, categories, staff, hours, history

    var localized: String {
        switch self {
        case .overview:   return tr("admin_overview")
        case .tasks:      return tr("admin_tasks")
        case .categories: return tr("admin_categories")
        case .staff:      return tr("admin_staff")
        case .hours:      return tr("admin_hours")
        case .history:    return tr("admin_history")
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

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("tab_admin"))
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    // Segment tabs — horizontal scroll since we have 4 now
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AdminTab.allCases, id: \.self) { t in
                                Button(t.localized) { tab = t }
                                    .font(.subheadline.weight(tab == t ? .semibold : .regular))
                                    .foregroundColor(tab == t ? .black : .gray)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(tab == t ? Color.bdAccent : Color.bgElevated)
                                    .clipShape(Capsule())
                            }
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
                case .hours:      HoursAdminView()
                case .history:    HistoryAdminView()
                }
            }
        }
        .environment(adminVM)
    }
}
