import Foundation

// MARK: - MK24 (151): streak freezes you earn

public enum StreakFreeze {
    public enum Week: Equatable { case hit, miss, pause }

    /// Oldest week first. Every 4 goal weeks in a row earn a freeze (2 at most); a missed week spends one
    /// instead of ending the streak. Paused (break) weeks neither count nor break it.
    public static func run(_ weeks: [Week], earnEvery: Int = 4, bank maxBank: Int = 2) -> (streak: Int, banked: Int, used: Int) {
        var streak = 0, banked = 0, used = 0, sinceEarned = 0
        for week in weeks {
            switch week {
            case .pause:
                continue
            case .hit:
                streak += 1
                sinceEarned += 1
                if sinceEarned >= earnEvery {
                    banked = min(banked + 1, maxBank)
                    sinceEarned = 0
                }
            case .miss:
                if banked > 0 {
                    banked -= 1
                    used += 1
                } else {
                    streak = 0
                    sinceEarned = 0
                }
            }
        }
        return (streak, banked, used)
    }

    public static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "streak.freezes") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "streak.freezes") }
    }
}

// MARK: - MK24 (150): milestone badges

public struct Badge: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String
    public let earned: Bool
    /// 0…1 toward it.
    public let progress: Double
}

public enum Milestones {
    public struct Totals: Equatable {
        public var sessions: Int
        public var bestStreakWeeks: Int
        public var prs: Int
        public var volumeTonnes: Double
        public var routineSteps: Int
        public var proteinDaysInARow: Int
        public init(sessions: Int, bestStreakWeeks: Int, prs: Int, volumeTonnes: Double, routineSteps: Int, proteinDaysInARow: Int) {
            self.sessions = sessions
            self.bestStreakWeeks = bestStreakWeeks
            self.prs = prs
            self.volumeTonnes = volumeTonnes
            self.routineSteps = routineSteps
            self.proteinDaysInARow = proteinDaysInARow
        }
    }

    public static func badges(_ t: Totals) -> [Badge] {
        func ladder(_ key: String, _ value: Double, _ steps: [Double], icon: String, title: (Double) -> String, detail: String) -> [Badge] {
            steps.map { step in
                Badge(id: "\(key).\(Int(step))", title: title(step), detail: detail, icon: icon,
                      earned: value >= step, progress: min(value / step, 1))
            }
        }
        return ladder("sessions", Double(t.sessions), [10, 25, 50, 100, 250, 500], icon: "dumbbell.fill",
                      title: { "\(Int($0)) sessions" }, detail: "Workouts logged")
            + ladder("streak", Double(t.bestStreakWeeks), [4, 8, 12, 26, 52], icon: "flame.fill",
                     title: { "\(Int($0))-week streak" }, detail: "Weeks in a row on goal")
            + ladder("prs", Double(t.prs), [10, 50, 100, 250], icon: "trophy.fill",
                     title: { "\(Int($0)) records" }, detail: "Personal records set")
            + ladder("volume", t.volumeTonnes, [10, 100, 500, 1000], icon: "scalemass.fill",
                     title: { "\(Int($0)) tonnes" }, detail: "Total weight lifted")
            + ladder("routine", Double(t.routineSteps), [100, 500, 1000], icon: "checklist",
                     title: { "\(Int($0)) routine steps" }, detail: "Steps ticked")
            + ladder("protein", Double(t.proteinDaysInARow), [7, 30], icon: "fork.knife",
                     title: { "\(Int($0)) days of protein" }, detail: "Target hit, days in a row")
    }

    /// Days in a row (ending today or yesterday) that hit the protein target.
    public static func proteinRun(_ days: [NutritionDay], target: Double, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard target > 0 else { return 0 }
        var run = 0
        var day = calendar.startOfDay(for: now)
        // Today only counts once it's hit; otherwise start from yesterday.
        if !(days.first { calendar.isDate($0.day, inSameDayAs: day) }.map { $0.proteinG >= target } ?? false) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while let entry = days.first(where: { calendar.isDate($0.day, inSameDayAs: day) }), entry.proteinG >= target {
            run += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            if run > 400 { break }
        }
        return run
    }
}

// MARK: - MK24 (145): quiet hours and the at-work / in-class window

public struct QuietWindow: Codable, Equatable {
    public var start: Int   // minutes after midnight
    public var end: Int
    public var weekdays: Set<Int>   // 1 = Sunday; the day the window starts on
    public init(start: Int, end: Int, weekdays: Set<Int> = Set(1...7)) {
        self.start = start
        self.end = end
        self.weekdays = weekdays
    }

    /// Windows can run past midnight (22:30 → 6:30).
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let weekday = calendar.component(.weekday, from: date)
        if start <= end {
            return weekdays.contains(weekday) && minutes >= start && minutes < end
        }
        // Overnight: the evening part belongs to today, the early part to yesterday's window.
        let yesterday = weekday == 1 ? 7 : weekday - 1
        return (weekdays.contains(weekday) && minutes >= start) || (weekdays.contains(yesterday) && minutes < end)
    }

    /// The first moment at or after `date` outside every window (checked in 5-minute steps, up to a day).
    public static func firstFree(after date: Date, windows: [QuietWindow], calendar: Calendar = .current) -> Date {
        var time = date
        for _ in 0..<(24 * 12) {
            if !windows.contains(where: { $0.contains(time, calendar: calendar) }) { return time }
            time = time.addingTimeInterval(300)
        }
        return date
    }
}
