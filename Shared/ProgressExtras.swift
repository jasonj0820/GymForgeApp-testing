import Foundation

// MARK: - MK24 (83): compare two periods

public struct PeriodStats: Equatable {
    public var sessions: Int
    public var sets: Int
    public var volumeKg: Double
    public var prs: Int
    public var weeks: Double
    /// Lift history key → heaviest weight in the period.
    public var topWeights: [String: Double]
    public var perWeek: Double { weeks > 0 ? Double(sessions) / weeks : 0 }

    public static func make(_ logs: [WorkoutLog], from start: Date, to end: Date) -> PeriodStats {
        let inside = logs.filter { $0.countsAsTraining && $0.startedAt >= start && $0.startedAt < end }
        var top: [String: Double] = [:]
        for log in inside {
            for exercise in log.exercises where !exercise.isCardio {
                let best = exercise.sets.map(\.weightKg).max() ?? 0
                let key = ExerciseLog.key(for: exercise.exerciseName)
                if best > (top[key] ?? 0) { top[key] = best }
            }
        }
        return PeriodStats(sessions: inside.count,
                           sets: inside.reduce(0) { $0 + $1.totalSets },
                           volumeKg: inside.reduce(0) { $0 + $1.totalVolumeKg },
                           prs: inside.reduce(0) { $0 + $1.prCount },
                           weeks: max(end.timeIntervalSince(start) / (7 * 86_400), 0),
                           topWeights: top)
    }

    /// Lifts done in both periods, with the change in heaviest weight (b − a).
    public static func liftChanges(_ a: PeriodStats, _ b: PeriodStats) -> [(key: String, from: Double, to: Double)] {
        a.topWeights.compactMap { key, from in b.topWeights[key].map { (key: key, from: from, to: $0) } }
            .sorted { ($0.to - $0.from) > ($1.to - $1.from) }
    }
}

// MARK: - MK24 (90): year in review

public struct YearReview: Equatable {
    public var year: Int
    public var sessions: Int
    public var hours: Double
    public var sets: Int
    public var volumeKg: Double
    public var prs: Int
    public var bestWeek: Int
    public var longestStreakWeeks: Int
    public var favouriteRoutine: String?
    public var mostImproved: [(name: String, from: Double, to: Double)]
    public var busiestMonth: Int?

    public static func == (l: YearReview, r: YearReview) -> Bool {
        l.year == r.year && l.sessions == r.sessions && l.sets == r.sets && l.prs == r.prs && l.longestStreakWeeks == r.longestStreakWeeks
    }

    /// `weekGoal`: a week counts toward the streak when it had at least this many sessions (min 1).
    public static func make(_ logs: [WorkoutLog], year: Int, weekGoal: Int = 1, calendar: Calendar = .current) -> YearReview {
        let inside = logs.filter { $0.countsAsTraining && calendar.component(.year, from: $0.startedAt) == year }
            .sorted { $0.startedAt < $1.startedAt }
        var perWeek: [Date: Int] = [:]
        for log in inside {
            if let week = calendar.dateInterval(of: .weekOfYear, for: log.startedAt)?.start { perWeek[week, default: 0] += 1 }
        }
        // Longest run of consecutive weeks meeting the bar.
        var longest = 0, run = 0
        var previous: Date?
        for week in perWeek.keys.sorted() where perWeek[week, default: 0] >= max(weekGoal, 1) {
            if let previous, let next = calendar.date(byAdding: .weekOfYear, value: 1, to: previous), calendar.isDate(next, inSameDayAs: week) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = week
        }
        var routineCounts: [String: Int] = [:]
        for log in inside { routineCounts[log.routineName, default: 0] += 1 }
        var months: [Int: Int] = [:]
        for log in inside { months[calendar.component(.month, from: log.startedAt), default: 0] += 1 }
        // First and last heaviest set per lift, for lifts done 4+ times.
        var firsts: [String: (name: String, value: Double)] = [:], lasts: [String: Double] = [:], counts: [String: Int] = [:]
        for log in inside {
            for exercise in log.exercises where !exercise.isCardio {
                guard let best = exercise.sets.map(\.weightKg).max(), best > 0 else { continue }
                let key = ExerciseLog.key(for: exercise.exerciseName)
                if firsts[key] == nil { firsts[key] = (exercise.exerciseName, best) }
                lasts[key] = best
                counts[key, default: 0] += 1
            }
        }
        let improved = firsts.compactMap { key, first -> (name: String, from: Double, to: Double)? in
            guard counts[key, default: 0] >= 4, let last = lasts[key], last > first.value else { return nil }
            return (first.name, first.value, last)
        }
        .sorted { ($0.to / $0.from) > ($1.to / $1.from) }
        return YearReview(
            year: year,
            sessions: inside.count,
            hours: inside.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) } / 3600,
            sets: inside.reduce(0) { $0 + $1.totalSets },
            volumeKg: inside.reduce(0) { $0 + $1.totalVolumeKg },
            prs: inside.reduce(0) { $0 + $1.prCount },
            bestWeek: perWeek.values.max() ?? 0,
            longestStreakWeeks: longest,
            favouriteRoutine: routineCounts.max { $0.value < $1.value }?.key,
            mostImproved: Array(improved.prefix(3)),
            busiestMonth: months.max { $0.value < $1.value }?.key
        )
    }
}

// MARK: - MK24 (85): where the weight went up

public enum LiftMarkers {
    /// Sessions whose heaviest set beat the previous session's.
    public static func weightIncreases(_ points: [(date: Date, value: Double)]) -> [Date] {
        let sorted = points.filter { $0.value > 0 }.sorted { $0.date < $1.date }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, next in next.value > previous.value ? next.date : nil }
    }

    /// Sessions where the target rep range changed from the session before ("8–12" → "6–10").
    public static func repRangeChanges(_ points: [(date: Date, low: Int, high: Int)]) -> [(date: Date, text: String)] {
        let sorted = points.filter { $0.low > 0 && $0.high > 0 }.sorted { $0.date < $1.date }
        return zip(sorted, sorted.dropFirst()).compactMap { previous, next in
            (next.low, next.high) != (previous.low, previous.high) ? (next.date, "\(next.low)–\(next.high)") : nil
        }
    }
}
