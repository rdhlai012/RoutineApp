import SwiftUI

// MARK: - Time pickers

/// A compact time picker bound to a `TimeOfDay`.
struct TimeOfDayPicker: View {
    let title: String
    @Binding var value: TimeOfDay

    private let calendar = Calendar.current

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                comps.hour = value.hour
                comps.minute = value.minute
                return calendar.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = calendar.dateComponents([.hour, .minute], from: newDate)
                value = TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            }
        )
    }

    var body: some View {
        DatePicker(title, selection: dateBinding, displayedComponents: .hourAndMinute)
    }
}

/// The large rounded picker capsule used by the Set Up Tomorrow flow.
/// An un-entered prayer is outlined in orange so the missing ones are obvious
/// at a glance without reading any text.
struct CapsuleTimePicker: View {
    let prayer: Prayer
    let placeholder: TimeOfDay
    @Binding var value: TimeOfDay?

    private var displayTime: TimeOfDay { value ?? placeholder }
    private var isEntered: Bool { value != nil }

    private var dateBinding: Binding<Date> {
        let calendar = Calendar.current
        return Binding(
            get: {
                var comps = calendar.dateComponents([.year, .month, .day], from: Date())
                comps.hour = displayTime.hour
                comps.minute = displayTime.minute
                return calendar.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = calendar.dateComponents([.hour, .minute], from: newDate)
                value = TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
                Haptics.selection()
            }
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: prayer.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(RT.prayer)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(prayer.displayName)
                    .font(.headline)
                    .foregroundStyle(RT.label)
                if !isEntered {
                    Text("Not set")
                        .font(.caption)
                        .foregroundStyle(RT.prayer)
                }
            }

            Spacer(minLength: 8)

            DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, RT.cardPadding)
        .padding(.vertical, 14)
        .frame(minHeight: RT.minTarget)
        .background(RT.surface, in: RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous)
                .strokeBorder(isEntered ? RT.hairline : RT.prayer.opacity(0.55),
                              lineWidth: isEntered ? 0.5 : 1.5)
        )
        .animation(.routineSpring, value: isEntered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.displayName) time")
        .accessibilityValue(isEntered ? displayTime.description : "not set")
    }
}

// MARK: - Banner

/// The attention strip used when something needs the person's input.
struct BannerView: View {
    let title: String
    let actionTitle: String
    var tint: Color = RT.prayer
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(RT.label)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .frame(minHeight: RT.minTarget)
        }
        .padding(.horizontal, RT.cardPadding)
        .padding(.vertical, 14)
        .background(tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
        )
    }
}

struct ConflictList: View {
    let conflicts: [ScheduleConflict]

