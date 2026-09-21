import SwiftUI

/// The routine itself: every task, reorderable, with its checklist.
/// The five obligatory prayers are pinned: they cannot be dragged, deleted or
/// switched off, which the rows show with a lock rather than only refusing.
struct ManageView: View {
    @EnvironmentObject private var app: AppData

    @State private var editing: RoutineTask?
    @State private var adding = false
    @State private var alert: GuardAlert?
    @State private var confirmingDelete: RoutineTask?
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.tasks) { task in
                        TaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = task }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !task.isProtected {
                                    Button(role: .destructive) {
                                        requestDelete(task)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                Button {
                                    editing = task
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(RT.accent)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !task.isProtected {
                                    Button {
                                        toggleEnabled(task)
                                    } label: {
                                        Label(task.enabled ? "Turn off" : "Turn on",
                                              systemImage: task.enabled ? "bell.slash" : "bell")
                                    }
                                    .tint(task.enabled ? .gray : RT.done)
                                }
                            }
                            .moveDisabled(task.isProtected)
                            .deleteDisabled(task.isProtected)
                            .listRowBackground(RT.surface)
                    }
                    .onMove { app.moveTasks(from: $0, to: $1) }
                } header: {
                    Text("Routine order")
                } footer: {
                    Text("Swipe a task to edit or turn it off. Press Edit, then drag to reorder. The five prayers are pinned and cannot be removed or silenced.")
                }

                Section {
                    Button {
                        adding = true
                    } label: {
                        Label("Add task", systemImage: "plus.circle.fill")
                    }
                    .listRowBackground(RT.surface)

                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    }
                    .listRowBackground(RT.surface)
                }

                Color.clear
                    .frame(height: RT.tabBarClearance)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RT.background.ignoresSafeArea())
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { EditButton() }
            .sheet(item: $editing) { task in
                TaskEditor(task: task).environmentObject(app)
            }
            .sheet(isPresented: $adding) {
                TaskEditor(task: RoutineTask(title: "New task",
                                             category: .other,
                                             timing: .fixed(TimeOfDay(hour: 9, minute: 0))),
                           isNew: true)
                    .environmentObject(app)
            }
            .alert(item: $alert) { item in
                Alert(title: Text("Not allowed"),
                      message: Text(item.message),
                      dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Delete this task?",
                                isPresented: Binding(get: { confirmingDelete != nil },
                                                     set: { if !$0 { confirmingDelete = nil } })) {
                Button("Delete anyway", role: .destructive) {
                    if let task = confirmingDelete {
                        Haptics.warning()
                        app.delete(task.id, confirmed: true)
                    }
                    confirmingDelete = nil
                }
                Button("Keep it", role: .cancel) { confirmingDelete = nil }
            } message: {
                Text(confirmingDelete.flatMap { TaskRules.canDelete($0).message } ?? "")
            }
            .confirmationDialog("Reset the whole routine?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive) {
                    Haptics.warning()
                    app.resetToDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tasks go back to the shipped defaults and all five prayers are recreated. Your history, prayer times and sleep logs are kept.")
            }
        }
    }

    private func toggleEnabled(_ task: RoutineTask) {
        var copy = task
        copy.enabled.toggle()
        switch app.update(copy) {
        case .allowed:
            Haptics.selection()
        case .refused(let message):
            Haptics.failure()
            alert = GuardAlert(message: message)
        case .needsConfirmation(let message):
            // Preparation tasks warn before being switched off.
            Haptics.warning()
            alert = GuardAlert(message: message + " Open the task to confirm.")
        }
    }

    private func requestDelete(_ task: RoutineTask) {
        switch TaskRules.canDelete(task) {
        case .refused(let message):
            Haptics.failure()
            alert = GuardAlert(message: message)
        case .needsConfirmation:
            confirmingDelete = task
        case .allowed:
            Haptics.warning()
            app.delete(task.id)
        }
    }
}

/// One row in the routine list.
private struct TaskRow: View {
    let task: RoutineTask

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: task.isProtected ? "moon.stars.fill" : symbol)
                .font(.system(size: 16))
                .foregroundStyle(task.isProtected ? RT.prayer : RT.secondaryLabel)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(task.enabled ? RT.label : RT.tertiaryLabel)
                    if task.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(RT.tertiaryLabel)
                    }
                }

                HStack(spacing: 8) {
                    Text(task.timing.describedShort)
                        .font(.caption)
                        .foregroundStyle(RT.secondaryLabel)
                    if task.onlyWhenGoingOut {
                        Text("Going out")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RT.accent)
                    }
                    if !task.enabled {
                        Text("Off")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RT.tertiaryLabel)
                    }
                }
            }

            Spacer(minLength: 8)

            if task.insistent {
                Image(systemName: "alarm.fill")
                    .font(.caption)
                    .foregroundStyle(RT.prayer)
            } else if !task.alarm {
                Image(systemName: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(RT.tertiaryLabel)
            }
        }
        .frame(minHeight: RT.minTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(task.isProtected ? "Locked obligatory prayer" : "Opens the task editor")
    }

    private var symbol: String {
        switch task.category {
        case .wake: return "sunrise.fill"
        case .hygiene: return "drop.fill"
        case .prayer: return "moon.stars.fill"
        case .quran: return "book.fill"
        case .skincare: return "sparkles"
        case .gym: return "figure.run"
        case .meal: return "fork.knife"
        case .sleep: return "bed.double.fill"
        case .other: return "circle"
        }
    }

    private var label: String {
        var parts = [task.title, task.timing.describedShort]
        if task.isProtected { parts.append("locked obligatory prayer") }
        if !task.enabled { parts.append("off") }
        return parts.joined(separator: ", ")
    }
}

