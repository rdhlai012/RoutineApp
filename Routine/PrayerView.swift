import SwiftUI

/// The prayer-times editor. It works for ANY date - tomorrow, today if you
/// forgot, or a past date from the calendar - and is the single place where
/// times are entered and a date is scheduled.
struct PrayerView: View {
    let dateKey: String
    /// Set when the screen is shown as a tab rather than a sheet.
    var embedded: Bool = false

    @EnvironmentObject private var app: AppData
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PrayerTimesDraft()
    @State private var goingOut = false
    @State private var saving = false
    @State private var outcome: ScheduleOutcome?
    @State private var errorMessage: String?
    @State private var loaded = false

    private var isTomorrow: Bool { dateKey == app.tomorrowKey }
    private var isToday: Bool { dateKey == app.todayKey }

    private var label: String {
        if isTomorrow { return "Tomorrow" }
        if isToday { return "Today" }
        return DateKey.longDisplay(dateKey)
    }

    private var saved: PrayerTimes? { app.prayerTimes(on: dateKey) }

    /// True while the pickers differ from what is actually stored.
    private var isDraft: Bool {
        guard let saved = saved else { return true }
        return draft.completed != saved
    }

    var body: some View {
        Group {
            if embedded {
                NavigationStack { form }
            } else {
                NavigationStack {
                    form
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }
                            }
                        }
                }
            }
        }
        .onAppear(perform: loadOnce)
    }

    private var form: some View {
        List {
            header
            pickers
            goingOutSection
            previewSection
            saveSection
        }
        .navigationTitle(isTomorrow ? "Set Up Tomorrow" : "Prayer Times")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(DateKey.longDisplay(dateKey)).font(.headline)
                if isDraft {
                    Label("Draft - not saved", systemImage: "pencil.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var pickers: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                OptionalTimeOfDayPicker(title: prayer.displayName,
                                        placeholder: placeholder(for: prayer),
                                        value: Binding(
                                            get: { draft[prayer] },
                                            set: { draft[prayer] = $0 }))
            }
        } header: {
            Text("All five times")
        } footer: {
            Text("Every prayer is required. The pickers start from today's times "
                 + "for convenience; nothing is scheduled until you save.")
        }
    }

    private var goingOutSection: some View {
        Section {
            Toggle(isTomorrow ? "I'm going out tomorrow" : "I'm going out this day",
                   isOn: $goingOut)
        } footer: {
            Text("Off by default. Turning it on adds the extra sunscreen reminders for this date only.")
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if let times = draft.completed {
            let result = TomorrowSetup.preview(dateKey: dateKey,
                                               times: times,
                                               data: previewData)
            Section("Preview") {
                ForEach(result.schedule) { planned in
                    PlannedRow(planned: planned, isComplete: false, toggle: nil)
                }
            }
            Section("Checks") {
                ConflictList(conflicts: result.conflicts)
            }
        } else {
            Section("Preview") {
                Text("Enter all five times to see the full day.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    Text(isTomorrow ? "SAVE TOMORROW'S TIMES" : "SAVE TIMES")
                        .font(.headline)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!TomorrowSetup.canSave(draft) || saving)

            Button {
                copyPreviousDay()
            } label: {
                HStack {
                    Spacer()
                    Text("COPY PREVIOUS DAY")
                        .font(.subheadline)
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(previousDayTimes == nil || saving)

            if let reason = TomorrowSetup.saveBlockedReason(draft) {
                Text(reason).font(.footnote).foregroundColor(.secondary)
            }
            if let errorMessage = errorMessage {
                Text(errorMessage).font(.footnote).foregroundColor(.red)
            }
            if let outcome = outcome {
                Text(outcome.message(label: label))
                    .font(.footnote)
                    .foregroundColor(outcome.isSuccess ? .green : .red)
            }
        }
    }

    // MARK: Helpers

    private var previousDayTimes: PrayerTimes? {
        guard let prevKey = DateKey.offset(dateKey, byDays: -1) else { return nil }
        return app.prayerTimes(on: prevKey)
    }

    private func copyPreviousDay() {
        if let times = previousDayTimes {
            draft = PrayerTimesDraft(times)
        }
    }

    /// A copy with this date's going-out choice applied, so the preview matches
    /// what saving would produce - without touching stored data.
    private var previewData: RoutineData {
        var copy = app.data
        copy.setGoingOut(goingOut, on: dateKey)
        return copy
    }

    private func placeholder(for prayer: Prayer) -> TimeOfDay {
        if let saved = saved { return saved[prayer] }
        if let today = app.prayerTimes(on: app.todayKey) { return today[prayer] }
        switch prayer {
        case .fajr: return TimeOfDay(hour: 5, minute: 0)
        case .dhuhr: return TimeOfDay(hour: 12, minute: 15)
        case .asr: return TimeOfDay(hour: 15, minute: 30)
        case .maghrib: return TimeOfDay(hour: 18, minute: 20)
        case .isha: return TimeOfDay(hour: 19, minute: 40)
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let saved = saved {
            draft = PrayerTimesDraft(saved)
        }
        goingOut = app.isGoingOut(on: dateKey)
    }

    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }

        app.setGoingOut(goingOut, on: dateKey)
        let result = await app.savePrayerTimes(draft, on: dateKey)
        switch result {
        case .failure(let error):
            errorMessage = error.message
            outcome = nil
        case .success(let value):
            outcome = value
            errorMessage = nil
        }
    }
}

/// The dedicated "Set Up Tomorrow" tab. Same editor, always pointed at tomorrow.
struct SetupTomorrowView: View {
    @EnvironmentObject private var app: AppData

    var body: some View {
        // Re-created if the date rolls over while the app is open.
        PrayerView(dateKey: app.tomorrowKey, embedded: true)
            .id(app.tomorrowKey)
    }
}
