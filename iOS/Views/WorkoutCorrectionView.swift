import SwiftUI

/// Edit a finished workout (sets, weights, reps, exercises, date and time), or log a missed one by hand.
/// Saving re-checks every PR in your history. Manual sessions aren't sent to Apple Health.
struct WorkoutCorrectionView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var log: WorkoutLog
    @State private var minutes: Int
    @State private var confirmDelete = false
    let isNew: Bool
    /// Called after a save (closes the missed-session sheet).
    var onSaved: (() -> Void)?

    /// Edit an existing workout.
    init(editing log: WorkoutLog) {
        _log = State(initialValue: log)
        _minutes = State(initialValue: max(Int((log.duration / 60).rounded()), 1))
        isNew = false
    }

    /// Log a missed session of `routine`, pre-filled from last time.
    init(missed routine: WorkoutRoutine, logs: [WorkoutLog], on date: Date, onSaved: (() -> Void)? = nil) {
        // 6pm that day — or an hour ago if that's still in the future.
        let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        let start = min(evening, Date.now.addingTimeInterval(-3600))
        let exercises: [ExerciseLog] = routine.exercises.map { item in
            let exercise = item.exercise
            let previous = logs.previousLog(for: exercise, before: start)
            var sets: [WorkoutSetLog]
            if let previous, !previous.sets.isEmpty {
                sets = previous.sets.map { old in
                    WorkoutSetLog(setNumber: old.setNumber, weightKg: old.weightKg, reps: old.reps, completedAt: start,
                                  durationSeconds: old.durationSeconds, distanceKm: old.distanceKm)
                }
            } else if exercise.isCardio {
                sets = [WorkoutSetLog(setNumber: 1, weightKg: 0, reps: 0, completedAt: start,
                                      durationSeconds: Double(exercise.cardioMinutes * 60))]
            } else {
                sets = (0..<max(exercise.defaultSets, 1)).map {
                    WorkoutSetLog(setNumber: $0 + 1, weightKg: 0, reps: exercise.repMin, completedAt: start)
                }
            }
            var entry = ExerciseLog(exerciseID: exercise.id, exerciseName: exercise.loggedName,
                                    repMinAtTime: exercise.repMin, repMaxAtTime: exercise.repMax,
                                    weightIncrementKgAtTime: exercise.weightIncrementKg, sets: sets,
                                    category: exercise.category)
            entry.load = exercise.load
            return entry
        }
        var new = WorkoutLog(routineID: routine.id, routineName: routine.name, startedAt: start,
                             endedAt: start.addingTimeInterval(60 * 60), exercises: exercises)
        new.isManual = true
        _log = State(initialValue: new)
        _minutes = State(initialValue: 60)
        isNew = true
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Started", selection: $log.startedAt, in: ...Date.now)
                Stepper("Duration: \(minutes) min", value: $minutes, in: 5...240, step: 5)
            } header: {
                Text(log.routineName)
            } footer: {
                Text(isNew
                     ? "Logged by hand: it counts for your week, streaks and progression, but has no heart rate and isn't added to Apple Health."
                     : "Fix anything that was logged wrong. PRs across your history are re-checked when you save.")
            }

            ForEach($log.exercises) { $exercise in
                Section {
                    ForEach($exercise.sets) { $set in
                        CorrectionSetRow(set: $set, isCardio: exercise.isCardio,
                                         unit: exercise.load?.unit ?? "kg")
                    }
                    .onDelete { offsets in exercise.sets.remove(atOffsets: offsets) }
                    Button {
                        let last = exercise.sets.last
                        exercise.sets.append(WorkoutSetLog(
                            setNumber: exercise.sets.count + 1, weightKg: last?.weightKg ?? 0,
                            reps: last?.reps ?? exercise.repMinAtTime,
                            completedAt: log.startedAt.addingTimeInterval(Double(exercise.sets.count) * 120),
                            durationSeconds: last?.durationSeconds, distanceKm: last?.distanceKm))
                    } label: {
                        Label("Add set", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text(exercise.exerciseName)
                        Spacer()
                        Button(role: .destructive) {
                            let id = exercise.id
                            log.exercises.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section {
                Menu {
                    ForEach(Array(store.correctionExercises.enumerated()), id: \.offset) { _, definition in
                        Button(definition.loggedName) { addExercise(definition) }
                    }
                } label: {
                    Label("Add exercise", systemImage: "plus.circle")
                }
            }

            if !isNew {
                Section {
                    Button("Delete this workout", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "Log missed session" : "Edit workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!hasAnySet)
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                store.deleteWorkout(log)
                dismiss()
            }
        }
    }

    private var hasAnySet: Bool {
        log.exercises.contains { exercise in exercise.sets.contains { $0.reps > 0 || ($0.durationSeconds ?? 0) > 0 } }
    }

    private func addExercise(_ definition: ExerciseDefinition) {
        var entry = ExerciseLog(exerciseID: definition.id, exerciseName: definition.loggedName,
                                repMinAtTime: definition.repMin, repMaxAtTime: definition.repMax,
                                weightIncrementKgAtTime: definition.weightIncrementKg,
                                sets: [WorkoutSetLog(setNumber: 1, weightKg: 0,
                                                     reps: definition.isCardio ? 0 : definition.repMin,
                                                     completedAt: log.startedAt,
                                                     durationSeconds: definition.isCardio ? Double(definition.cardioMinutes * 60) : nil)],
                                category: definition.category)
        entry.load = definition.load
        log.exercises.append(entry)
    }

    private func save() {
        var final = log
        final.endedAt = final.startedAt.addingTimeInterval(Double(minutes) * 60)
        for e in final.exercises.indices {
            // Empty sets are dropped; the rest renumbered and timed inside the session.
            final.exercises[e].sets.removeAll { $0.reps <= 0 && ($0.durationSeconds ?? 0) <= 0 }
            for s in final.exercises[e].sets.indices {
                final.exercises[e].sets[s].setNumber = s + 1
                if final.exercises[e].sets[s].completedAt < final.startedAt || final.exercises[e].sets[s].completedAt > final.endedAt {
                    final.exercises[e].sets[s].completedAt = final.startedAt
                }
            }
        }
        final.exercises.removeAll { $0.sets.isEmpty }
        store.saveCorrectedWorkout(final)
        if let onSaved { onSaved() } else { dismiss() }
    }
}

/// One set: weight + reps (or minutes + km for cardio), typed as text so decimals and empty fields work.
private struct CorrectionSetRow: View {
    @Binding var set: WorkoutSetLog
    let isCardio: Bool
    let unit: String
    @State private var first = ""
    @State private var second = ""
    @State private var loaded = false

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Set \(set.setNumber)")
            Spacer()
            TextField("0", text: $first)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text(isCardio ? "min" : unit).foregroundStyle(.secondary).font(.caption)
            TextField(isCardio ? "km" : "0", text: $second)
                .keyboardType(isCardio ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Text(isCardio ? "km" : "reps").foregroundStyle(.secondary).font(.caption)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if isCardio {
                first = set.durationSeconds.map { GFFormat.km($0 / 60) } ?? ""
                second = set.distanceKm.map { GFFormat.km($0) } ?? ""
            } else {
                first = GFFormat.kg(set.weightKg)
                second = "\(set.reps)"
            }
        }
        .onChange(of: first) { _, text in
            if isCardio {
                set.durationSeconds = number(text).map { $0 * 60 }
            } else {
                set.weightKg = max(0, number(text) ?? 0)
            }
        }
        .onChange(of: second) { _, text in
            if isCardio {
                let km = number(text)
                set.distanceKm = (km ?? 0) > 0 ? km : nil
            } else {
                set.reps = max(0, Int(text.trimmingCharacters(in: .whitespaces)) ?? 0)
            }
        }
    }
}
