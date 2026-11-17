import Foundation

// MARK: - MK24 (G2): water, caffeine, weekly averages, goal weight, weigh-in day

public enum WaterMath {
    /// 35 ml per kg (3 L without a weight), plus 500 ml on a training day.
    public static func target(weightKg: Double?, training: Bool) -> Int {
        let base = weightKg.map { Int(($0 * 35 / 250).rounded()) * 250 } ?? 3000
        return base + (training ? 500 : 0)
    }

    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public enum CaffeineMath {
    /// Caffeine's half-life in a typical adult, in hours.
    public static let halfLife = 5.0

    /// Milligrams still in your system at `date`.
    public static func remaining(_ entries: [CaffeineEntry], at date: Date) -> Double {
        entries.filter { $0.date <= date }.reduce(0) { total, entry in
            total + Double(entry.mg) * pow(0.5, date.timeIntervalSince(entry.date) / 3600 / halfLife)
        }
    }

    /// The last time for caffeine before a bedtime (8 hours before by default).
    public static func cutoff(bedtime: Date, hoursBefore: Double = 8) -> Date {
        bedtime.addingTimeInterval(-hoursBefore * 3600)
    }
}

public struct WeekAverage: Equatable, Identifiable {
    public var weekStart: Date
    public var calories: Double?
    public var protein: Double?
    public var weight: Double?
    /// Change in average weight from the week before.
    public var weightChange: Double?
    public var id: Date { weekStart }
}

public enum WeeklyAverages {
    /// The last `weeks` full-or-current weeks, newest first. Only days with something logged count toward an average.
    public static func make(nutrition: [NutritionDay], weights: [(date: Date, kg: Double)], weeks: Int = 8,
                            now: Date = .now, calendar: Calendar = .current) -> [WeekAverage] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        var rows: [WeekAverage] = []
        for back in (0..<(weeks + 1)).reversed() {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            let days = nutrition.filter { $0.day >= start && $0.day < end }
            let w = mean(weights.filter { $0.date >= start && $0.date < end }.map(\.kg))
            let previous = rows.last?.weight
            rows.append(WeekAverage(weekStart: start,
                                    calories: mean(days.compactMap(\.calories).filter { $0 > 0 }),
                                    protein: mean(days.map(\.proteinG).filter { $0 > 0 }),
                                    weight: w,
                                    weightChange: w.flatMap { now in previous.map { now - $0 } }))
        }
        return Array(rows.dropFirst().reversed())   // the extra oldest week only gave the first change
    }
}

public enum WeightGoalMath {
    public enum Status: Equatable {
        case reached
        /// Needed kg per week to get there by the date, and your trend (kg per week) over the last 4 weeks.
        case needs(perWeek: Double, trend: Double?)
        case noDate(trend: Double?)
    }

    /// Least-squares trend over the last 28 days, kg per week (nil with fewer than 4 weigh-ins).
    public static func trend(_ weights: [(date: Date, kg: Double)], now: Date = .now) -> Double? {
        let recent = weights.filter { $0.date > now.addingTimeInterval(-28 * 86_400) && $0.date <= now }
        guard recent.count >= 4, let first = recent.map(\.date).min() else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86_400 }, ys = recent.map(\.kg)
        let n = Double(recent.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
        guard sxx > 0 else { return nil }
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx * 7
    }

    public static func status(goal: GoalWeight, current: Double, weights: [(date: Date, kg: Double)], now: Date = .now) -> Status {
        // Which way you're going comes from where you started (MK24.2), so a bulk that overshoots its goal
        // is "reached", not "now lose weight". Goals set before that guess from where you are.
        let gaining = goal.startKg.map { goal.kg >= $0 } ?? (goal.kg >= current)
        if abs(goal.kg - current) < 0.3 || (gaining ? current >= goal.kg : current <= goal.kg) { return .reached }
        let t = trend(weights, now: now)
        guard let by = goal.by, by > now else { return .noDate(trend: t) }
        let weeks = by.timeIntervalSince(now) / (7 * 86_400)
        return .needs(perWeek: (goal.kg - current) / max(weeks, 0.5), trend: t)
    }
}

public extension WeighIn {
    /// MK24 (105): the weigh-in day (1 = Sunday … 7 = Saturday), and whether you weigh in daily instead.
    static var weekday: Int {
        get { (UserDefaults.standard.object(forKey: "weighin.weekday") as? Int).map { min(max($0, 1), 7) } ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "weighin.weekday") }
    }
    static var daily: Bool {
        get { UserDefaults.standard.bool(forKey: "weighin.daily") }
        set { UserDefaults.standard.set(newValue, forKey: "weighin.daily") }
    }
    static var dayName: String { Calendar.current.weekdaySymbols[weekday - 1] }
}
