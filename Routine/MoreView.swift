import SwiftUI

/// Stats, sleep settings, notification status and the test alarm.
struct MoreView: View {
    @EnvironmentObject private var app: AppData
    @EnvironmentObject private var scheduler: NotificationScheduler

    @State private var testSent = false

    var body: some View {
        NavigationStack {
            List {
                statsSection
                notificationSection
                sleepSettingsSection
                thresholdSection
                aboutSection
            }
            .navigationTitle("More")
            .task { await scheduler.refreshAuthorization() }
        }
    }

    // MARK: Stats

    private var statsSection: some View {
        Section("Days passed") {
            let stats = app.stats
            row("Started", DateKey.longDisplay(app.settings.startDateKey))
            row("Day", "\(stats.dayNumber)")
            row("Current streak", "\(stats.currentStreak)")
            row("Longest streak", "\(stats.longestStreak)")
            row("Good days", "\(stats.goodDays) of \(stats.daysRecorded)")
        }
    }

    // MARK: Notifications

    private var notificationSection: some View {
        Section {
            row("Permission", scheduler.authorizationDescription)
            row("Pending reminders", "\(scheduler.pendingCount)")
            if scheduler.lastTruncatedCount > 0 {
                Text("\(scheduler.lastTruncatedCount) later reminders were skipped to stay "
                     + "under the iOS limit of 64 pending notifications.")
                    .font(.caption).foregroundColor(.orange)
            }

            if scheduler.isDenied {
                Label("Notifications are blocked. Open iOS Settings > Notifications > Routine "
                      + "and allow them, or nothing will ring.", systemImage: "bell.slash")
                    .font(.footnote).foregroundColor(.red)
            } else if scheduler.authorizationStatus == .notDetermined {
                Button("Allow notifications") {
                    Task { await scheduler.requestAuthorization() }
                }
            }

            Button("Send test alarm") {
                Task {
                    await scheduler.sendTestAlarm()
                    testSent = true
                }
            }
            if testSent {
                Text("Test alarm will fire in about 10 seconds. Lock the phone to hear it properly.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Button("Re-apply the whole schedule") {
                Task { await scheduler.reschedule(data: app.data) }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("These are local notifications. They can NOT bypass Silent mode, a Focus, or "
                 + "Do Not Disturb, and they are not Clock alarms. Keep a Clock alarm as a backup "
                 + "for the 4:50 wake-up.")
        }
    }

    // MARK: Sleep settings

    private var sleepSettingsSection: some View {
        Section {
            TimeOfDayPicker(title: "Fixed wake time",
                            value: Binding(get: { app.settings.wakeTime },
                                           set: { value in mutate { $0.wakeTime = value } }))
            Stepper(value: Binding(get: { app.settings.goalSleepMinutes },
                                   set: { value in mutate { $0.goalSleepMinutes = value } }),
                    in: 240...600, step: 15) {
                Text("Goal \(SleepMath.describe(minutes: app.settings.goalSleepMinutes))")
            }
            Stepper(value: Binding(get: { app.settings.minimumSleepMinutes },
                                   set: { value in mutate { $0.minimumSleepMinutes = value } }),
                    in: 180...600, step: 15) {
                Text("Minimum \(SleepMath.describe(minutes: app.settings.minimumSleepMinutes))")
            }
            row("Target bedtime", app.settings.targetBedtime.description)
            row("Latest bedtime", app.settings.latestBedtime.description)
        } header: {
            Text("Sleep")
        } footer: {
            Text("The wake time is shared with the Wake up task in your routine.")
        }
    }

    private var thresholdSection: some View {
        Section {
            Stepper(value: Binding(get: { Int(app.settings.goodDayThreshold * 100) },
                                   set: { value in mutate { $0.goodDayThreshold = Double(value) / 100 } }),
                    in: 50...100, step: 5) {
                Text("Good day at \(Int(app.settings.goodDayThreshold * 100))%")
            }
            Stepper(value: Binding(get: { app.settings.nudgeOffsetAfterMaghrib },
                                   set: { value in mutate { $0.nudgeOffsetAfterMaghrib = value } }),
                    in: 0...120, step: 5) {
                Text("Evening nudge: Maghrib + \(app.settings.nudgeOffsetAfterMaghrib) min")
            }
        } header: {
            Text("Targets")
        } footer: {
            Text("The nudge is a one-off reminder each evening to enter tomorrow's times. "
                 + "It cancels itself once tomorrow is saved.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Text("Routine keeps everything on this iPhone. No account, no server, no network.")
                .font(.footnote).foregroundColor(.secondary)
            NavigationLink("Sleep log") { SleepView() }
        }
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
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }
}
