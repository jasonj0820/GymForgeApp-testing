import Foundation

// MARK: - Formatting

public enum GFFormat {
    /// 80 -> "80", 82.5 -> "82.5", 81.25 -> "81.25"
    public static func kg(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    public static func signed(_ value: Double, decimals: Int = 1) -> String {
        let body = String(format: "%.\(decimals)f", abs(value))
        return value < 0 ? "−\(body)" : "+\(body)"
    }

    /// 1500 s -> "25 min", 3900 s -> "1 h 5 min"
    public static func minutes(_ seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        if total >= 60 { return "\(total / 60) h \(total % 60) min" }
        return "\(total) min"
    }

    public static func km(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 12_345 kg -> "12.3 t", 950 -> "950 kg"
    public static func volume(_ kg: Double) -> String {
        kg >= 10_000 ? String(format: "%.1f t", kg / 1000) : "\(Int(kg.rounded())) kg"
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Consistency

public struct ConsistencyStats: Equatable {
    public var weeklyGoal: Int
    public var thisWeekCount: Int
    public var last4WeeksCount: Int
    public var last4WeeksTarget: Int
    public var previous4WeeksCount: Int
    /// MK17: target for weeks 5–8 (break weeks left out, so it can differ from the last 4).
    public var previous4WeeksTarget: Int = 0
    public var missedLast4Weeks: Int
    public var streakWeeks: Int
    public var averagePerWeek: Double
    public var weeksTracked: Int

    public var thisWeekAdherence: Double {
        weeklyGoal > 0 ? min(1, Double(thisWeekCount) / Double(weeklyGoal)) : 0
    }
    public var last4WeeksAdherence: Double {
        last4WeeksTarget > 0 ? min(1, Double(last4WeeksCount) / Double(last4WeeksTarget)) : 0
    }
    public var previous4WeeksAdherence: Double? {
        guard weeksTracked >= 8, last4WeeksTarget > 0, previous4WeeksTarget > 0 else { return nil }
        return min(1, Double(previous4WeeksCount) / Double(previous4WeeksTarget))
    }
}

public enum ConsistencyCalculator {
    public static func stats(
        logs: [WorkoutLog],
        weeklyGoal: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        breaks: [DateInterval] = []
    ) -> ConsistencyStats {
        let goal = max(weeklyGoal, 1)
        let logs = logs.filter(\.countsAsTraining)   // MK10.2: cardio is an extra, not a session
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        func count(weeksAgo offset: Int) -> Int {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: weekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return 0 }
            return logs.filter { $0.startedAt >= start && $0.startedAt < end }.count
        }

        var weeksTracked = 0
        if let first = logs.map(\.startedAt).min(),
           let firstWeek = calendar.dateInterval(of: .weekOfYear, for: first)?.start {
            weeksTracked = max(0, calendar.dateComponents([.weekOfYear], from: firstWeek, to: weekStart).weekOfYear ?? 0)
        }

        /// A week that overlaps a "Give me a break".
        func onBreak(weeksAgo offset: Int) -> Bool {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: weekStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return false }
            return breaks.contains { $0.start < end && $0.end > start }
        }

        let thisWeek = count(weeksAgo: 0)
        // MK17: break weeks are left out of adherence and averages too (not only the streak), so a break
        // never reads as "inconsistent training" afterwards.
        let trackedLastFour = (1...4).filter { $0 <= weeksTracked && !onBreak(weeksAgo: $0) }.map { count(weeksAgo: $0) }
        let previousFour = (5...8).filter { $0 <= weeksTracked && !onBreak(weeksAgo: $0) }.map { count(weeksAgo: $0) }

        var streak = 0
        var offset = 1
        while offset <= weeksTracked, offset <= 260 {
            // MK11.3: weeks on a "Give me a break" pause the streak instead of breaking it.
            if onBreak(weeksAgo: offset) {
                offset += 1
                continue
            }
            guard count(weeksAgo: offset) >= goal else { break }
            streak += 1
            offset += 1
        }
        if thisWeek >= goal { streak += 1 }

        let averageWeeks = weeksTracked > 0 ? (1...min(8, weeksTracked)).filter { !onBreak(weeksAgo: $0) } : []
        let average: Double
        if !averageWeeks.isEmpty {
            let total = averageWeeks.reduce(0) { $0 + count(weeksAgo: $1) }
            average = Double(total) / Double(averageWeeks.count)
        } else {
            average = Double(thisWeek)
        }

        return ConsistencyStats(
            weeklyGoal: goal,
            thisWeekCount: thisWeek,
            last4WeeksCount: trackedLastFour.reduce(0, +),
            last4WeeksTarget: goal * trackedLastFour.count,
            previous4WeeksCount: previousFour.reduce(0, +),
            previous4WeeksTarget: goal * previousFour.count,
            missedLast4Weeks: trackedLastFour.reduce(0) { $0 + max(0, goal - $1) },
            streakWeeks: streak,
            averagePerWeek: average,
            weeksTracked: weeksTracked
        )
    }
}

// MARK: - Body composition trends

public enum BodyTrendCalculator {
    /// Trailing average so a single noisy scale reading doesn't swing the trend.
    public static func rollingAverage(_ points: [BodyMetricPoint], days: Int = 7) -> [BodyMetricPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        let window = Double(days) * 86_400
        return sorted.map { point in
            let start = point.date.addingTimeInterval(-window)
            let values = sorted.filter { $0.date > start && $0.date <= point.date }.map(\.value)
            let average = values.reduce(0, +) / Double(max(values.count, 1))
            return BodyMetricPoint(metric: point.metric, date: point.date, value: average)
        }
    }

    public static func recentAverage(_ points: [BodyMetricPoint], days: Int = 7, now: Date = .now) -> Double? {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let values = points.filter { $0.date > start && $0.date <= now }.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Change per week, comparing the last 7 days with the window 3–5 weeks ago.
    public static func weeklyChange(_ points: [BodyMetricPoint], now: Date = .now) -> Double? {
        let day: TimeInterval = 86_400
        let recent = points.filter { $0.date > now.addingTimeInterval(-7 * day) && $0.date <= now }.map(\.value)
        let past = points.filter {
            $0.date > now.addingTimeInterval(-35 * day) && $0.date <= now.addingTimeInterval(-21 * day)
        }.map(\.value)
        guard !recent.isEmpty, !past.isEmpty else { return nil }
        let recentAverage = recent.reduce(0, +) / Double(recent.count)
        let pastAverage = past.reduce(0, +) / Double(past.count)
        return (recentAverage - pastAverage) / 3.5
    }

    /// Lean mass estimate = weight × (1 − body fat %), pairing readings taken within 36 hours.
    public static func leanMass(weights: [BodyMetricPoint], fats: [BodyMetricPoint]) -> [BodyMetricPoint] {
        var result: [BodyMetricPoint] = []
        for fat in fats {
            let closest = weights.min { abs($0.date.timeIntervalSince(fat.date)) < abs($1.date.timeIntervalSince(fat.date)) }
            guard let weight = closest, abs(weight.date.timeIntervalSince(fat.date)) <= 36 * 3600 else { continue }
            result.append(BodyMetricPoint(metric: .leanMass, date: fat.date, value: weight.value * (1 - fat.value / 100)))
        }
        return result.sorted { $0.date < $1.date }
    }
}

// MARK: - Strength trend

public enum StrengthTrend: Equatable {
    case up, flat, down, unknown
}

public enum StrengthAnalyzer {
    /// Average change in estimated 1RM across exercises trained at least twice in the window.
    public static func trend(logs: [WorkoutLog], now: Date = .now, days: Int = 42) -> StrengthTrend {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        var series: [String: [(Date, Double)]] = [:]
        // MK17: deload / short / easy / tired sessions stay out, and each grip or tempo variation is its own lift.
        for workout in logs where workout.startedAt >= start && workout.startedAt <= now && !workout.isAtypical {
            for exercise in workout.exercises {
                let value = exercise.estimatedOneRepMaxKg
                guard value > 0 else { continue }
                series[exercise.trendKey, default: []].append((workout.startedAt, value))
            }
        }
        var changes: [Double] = []
        for (_, values) in series where values.count >= 2 {
            let ordered = values.sorted { $0.0 < $1.0 }
            if let first = ordered.first?.1, let last = ordered.last?.1, first > 0 {
                changes.append((last - first) / first)
            }
        }
        guard !changes.isEmpty else { return .unknown }
        let average = changes.reduce(0, +) / Double(changes.count)
        if average > 0.02 { return .up }
        if average < -0.02 { return .down }
        return .flat
    }
}
