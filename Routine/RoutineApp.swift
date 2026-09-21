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
                .tint(RT.accent)
                .preferredColorScheme(.dark)
                .onAppear { app.onAppear() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.onForeground() }
        }
    }
}

enum TabSelection: Hashable {
    case today, tomorrow, calendar, routine, more
}

/// The system `TabView` is what produces the floating Liquid Glass tab bar on
/// iOS 26 and later, along with its selection glow, scroll-edge behaviour,
/// Dynamic Type handling and VoiceOver support. Hand-rolling that bar would
/// look close and behave worse, so this stays native.
struct RootView: View {
    @EnvironmentObject private var app: AppData
    @State private var selection: TabSelection = .today

    var body: some View {
        TabView(selection: $selection) {
            DayView()
                .tag(TabSelection.today)
                .tabItem { Label("Today", systemImage: "sun.max") }

            SetupTomorrowView()
                .tag(TabSelection.tomorrow)
                .tabItem { Label("Tomorrow", systemImage: "moon.stars") }
                .badge(app.needsTomorrowsPrayerTimes ? Text("!") : nil)

            CalendarTab()
                .tag(TabSelection.calendar)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            ManageView()
                .tag(TabSelection.routine)
                .tabItem { Label("Routine", systemImage: "checklist") }

            MoreView()
                .tag(TabSelection.more)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onChange(of: selection) { Haptics.selection() }
    }
}
