import SwiftUI

/// The full record for one date, grouped by category. Past days stay editable.
struct DayDetailView: View {
    let dateKey: String

    @EnvironmentObject private var app: AppData
    @State private var noteDraft = ""
    @State private var editor: DateKeyItem?

    private var plan: [PlannedTask] { app.plan(for: dateKey) }

    private var groups: [CategoryGroup] {
        Dictionary(grouping: plan, by: { $0.task.category })
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { CategoryGroup(category: $0.key, items: $0.value) }
    }

    var body: some View {
        List {
            Section {
                CompletionBar(completion: app.completion(for: dateKey))
                Text("Day \(Stats.dayNumber(on: dateKey, data: app.data))")
                    .font(.caption).foregroundColor(.secondary)
                Toggle("Going out", isOn: Binding(
                    get: { app.isGoingOut(on: dateKey) },
                    set: { app.setGoingOut($0, on: dateKey) }))
            }

            Section("Prayer times") {
                if let times = app.prayerTimes(on: dateKey) {
                    ForEach(Prayer.allCases) { prayer in
                        HStack {
                            Text(prayer.displayName)
                            Spacer()
                            Text(times[prayer].description).monospacedDigit()
                        }
                    }
                } else {
                    Text("Not entered").foregroundColor(.secondary)
                }
                Button("Edit prayer times") { editor = DateKeyItem(dateKey) }
            }

            ForEach(groups) { group in
                Section(group.category.displayName) {
                    ForEach(group.items) { planned in
                        VStack(alignment: .leading, spacing: 6) {
                            PlannedRow(planned: planned,
                                       isComplete: app.isComplete(planned.id, on: dateKey),
                                       toggle: { app.toggleTask(planned.id, on: dateKey) })
                            ForEach(planned.task.steps.filter(\.enabled)) { step in
                                Toggle(step.name, isOn: Binding(
                                    get: { app.isStepComplete(step.id, task: planned.id, on: dateKey) },
                                    set: { _ in app.toggleStep(step.id, task: planned.id, on: dateKey) }))
                                    .font(.footnote)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                }
            }

            Section("Sleep") {
                SleepEditor(dateKey: dateKey)
            }

            Section("Daily note") {
                TextField("Note for this day", text: $noteDraft, axis: .vertical)
                    .lineLimit(1...6)
                Button("Save note") { app.setNote(noteDraft, on: dateKey) }
                    .disabled(noteDraft == (app.day(dateKey)?.note ?? ""))
            }
        }
        .navigationTitle(DateKey.longDisplay(dateKey))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { noteDraft = app.day(dateKey)?.note ?? "" }
        .sheet(item: $editor) { item in
            PrayerView(dateKey: item.key).environmentObject(app)
        }
    }
}

/// One category's worth of a day, for `ForEach`.
struct CategoryGroup: Identifiable {
    let category: TaskCategory
    let items: [PlannedTask]
    var id: String { category.rawValue }
}

/// Bedtime / wake time for one date, with the derived duration and status.
struct SleepEditor: View {
    let dateKey: String
    @EnvironmentObject private var app: AppData

    @State private var bedtime = TimeOfDay(hour: 22, minute: 10)
    @State private var wakeTime = RoutineSettings.defaultWakeTime
    @State private var loaded = false

    private var duration: Int {
        SleepLog(bedtime: bedtime, wakeTime: wakeTime).durationMinutes
    }

    var body: some View {
        Group {
            TimeOfDayPicker(title: "Bedtime", value: $bedtime)
            TimeOfDayPicker(title: "Wake time", value: $wakeTime)

            HStack {
                Text("Duration")
                Spacer()
                Text(SleepMath.describe(minutes: duration)).monospacedDigit()
            }
            HStack {
                Text("Status")
                Spacer()
                Text(SleepMath.status(durationMinutes: duration,
                                      minimumMinutes: app.settings.minimumSleepMinutes,
                                      goalMinutes: app.settings.goalSleepMinutes).displayName)
                    .foregroundColor(.secondary)
            }

            Button("Save sleep") {
                app.setSleep(bedtime: bedtime, wakeTime: wakeTime, on: dateKey)
            }
            if app.sleep(on: dateKey) != nil {
                Button("Clear sleep", role: .destructive) { app.clearSleep(on: dateKey) }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let log = app.sleep(on: dateKey) {
                bedtime = log.bedtime
                wakeTime = log.wakeTime
            } else {
                wakeTime = app.settings.wakeTime
                bedtime = app.settings.targetBedtime
            }
        }
    }
}
