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
                // Header: title + secondary-admin icon buttons
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
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)

                // Folder-tab row: the selected tab has `bgPrimary`
                // (same as body), so it "cuts through" the `bgCard`
                // band and visually merges into the content below.
                HStack(spacing: 0) {
                    ForEach(AdminTab.allCases, id: \.self) { t in
                        Button { tab = t } label: {
                            Text(t.localized)
                                .font(.subheadline.weight(tab == t ? .semibold : .regular))
                                .foregroundColor(tab == t ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    UnevenRoundedRectangle(
                                        cornerRadii: tab == t
                                            ? .init(topLeading: 14, bottomLeading: 0,
                                                    bottomTrailing: 0, topTrailing: 14)
                                            : .init()
                                    )
                                    .fill(tab == t ? Color.bgPrimary : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.bgCard)

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
