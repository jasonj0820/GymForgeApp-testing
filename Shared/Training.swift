import Foundation

// MARK: - Program blocks

public enum ProgramPhase: String, Codable, CaseIterable, Identifiable {
    case hypertrophy, strength, endurance, deload
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hypertrophy: return "Hypertrophy"
        case .strength: return "Strength"
        case .endurance: return "Endurance"
        case .deload: return "Deload"
        }
    }

    public var summary: String {
        switch self {
        case .hypertrophy: return "Your normal rep ranges."
        case .strength: return "Heavier, lower reps (8–12 becomes 5–8)."
        case .endurance: return "Lighter, higher reps (8–12 becomes 12–18)."
        case .deload: return "One less set and ~10% lighter to recover."
        }
    }

    /// Applies the phase's rep range to an exercise and its alternatives. Cardio is left alone.
    public static func adjust(_ exercise: ExerciseDefinition, for phase: ProgramPhase?) -> ExerciseDefinition {
        guard let phase, !exercise.isCardio else { return exercise }
        var copy = exercise
        switch phase {
        case .strength:
            let low = Swift.max(3, exercise.repMin - 3)
            copy.repMin = low
            copy.repMax = Swift.max(low + 2, exercise.repMax - 4)
        case .endurance:
            copy.repMin = exercise.repMin + 4
            copy.repMax = Swift.max(copy.repMin + 2, exercise.repMax + 6)
        case .hypertrophy, .deload:
            break
        }
        if let alternatives = exercise.alternatives {
            copy.alternatives = alternatives.map { adjust($0, for: phase) }
        }
        return copy
    }

    /// Deload / light session: one less set (minimum 1), applied to alternatives too.
    public static func reduceSets(_ exercise: ExerciseDefinition) -> ExerciseDefinition {
        var copy = exercise
        if !exercise.isCardio {
            copy.defaultSets = Swift.max(1, exercise.defaultSets - 1)
        }
        if let alternatives = exercise.alternatives {
            copy.alternatives = alternatives.map { reduceSets($0) }
        }
        return copy
    }

    /// ~90% of the weight, rounded down to the exercise's increment.
    public static func deloadWeight(_ weight: Double, increment: Double) -> Double {
        let step = increment > 0 ? increment : 2.5
        // ~90%, to the nearest plate step, but always at least one step lighter.
        let rounded = ((weight * 0.9) / step).rounded() * step
        return Swift.max(0, rounded >= weight ? weight - step : rounded)
    }
}

public struct ProgramBlock: Codable, Hashable, Identifiable {
    public var id: UUID
    public var phase: ProgramPhase
    public var weeks: Int

    public init(id: UUID = UUID(), phase: ProgramPhase, weeks: Int) {
        self.id = id
        self.phase = phase
        self.weeks = weeks
    }
}

public struct ProgramPosition: Hashable {
    public var block: ProgramBlock
    public var blockIndex: Int
    /// 1-based week within the block.
    public var week: Int
    public var blockEnds: Date
}

public struct ProgramPlan: Codable, Hashable {
    public var name: String
    public var blocks: [ProgramBlock]
    public var startDate: Date
    public var repeats: Bool

    public init(name: String, blocks: [ProgramBlock], startDate: Date, repeats: Bool = true) {
        self.name = name
        self.blocks = blocks
        self.startDate = startDate
        self.repeats = repeats
    }

    public var totalWeeks: Int { blocks.reduce(0) { $0 + Swift.max($1.weeks, 1) } }

    public func position(at date: Date, calendar: Calendar = .current) -> ProgramPosition? {
        guard !blocks.isEmpty, date >= startDate else { return nil }
        let start = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
        var week = days / 7
        let total = totalWeeks
        guard total > 0 else { return nil }
        if week >= total {
            guard repeats else { return nil }
            week %= total
        }
        let cycleStartWeek = (days / 7) - week
        var cursor = 0
        for (index, block) in blocks.enumerated() {
            let length = Swift.max(block.weeks, 1)
            if week < cursor + length {
                let endWeek = cycleStartWeek + cursor + length
                let ends = calendar.date(byAdding: .day, value: endWeek * 7, to: start) ?? date
                return ProgramPosition(block: block, blockIndex: index, week: week - cursor + 1, blockEnds: ends)
            }
            cursor += length
        }
        return nil
    }

