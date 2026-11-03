import Foundation

public enum ProgressionAction: Equatable {
    case noHistory
    case increaseWeight(suggestedKg: Double)
    case keepWeight(targetTotalReps: Int)
    case reduceWeight(suggestedKg: Double)
    case cardio
}

public struct ProgressionRecommendation: Equatable {
    public var action: ProgressionAction
    public var title: String
    public var message: String

    public init(action: ProgressionAction, title: String, message: String) {
        self.action = action
        self.title = title
        self.message = message
    }
}

public struct SessionComparison: Equatable {
    public enum Kind: Equatable { case firstTime, improved, matched, declined }
    public var kind: Kind
    public var summary: String

    public init(kind: Kind, summary: String) {
        self.kind = kind
        self.summary = summary
    }
}

public enum ProgressionEngine {
    /// Double progression:
    /// - No history: start at the bottom of the exercise's rep range.
    /// - Every planned working set at the top weight reached repMax: add the exercise's increment.
    /// - Otherwise keep the weight and beat last session's total reps (progress doesn't need to be perfect).
    /// - Every set below repMin: suggest backing off one increment.
    public static func recommendation(
        for exercise: ExerciseDefinition,
        previous: ExerciseLog?
    ) -> ProgressionRecommendation {
        if exercise.isCardio {
            guard let previous, previous.totalDurationSeconds > 0 else {
                return .init(action: .noHistory, title: "Cardio", message: "Aim for about \(exercise.cardioMinutes) minutes.")
            }
            var last = GFFormat.minutes(previous.totalDurationSeconds)
            if previous.totalDistanceKm > 0 { last += " / \(GFFormat.km(previous.totalDistanceKm)) km" }
            return .init(action: .cardio, title: "Beat \(last)", message: "Last time: \(last). Go a little longer, further or faster.")
        }
        guard let previous, !previous.sets.isEmpty else {
            return .init(
                action: .noHistory,
                title: "Start the range",
                message: "Aim for \(exercise.repMin)–\(exercise.repMax) reps with a weight you can control."
            )
        }

        if exercise.isAssisted {
            return assistedRecommendation(for: exercise, previous: previous)
        }

        let topWeight = previous.bestWeightKg
        let workingSets = previous.sets.filter { $0.weightKg >= topWeight - 0.001 }
        let enoughSets = workingSets.count >= max(exercise.defaultSets, 1)
        let allAtTop = enoughSets && workingSets.allSatisfy { $0.reps >= exercise.repMax }
        let allBelowFloor = previous.sets.allSatisfy { $0.reps < exercise.repMin }
        let increment = exercise.weightIncrementKg > 0 ? exercise.weightIncrementKg : 2.5

        // New program block changed the rep range (e.g. 8–12 → 5–8) and last time's reps don't fit it:
        // re-aim from estimated strength instead of creeping one plate at a time.
        let rangeChanged = previous.repMinAtTime != exercise.repMin || previous.repMaxAtTime != exercise.repMax
        let topReps = workingSets.map(\.reps).max() ?? 0
        if rangeChanged, topReps > exercise.repMax || allBelowFloor, previous.estimatedOneRepMaxKg > 0 {
            let aimReps = Double(min(exercise.repMin + 2, exercise.repMax))
            let kg = clean(((previous.estimatedOneRepMaxKg / (1 + aimReps / 30)) / increment).rounded(.down) * increment)
            if kg > 0, abs(kg - topWeight) >= increment - 0.001 {
                return .init(
                    action: kg > topWeight ? .increaseWeight(suggestedKg: kg) : .reduceWeight(suggestedKg: kg),
                    title: "New rep range",
                    message: "Your reps are now \(exercise.repMin)–\(exercise.repMax). Based on last time's \(GFFormat.kg(topWeight)) kg × \(topReps), start around \(GFFormat.kg(kg)) kg."
                )
            }
        }

        // MK17: bodyweight (a weight step of 0) has no plate to add — progress the movement instead.
        if allAtTop, exercise.isBodyweight, topWeight <= 0 {
            return .init(
                action: .keepWeight(targetTotalReps: previous.totalReps),
                title: "Top of the range",
                message: "You hit \(exercise.repMax) reps on every set with bodyweight. Hold it there and slow the lowering to 3 seconds, add a pause, or move to a harder variation."
            )
        }

        // Effort: hitting the top of the range on a set taken to failure isn't a reason to add weight yet.
        if allAtTop, let lastEffort = workingSets.last?.rir, lastEffort == 0 {
            return .init(
                action: .keepWeight(targetTotalReps: previous.totalReps),
                title: "Own \(GFFormat.kg(topWeight)) kg first",
                message: "You hit \(exercise.repMax) reps, but the last set was to failure. Repeat \(GFFormat.kg(topWeight)) kg and finish with a rep in the tank — then it goes up."
            )
        }

        if allAtTop {
            let next = clean(topWeight + increment)
            return .init(
                action: .increaseWeight(suggestedKg: next),
                title: "Ready to progress",
                message: "You hit \(exercise.repMax) reps on every working set. Try \(GFFormat.kg(next)) kg next session and build back up from \(exercise.repMin) reps."
            )
        }

        if allBelowFloor, topWeight > 0 {
            let next = max(0, clean(topWeight - increment))
            return .init(
                action: .reduceWeight(suggestedKg: next),
                title: "Weight may be too heavy",
                message: "Every set finished below \(exercise.repMin) reps. Consider \(GFFormat.kg(next)) kg and rebuild within \(exercise.repMin)–\(exercise.repMax)."
            )
        }

        // Autoregulation: every rated working set had 3+ reps left and you're well into the range — go up now.
        let rated = workingSets.compactMap(\.rir)
        if enoughSets, exercise.weightIncrementKg > 0, topWeight > 0,
           rated.count >= max(2, workingSets.count - 1), rated.allSatisfy({ $0 >= 3 }),
           workingSets.allSatisfy({ $0.reps >= (exercise.repMin + exercise.repMax) / 2 }) {
            let next = clean(topWeight + increment)
            return .init(
                action: .increaseWeight(suggestedKg: next),
                title: "Felt easy — go up",
                message: "Every set had 3+ reps left at \(GFFormat.kg(topWeight)) kg. Try \(GFFormat.kg(next)) kg next session."
            )
        }

        let target = previous.totalReps + 1
        return .init(
            action: .keepWeight(targetTotalReps: target),
            title: "Keep \(exercise.formatLoad(topWeight))",
            message: "Beat last time's \(previous.totalReps) total reps — aim for \(target)+ while staying in \(exercise.repMin)–\(exercise.repMax)."
        )
    }