    var body: some View {
        if conflicts.isEmpty {
            Label("No sequence conflicts", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(RT.done)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(conflicts) { conflict in
                    Label(conflict.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(RT.prayer)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Hero

/// The day's headline: a progress ring, the count, and one line of motivation.
struct HeroRingView: View {
    let completion: DayCompletion
    let insight: DailyInsight

    private var ringColor: Color {
        completion.state == .complete ? RT.done : RT.accent
    }

    var body: some View {
        HStack(spacing: RT.cardPadding) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.001, CGFloat(completion.fraction)))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(completion.percent)%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(RT.label)
                    .monospacedDigit()
            }
            .frame(width: 72, height: 72)
            .animation(.routineRing, value: completion.fraction)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(completion.completedCount) of \(completion.plannedCount) completed")
                    .font(.headline)
                    .foregroundStyle(RT.label)
                Text(insight.headline)
                    .font(.subheadline)
                    .foregroundStyle(completion.state == .complete ? RT.done : RT.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(RT.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingGlass(radius: RT.heroRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's progress")
        .accessibilityValue("\(completion.percent) percent, \(completion.completedCount) of \(completion.plannedCount) completed. \(insight.headline)")
    }
}

/// The smart insight card that sits directly under the hero.
struct InsightCard: View {
    let insight: DailyInsight
    var action: (() -> Void)?

    private var tint: Color {
        switch insight.kind {
        case .noPrayerTimes: return RT.prayer
        case .allDone: return RT.done
        default: return RT.accent
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: insight.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RT.label)
                Text(insight.detail)
                    .font(.footnote)
                    .foregroundStyle(RT.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RT.tertiaryLabel)
                    .accessibilityHidden(true)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { action?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.headline). \(insight.detail)")
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

// MARK: - Prayer timeline

/// The five prayers for one date, or an elegant empty state.
struct PrayerTimelineCard: View {
    let times: PrayerTimes?
    var nextPrayer: Prayer?
    let editAction: () -> Void

    var body: some View {
        Group {
            if let times = times {
                VStack(spacing: 0) {
                    ForEach(Prayer.allCases) { prayer in
                        row(prayer, at: times[prayer])
                        if prayer != .isha {
                            Divider()
                                .overlay(RT.hairline)
                                .padding(.leading, 40)
                        }
                    }
                }
                .card(padding: nil)
                .padding(.horizontal, RT.cardPadding)
                .padding(.vertical, 4)
            } else {
                emptyState
            }
        }
    }

    private func row(_ prayer: Prayer, at time: TimeOfDay) -> some View {
        let isNext = prayer == nextPrayer
        return HStack(spacing: 14) {
            Image(systemName: prayer.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(RT.prayer)
                .frame(width: 26)
                .accessibilityHidden(true)

            Text(prayer.displayName)
                .font(.body.weight(isNext ? .semibold : .regular))
                .foregroundStyle(RT.label)

            if isNext {
                Text("NEXT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RT.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RT.accent.opacity(0.16), in: Capsule())
            }

            Spacer(minLength: 8)

            Text(time.description)
                .font(.body.monospacedDigit())
                .foregroundStyle(isNext ? RT.label : RT.secondaryLabel)
        }
        .padding(.vertical, 14)
        .frame(minHeight: RT.minTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.displayName) \(time.description)\(isNext ? ", next" : "")")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(RT.prayer)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Prayer times needed")
                    .font(.headline)
                    .foregroundStyle(RT.label)
                Text("Nothing prayer-anchored is scheduled until these are entered.")
                    .font(.footnote)
                    .foregroundStyle(RT.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Enter times", action: editAction)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(RT.prayer)
                .controlSize(.large)
                .frame(minHeight: RT.minTarget)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, RT.cardPadding)
        .card(padding: nil)
    }
}

// MARK: - Task capsule

/// One task on Today. Prayer tasks are marked with an orange glyph rather than
/// orange text, so the colour reads as a category and never as a warning.
struct PlannedRow: View {
    let planned: PlannedTask
    let isComplete: Bool
    let toggle: (() -> Void)?

    private var task: RoutineTask { planned.task }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            checkbox

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if task.isProtected {
                        Image(systemName: "moon.stars.fill")
                            .font(.caption)
                            .foregroundStyle(RT.prayer)
                            .accessibilityHidden(true)
                    }
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(RT.label)
                        .strikethrough(isComplete, color: RT.secondaryLabel)
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(RT.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if let time = planned.time {
                Text(time.description)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isComplete ? RT.tertiaryLabel : RT.secondaryLabel)
            } else {
                Text(planned.unresolvedReason ?? "Not scheduled")
                    .font(.caption)
                    .foregroundStyle(RT.prayer)
            }
        }
        .padding(RT.cardPadding)
        .frame(minHeight: RT.minTarget)
        .background(RT.surface, in: RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RT.cardRadius, style: .continuous)
                .strokeBorder(RT.hairline, lineWidth: 0.5)
        )
        .opacity(isComplete ? 0.55 : 1)
        .animation(.routineSpring, value: isComplete)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isComplete ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(toggle == nil ? "" : (isComplete ? "Marks not done" : "Marks done"))
    }

    private var checkbox: some View {
        Button {
            guard let toggle = toggle else { return }
            isComplete ? Haptics.uncompleted() : Haptics.completed()
            withAnimation(.routineSpring) { toggle() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isComplete ? RT.done : RT.tertiaryLabel, lineWidth: 1.8)
                    .frame(width: 26, height: 26)
                Circle()
                    .fill(RT.done)
                    .frame(width: 26, height: 26)
                    .scaleEffect(isComplete ? 1 : 0.01)
                    .opacity(isComplete ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.black)
                    .scaleEffect(isComplete ? 1 : 0.01)
                    .opacity(isComplete ? 1 : 0)
            }
            .frame(width: RT.minTarget, height: RT.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(toggle == nil)
        .accessibilityHidden(true)
    }

    private var subtitle: String? {
        if let note = task.note, !note.isEmpty { return note }
        if task.isProtected { return "Obligatory" }
        return nil
    }

    private var accessibilityLabel: String {
        var parts = [task.title]
        if task.isProtected { parts.append("obligatory prayer") }
        if let time = planned.time {
            parts.append(time.description)
        } else {
            parts.append(planned.unresolvedReason ?? "not scheduled")
        }
        if isComplete { parts.append("completed") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Checklist

/// Inline checklist steps, e.g. the skincare products.
struct StepToggleRow: View {
    let name: String
    let isComplete: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            isComplete ? Haptics.uncompleted() : Haptics.completed()
            withAnimation(.routineSpring) { toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isComplete ? RT.done : RT.tertiaryLabel)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(isComplete ? RT.secondaryLabel : RT.label)
                    .strikethrough(isComplete, color: RT.tertiaryLabel)
                Spacer(minLength: 0)
            }
            .frame(minHeight: RT.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isComplete ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Progress

struct CompletionBar: View {
    let completion: DayCompletion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(completion.percent)% complete")
                    .font(.caption)
                    .foregroundStyle(RT.secondaryLabel)
                Spacer()
                Text("\(completion.completedCount)/\(completion.plannedCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(RT.tertiaryLabel)
            }
            ProgressView(value: completion.fraction)
                .tint(completion.state == .complete ? RT.done : RT.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completion.percent) percent complete")
    }
}
