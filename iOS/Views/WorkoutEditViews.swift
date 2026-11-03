import SwiftUI

/// Identifies a logged set to edit (sheet item).
struct SetEditTarget: Identifiable, Hashable {
    let id: UUID
    let exerciseID: UUID
}

/// Identifies an exercise in today's workout (sheet item).
struct ExerciseSlotTarget: Identifiable, Hashable {
    /// Routine item id (stays the same through swaps).
    let id: UUID
}

/// Change the weight / reps (or time / distance) of a set you already logged, or delete it.
struct EditSetView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let target: SetEditTarget

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var minutesText = ""
    @State private var kmText = ""
    @State private var effort: Int?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var originalMinutesText = ""

    private var exercise: ExerciseDefinition? { store.activeWorkout?.exerciseDefinition(id: target.exerciseID) }
    private var set: WorkoutSetLog? { store.activeWorkout?.completedSets[target.exerciseID]?.first { $0.id == target.id } }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private var canSave: Bool {
        guard let exercise else { return false }
        if exercise.isCardio { return (number(minutesText) ?? 0) > 0 }
        return number(weightText) != nil && Int(repsText.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        Form {
            if let exercise, let set {
                Section {
                    if exercise.isCardio {
                        field("Time", text: $minutesText, unit: "min", keyboard: .decimalPad)
                        field("Distance", text: $kmText, unit: "km", keyboard: .decimalPad)
                    } else {
                        field(exercise.isAssisted ? "Assistance" : "Weight", text: $weightText, unit: "kg", keyboard: .decimalPad)
                        field("Reps", text: $repsText, unit: "reps", keyboard: .numberPad)
                        Picker("Reps left", selection: $effort) {
                            Text("Not rated").tag(Int?.none)
                            Text("Failure").tag(Int?.some(0))
                            Text("1").tag(Int?.some(1))
                            Text("2").tag(Int?.some(2))
                            Text("3").tag(Int?.some(3))
                            Text("4+").tag(Int?.some(4))
                        }
                    }
                } header: {
                    Text("\(exercise.name) · " + (exercise.isCardio ? "Cardio" : "Set \(set.setNumber)"))
                } footer: {
                    Text("Logged \(set.completedAt.formatted(date: .omitted, time: .shortened)) as \(set.summaryText). PRs are re-checked when you save.")
                }

                Section {
                    Button("Delete this set", role: .destructive) { confirmDelete = true }
                }
            } else {
                ContentUnavailableView("Set not found", systemImage: "questionmark.circle",
                                       description: Text("It may have been deleted on your Watch."))
            }
        }
        .navigationTitle("Edit set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("Delete this set?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete set", role: .destructive) {
                let id = target.id
                dismiss()
                DispatchQueue.main.async { store.deleteSet(id: id) }
            }
        } message: {
            Text("The sets after it are renumbered.")
        }
        .onAppear(perform: load)
    }

    private func field(_ title: String, text: Binding<String>, unit: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard !loaded, let set else { return }
        loaded = true
        weightText = GFFormat.kg(set.weightKg)
        repsText = "\(set.reps)"
        minutesText = set.durationSeconds.map { GFFormat.km($0 / 60) } ?? ""
        originalMinutesText = minutesText
        kmText = set.distanceKm.map { GFFormat.km($0) } ?? ""
        effort = set.rir
    }

    private func save() {
        guard let exercise else { return }
        if exercise.isCardio {
            guard let minutes = number(minutesText), minutes > 0 else { return }
            let km = number(kmText)
            // Keep the exact seconds unless the time was actually changed.
            let seconds = minutesText == originalMinutesText ? (set?.durationSeconds ?? minutes * 60) : minutes * 60
            store.editSet(id: target.id, weightKg: 0, reps: 0, durationSeconds: seconds,
                          distanceKm: (km ?? 0) > 0 ? km : nil, rir: nil)
        } else {
            guard let weight = number(weightText), let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) else { return }
            store.editSet(id: target.id, weightKg: max(0, weight), reps: max(0, reps), rir: effort)
        }
        dismiss()
    }
}

/// One exercise in today's workout: its logged sets (tap to fix), planned sets (+ / −), and shortcuts.
struct ExerciseSetsSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let target: ExerciseSlotTarget

    var body: some View {
        NavigationStack {
            Group {
                if let state = store.activeWorkout,
                   let index = state.routine.exercises.firstIndex(where: { $0.id == target.id }) {
                    content(state: state, index: index)
                } else {
                    ContentUnavailableView("Workout ended", systemImage: "flag.checkered")
                }
            }
            .navigationTitle("Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: SetEditTarget.self) { target in
                EditSetView(target: target)
            }
        }
    }

    @ViewBuilder
    private func content(state: ActiveWorkoutState, index: Int) -> some View {
        let item = state.routine.exercises[index]
        let exercise = item.exercise
        let done = state.sets(for: item)
        // Sets logged on an exercise that was swapped out of this slot today.
        let retired = (state.retiredExercises ?? []).filter { old in
            state.plannedExercise(for: item).withAlternatives.contains { $0.id == old.id }
                && !(state.completedSets[old.id] ?? []).isEmpty
        }

        List {
            Section {
                if done.isEmpty {
                    Text("No sets logged yet.").foregroundStyle(.secondary)
                }
                ForEach(done) { set in
                    setRow(set, exerciseID: exercise.id, isCardio: exercise.isCardio)
                }
            } header: {
                Text(exercise.name)
            } footer: {
                if !done.isEmpty { Text("Tap a set to change it. Swipe left to delete.") }
            }

            ForEach(retired) { old in
                Section("\(old.name) (swapped out)") {
                    ForEach(state.completedSets[old.id] ?? []) { set in
                        setRow(set, exerciseID: old.id, isCardio: old.isCardio)
                    }
                }
            }

            if !exercise.isCardio {
                Section {
                    Stepper(value: Binding(get: { exercise.defaultSets },
                                           set: { store.setPlannedSets($0, at: index) }),
                            in: max(1, done.count)...max(20, done.count)) {
                        LabeledContent("Planned today", value: "\(exercise.defaultSets) set\(exercise.defaultSets == 1 ? "" : "s")")
                    }
                } footer: {
                    Text("For today only. To change it for good, edit the routine.")
                }
            }

            Section {
                if index != state.exerciseIndex || state.isComplete {
                    Button {
                        if state.isFinished(item) && !state.isSkipped(item) {
                            store.addExtraSet(toExercise: index)
                        } else {
                            store.jumpToExercise(index)
                        }
                        dismiss()
                    } label: {
                        Label(state.isFinished(item) && !state.isSkipped(item) ? "Do one more set now" : "Do this exercise now",
                              systemImage: "arrow.right.circle")
                    }
                }
            }
        }
    }

    private func setRow(_ set: WorkoutSetLog, exerciseID: UUID, isCardio: Bool) -> some View {
        NavigationLink(value: SetEditTarget(id: set.id, exerciseID: exerciseID)) {
            HStack {
                Text(isCardio ? "Logged" : "Set \(set.setNumber)")
                if set.isPR == true {
                    Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                }
                Spacer()
                Text(set.summaryText).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                store.deleteSet(id: set.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
