import Foundation

/// MK11.1: Sergeant Cluck as your coach during a workout — what he says right now, the plans you
/// accepted that apply today, and his reasoning when you tap "Explain, Sergeant".
public struct CluckCue: Equatable {
    public enum Moment: Equatable { case intro, set, rest, done }
    public var moment: Moment
    public var headline: String
    public var reminders: [String]
    public var reasons: [String]
}

public enum CluckCoach {
    /// Accepted, unresolved coaching from the last 8 weeks that names an exercise in today's session
    /// (or a light session, if today is one).
    public static func reminders(for state: ActiveWorkoutState, suggestions: [CoachSuggestion], now: Date = .now) -> [String] {
        let keys = Set(state.routine.exercises.map(\.exercise.historyKey))
        return suggestions
            .filter { !$0.resolved && $0.acceptedAt >= now.addingTimeInterval(-56 * 86_400) }
            .filter { suggestion in
                if let key = suggestion.exerciseKey { return keys.contains(key) }
                return suggestion.kind == .deload && state.deload
            }
            .sorted { $0.acceptedAt > $1.acceptedAt }
            .prefix(2)
            .map { "You agreed: \($0.text)" }
    }

    public static func cue(state: ActiveWorkoutState, plan: SetPlan?, recommendation: ProgressionRecommendation?,
                           formCue: String?, suggestions: [CoachSuggestion], now: Date = .now) -> CluckCue {
        let reminders = reminders(for: state, suggestions: suggestions, now: now)
        var reasons: [String] = []
        let effort = state.targetRIR.map { EffortTarget.text($0) }
        if let label = state.blockLabel, let effort {
            reasons.append("\(label): working sets \(effort). Effort climbs through a block, then a deload resets fatigue.")
        } else if let effort {
            reasons.append("Working sets \(effort) — close enough to failure to grow, far enough to recover.")
        }
        if let tag = SessionTag.explaining(Set(state.sessionTags ?? [])) {
            reasons.append("Today is tagged \"\(tag.title.lowercased())\" — a lower number won't be read as lost strength.")
        }
        reasons += reminders.map { $0.replacingOccurrences(of: "You agreed: ", with: "Accepted plan: ") }

        guard let item = state.currentItem, !state.isComplete else {
            return CluckCue(moment: .done, headline: "All planned sets done. Finish it and log it, recruit.",
                            reminders: [], reasons: reasons)
        }
        let exercise = item.exercise
        let done = state.sets(for: item).count
        let target = plan?.target(at: done)
        if let recommendation, !exercise.isCardio {
            reasons.insert("\(exercise.name): \(recommendation.title). \(recommendation.message)", at: 0)
        }
        if let plan, !plan.reason.isEmpty { reasons.insert(plan.reason, at: min(1, reasons.count)) }
        if let adjustment = plan?.adjustment { reasons.insert(adjustment, at: 0) }

        // First thing: what today is.
        if state.totalCompletedSets == 0 && !state.isResting {
            let lifts = state.routine.exercises.filter { !$0.exercise.isCardio }
            var text = "\(state.routine.name): \(lifts.count) exercise\(lifts.count == 1 ? "" : "s"), \(state.totalPlannedSets) sets, ~\(TimeBudget.estimateMinutes(state)) min."
            if state.deload { text += " Light day — leave plenty in the tank." }
            else if let effort { text += " Working sets \(effort)." }
            text += " First up: \(exercise.name)."
            return CluckCue(moment: .intro, headline: text, reminders: reminders, reasons: reasons)
        }

        let next = targetText(exercise, target)
        if state.isResting {
            let rest = "\(exercise.restSeconds / 60):\(String(format: "%02d", exercise.restSeconds % 60))"
            let failed = state.lastLoggedSet?.rir == 0
            var text = "Rest \(rest). Next: \(exercise.name) set \(done + 1)\(next.isEmpty ? "" : " — \(next)")."
            if failed { text += " That last one was to failure — breathe, take the full rest." }
            return CluckCue(moment: .rest, headline: text, reminders: [], reasons: reasons)
        }

        var text = "Set \(done + 1) of \(exercise.defaultSets)\(next.isEmpty ? "" : ": \(next)")."
        if let formCue, !formCue.isEmpty { text += " \(formCue)" }
        return CluckCue(moment: .set, headline: text, reminders: done == 0 ? reminders : [], reasons: reasons)
    }

    /// "80 kg × 8, ~2 reps left"
    static func targetText(_ exercise: ExerciseDefinition, _ target: SetTarget?) -> String {
        guard let target, !exercise.isCardio else { return exercise.isCardio ? "\(exercise.cardioMinutes) min" : "" }
        var text = target.weightKg > 0 ? "\(GFFormat.kg(target.weightKg)) kg × \(target.reps)" : "\(target.reps) reps"
        if let rir = target.rir { text += ", \(EffortTarget.text(rir))" }
        return text
    }
}
