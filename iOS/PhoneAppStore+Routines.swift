import Foundation

/// MK10.1: change a routine straight from the routine screen or mid-workout —
/// replace an exercise for good, remove, reorder or add one.
extension PhoneAppStore {
    /// A library exercise (or your own name) as a routine exercise with sensible settings.
    func makeExercise(named rawName: String, sets: Int = 3, like base: ExerciseDefinition? = nil) -> ExerciseDefinition? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        // A library exercise: its name and settings. Your own name that the library recognises: its settings.
        if let info = ExerciseLibrary.profile(named: name) ?? ExerciseLibrary.profile(for: name) {
            return ExerciseDefinition(name: name, category: info.category, repMin: info.repMin, repMax: info.repMax,
                                      defaultSets: sets, restSeconds: info.restSeconds, weightIncrementKg: info.increment)
        }
        return ExerciseDefinition(name: name, category: base?.category ?? ExerciseCategory.guess(from: name),
                                  repMin: base?.repMin ?? 8, repMax: base?.repMax ?? 12, defaultSets: sets,
                                  restSeconds: base?.restSeconds ?? 120, weightIncrementKg: base?.weightIncrementKg ?? 2.5)
    }

    /// Replaces an exercise in this routine for good. The old one stays as a one-tap swap option
    /// and keeps its own history; the new one starts its own.
    func replaceExercise(routineID: UUID, itemID: UUID, with replacement: ExerciseDefinition) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }),
              let e = routines[r].exercises.firstIndex(where: { $0.id == itemID }) else { return }
        let old = routines[r].exercises[e].exercise
        // Promote an existing swap option (keeps its id, so its history and the Watch stay linked).
        var new = old.alternatives?.first { $0.id == replacement.id || $0.historyKey == replacement.historyKey } ?? replacement
        new.defaultSets = old.defaultSets
        var previous = old
        previous.alternatives = nil
        var options = (old.alternatives ?? []).filter { $0.id != new.id && $0.historyKey != new.historyKey }
        options.insert(previous, at: 0)
        new.alternatives = options
        routines[r].exercises[e].exercise = new
        persistAndSync()
    }

    func removeExercise(routineID: UUID, itemID: UUID) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }),
              let e = routines[r].exercises.firstIndex(where: { $0.id == itemID }) else { return }
        // Don't leave the one before it linked to nothing.
        if e > 0, routines[r].exercises[e].isSupersetWithNext != true { routines[r].exercises[e - 1].isSupersetWithNext = false }
        routines[r].exercises.remove(at: e)
        for index in routines[r].exercises.indices { routines[r].exercises[index].order = index }
        persistAndSync()
    }

    /// Up (-1) or down (+1). Moving an exercise breaks its superset link.
    func moveExercise(routineID: UUID, itemID: UUID, by offset: Int) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }),
              let e = routines[r].exercises.firstIndex(where: { $0.id == itemID }) else { return }
        let target = e + offset
        guard target >= 0, target < routines[r].exercises.count else { return }
        routines[r].exercises[e].isSupersetWithNext = false
        if e > 0 { routines[r].exercises[e - 1].isSupersetWithNext = false }
        routines[r].exercises.swapAt(e, target)
        for index in routines[r].exercises.indices { routines[r].exercises[index].order = index }
        persistAndSync()
    }

    func addExercise(_ exercise: ExerciseDefinition, toRoutine routineID: UUID) {
        guard let r = routines.firstIndex(where: { $0.id == routineID }) else { return }
        routines[r].exercises.append(RoutineExercise(exercise: exercise, order: routines[r].exercises.count))
        persistAndSync()
    }

    // MARK: Mid-workout

    /// Adds an exercise to today's workout, and to the routine too if you want it there next time.
    func addExerciseToWorkout(_ exercise: ExerciseDefinition, alsoToRoutine: Bool) {
        guard var state = activeWorkout else { return }
        let itemID = UUID()
        state.appendExercise(exercise, itemID: itemID)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
        if alsoToRoutine, let r = routines.firstIndex(where: { $0.id == state.routine.id }) {
            routines[r].exercises.append(RoutineExercise(id: itemID, exercise: exercise, order: routines[r].exercises.count))
        }
        persistAndSync()
    }

    /// Today's swap becomes the routine's exercise from now on.
    func makeSwapPermanent(at index: Int) {
        guard let state = activeWorkout, index >= 0, index < state.routine.exercises.count else { return }
        let item = state.routine.exercises[index]
        guard state.swappedFrom(item) != nil else { return }
        replaceExercise(routineID: state.routine.id, itemID: item.id, with: item.exercise)
    }

    /// Already the routine's exercise (so "Make permanent" can hide).
    func isPermanent(_ item: RoutineExercise, in state: ActiveWorkoutState) -> Bool {
        guard let routine = routines.first(where: { $0.id == state.routine.id }),
              let saved = routine.exercises.first(where: { $0.id == item.id }) else { return false }
        return saved.exercise.id == item.exercise.id || saved.exercise.historyKey == item.exercise.historyKey
    }
}