    /// Assisted machines: the weight is help. Hit the top of the range on every set → take
    /// assistance AWAY; every set short of the range → add assistance.
    static func assistedRecommendation(for exercise: ExerciseDefinition, previous: ExerciseLog) -> ProgressionRecommendation {
        let assist = previous.sets.filter { $0.reps > 0 }.map(\.weightKg).min() ?? 0
        let workingSets = previous.sets.filter { $0.weightKg <= assist + 0.001 }
        let enoughSets = workingSets.count >= max(exercise.defaultSets, 1)
        let allAtTop = enoughSets && workingSets.allSatisfy { $0.reps >= exercise.repMax }
        let allBelowFloor = previous.sets.allSatisfy { $0.reps < exercise.repMin }
        let step = exercise.weightIncrementKg > 0 ? exercise.weightIncrementKg : 2.5

        if allAtTop, let lastEffort = workingSets.last?.rir, lastEffort == 0 {
            return .init(action: .keepWeight(targetTotalReps: previous.totalReps),
                         title: "Own \(GFFormat.kg(assist)) kg assist first",
                         message: "You hit \(exercise.repMax) reps, but the last set was to failure. Repeat \(GFFormat.kg(assist)) kg of assistance with a rep in the tank — then take some away.")
        }
        if allAtTop {
            if assist <= 0.001 {
                return .init(action: .keepWeight(targetTotalReps: previous.totalReps + 1),
                             title: "No assistance needed",
                             message: "You did \(exercise.repMax)+ reps with no help. Time to move to regular pull-ups (or add reps).")
            }
            let next = max(0, clean(assist - step))
            return .init(action: .increaseWeight(suggestedKg: next),
                         title: "Less assistance",
                         message: "You hit \(exercise.repMax) reps on every set. Drop to \(GFFormat.kg(next)) kg of assistance (harder) and build back up from \(exercise.repMin) reps.")
        }
        if allBelowFloor {
            let next = clean(assist + step)
            return .init(action: .reduceWeight(suggestedKg: next),
                         title: "More assistance",
                         message: "Every set finished below \(exercise.repMin) reps. Use \(GFFormat.kg(next)) kg of assistance (easier) and rebuild within \(exercise.repMin)–\(exercise.repMax).")
        }
        let target = previous.totalReps + 1
        return .init(action: .keepWeight(targetTotalReps: target),
                     title: "Keep \(GFFormat.kg(assist)) kg assist",
                     message: "Beat last time's \(previous.totalReps) total reps — aim for \(target)+ while staying in \(exercise.repMin)–\(exercise.repMax). Less assistance = harder.")
    }

