import SwiftUI

/// Sleep: tonight's targets, today's log, and the last seven nights.
struct SleepView: View {
    @EnvironmentObject private var app: AppData

    private var settings: RoutineSettings { app.settings }

    var body: some View {
        List {
            Section("Targets") {
                row("Fixed wake time", settings.wakeTime.description)
                row("Goal", SleepMath.describe(minutes: settings.goalSleepMinutes))
                row("Minimum", SleepMath.describe(minutes: settings.minimumSleepMinutes))
                row("Target bedtime", settings.targetBedtime.description)
                row("Latest bedtime", settings.latestBedtime.description)
            }

            Section("Today") {
                SleepEditor(dateKey: app.todayKey)
            }

            Section("Last 7 nights") {
                let summary = app.recentSleepSummary
                if summary.nightsLogged == 0 {
                    Text("Nothing logged yet.").foregroundColor(.secondary)
                } else {
                    row("Nights logged", "\(summary.nightsLogged)")
                    row("Average", summary.averageDescription)
                    row("Met minimum", "\(summary.nightsMeetingMinimum) of \(summary.nightsLogged)")
                    row("Met goal", "\(summary.nightsMeetingGoal) of \(summary.nightsLogged)")
                }
            }

            Section("History") {
                ForEach(lastSevenKeys, id: \.self) { key in
                    HStack {
                        Text(DateKey.longDisplay(key)).font(.caption)
                        Spacer()
                        if let log = app.sleep(on: key) {
                            Text(log.durationDescription).monospacedDigit()
                            Circle()
                                .fill(color(for: SleepMath.status(log, settings: settings)))
                                .frame(width: 8, height: 8)
                        } else {
                            Text("-").foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sleep")
    }

    private var lastSevenKeys: [String] {
        (0..<7).compactMap { DateKey.offset(app.todayKey, byDays: -$0) }
    }

    private func color(for status: SleepStatus) -> Color {
        switch status {
        case .meetsGoal: return .green
        case .meetsMinimum: return .yellow
        case .belowMinimum: return .red
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }
}
