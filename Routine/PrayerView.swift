import SwiftUI

/// The prayer-times editor. It works for ANY date - tomorrow, today if you
/// forgot, or a past date from the calendar - and is the single place where
/// times are entered and a date is scheduled.
struct PrayerView: View {
    let dateKey: String
    /// True when shown as a tab rather than as a sheet.
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
        NavigationStack {
            form
                .toolbar {
                    if !embedded {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
        }
        .onAppear(perform: loadOnce)
    }

    private var form: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RT.sectionSpacing) {
                header
                pickers
                goingOutRow
                previewSection
                saveSection

                Color.clear.frame(height: RT.tabBarClearance)
            }
            .padding(.horizontal, RT.screenPadding)
            .padding(.top, 8)
        }
        .routineScreen()
        .navigationTitle(isTomorrow ? "Set Up Tomorrow" : "Prayer Times")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DateKey.longDisplay(dateKey))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(RT.label)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Circle()
                    .fill(isDraft ? RT.prayer : RT.done)
                    .frame(width: 7, height: 7)
                Text(isDraft ? "Draft - not saved" : "Saved")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isDraft ? RT.prayer : RT.done)
            }
            .animation(.routineSpring, value: isDraft)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Pickers

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("All five times")

            VStack(spacing: 10) {
                ForEach(Prayer.allCases) { prayer in
                    CapsuleTimePicker(prayer: prayer,
                                      placeholder: placeholder(for: prayer),
                                      value: Binding(
                                        get: { draft[prayer] },
                                        set: { draft[prayer] = $0 }))
                }
            }

            if let previous = previousDayTimes {
                Button {
                    Haptics.selection()
                    withAnimation(.routineSpring) { draft = PrayerTimesDraft(previous) }
                } label: {
                    Label("Copy the previous day", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: RT.minTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(RT.accent)
                .card(padding: nil)
            }

            Text("Every prayer is required. Pickers start from the nearest known day for convenience; nothing is scheduled until you save.")
                .font(.caption)
                .foregroundStyle(RT.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var goingOutRow: some View {
        Toggle(isTomorrow ? "I'm going out tomorrow" : "I'm going out this day",
               isOn: $goingOut)
            .font(.subheadline.weight(.medium))
            .tint(RT.accent)
            .card()
            .onChange(of: goingOut) { _ in Haptics.selection() }
    }

    // MARK: Live preview

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Preview")

            if let times = draft.completed {
                let result = TomorrowSetup.preview(dateKey: dateKey,
                                                   times: times,
                                                   data: previewData)
                VStack(spacing: 0) {
                    ForEach(Array(result.schedule.enumerated()), id: \.element.id) { index, planned in
                        previewRow(planned, isLast: index == result.schedule.count - 1)
                    }
                }
                .card(padding: nil)
                .padding(.horizontal, RT.cardPadding)
                .padding(.vertical, 6)

                ConflictList(conflicts: result.conflicts).card()
            } else {
                VStack(spacing: 8) {
                    Text("Enter all five times")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RT.label)
                    Text(missingSummary)
                        .font(.footnote)
                        .foregroundStyle(RT.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .card(padding: nil)
            }
        }
    }

    /// One step of the generated chain, with a connector down to the next.
    private func previewRow(_ planned: PlannedTask, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(planned.task.isProtected ? RT.prayer : RT.accent.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(RT.hairline)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(planned.task.title)
                    .font(.subheadline.weight(planned.task.isProtected ? .semibold : .regular))
                    .foregroundStyle(RT.label)
                if let note = planned.task.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(RT.tertiaryLabel)
                }
            }

            Spacer(minLength: 8)

            Text(planned.time?.description ?? "-")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(RT.secondaryLabel)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var missingSummary: String {
        let missing = draft.missing.map(\.displayName)
        if missing.isEmpty { return "" }
        return "Still needed: " + missing.joined(separator: ", ")
    }

    // MARK: Save

    private var saveSection: some View {
        VStack(spacing: 14) {
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text(isTomorrow ? "SAVE TOMORROW'S TIMES" : "SAVE TIMES")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(RT.accent)
            .disabled(!TomorrowSetup.canSave(draft) || saving)

            if let reason = TomorrowSetup.saveBlockedReason(draft) {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(RT.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let outcome = outcome {
                Label(outcome.message(label: label),
                      systemImage: outcome.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(outcome.isSuccess ? RT.done : .red)
                    .fixedSize(horizontal: false, vertical: true)
                    .card()
            }
        }
    }

    // MARK: Helpers

    private var previousDayTimes: PrayerTimes? {
        guard let previousKey = DateKey.offset(dateKey, byDays: -1) else { return nil }
        return app.prayerTimes(on: previousKey)
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
        if let previous = previousDayTimes { return previous[prayer] }
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
        if let saved = saved { draft = PrayerTimesDraft(saved) }
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
            Haptics.failure()
            errorMessage = error.message
            outcome = nil
        case .success(let value):
            value.isSuccess ? Haptics.success() : Haptics.warning()
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
