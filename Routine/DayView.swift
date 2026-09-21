import SwiftUI

/// Today: banners for missing prayer times, the going-out switch, the schedule,
/// the daily note and a sleep summary.
struct DayView: View {
    @EnvironmentObject private var app: AppData
    @EnvironmentObject private var scheduler: NotificationScheduler

    @State private var editorDate: DateKeyItem?
    @State private var noteDraft: String = ""

    private var todayKey: String { app.todayKey }

    var body: some View {
        NavigationStack {
            List {
                if scheduler.isDenied {
                    Section {
                        Label("Notifications are blocked in iOS Settings. Nothing can ring until you allow them.",
                              systemImage: "bell.slash")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                if app.needsTodaysPrayerTimes || app.needsTomorrowsPrayerTimes {
                    Section {
                        if app.needsTodaysPrayerTimes {
                            BannerView(title: "Today's prayer times haven't been entered.",
                                       actionTitle: "Enter today's times") {
                                editorDate = DateKeyItem(todayKey)
                            }
                        }
                        if app.needsTomorrowsPrayerTimes {
                            BannerView(title: "Tomorrow's prayer times haven't been entered.",
                                       actionTitle: "Set up tomorrow") {
                                editorDate = DateKeyItem(app.tomorrowKey)
                            }
                        }
                    }
                }

                Section {
                    CompletionBar(completion: app.completion(for: todayKey))
                    Toggle("I'm going out today", isOn: Binding(
                        get: { app.isGoingOut(on: todayKey) },
                        set: { app.setGoingOut($0, on: todayKey) }))
                } header: {
                    Text(DateKey.longDisplay(todayKey))
                }

                Section("Prayer times") {
                    if let times = app.prayerTimes(on: todayKey) {
                        ForEach(Prayer.allCases) { prayer in
                            HStack {
                                Text(prayer.displayName)
                                Spacer()
                                Text(times[prayer].description).monospacedDigit()
                            }
                        }
                        Button("Edit today's times") { editorDate = DateKeyItem(todayKey) }
                    } else {
                        Text("Not entered").foregroundColor(.secondary)
                        Button("Enter today's times") { editorDate = DateKeyItem(todayKey) }
                    }
                }

                let plan = app.plan(for: todayKey)
                Section("Schedule") {
                    if plan.isEmpty {
                        Text("Nothing scheduled.").foregroundColor(.secondary)
                    }
                    ForEach(plan) { planned in
                        PlannedRow(planned: planned,
                                   isComplete: app.isComplete(planned.id, on: todayKey),
                                   toggle: { app.toggleTask(planned.id, on: todayKey) })
                        if !planned.task.steps.isEmpty {
                            ForEach(planned.task.steps.filter(\.enabled)) { step in
                                Toggle(step.name, isOn: Binding(
                                    get: { app.isStepComplete(step.id, task: planned.id, on: todayKey) },
                                    set: { _ in app.toggleStep(step.id, task: planned.id, on: todayKey) }))
                                    .font(.footnote)
                                    .padding(.leading, 28)
                            }
                        }
                    }
                }

                let conflicts = app.conflicts(for: todayKey)
                if !conflicts.isEmpty {
                    Section("Conflicts") { ConflictList(conflicts: conflicts) }
                }

                Section("Sleep") {
                    if let log = app.sleep(on: todayKey) {
                        HStack {
                            Text("\(log.bedtime.description) - \(log.wakeTime.description)")
                            Spacer()
                            Text(log.durationDescription).monospacedDigit()
                        }
                        if let status = app.sleepStatus(on: todayKey) {
                            Text(status.displayName).font(.caption).foregroundColor(.secondary)
                        }
                    } else {
                        Text("Not logged").foregroundColor(.secondary)
                    }
                    NavigationLink("Sleep log") { SleepView() }
                }

                Section("Note") {
                    TextField("How did today go?", text: $noteDraft, axis: .vertical)
                        .lineLimit(1...5)
                        .onSubmit { app.setNote(noteDraft, on: todayKey) }
                    Button("Save note") { app.setNote(noteDraft, on: todayKey) }
                        .disabled(noteDraft == (app.day(todayKey)?.note ?? ""))
                }
            }
            .navigationTitle("Today")
            .onAppear { noteDraft = app.day(todayKey)?.note ?? "" }
            .sheet(item: $editorDate) { item in
                PrayerView(dateKey: item.key)
                    .environmentObject(app)
            }
        }
    }
}

/// Lets a yyyy-MM-dd key drive `.sheet(item:)` without conforming String itself.
struct DateKeyItem: Identifiable, Hashable {
    let key: String
    var id: String { key }
    init(_ key: String) { self.key = key }
}
