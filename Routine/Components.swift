import SwiftUI

/// A wheel/compact time picker bound to a `TimeOfDay`.
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

/// Same, for a value that may not have been entered yet.
struct OptionalTimeOfDayPicker: View {
    let title: String
    let placeholder: TimeOfDay
    @Binding var value: TimeOfDay?

    var body: some View {
        HStack {
            TimeOfDayPicker(title: title,
                            value: Binding(get: { value ?? placeholder },
                                           set: { value = $0 }))
            if value == nil {
                Text("not set")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// The yellow "something needs your attention" strip used on Today.
struct BannerView: View {
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
    }
}

struct ConflictList: View {
    let conflicts: [ScheduleConflict]

    var body: some View {
        if conflicts.isEmpty {
            Label("No sequence conflicts", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundColor(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(conflicts) { conflict in
                    Label(conflict.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

/// One line in a day's schedule.
struct PlannedRow: View {
    let planned: PlannedTask
    let isComplete: Bool
    let toggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let toggle = toggle {
                Button(action: toggle) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isComplete ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(planned.task.title)
                    .strikethrough(isComplete)
                if let note = planned.task.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.secondary)
                }
                if planned.task.isProtected {
                    Text("Obligatory prayer").font(.caption2).foregroundColor(.secondary)
                }
            }

            Spacer()

            if let time = planned.time {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(time.description).monospacedDigit()
                    if planned.task.timing.isAnchored {
                        Text(planned.task.timing.describedShort)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            } else {
                Text(planned.unresolvedReason ?? "Not scheduled")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

struct CompletionBar: View {
    let completion: DayCompletion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(completion.percent)% complete").font(.caption)
                Spacer()
                Text("\(completion.completedCount)/\(completion.plannedCount)")
                    .font(.caption).foregroundColor(.secondary)
            }
            ProgressView(value: completion.fraction)
                .tint(completion.state == .complete ? .green : .accentColor)
        }
    }
}

extension DayState {
    var color: Color {
        switch self {
        case .complete: return .green
        case .partial: return .yellow
        case .missed: return .red
        case .noData: return .secondary.opacity(0.35)
        }
    }
}