struct GuardAlert: Identifiable {
    let id = UUID()
    let message: String
}

/// Edits one task, including its checklist steps.
struct TaskEditor: View {
    @State var task: RoutineTask
    var isNew: Bool = false

    @EnvironmentObject private var app: AppData
    @Environment(\.dismiss) private var dismiss

    @State private var alert: GuardAlert?
    @State private var pendingConfirmation: String?
    @State private var newStepName = ""

    private var isFixed: Bool { !task.timing.isAnchored }

    var body: some View {
        NavigationStack {
            List {
                Section("Task") {
                    TextField("Title", text: $task.title)
                    TextField("Note (shown in the reminder)",
                              text: Binding(get: { task.note ?? "" },
                                            set: { task.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                    Picker("Category", selection: $task.category) {
                        ForEach(TaskCategory.allCases) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                .listRowBackground(RT.surface)

                Section("Timing") {
                    if task.isProtected {
                        Label("\(task.protectedPrayer?.displayName ?? "This prayer") is anchored to the adhan. Only the offset and note can change.",
                              systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(RT.secondaryLabel)
                        offsetStepper
                    } else {
                        Picker("Kind", selection: Binding(
                            get: { isFixed ? 0 : 1 },
                            set: { newValue in
                                task.timing = newValue == 0
                                    ? .fixed(TimeOfDay(hour: 9, minute: 0))
                                    : .anchored(prayer: .fajr, offset: 0)
                            })) {
                                Text("Fixed time").tag(0)
                                Text("Prayer-anchored").tag(1)
                            }
                            .pickerStyle(.segmented)

                        if let fixed = task.timing.fixedTime {
                            TimeOfDayPicker(title: "Time",
                                            value: Binding(get: { fixed },
                                                           set: { task.timing = .fixed($0) }))
                        } else {
                            Picker("Prayer", selection: Binding(
                                get: { task.timing.anchorPrayer ?? .fajr },
                                set: { task.timing = .anchored(prayer: $0,
                                                               offset: task.timing.offset) })) {
                                ForEach(Prayer.allCases) { prayer in
                                    Text(prayer.displayName).tag(prayer)
                                }
                            }
                            offsetStepper
                        }
                    }
                }
                .listRowBackground(RT.surface)

                Section {
                    Toggle("Enabled", isOn: $task.enabled)
                        .disabled(task.isProtected)
                    Toggle("Alarm sound", isOn: $task.alarm)
                        .disabled(task.isProtected)
                    Toggle("Insistent (5 bursts)", isOn: $task.insistent)
                    Toggle("Only when going out", isOn: $task.onlyWhenGoingOut)
                        .disabled(task.isProtected)
                } header: {
                    Text("Reminder")
                } footer: {
                    if task.insistent {
                        Text("Uses the bundled 28-second alarm sound. It still cannot bypass Silent mode or a Focus - keep a Clock alarm as a backup.")
                    }
                }
                .listRowBackground(RT.surface)

                Section("Checklist") {
                    ForEach($task.steps) { $step in
                        HStack {
                            TextField("Step", text: $step.name)
                            Toggle("", isOn: $step.enabled).labelsHidden()
                        }
                    }
                    .onDelete { task.steps.remove(atOffsets: $0) }
                    .onMove { task.steps.move(fromOffsets: $0, toOffset: $1) }

                    HStack {
                        TextField("Add a step", text: $newStepName)
                        Button("Add") {
                            let trimmed = newStepName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            Haptics.selection()
                            task.steps.append(ChecklistStep(name: trimmed))
                            newStepName = ""
                        }
                        .disabled(newStepName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .listRowBackground(RT.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(RT.background.ignoresSafeArea())
            .navigationTitle(isNew ? "New task" : task.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(confirmed: false) }
                }
            }
            .alert(item: $alert) { item in
                Alert(title: Text("Not allowed"),
                      message: Text(item.message),
                      dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Are you sure?",
                                isPresented: Binding(get: { pendingConfirmation != nil },
                                                     set: { if !$0 { pendingConfirmation = nil } })) {
                Button("Yes, save it", role: .destructive) {
                    pendingConfirmation = nil
                    save(confirmed: true)
                }
                Button("Cancel", role: .cancel) { pendingConfirmation = nil }
            } message: {
                Text(pendingConfirmation ?? "")
            }
        }
    }

    private var offsetStepper: some View {
        Stepper(value: Binding(
            get: { task.timing.offset },
            set: { task.timing = .anchored(prayer: task.timing.anchorPrayer ?? .fajr, offset: $0) }),
                in: -120...120, step: 5) {
            HStack {
                Text("Offset")
                Spacer()
                Text(offsetLabel)
                    .foregroundStyle(RT.secondaryLabel)
                    .monospacedDigit()
            }
        }
    }

    private var offsetLabel: String {
        let offset = task.timing.offset
        if offset == 0 { return "At the adhan" }
        return offset < 0 ? "\(-offset) min before" : "\(offset) min after"
    }

    private func save(confirmed: Bool) {
        if isNew {
            Haptics.success()
            app.add(task)
            dismiss()
            return
        }
        switch app.update(task, confirmed: confirmed) {
        case .allowed:
            Haptics.success()
            dismiss()
        case .refused(let message):
            Haptics.failure()
            alert = GuardAlert(message: message)
        case .needsConfirmation(let message):
            pendingConfirmation = message
        }
    }
}
