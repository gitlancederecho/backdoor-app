import SwiftUI

struct ContentView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(VenueViewModel.self) private var venue
    @State private var taskVM: TaskViewModel?

    var body: some View {
        Group {
            if auth.isLoading || !venue.isLoaded {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    ProgressView().tint(.bdAccent)
                }
            } else if !auth.isSignedIn {
                LoginView()
            } else if let taskVM {
                MainTabView()
                    .environment(taskVM)
            } else {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    ProgressView().tint(.bdAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if taskVM == nil && venue.isLoaded {
                taskVM = TaskViewModel(
                    date: BusinessDay.currentBusinessDayISO(schedule: venue.schedule, settings: venue.settings)
                )
            }
        }
        .onChange(of: venue.isLoaded) { _, loaded in
            if loaded && taskVM == nil {
                taskVM = TaskViewModel(
                    date: BusinessDay.currentBusinessDayISO(schedule: venue.schedule, settings: venue.settings)
                )
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(TaskViewModel.self) private var taskVM
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        // Re-read lang.current so tab labels refresh when the user changes language
        let _ = lang.current
        TabView {
            Tab(tr("tab_today"), systemImage: "checkmark.square") {
                TaskBoardView()
                    .environment(taskVM)
            }
            Tab(tr("tab_mine"), systemImage: "person.circle") {
                TaskBoardView(filterMine: true)
                    .environment(taskVM)
            }
            if auth.isAdmin {
                Tab(tr("tab_admin"), systemImage: "gearshape") {
                    AdminView()
                        .environment(taskVM)
                }
            }
        }
        .tint(.bdAccent)
    }
}
