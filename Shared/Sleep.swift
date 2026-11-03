import Foundation

// MK11: sleep schedule (a bedtime and wake time for each night), how well you stick to it,
// and Sergeant Cluck's comments on your gym pattern.

/// Bedtime and wake time per night, keyed by the evening's weekday (1 = Sunday … 7 = Saturday),
/// in minutes after midnight. "Monday: 23:00 → 07:00" means bed Monday night, up Tuesday morning.
public struct SleepSchedule: Codable, Hashable {
    public var bedtime: [Int: Int]
    public var wake: [Int: Int]

    public init(bedtime: [Int: Int] = [:], wake: [Int: Int] = [:]) {
        self.bedtime = bedtime
        self.wake = wake
    }

    public static let standard = SleepSchedule(bedtime: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 23 * 60) }),
                                               wake: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 7 * 60) }))

    public func bedMinutes(_ weekday: Int) -> Int { bedtime[weekday] ?? 23 * 60 }
    public func wakeMinutes(_ weekday: Int) -> Int { wake[weekday] ?? 7 * 60 }

    /// Bedtime for the night that starts on `evening`'s day (after-midnight bedtimes land on the next day).
    public func bedtime(forNightOf evening: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: evening)
        let minutes = bedMinutes(calendar.component(.weekday, from: day))
        let offset = minutes < 12 * 60 ? minutes + 24 * 60 : minutes
        return day.addingTimeInterval(Double(offset) * 60)
    }

    /// Wake time the morning after `evening`.
    public func wakeTime(forNightOf evening: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: evening)
        let minutes = wakeMinutes(calendar.component(.weekday, from: day))
        return day.addingTimeInterval(Double(24 * 60 + minutes) * 60)
    }

    /// The next bedtime after `date` that hasn't passed (tonight's, or tomorrow's if tonight's is gone).
    public func nextBedtime(after date: Date, calendar: Calendar = .current) -> Date {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        for offset in 0...2 {
            let evening = calendar.date(byAdding: .day, value: offset, to: yesterday) ?? date
            let bed = bedtime(forNightOf: evening, calendar: calendar)
            if bed > date { return bed }
        }
        return bedtime(forNightOf: date, calendar: calendar)
    }

    public static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

/// MK11.2: Sergeant Cluck nags you after bedtime until you tap "I'm going to bed".
public enum BedtimeNag {
    /// Minutes past bedtime: every 10 min, then every 5 once you're 30+ min late, stopping at an hour.
    public static let offsets = [10, 20, 30, 35, 40, 45, 50, 55, 60]
    /// The card shows from 10 min before bed until an hour after (or until you tap the button).
    public static let windowBefore: TimeInterval = 10 * 60
    /// The Lock Screen card can go up this early, so it's already there when wind-down starts.
    public static let cardBefore: TimeInterval = 2 * 3600
    public static let windowAfter: TimeInterval = 60 * 60

