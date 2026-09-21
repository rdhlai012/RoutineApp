import SwiftUI

/// The routine itself: every task, editable, reorderable, with its checklist.
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
                    Text("The five prayers are protected: they cannot be deleted or silenced. "
                         + "Only their offset and note can change.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                ForEach(app.tasks) { task in
                    Button { editing = task } label: { row(task) }
                        .buttonStyle(.plain)
                }
                .onMove { app.moveTasks(from: $0, to: $1) }
                .onDelete(perform: requestDelete)

                Section {
                    Button("Add task") { adding = true }
                    Button("Reset to defaults", role: .destructive) { confirmingReset = true }
                }
            }
            .navigationTitle("Routine")
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
                Alert(title: Text("Not allowed"), message: Text(item.message),
                      dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Delete this task?",
                                isPresented: Binding(get: { confirmingDelete != nil },
                                                     set: { if !$0 { confirmingDelete = nil } })) {
                Button("Delete anyway", role: .destructive) {
                    if let task = confirmingDelete { app.delete(task.id, confirmed: true) }
                    confirmingDelete = nil
                }
                Button("Keep it", role: .cancel) { confirmingDelete = nil }
            } message: {
                Text(confirmingDelete.map { TaskRules.canDelete($0).message ?? "" } ?? "")
            }
            .confirmationDialog("Reset the whole routine?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive) { app.resetToDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your tasks go back to the shipped defaults. All five prayers are recreated. "
                     + "Your history, prayer times and sleep logs are kept.")
            }
        }
    }

    private func row(_ task: RoutineTask) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.title)
                    if task.isProtected {
                        Image(systemName: "lock.fill").font(.caption2).foregroundColor(.secondary)
                    }
                    if !task.enabled {
                        Text("off").font(.caption2).foregroundColor(.secondary)
                    }
                }
                Text(task.timing.describedShort).font(.caption).foregroundColor(.secondary)
                if task.onlyWhenGoingOut {
                    Text("Only when going out").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if task.insistent {
                Image(systemName: "alarm.fill").foregroundColor(.orange)
            } else if !task.alarm {
                Image(systemName: "bell.slash").foregroundColor(.secondary)
            }
        }
    }

    private func requestDelete(_ offsets: IndexSet) {
        for index in offsets {
            let task = app.tasks[index]
            switch TaskRules.canDelete(task) {
            case .refused(let message):
                alert = GuardAlert(message: message)
            case .needsConfirmation:
                confirmingDelete = task
            case .allowed:
                app.delete(task.id)
            }
        }
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

                Section("Timing") {
                    if task.isProtected {
                        Text("\(task.protectedPrayer?.displayName ?? "This prayer") is anchored to "
                             + "the adhan. Only the offset can change.")
                            .font(.footnote).foregroundColor(.secondary)
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

                Section("Reminder") {
                    Toggle("Enabled", isOn: $task.enabled)
                        .disabled(task.isProtected)
                    Toggle("Alarm sound", isOn: $task.alarm)
                        .disabled(task.isProtected)
                    Toggle("Insistent (5 bursts, alarm.wav)", isOn: $task.insistent)
                    Toggle("Only when going out", isOn: $task.onlyWhenGoingOut)
                        .disabled(task.isProtected)
                    if task.insistent {
                        Text("Uses the bundled 28-second alarm sound. It still cannot bypass "
                             + "Silent mode or a Focus - keep a Clock alarm as a backup.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

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
                            task.steps.append(ChecklistStep(name: trimmed))
                            newStepName = ""
                        }
                    }
                }
            }
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
                Alert(title: Text("Not allowed"), message: Text(item.message),
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
            Text(offsetLabel)
        }
    }

    private var offsetLabel: String {
        let offset = task.timing.offset
        if offset == 0 { return "At the adhan" }
        return offset < 0 ? "\(-offset) min before" : "\(offset) min after"
    }

    private func save(confirmed: Bool) {
        if isNew {
            app.add(task)
            dismiss()
            return
        }
        switch app.update(task, confirmed: confirmed) {
        case .allowed:
            dismiss()
        case .refused(let message):
            alert = GuardAlert(message: message)
        case .needsConfirmation(let message):
            pendingConfirmation = message
        }
    }
}
