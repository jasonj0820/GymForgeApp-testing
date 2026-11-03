import Foundation

// MK10.1: after the workout — heart rate (peak, graph, per exercise, vs your usual), a set-by-set
// comparison with last time, and a short brief from the coach on how today went.

// MARK: - Heart rate

/// One heart-rate reading during a workout (seconds from the start, beats per minute). Compact on purpose.
public struct HeartRatePoint: Codable, Hashable {
    public var t: Int
    public var bpm: Int
    public init(t: Int, bpm: Int) {
        self.t = t
        self.bpm = bpm
    }
}

public struct HeartRateSummary: Hashable {
    public struct ExercisePeak: Hashable {
        public let name: String
        public let peak: Int
    }
    public let peak: Int?
    public let average: Int?
    /// Average peak of your last few sessions of this routine.
    public let usualPeak: Int?
    /// Seconds in zones 1–5 (from the readings; empty without them).
    public let zoneSeconds: [Double]
    public let exercisePeaks: [ExercisePeak]
}

public enum HeartRateAnalysis {
    public static func summary(for log: WorkoutLog, logs: [WorkoutLog], maxHeartRate: Double) -> HeartRateSummary {
        let series = log.heartRateSeries ?? []
        let peak = log.maxHeartRateBPM.map { Int($0.rounded()) } ?? series.map(\.bpm).max()
        let average = log.averageHeartRateBPM.map { Int($0.rounded()) }
            ?? (series.isEmpty ? nil : series.map(\.bpm).reduce(0, +) / series.count)

        let earlier = logs.filter { $0.routineID == log.routineID && $0.id != log.id && $0.startedAt < log.startedAt }
            .sorted { $0.startedAt > $1.startedAt }.prefix(5).compactMap(\.maxHeartRateBPM)
        let usual = earlier.count >= 2 ? Int((earlier.reduce(0, +) / Double(earlier.count)).rounded()) : nil

        var zones: [Double] = [0, 0, 0, 0, 0]
        for (index, point) in series.enumerated() {
            let next = index + 1 < series.count ? series[index + 1].t : point.t + 10
            let seconds = Double(Swift.min(Swift.max(next - point.t, 0), 60))
            if let zone = HeartZones.zone(heartRate: Double(point.bpm), max: maxHeartRate) { zones[zone] += seconds }
        }

        // Each exercise's highest reading: from just before its first set to just after its last.
        var peaks: [HeartRateSummary.ExercisePeak] = []
        if !series.isEmpty {
            for exercise in log.exercises where !exercise.sets.isEmpty {
                var best = 0
                for set in exercise.sets {
                    let end = Int(set.completedAt.timeIntervalSince(log.startedAt)) + 20
                    let start = end - 80
                    best = Swift.max(best, series.filter { $0.t >= start && $0.t <= end }.map(\.bpm).max() ?? 0)
                    if let atEnd = set.heartRateAtEnd { best = Swift.max(best, Int(atEnd)) }
                }
                if best > 0 { peaks.append(.init(name: exercise.exerciseName, peak: best)) }
            }
        } else {
            for exercise in log.exercises {
                let best = exercise.sets.compactMap(\.heartRateAtEnd).max()
                if let best { peaks.append(.init(name: exercise.exerciseName, peak: Int(best))) }
            }
        }
        peaks.sort { $0.peak > $1.peak }
        return HeartRateSummary(peak: peak, average: average, usualPeak: usual, zoneSeconds: series.isEmpty ? [] : zones,
                                exercisePeaks: peaks)
    }
}

// MARK: - Set-by-set comparison

public enum SetComparison {
    public enum Arrow: String { case up = "↑", down = "↓", same = "=", new = "" }