    public static func suggestedPrefill(
        for exercise: ExerciseDefinition,
        previous: ExerciseLog?,
        setIndex: Int,
        todaySets: [WorkoutSetLog] = []
    ) -> (weightKg: Double, reps: Int) {
        var weight: Double = 0
        var reps = exercise.repMin

        if let previous, !previous.sets.isEmpty {
            switch recommendation(for: exercise, previous: previous).action {
            case .increaseWeight(let kg), .reduceWeight(let kg):
                weight = kg
                reps = exercise.repMin
            case .keepWeight, .noHistory, .cardio:
                let old = previous.sets[min(max(setIndex, 0), previous.sets.count - 1)]
                weight = old.weightKg
                reps = min(max(old.reps, exercise.repMin), exercise.repMax)
            }
        }

        // If you changed the weight earlier today, carry it into the next set.
        if let last = todaySets.last, last.weightKg > 0 {
            weight = last.weightKg
        }
        return (weight, reps)
    }

    /// Recognises progress even when it isn't a clean +1 rep (e.g. 10/9/8 -> 10/10/9 is progress).
    /// MK11.1: compares like with like — sets at the same load are paired one-to-one (extra sets don't count as
    /// "better", missing sets aren't a "decline"), a changed rep range or load is judged by estimated 1RM,
    /// recorded effort breaks ties, and a drop has to be meaningful (2+ reps, or 3%+ est. 1RM).
    /// `context`: the session's tags — a lower result on a short / easy / tired day is noted, not called a decline.
    public static func compare(current: ExerciseLog, previous: ExerciseLog?, context: Set<SessionTag> = []) -> SessionComparison {
        if previous == nil, let variation = current.variation {
            return .init(kind: .firstTime, summary: "First time logged with \(variation.lowercased())")
        }
        let result = rawCompare(current: current, previous: previous)
        guard result.kind == .declined, let tag = SessionTag.explaining(context) else { return result }
        return .init(kind: .matched, summary: "\(result.summary) — \(tag.excuse), not a real drop")
    }

