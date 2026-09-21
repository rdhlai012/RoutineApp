import SwiftUI

@main
struct RoutineApp: App {
    @StateObject private var app = AppData()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(NotificationScheduler.shared)
                .onAppear { app.onAppear() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { app.onForeground() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppData

    var body: some View {
        TabView {
            DayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            SetupTomorrowView()
                .tabItem { Label("Tomorrow", systemImage: "moon.stars") }
                .badge(app.needsTomorrowsPrayerTimes ? Text("!") : nil)

            CalendarTab()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            ManageView()
                .tabItem { Label("Routine", systemImage: "list.bullet") }

            MoreView()
                .tabItem { Label("More", systemImage: "gearshape") }
        }
    }
}