    /// Nights in a row (ending tonight, or last night if tonight isn't logged yet) in bed by bedtime.
    /// `log`: evening (start of day) → minutes late when you tapped "I'm going to bed".
    public static func streak(log: [Date: Int], today: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        let byDay = Dictionary(log.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: min)
        if byDay[day] == nil { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while let late = byDay[day], late <= 0 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    public static func message(minutesLate: Int) -> (title: String, body: String) {
        switch minutesLate {
        case ..<30:
            return ("🪖 GO TO BED", "It's \(minutesLate) minutes past your bedtime. Phone down, recruit.")
        case ..<45:
            return ("🪖 GO TO BED. NOW.", "IT'S \(minutesLate) MINUTES PAST YOUR BEDTIME. Tomorrow's session is suffering already.")
        case ..<60:
            return ("🪖 BED. NOW. RECRUIT.", "\(minutesLate) MINUTES LATE. Muscles don't grow while you scroll.")
        default:
            return ("🪖 LAST WARNING", "AN HOUR PAST YOUR BEDTIME. I'm going to bed. You should have an hour ago.")
        }
    }
}

public struct SleepReport: Hashable {
    public struct Night: Hashable {
        public let night: SleepNight
        /// + = later than planned.
        public let bedMinutesOff: Int
        public let wakeMinutesOff: Int
        public var onSchedule: Bool { abs(bedMinutesOff) <= 30 && abs(wakeMinutesOff) <= 30 }
        public var late: Bool { bedMinutesOff > 30 }
    }
    public let nights: [Night]
    /// 0–100: 100 = every night within minutes of plan.
    public let score: Int?
    public let onScheduleStreak: Int
    public let lateNights7: Int
    public let averageHours7: Double?
    public var lastNight: Night? { nights.last }
}

public enum SleepAnalysis {
    /// The last 14 nights against your schedule.
    public static func report(nights: [SleepNight], schedule: SleepSchedule, now: Date = .now,
                              calendar: Calendar = .current) -> SleepReport {
        let since = now.addingTimeInterval(-14 * 86_400)
        let scored: [SleepReport.Night] = nights.filter { $0.date >= since }.sorted { $0.date < $1.date }.compactMap { night in
            guard let start = night.start, let end = night.end else { return nil }
            // The evening this sleep belongs to (bedtimes up to ~noon next day count for the night before).
            let evening = calendar.startOfDay(for: start.addingTimeInterval(-12 * 3600))
            let bed = schedule.bedtime(forNightOf: evening, calendar: calendar)
            let wake = schedule.wakeTime(forNightOf: evening, calendar: calendar)
            return SleepReport.Night(night: night, bedMinutesOff: Int(start.timeIntervalSince(bed) / 60),
                                     wakeMinutesOff: Int(end.timeIntervalSince(wake) / 60))
        }
        let score: Int? = scored.isEmpty ? nil : {
            let off = scored.map { Double(abs($0.bedMinutesOff) + abs($0.wakeMinutesOff)) / 2 }.reduce(0, +) / Double(scored.count)
            return max(0, min(100, Int((100 - off * 0.8).rounded())))   // 30 min off on average ≈ 76
        }()
        var streak = 0
        for night in scored.reversed() {
            guard night.onSchedule else { break }
            streak += 1
        }
        let week = scored.filter { $0.night.date >= now.addingTimeInterval(-7 * 86_400) }
        let hours = nights.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }.map(\.hoursAsleep)
        return SleepReport(nights: scored, score: score, onScheduleStreak: streak,
                           lateNights7: week.filter(\.late).count,
                           averageHours7: hours.isEmpty ? nil : hours.reduce(0, +) / Double(hours.count))
    }

    /// "+18 min" / "−5 min" / "on time".
    public static func offText(_ minutes: Int) -> String {
        abs(minutes) <= 5 ? "on time" : (minutes > 0 ? "+\(minutes) min late" : "\(-minutes) min early")
    }
}

// MARK: - Sergeant Cluck on your gym pattern

public enum CluckPatterns {
    /// One comment on the last 4–8 weeks (nil = nothing worth saying), and the weekday you keep skipping.
    public static func gym(logs: [WorkoutLog], plans: [DayPlan], weeklyGoal: Int, now: Date = .now,
                           calendar: Calendar = .current) -> (line: String?, skipWeekday: Int?) {
        let lifts = logs.filter { $0.countsAsTraining && $0.startedAt <= now }
        let today = calendar.startOfDay(for: now)
        let names = calendar.weekdaySymbols

        // A planned weekday you keep missing.
        var planned: [Int: Int] = [:]
        var done: [Int: Int] = [:]
        for plan in plans where plan.kind == .workout && plan.day < today && plan.day >= today.addingTimeInterval(-56 * 86_400) {
            let weekday = calendar.component(.weekday, from: plan.day)
            planned[weekday, default: 0] += 1
            if lifts.contains(where: { calendar.isDate($0.startedAt, inSameDayAs: plan.day) }) { done[weekday, default: 0] += 1 }
        }
        let skip = planned.filter { $0.value >= 2 && Double(done[$0.key] ?? 0) / Double($0.value) <= 0.4 }
            .max { $0.value < $1.value }?.key
        if let skip {
            return ("\(names[(skip - 1) % 7])s are a ghost town — planned \(planned[skip] ?? 0), done \(done[skip] ?? 0).", skip)
        }

        // Weeks under goal in a row.
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            var short = 0
            for offset in 1...4 {
                guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: week.start),
                      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start),
                      lifts.contains(where: { $0.startedAt < end }) else { break }
                guard lifts.filter({ $0.startedAt >= start && $0.startedAt < end }).count < weeklyGoal else { break }
                short += 1
            }
            if short >= 2 { return ("\(short) weeks in a row under your goal. That's a pattern, not a blip.", nil) }
        }

        // A long gap in the last 4 weeks.
        let recent = lifts.filter { $0.startedAt >= today.addingTimeInterval(-28 * 86_400) }.map(\.startedAt).sorted()
        if recent.count >= 2 {
            let longest = zip(recent, recent.dropFirst()).map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0),
                                                                                         to: calendar.startOfDay(for: $1)).day ?? 0 }.max() ?? 0
            if longest >= 6 { return ("You vanished for \(longest) days this month. Don't make me send a search party.", nil) }
        }

        // Sessions getting shorter.
        let lastTwo = lifts.filter { $0.startedAt >= today.addingTimeInterval(-14 * 86_400) }
        let before = lifts.filter { $0.startedAt < today.addingTimeInterval(-14 * 86_400) && $0.startedAt >= today.addingTimeInterval(-42 * 86_400) }
        if lastTwo.count >= 2, before.count >= 3 {
            let recentMinutes = lastTwo.map(\.duration).reduce(0, +) / Double(lastTwo.count) / 60
            let olderMinutes = before.map(\.duration).reduce(0, +) / Double(before.count) / 60
            if recentMinutes < olderMinutes * 0.75 {
                return ("Sessions are shrinking — \(Int(recentMinutes)) min lately vs \(Int(olderMinutes)). Half-effort is still half.", nil)
            }
        }

        // Strong start, fades by the end of the week.
        let month = lifts.filter { $0.startedAt >= today.addingTimeInterval(-28 * 86_400) }
        if month.count >= 6 {
            let early = month.filter { [2, 3].contains(calendar.component(.weekday, from: $0.startedAt)) }.count
            if Double(early) / Double(month.count) > 0.6 {
                return ("Strong Mondays, ghost by Thursday. Finish the week like you start it.", nil)
            }
        }
        return (nil, nil)
    }
}