    /// "9 vs 8 ↑" for set `index`, against the same set last time.
    public static func arrow(set: WorkoutSetLog, index: Int, previous: ExerciseLog?) -> (text: String, arrow: Arrow)? {
        guard let previous, index < previous.sets.count, set.reps > 0 else { return nil }
        let old = previous.sets[index]
        let assisted = previous.isAssisted
        let sameWeight = abs(old.weightKg - set.weightKg) < 0.01
        if sameWeight {
            let arrow: Arrow = set.reps > old.reps ? .up : (set.reps < old.reps ? .down : .same)
            return ("\(set.reps) vs \(old.reps)", arrow)
        }
        let heavier = assisted ? set.weightKg < old.weightKg : set.weightKg > old.weightKg
        let now = set.estimatedOneRepMaxKg
        let then = old.estimatedOneRepMaxKg
        let arrow: Arrow
        if assisted {
            arrow = heavier && set.reps >= old.reps ? .up : (!heavier && set.reps <= old.reps ? .down : .same)
        } else {
            arrow = now > then + 0.5 ? .up : (now < then - 0.5 ? .down : .same)
        }
        return ("\(GFFormat.kg(set.weightKg))×\(set.reps) vs \(GFFormat.kg(old.weightKg))×\(old.reps)", arrow)
    }

    /// Even targets for a total: 25 over 3 sets → [9, 8, 8].
    public static func evenTargets(total: Int, sets: Int) -> [Int] {
        guard sets > 0 else { return [] }
        let base = total / sets
        let extra = total % sets
        return (0..<sets).map { base + ($0 < extra ? 1 : 0) }
    }

    /// One line of advice comparing today's sets with last time — reads the pattern, not just the total.
    public static func advice(current: [WorkoutSetLog], previous: ExerciseLog?, repMin: Int, repMax: Int,
                              assisted: Bool) -> String? {
        let today = current.filter { $0.reps > 0 }
        guard let previous, !previous.isCardio else { return nil }
        let before = previous.sets.filter { $0.reps > 0 }
        guard today.count >= 2, before.count >= 2 else { return nil }
        let todayReps = today.map(\.reps)
        let beforeReps = before.map(\.reps)
        let now = todayReps.map(String.init).joined(separator: "·")
        let then = beforeReps.map(String.init).joined(separator: "·")

        let weightToday = today.map(\.weightKg).max() ?? 0
        let weightBefore = before.map(\.weightKg).max() ?? 0
        if abs(weightToday - weightBefore) >= 0.01 {
            let better = assisted ? weightToday < weightBefore : weightToday > weightBefore
            let e1Now = today.map(\.estimatedOneRepMaxKg).max() ?? 0
            let e1Then = before.map(\.estimatedOneRepMaxKg).max() ?? 0
            let load = "\(GFFormat.kg(weightToday)) kg × \(now) vs \(GFFormat.kg(weightBefore)) kg × \(then)"
            if assisted {
                return better ? "Less help than last time (\(load)) — that's progress." : "More help than last time (\(load))."
            }
            if better && e1Now >= e1Then - 0.5 { return "Heavier and holding the reps (\(load)) — stronger than last time." }
            if better { return "Heavier, fewer reps (\(load)). Stay at \(GFFormat.kg(weightToday)) kg until the reps come back." }
            return "Lighter today (\(load))."
        }

        let count = Swift.min(todayReps.count, beforeReps.count)
        let a = Array(todayReps.prefix(count))
        let b = Array(beforeReps.prefix(count))
        let totalNow = todayReps.reduce(0, +)
        let totalThen = beforeReps.reduce(0, +)
        let dropNow = (a.first ?? 0) - (a.last ?? 0)
        let dropThen = (b.first ?? 0) - (b.last ?? 0)
        let even = evenTargets(total: totalNow + 1, sets: todayReps.count).map(String.init).joined(separator: "·")
        let compare = "\(now) vs \(then)"

        if zip(a, b).allSatisfy({ $0 >= $1 }), zip(a, b).contains(where: { $0 > $1 }) {
            if todayReps.allSatisfy({ $0 >= repMax }) {
                return "Up on every set (\(compare)) and at the top of the range — the weight goes up next time."
            }
            return "Up on every set (\(compare)). Keep the weight and keep adding reps."
        }
        if zip(a, b).allSatisfy({ $0 <= $1 }), zip(a, b).contains(where: { $0 < $1 }) {
            return "Down on every set (\(compare)). Check sleep, food and rest times before blaming the program."
        }
        if dropNow >= 3, dropNow > dropThen {
            if totalNow > totalThen {
                return "More reps overall (\(totalNow) vs \(totalThen)) — progress, even with the drop on the last set (\(compare)). Aim for \(even) next time."
            }
            if totalNow == totalThen {
                return "Same total (\(totalNow)), but you ran out on the last set (\(compare)). Rest a bit longer before it, or pace for \(even) — even sets build more."
            }
            return "Fewer reps (\(totalNow) vs \(totalThen)) and a big drop on the last set (\(compare)) — rest longer between sets."
        }
        if let first = a.first, let old = b.first, first < old, zip(a.dropFirst(), b.dropFirst()).allSatisfy({ $0 >= $1 }) {
            return "Slow start on set 1 (\(compare)) — do one more ramp-up set before your first working set."
        }
        if totalNow > totalThen { return "+\(totalNow - totalThen) rep\(totalNow - totalThen == 1 ? "" : "s") overall (\(compare)). Progress." }
        if totalNow == totalThen { return "Matched last time (\(compare)). Aim for \(even) next time." }
        return "\(totalThen - totalNow) fewer reps than last time (\(compare))."
    }
}

