import SwiftUI

struct RoutineEditorView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State var routine: WorkoutRoutine
    @State private var showingAddExercise = false

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $routine.name)
            }

            Section {
                ForEach(routine.exercises) { item in
                    NavigationLink {
                        ExerciseEditorView(exercise: item.exercise) { updated in
                            if let index = routine.exercises.firstIndex(where: { $0.id == item.id }) {
                                routine.exercises[index].exercise = updated
                                saveIfExisting()
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(item.exercise.name)
                                if !item.exercise.alternativeList.isEmpty {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                                }
                                if item.exercise.notes != nil {
                                    Image(systemName: "note.text").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(summary(item.exercise))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.isSupersetWithNext {
                                Label("Superset with next", systemImage: "link")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    routine.exercises.remove(atOffsets: offsets)
                    renumber()
                }
                .onMove { source, destination in
                    routine.exercises.move(fromOffsets: source, toOffset: destination)
                    renumber()
                }

                Button("Add exercise", systemImage: "plus") { showingAddExercise = true }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Edit to reorder. Changing a rep range only affects future workouts — history keeps what you did.")
            }

            if routine.exercises.count > 1 {
                Section {
                    ForEach(0..<(routine.exercises.count - 1), id: \.self) { index in
                        Toggle(isOn: $routine.exercises[index].isSupersetWithNext) {
                            Text("\(routine.exercises[index].exercise.name) + \(routine.exercises[index + 1].exercise.name)")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Supersets")
                } footer: {
                    Text("Linked exercises alternate set by set, and rest only starts after the last one in the group.")
                }
            }
        }
        .navigationTitle(routine.name.isEmpty ? "Routine" : routine.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateRoutine(routine)
                    dismiss()
                }
                .disabled(routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            NavigationStack {
                ExerciseEditorView(exercise: ExerciseDefinition(name: "", category: .other)) { exercise in
                    routine.exercises.append(RoutineExercise(exercise: exercise, order: routine.exercises.count))
                    saveIfExisting()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddExercise = false }
                    }
                }
            }
        }
    }

    private func summary(_ exercise: ExerciseDefinition) -> String {
        if exercise.isCardio {
            return "Cardio • \(exercise.cardioMinutes) min"
        }
        return "\(exercise.defaultSets) sets • \(exercise.repMin)–\(exercise.repMax) reps • \(GFFormat.duration(TimeInterval(exercise.restSeconds))) rest • +\(GFFormat.kg(exercise.weightIncrementKg)) kg"
    }

    /// Saving an exercise saves the routine straight away (so leaving with "<" doesn't lose it).
    private func saveIfExisting() {
        guard store.routines.contains(where: { $0.id == routine.id }),
              !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.updateRoutine(routine)
    }

    private func renumber() {
        for index in routine.exercises.indices {
            routine.exercises[index].order = index
        }
    }
}
