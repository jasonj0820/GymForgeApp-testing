import Foundation

/// MK11.3: "Give me a break" and per-session exercise variations.
extension PhoneAppStore {
    var activeBreak: GymBreak? { extras.breaks.last { $0.isActive() } }

    /// First week back after a break: offer a light comeback session.
    var comebackSuggested: Bool { GymBreakRules.comeback(breaks: extras.breaks, logs: workoutLogs) }

    func breakRefusal(reason: GymBreak.Reason, count: Int, detail: String, lastDue: Date) -> String? {
        GymBreakRules.refusal(reason: reason, count: count, detail: detail, lastDue: lastDue, history: extras.breaks)
    }

    func startBreak(reason: GymBreak.Reason, count: Int, detail: String, mode: GymBreak.Mode, lastDue: Date) {
        guard breakRefusal(reason: reason, count: count, detail: detail, lastDue: lastDue) == nil else { return }
        extras.breaks.append(GymBreakRules.make(reason: reason, count: count, detail: detail, mode: mode, lastDue: lastDue))
        saveExtras()
        rescheduleReminders()
    }

    func endBreakEarly() {
        guard let index = extras.breaks.lastIndex(where: { $0.isActive() }) else { return }
        extras.breaks[index].endedEarly = .now
        saveExtras()
        rescheduleReminders()
    }

    /// Today's variation for an exercise in the workout in progress.
    func setVariation(_ text: String?, for item: RoutineExercise) {
        guard var state = activeWorkout else { return }
        state.setVariation(text, for: item.exercise.id)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// The variation noted the last time you did this exercise (any variation).
    func lastVariation(for exercise: ExerciseDefinition, before date: Date) -> String? {
        workoutLogs.filter { $0.startedAt < date }.sorted { $0.startedAt > $1.startedAt }
            .lazy.compactMap { $0.exercises.first { $0.matches(exercise) } }.first?.variation
    }
}