    private static func rawCompare(current: ExerciseLog, previous: ExerciseLog?) -> SessionComparison {
        guard let previous, !previous.sets.isEmpty else {
            return .init(kind: .firstTime, summary: "First time logged")
        }
        if current.isCardio {
            let timeDelta = current.totalDurationSeconds - previous.totalDurationSeconds
            let distanceDelta = current.totalDistanceKm - previous.totalDistanceKm
            if distanceDelta > 0.01 { return .init(kind: .improved, summary: "+\(GFFormat.km(distanceDelta)) km") }
            if timeDelta > 30 { return .init(kind: .improved, summary: "+\(GFFormat.minutes(timeDelta))") }
            if distanceDelta < -0.01 || timeDelta < -30 { return .init(kind: .declined, summary: "Shorter than last time") }
            return .init(kind: .matched, summary: "Matched last session")
        }
        if current.isAssisted, let now = current.leastAssistanceKg, let before = previous.leastAssistanceKg {
            let less = before - now
            if less > 0.001 { return .init(kind: .improved, summary: "−\(GFFormat.kg(less)) kg assistance") }
            if less < -0.001 { return .init(kind: .declined, summary: "+\(GFFormat.kg(-less)) kg more assistance") }
            return pairedSets(current.sets.filter { abs($0.weightKg - now) < 0.001 },
                              previous.sets.filter { abs($0.weightKg - before) < 0.001 })
        }
        let topNow = current.bestWeightKg, topBefore = previous.bestWeightKg
        let e1Now = current.estimatedOneRepMaxKg, e1Before = previous.estimatedOneRepMaxKg
        let e1Change = e1Before > 0 ? (e1Now / e1Before - 1) * 100 : 0
        let pct = String(format: "%.0f%%", abs(e1Change))

        // A different rep range: the reps aren't comparable, strength is.
        if topBefore > 0, current.repMinAtTime != previous.repMinAtTime || current.repMaxAtTime != previous.repMaxAtTime {
            if e1Change >= 2 { return .init(kind: .improved, summary: "New rep range — est. 1RM +\(pct)") }
            if e1Change <= -4 { return .init(kind: .declined, summary: "New rep range — est. 1RM −\(pct)") }
            return .init(kind: .matched, summary: "New rep range — strength about the same")
        }
        if topNow > topBefore + 0.001 {
            if topBefore > 0, e1Change <= -3 {
                return .init(kind: .matched, summary: "+\(GFFormat.kg(topNow - topBefore)) kg but reps dropped — hold it until they come back")
            }
            return .init(kind: .improved, summary: "+\(GFFormat.kg(topNow - topBefore)) kg on top weight")
        }
        if topNow < topBefore - 0.001 {
            let less = GFFormat.kg(topBefore - topNow)
            if e1Change >= 1 { return .init(kind: .improved, summary: "−\(less) kg but more reps — est. 1RM +\(pct)") }
            if e1Change <= -3 { return .init(kind: .declined, summary: "−\(less) kg on top weight (est. 1RM −\(pct))") }
            return .init(kind: .matched, summary: "Lighter (−\(less) kg), similar strength")
        }
        // Same top weight: pair the sets done at it.
        return pairedSets(current.sets.filter { abs($0.weightKg - topNow) < 0.001 && $0.reps > 0 },
                          previous.sets.filter { abs($0.weightKg - topBefore) < 0.001 && $0.reps > 0 })
    }

    /// Set 1 vs set 1, set 2 vs set 2… at the same load. Effort (reps left) settles ties.
    private static func pairedSets(_ now: [WorkoutSetLog], _ before: [WorkoutSetLog]) -> SessionComparison {
        let pairs = Array(zip(now, before))
        guard !pairs.isEmpty else { return .init(kind: .matched, summary: "Not comparable to last time") }
        let repDelta = pairs.reduce(0) { $0 + $1.0.reps - $1.1.reps }
        let effort = pairs.compactMap { pair -> Int? in
            guard let today = pair.0.rir, let then = pair.1.rir else { return nil }
            return today - then
        }
        // + = more left in the tank today than last time on the same sets.
        let effortDelta: Double? = effort.isEmpty ? nil : Double(effort.reduce(0, +)) / Double(effort.count)
        let setNote: String
        if now.count < before.count { setNote = " (\(now.count) of \(before.count) sets)" }
        else if now.count > before.count { setNote = " (+\(now.count - before.count) extra set\(now.count - before.count == 1 ? "" : "s"))" }
        else { setNote = "" }

        if repDelta > 0 { return .init(kind: .improved, summary: "+\(repDelta) rep\(repDelta == 1 ? "" : "s") on matching sets" + setNote) }
        if repDelta == 0 {
            if let effortDelta, effortDelta >= 1 { return .init(kind: .improved, summary: "Same reps, more left in the tank" + setNote) }
            if let effortDelta, effortDelta <= -1 { return .init(kind: .matched, summary: "Same reps, but closer to failure" + setNote) }
            return .init(kind: .matched, summary: "Matched last session" + setNote)
        }
        if let effortDelta, effortDelta >= 1 {
            return .init(kind: .matched, summary: "\(repDelta) reps, but you left more in the tank" + setNote)
        }
        if repDelta >= -1 { return .init(kind: .matched, summary: "Within a rep of last time" + setNote) }
        return .init(kind: .declined, summary: "\(repDelta) reps on matching sets" + setNote)
    }

    private static func clean(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
