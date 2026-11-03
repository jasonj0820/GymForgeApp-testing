import SwiftUI

/// MK10.1: pick an exercise — the coach's suggestions first, then the whole library (searchable,
/// by body part), or type your own.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let suggestions: [String]
    /// Mid-workout "add": also put it in the routine for next time?
    var showRoutineToggle = false
    let onPick: (_ name: String, _ alsoToRoutine: Bool) -> Void

    @State private var search = ""
    @State private var alsoToRoutine = true

    private var matches: [ExerciseProfile] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return ExerciseLibrary.all }
        return ExerciseLibrary.all.filter { profile in
            profile.name.lowercased().contains(query) || profile.keywords.contains { $0.contains(query) }
                || profile.muscles.keys.contains { $0.title.lowercased().contains(query) }
        }
    }

    private var categories: [ExerciseCategory] {
        ExerciseCategory.allCases.filter { category in matches.contains { $0.category == category } }
    }

    var body: some View {
        List {
            if showRoutineToggle {
                Section {
                    Toggle("Also add to the routine", isOn: $alsoToRoutine)
                } footer: {
                    Text(alsoToRoutine ? "It'll be in this routine next time too." : "Just for today.")
                }
            }
            let typed = search.trimmingCharacters(in: .whitespaces)
            if !typed.isEmpty, !ExerciseLibrary.all.contains(where: { $0.name.lowercased() == typed.lowercased() }) {
                Section {
                    Button {
                        pick(typed)
                    } label: {
                        Label("Use \"\(typed)\"", systemImage: "plus.circle")
                    }
                } footer: {
                    if let guess = ExerciseLibrary.profile(for: typed) {
                        Text("Coach settings from \(guess.name): \(guess.repMin)–\(guess.repMax) reps, \(guess.restSeconds / 60):\(String(format: "%02d", guess.restSeconds % 60)) rest.")
                    }
                }
            }
            if typed.isEmpty, !suggestions.isEmpty {
                Section("Coach suggests") {
                    ForEach(suggestions, id: \.self) { name in
                        row(ExerciseLibrary.profile(named: name), name: name)
                    }
                }
            }
            ForEach(categories) { category in
                Section(category.title) {
                    ForEach(matches.filter { $0.category == category }, id: \.name) { profile in
                        row(profile, name: profile.name)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search exercises or muscles")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func row(_ profile: ExerciseProfile?, name: String) -> some View {
        Button {
            pick(name)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                if let profile {
                    Text(profile.primaryMuscles.map(\.title).joined(separator: ", ")
                         + " · \(profile.repMin)–\(profile.repMax) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func pick(_ name: String) {
        onPick(name, alsoToRoutine)
        dismiss()
    }
}

extension ExerciseLibrary {
    /// Good swaps for an exercise (from the library), not already in the routine.
    static func swapSuggestions(for exercise: ExerciseDefinition, in routine: WorkoutRoutine?) -> [String] {
        let used = Set((routine?.exercises ?? []).map { ExerciseLog.key(for: $0.exercise.name) })
        var names = profile(for: exercise.name)?.substitutes ?? []
        // Same main muscle, same kind of movement.
        if let info = profile(for: exercise.name), let muscle = info.primaryMuscles.first {
            names += all.filter { $0.kind == info.kind && $0.primaryMuscles.first == muscle && $0.name != info.name }.map(\.name)
        }
        var seen = Set<String>()
        return names.filter { !used.contains(ExerciseLog.key(for: $0)) && seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    /// What a routine is missing: muscles in its body parts with no direct work, then similar exercises.
    static func addSuggestions(for routine: WorkoutRoutine?) -> [String] {
        guard let routine else { return [] }
        let used = Set(routine.exercises.map { ExerciseLog.key(for: $0.exercise.name) })
        var trained = Set<Muscle>()
        var areas = Set<ExerciseCategory>()
        for item in routine.exercises where !item.exercise.isCardio {
            let muscles = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)
            for (muscle, share) in muscles {
                areas.insert(muscle.category)
                if share >= 1 { trained.insert(muscle) }
            }
        }
        var names: [String] = []
        for muscle in Muscle.allCases where areas.contains(muscle.category) && !trained.contains(muscle) {
            if let pick = CoachBrain.suggestedExercise(for: muscle) { names.append(pick.name) }
        }
        for item in routine.exercises {
            names += profile(for: item.exercise.name)?.substitutes ?? []
        }
        var seen = Set<String>()
        return names.filter { !used.contains(ExerciseLog.key(for: $0)) && seen.insert($0).inserted }.prefix(6).map { $0 }
    }
}
