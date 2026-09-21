import SwiftUI
import UIKit

/// Today, in the order the day is actually lived:
/// hero progress, one insight, the prayer timeline, the routine, sleep, notes.
struct DayView: View {
    @EnvironmentObject private var app: AppData
    @EnvironmentObject private var scheduler: NotificationScheduler

    @State private var editorDate: DateKeyItem?
    @State private var noteDraft: String = ""
    @State private var expandedTask: UUID?

    private var todayKey: String { app.todayKey }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RT.sectionSpacing) {
                    alerts
                    hero
                    prayerSection
                    routineSection
                    conflictSection
                    sleepSection
                    noteSection

                    Color.clear.frame(height: RT.tabBarClearance)
                }
                .padding(.horizontal, RT.screenPadding)
                .padding(.top, 8)
            }
            .routineScreen()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { noteDraft = app.day(todayKey)?.note ?? "" }
            .sheet(item: $editorDate) { item in
                PrayerView(dateKey: item.key).environmentObject(app)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var alerts: some View {
        if scheduler.isDenied {
            BannerView(title: "Notifications are blocked. Nothing can ring.",
                       actionTitle: "Settings",
                       tint: .red) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        }
        if app.needsTomorrowsPrayerTimes {
            BannerView(title: "Tomorrow's prayer times haven't been entered.",
                       actionTitle: "Set up") {
                editorDate = DateKeyItem(app.tomorrowKey)
            }
        }
    }

    private var hero: some View {
        let completion = app.completion(for: todayKey)
        let insight = app.insight(for: todayKey)
        return VStack(alignment: .leading, spacing: 14) {
            Text(DateKey.longDisplay(todayKey))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RT.secondaryLabel)

            HeroRingView(completion: completion, insight: insight)

            InsightCard(insight: insight,
                        action: insight.kind == .noPrayerTimes
                            ? { editorDate = DateKeyItem(todayKey) }
                            : nil)
        }
    }

    @ViewBuilder
    private var prayerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if app.prayerTimes(on: todayKey) == nil {
                SectionHeader("Prayers")
            } else {
                SectionHeader("Prayers", actionTitle: "Edit") {
                    editorDate = DateKeyItem(todayKey)
                }
            }
            PrayerTimelineCard(times: app.prayerTimes(on: todayKey),
                               nextPrayer: app.nextPrayer(on: todayKey)) {
                editorDate = DateKeyItem(todayKey)
            }
        }
    }

    private var routineSection: some View {
        let plan = app.plan(for: todayKey)
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Routine")

            Toggle("Going out today", isOn: Binding(
                get: { app.isGoingOut(on: todayKey) },
                set: { value in
                    Haptics.selection()
                    app.setGoingOut(value, on: todayKey)
                }))
                .font(.subheadline.weight(.medium))
                .tint(RT.accent)
                .card()

            if plan.isEmpty {
                Text("Nothing scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(RT.secondaryLabel)
                    .card()
            }

            ForEach(plan) { planned in
                taskGroup(planned)
            }
        }
    }

    /// A task plus, where it has one, its inline checklist.
    @ViewBuilder
    private func taskGroup(_ planned: PlannedTask) -> some View {
        let steps = planned.task.steps.filter(\.enabled)
        let isExpanded = expandedTask == planned.id

        VStack(spacing: 8) {
            PlannedRow(planned: planned,
                       isComplete: app.isComplete(planned.id, on: todayKey),
                       toggle: { app.toggleTask(planned.id, on: todayKey) })

            if !steps.isEmpty {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(steps) { step in
                            StepToggleRow(
                                name: step.name,
                                isComplete: app.isStepComplete(step.id, task: planned.id, on: todayKey),
                                toggle: { app.toggleStep(step.id, task: planned.id, on: todayKey) })
                        }

                        Button("Hide") {
                            withAnimation(.routineSpring) { expandedTask = nil }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(RT.accent)
                        .frame(minHeight: 32)
                    }
                    .padding(.horizontal, RT.cardPadding)
                    .padding(.vertical, 6)
                    .background(RT.surface,
                                in: RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous))
                } else {
                    Button {
                        withAnimation(.routineSpring) { expandedTask = planned.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(stepSummary(planned, steps: steps))
                                .font(.caption)
                                .foregroundStyle(RT.secondaryLabel)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RT.tertiaryLabel)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, RT.cardPadding)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func stepSummary(_ planned: PlannedTask, steps: [ChecklistStep]) -> String {
        let done = steps.filter { app.isStepComplete($0.id, task: planned.id, on: todayKey) }.count
        return "\(done) of \(steps.count) products"
    }

    @ViewBuilder
    private var conflictSection: some View {
        let conflicts = app.conflicts(for: todayKey)
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Conflicts")
                ConflictList(conflicts: conflicts).card()
            }
        }
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Sleep")
            VStack(alignment: .leading, spacing: 12) {
                if let log = app.sleep(on: todayKey) {
                    HStack {
                        Text("\(log.bedtime.description) - \(log.wakeTime.description)")
                            .font(.subheadline)
                            .foregroundStyle(RT.label)
                        Spacer()
                        Text(log.durationDescription)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(RT.label)
                    }
                    if let status = app.sleepStatus(on: todayKey) {
                        HStack(spacing: 7) {
                            Circle().fill(status.color).frame(width: 7, height: 7)
                            Text(status.displayName)
                                .font(.caption)
                                .foregroundStyle(RT.secondaryLabel)
                        }
                    }
                } else {
                    Text("Not logged yet.")
                        .font(.subheadline)
                        .foregroundStyle(RT.secondaryLabel)
                    Text("Target bedtime \(app.settings.targetBedtime.description), latest \(app.settings.latestBedtime.description)")
                        .font(.caption)
                        .foregroundStyle(RT.tertiaryLabel)
                }

                NavigationLink {
                    SleepView()
                } label: {
                    HStack {
                        Text("Sleep log")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(RT.accent)
                    .frame(minHeight: RT.minTarget)
                }
            }
            .card()
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Note")
            VStack(alignment: .trailing, spacing: 12) {
                TextField("How did today go?", text: $noteDraft, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if noteDraft != (app.day(todayKey)?.note ?? "") {
                    Button("Save") {
                        Haptics.success()
                        app.setNote(noteDraft, on: todayKey)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(RT.accent)
                    .frame(minHeight: RT.minTarget)
                }
            }
            .card()
        }
    }
}

/// Lets a yyyy-MM-dd key drive `.sheet(item:)` without conforming String itself.
struct DateKeyItem: Identifiable, Hashable {
    let key: String
    var id: String { key }
    init(_ key: String) { self.key = key }
}