// MARK: - Coach's brief

public struct WorkoutBrief: Hashable {
    /// "Strong session" / "Solid session" / "Mixed session" / "Tough day" / "Easy week, job done".
    public let rating: String
    public let lines: [String]
    /// Set-by-set notes for each exercise.
    public let exerciseNotes: [String: String]
    public var spoken: String { ([rating + "."] + lines).joined(separator: " ") }
}

public enum WorkoutBriefBuilder {
    /// `logs` may include `log` itself; only earlier sessions are compared.
    public static func make(for log: WorkoutLog, logs: [WorkoutLog], style: CoachStyle, targetRIR: Int? = nil,
                            readiness: Readiness? = nil, cardio: [CardioSession] = []) -> WorkoutBrief {
        let history = logs.filter { $0.startedAt < log.startedAt && $0.id != log.id }
        var up: [String] = []
        var down: [String] = []
        var notes: [String: String] = [:]
        var targeted = 0
        var hit = 0
        var failures = 0
        var rated = 0
        var nextStep: String?

        for exercise in log.exercises where !exercise.isCardio && !exercise.sets.isEmpty {
            let previous = history.previousLog(where: { $0.matches(exercise) }, before: log.startedAt)
            let comparison = ProgressionEngine.compare(current: exercise, previous: previous, context: log.tagSet)
            switch comparison.kind {
            case .improved: up.append(exercise.exerciseName)
            case .declined: down.append(exercise.exerciseName)
            case .matched, .firstTime: break
            }
            if let note = SetComparison.advice(current: exercise.sets, previous: previous, repMin: exercise.repMinAtTime,
                                               repMax: exercise.repMaxAtTime, assisted: exercise.isAssisted) {
                notes[exercise.exerciseName] = note
                if nextStep == nil, note.contains("next time") || note.contains("rest longer") || note.contains("ramp-up") {
                    nextStep = "\(exercise.exerciseName): " + lowerFirst(note)
                }
            }
            for set in exercise.sets {
                if let reps = set.targetReps, reps > 0 {
                    targeted += 1
                    let weightOK: Bool
                    if let target = set.targetWeightKg, target > 0 {
                        weightOK = exercise.isAssisted ? set.weightKg <= target + 0.01 : set.weightKg >= target - 0.01
                    } else {
                        weightOK = true
                    }
                    if weightOK && set.reps >= reps { hit += 1 }
                }
                if let rir = set.rir {
                    rated += 1
                    if rir == 0 { failures += 1 }
                }
            }
            // The weight is going up next time: the clearest next step there is.
            if nextStep == nil {
                let definition = ExerciseDefinition(name: exercise.exerciseName, category: exercise.category ?? .other,
                                                    repMin: exercise.repMinAtTime, repMax: exercise.repMaxAtTime,
                                                    defaultSets: exercise.sets.count, weightIncrementKg: exercise.weightIncrementKgAtTime)
                if case .increaseWeight(let kg) = ProgressionEngine.recommendation(for: definition, previous: exercise).action, kg > 0 {
                    nextStep = "\(exercise.exerciseName) goes \(exercise.isAssisted ? "to less help" : "up"): \(GFFormat.kg(kg)) kg next time."
                }
            }
        }

        let prs = log.exercises.flatMap(\.sets).filter { $0.isPR == true }.count
        let hitShare = targeted > 0 ? Double(hit) / Double(targeted) : nil

        // Rating.
        var score = 50.0
        score += Double(up.count) * 10 - Double(down.count) * 12 + Double(Swift.min(prs, 3)) * 8
        if let hitShare { score += (hitShare - 0.6) * 50 }
        let rating: String
        if log.isDeload == true {
            rating = "Easy week, job done"
        } else if !log.tagSet.isEmpty, score < 58 {
            rating = "Done on a tough day"
        } else if score >= 80 {
            rating = "Strong session"
        } else if score >= 58 {
            rating = "Solid session"
        } else if score >= 40 {
            rating = "Mixed session"
        } else {
            rating = "Tough day"
        }

        var lines: [String] = []
        // What went well.
        var good: [String] = []
        if prs > 0 { good.append("\(prs) PR\(prs == 1 ? "" : "s")") }
        if !up.isEmpty { good.append("up on " + list(up)) }
        if let hitShare, targeted >= 3 { good.append("\(Int((hitShare * 100).rounded()))% of targets hit") }
        if !good.isEmpty { lines.append(capitalizedFirst(good.joined(separator: ", ")) + ".") }
        // What fell short.
        if !down.isEmpty { lines.append("Down on " + list(down) + ".") }
        if let targetRIR, targetRIR >= 2, rated >= 3, failures >= 2 {
            lines.append("\(failures) sets went to failure when the plan said leave ~\(targetRIR) — save that for the last week of the block.")
        }
        // Context.
        if let tag = SessionTag.explaining(log.tagSet) {
            let titles = (log.sessionTags ?? []).map { $0.title.lowercased() }.joined(separator: ", ")
            lines.append("Logged as \(titles) — \(tag == .equipmentUnavailable ? "swaps" : "lower numbers") won't count against your trends or plateaus.")
        } else if let readiness, readiness.level == .low, down.count <= 1 {
            lines.append("On low recovery (\(readiness.reasons.first?.lowercased() ?? "short sleep")), holding your numbers is a win.")
        } else if let hard = cardio.filter({ $0.endedAt < log.startedAt && log.startedAt.timeIntervalSince($0.endedAt) < 30 * 3600 && $0.isHardOnLegs }).first,
                  !down.isEmpty {
            lines.append("The \(hard.kind == .run ? "run" : "basketball") the day before will have cost you some of that.")
        }
        // Next step.
        if let nextStep { lines.append("Next: " + nextStep) }
        if lines.isEmpty { lines.append("Matched your last numbers — steady.") }
        if let closer = closer(style: style, rating: rating) { lines.append(closer) }

        return WorkoutBrief(rating: rating, lines: Array(lines.prefix(5)), exerciseNotes: notes)
    }

    private static func closer(style: CoachStyle, rating: String) -> String? {
        let good = rating.hasPrefix("Strong") || rating.hasPrefix("Solid") || rating.hasPrefix("Easy")
        switch style {
        case .pushMe: return good ? "Now do it again, heavier." : "Shake it off. Next session, no excuses."
        case .motivating: return good ? "That's how it's built — one session at a time." : "Every session counts, even the hard ones."
        case .analytical: return nil
        case .supportive: return good ? "Really good work today." : "Showing up on a hard day is the habit that wins."
        case .hardTruth: return good ? "Good. Standards don't take days off." : "Not your best. Fix the next one."
        case .heartbreak: return good ? "She's going to notice. Keep going." : "Bad day, not a bad you. Back at it."
        }
    }

    private static func list(_ names: [String]) -> String {
        if names.count <= 3 { return names.joined(separator: ", ") }
        return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more"
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