    public static let templates: [ProgramPlan] = [
        ProgramPlan(name: "Hypertrophy → Strength", blocks: [
            ProgramBlock(phase: .hypertrophy, weeks: 6),
            ProgramBlock(phase: .strength, weeks: 4),
            ProgramBlock(phase: .deload, weeks: 1)
        ], startDate: .now),
        ProgramPlan(name: "Hypertrophy + deload", blocks: [
            ProgramBlock(phase: .hypertrophy, weeks: 5),
            ProgramBlock(phase: .deload, weeks: 1)
        ], startDate: .now),
        ProgramPlan(name: "Strength focus", blocks: [
            ProgramBlock(phase: .strength, weeks: 5),
            ProgramBlock(phase: .deload, weeks: 1)
        ], startDate: .now),
        ProgramPlan(name: "Endurance → Hypertrophy → Strength", blocks: [
            ProgramBlock(phase: .endurance, weeks: 3),
            ProgramBlock(phase: .hypertrophy, weeks: 4),
            ProgramBlock(phase: .strength, weeks: 3),
            ProgramBlock(phase: .deload, weeks: 1)
        ], startDate: .now)
    ]
}

// MARK: - Readiness (sleep & recovery)

public struct Readiness: Equatable {
    public enum Level: String { case ready, moderate, low }
    public var level: Level
    public var score: Int
    public var reasons: [String]
    public var sleepHours: Double?
    public var restingHR: Double?
    public var restingHRBaseline: Double?
    public var hrv: Double?
    public var hrvBaseline: Double?

    public var title: String {
        switch level {
        case .ready: return "Ready to train"
        case .moderate: return "Moderately recovered"
        case .low: return "Take it easier today"
        }
    }

    public var suggestLightSession: Bool { level == .low }
}

public enum ReadinessEngine {
    /// Combines last night's sleep and resting HR / HRV against your 30-day baselines.
    public static func evaluate(
        sleep: [SleepNight],
        restingHR: [BodyMetricPoint],
        hrv: [BodyMetricPoint],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Readiness? {
        let today = calendar.startOfDay(for: now)
        let lastNight = sleep.first { calendar.isDate($0.date, inSameDayAs: today) }?.hoursAsleep

        func latest(_ points: [BodyMetricPoint]) -> Double? {
            points.filter { now.timeIntervalSince($0.date) < 36 * 3600 && $0.date <= now }
                .max { $0.date < $1.date }?.value
        }
        func baseline(_ points: [BodyMetricPoint]) -> Double? {
            let values = points.filter {
                let age = now.timeIntervalSince($0.date)
                return age > 2 * 86_400 && age < 30 * 86_400
            }.map(\.value)
            guard values.count >= 5 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }

        let rhr = latest(restingHR)
        let rhrBase = baseline(restingHR)
        let hrvNow = latest(hrv)
        let hrvBase = baseline(hrv)
        guard lastNight != nil || (rhr != nil && rhrBase != nil) || (hrvNow != nil && hrvBase != nil) else { return nil }

        var score = 100
        var reasons: [String] = []
        if let hours = lastNight {
            let text = String(format: "%.1f h", hours)
            if hours < 5 { score -= 35; reasons.append("Only \(text) sleep") }
            else if hours < 6 { score -= 20; reasons.append("Short sleep (\(text))") }
            else if hours < 7 { score -= 8; reasons.append("Slightly short sleep (\(text))") }
            else { reasons.append("Good sleep (\(text))") }
        }
        if let rhr, let rhrBase {
            let diff = rhr - rhrBase
            if diff >= 7 { score -= 25; reasons.append("Resting HR \(Int(diff.rounded())) bpm above normal") }
            else if diff >= 4 { score -= 12; reasons.append("Resting HR slightly elevated (+\(Int(diff.rounded())))") }
            else { reasons.append("Resting HR normal") }
        }
        if let hrvNow, let hrvBase, hrvBase > 0 {
            let ratio = hrvNow / hrvBase
            if ratio < 0.8 { score -= 20; reasons.append("HRV well below your normal") }
            else if ratio < 0.9 { score -= 10; reasons.append("HRV a little low") }
            else { reasons.append("HRV normal") }
        }
        score = Swift.max(0, Swift.min(100, score))
        let level: Readiness.Level = score >= 75 ? .ready : (score >= 55 ? .moderate : .low)
        return Readiness(level: level, score: score, reasons: reasons, sleepHours: lastNight,
                         restingHR: rhr, restingHRBaseline: rhrBase, hrv: hrvNow, hrvBaseline: hrvBase)
    }

    /// Merges overlapping "asleep" intervals (Watch + iPhone often both record) into hours per wake-up day.
    public static func nights(from intervals: [DateInterval], calendar: Calendar = .current) -> [SleepNight] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: Swift.max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        var totals: [Date: Double] = [:]
        var bounds: [Date: (start: Date, end: Date)] = [:]
        for interval in merged {
            let day = calendar.startOfDay(for: interval.end)
            totals[day, default: 0] += interval.duration / 3600
            // Bed / wake times come from the night's sleep, not an afternoon nap.
            guard calendar.component(.hour, from: interval.end) < 14 else { continue }
            let old = bounds[day]
            bounds[day] = (Swift.min(old?.start ?? interval.start, interval.start), Swift.max(old?.end ?? interval.end, interval.end))
        }
        return totals.map { SleepNight(date: $0.key, hoursAsleep: $0.value, start: bounds[$0.key]?.start, end: bounds[$0.key]?.end) }
            .sorted { $0.date < $1.date }
    }
}

