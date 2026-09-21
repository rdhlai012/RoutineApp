import SwiftUI

/// Settings, in native grouped cells: streaks, sleep, goals, notifications,
/// data and about.
struct MoreView: View {
    @EnvironmentObject private var app: AppData
    @EnvironmentObject private var scheduler: NotificationScheduler

    @State private var testSent = false

    var body: some View {
        NavigationStack {
            List {
                statsSection
                sleepSection
                goalsSection
                notificationSection
                dataSection
                aboutSection

                Color.clear
                    .frame(height: RT.tabBarClearance)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RT.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .task { await scheduler.refreshAuthorization() }
        }
    }

    // MARK: Streaks

    private var statsSection: some View {
        Section {
            let stats = app.stats
            row("Day", "\(stats.dayNumber)")
            row("Current streak", "\(stats.currentStreak)")
            row("Longest streak", "\(stats.longestStreak)")
            row("Good days", "\(stats.goodDays) of \(stats.daysRecorded)")
            row("Started", DateKey.longDisplay(app.settings.startDateKey))
        } header: {
            Text("Progress")
        }
        .listRowBackground(RT.surface)
    }

    // MARK: Sleep

    private var sleepSection: some View {
        Section {
            TimeOfDayPicker(title: "Wake time",
                            value: Binding(get: { app.settings.wakeTime },
                                           set: { value in mutate { $0.wakeTime = value } }))

            Stepper(value: Binding(get: { app.settings.goalSleepMinutes },
                                   set: { value in mutate { $0.goalSleepMinutes = value } }),
                    in: 240...600, step: 15) {
                labelled("Goal sleep", SleepMath.describe(minutes: app.settings.goalSleepMinutes))
            }

            Stepper(value: Binding(get: { app.settings.minimumSleepMinutes },
                                   set: { value in mutate { $0.minimumSleepMinutes = value } }),
                    in: 180...600, step: 15) {
                labelled("Minimum sleep", SleepMath.describe(minutes: app.settings.minimumSleepMinutes))
            }

            row("Target bedtime", app.settings.targetBedtime.description)
            row("Latest bedtime", app.settings.latestBedtime.description)
        } header: {
            Text("Sleep")
        } footer: {
            Text("The wake time is shared with the Wake up task in your routine.")
        }
        .listRowBackground(RT.surface)
    }

    // MARK: Goals

    private var goalsSection: some View {
        Section {
            Stepper(value: Binding(get: { Int((app.settings.goodDayThreshold * 100).rounded()) },
                                   set: { value in mutate { $0.goodDayThreshold = Double(value) / 100 } }),
                    in: 50...100, step: 5) {
                labelled("Completion target", "\(Int((app.settings.goodDayThreshold * 100).rounded()))%")
            }

            Stepper(value: Binding(get: { app.settings.nudgeOffsetAfterMaghrib },
                                   set: { value in mutate { $0.nudgeOffsetAfterMaghrib = value } }),
                    in: 0...120, step: 5) {
                labelled("Evening reminder", "Maghrib + \(app.settings.nudgeOffsetAfterMaghrib) min")
            }
        } header: {
            Text("Daily goals")
        } footer: {
            Text("The evening reminder is a one-off nudge to enter tomorrow's times. It cancels itself once tomorrow is saved.")
        }
        .listRowBackground(RT.surface)
    }

    // MARK: Notifications

    private var notificationSection: some View {
        Section {
            HStack {
                Text("Permission")
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(scheduler.isDenied ? Color.red : RT.done)
                        .frame(width: 7, height: 7)
                    Text(scheduler.authorizationDescription)
                        .foregroundStyle(RT.secondaryLabel)
                }
            }
            .accessibilityElement(children: .combine)

            row("Pending reminders", "\(scheduler.pendingCount)")

            if scheduler.lastTruncatedCount > 0 {
                Text("\(scheduler.lastTruncatedCount) later reminders were skipped to stay under the iOS limit of 64 pending notifications.")
                    .font(.caption)
                    .foregroundStyle(RT.prayer)
            }

            if scheduler.isDenied {
                Label("Blocked. Open iOS Settings > Notifications > Routine and allow them, or nothing will ring.",
                      systemImage: "bell.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if scheduler.authorizationStatus == .notDetermined {
                Button("Allow notifications") {
                    Task { await scheduler.requestAuthorization() }
                }
            }

            Button {
                Haptics.selection()
                Task {
                    await scheduler.sendTestAlarm()
                    testSent = true
                }
            } label: {
                Label("Send test alarm", systemImage: "alarm.waves.left.and.right.fill")
            }

            if testSent {
                Text("Test alarm fires in about 10 seconds. Lock the phone to hear it properly.")
                    .font(.caption)
                    .foregroundStyle(RT.secondaryLabel)
            }

            Button {
                Task { await scheduler.reschedule(data: app.data) }
            } label: {
                Label("Re-apply the whole schedule", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("These are local notifications. They can NOT bypass Silent mode, a Focus, or Do Not Disturb, and they are not Clock alarms. Keep a Clock alarm as a backup for the wake-up.")
        }
        .listRowBackground(RT.surface)
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            NavigationLink {
                SleepView()
            } label: {
                Label("Sleep log", systemImage: "bed.double.fill")
            }

            // The routine editor lives in its own tab. Pushing it here would
            // nest a second NavigationStack inside this one.
            Label("Edit the routine in the Routine tab", systemImage: "checklist")
                .font(.footnote)
                .foregroundStyle(RT.secondaryLabel)
        } header: {
            Text("Data")
        } footer: {
            Text("Everything is stored in routine.json on this iPhone. No account, no server, no network.")
        }
        .listRowBackground(RT.surface)
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            row("Version", appVersion)
            row("Deployment target", "iOS 26.0")
            HStack {
                Text("Privacy")
                Spacer()
                Text("On device only")
                    .foregroundStyle(RT.secondaryLabel)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("About")
        }
        .listRowBackground(RT.surface)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Helpers

    private func mutate(_ body: (inout RoutineSettings) -> Void) {
        var settings = app.settings
        body(&settings)
        app.updateSettings(settings)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(RT.secondaryLabel)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(RT.secondaryLabel)
                .monospacedDigit()
        }
    }
}