// MARK: - Weekly volume per muscle group

public enum MuscleVolume {
    /// Working sets per muscle group logged in the window (cardio excluded).
    public static func sets(
        logs: [WorkoutLog],
        from start: Date,
        to end: Date,
        categoryLookup: [String: ExerciseCategory] = [:]
    ) -> [ExerciseCategory: Int] {
        var result: [ExerciseCategory: Int] = [:]
        for workout in logs where workout.startedAt >= start && workout.startedAt < end {
            for exercise in workout.exercises where !exercise.isCardio {
                let category = exercise.category
                    ?? categoryLookup[ExerciseLog.key(for: exercise.exerciseName)]
                    ?? ExerciseCategory.guess(from: exercise.exerciseName)
                guard category != .cardio else { continue }
                result[category, default: 0] += exercise.sets.count
            }
        }
        return result
    }

    /// Average sets per week over the last `weeks` full 7-day windows.
    public static func weeklyAverage(
        logs: [WorkoutLog],
        weeks: Int,
        now: Date = .now,
        categoryLookup: [String: ExerciseCategory] = [:]
    ) -> [ExerciseCategory: Double] {
        let start = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        let totals = sets(logs: logs, from: start, to: now, categoryLookup: categoryLookup)
        return totals.mapValues { Double($0) / Double(Swift.max(weeks, 1)) }
    }

    public static func lookup(from routines: [WorkoutRoutine]) -> [String: ExerciseCategory] {
        var map: [String: ExerciseCategory] = [:]
        for exercise in routines.flatMap(\.allExercises) {
            map[exercise.historyKey] = exercise.category
        }
        return map
    }
}

// MARK: - Heart-rate recovery

public enum RecoveryTrend {
    /// Compares the last 3 workouts' average HR recovery with the 10 before them.
    public static func change(logs: [WorkoutLog]) -> (recent: Double, baseline: Double)? {
        let values = logs.sorted { $0.startedAt > $1.startedAt }.compactMap(\.averageHeartRateRecovery)
        guard values.count >= 6 else { return nil }
        let recent = Array(values.prefix(3))
        let baseline = Array(values.dropFirst(3).prefix(10))
        let recentAverage = recent.reduce(0, +) / Double(recent.count)
        let baselineAverage = baseline.reduce(0, +) / Double(baseline.count)
        return (recentAverage, baselineAverage)
    }
}
