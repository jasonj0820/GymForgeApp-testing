import Foundation

// MARK: - MK24 (I): basketball beyond the Watch recording — shot chart, drills, interval timer, jumps, game stats

public struct Hoops: Codable, Equatable {
    public var shots: [Shot] = []
    public var drills: [Drill] = Drill.starters
    public var drillLogs: [DrillLog] = []
    public var jumps: [JumpEntry] = []
    public var games: [GameStats] = []
    public init() {}

    enum CodingKeys: String, CodingKey { case shots, drills, drillLogs, jumps, games }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shots = try c.decodeIfPresent([Shot].self, forKey: .shots) ?? []
        drills = try c.decodeIfPresent([Drill].self, forKey: .drills) ?? Drill.starters
        drillLogs = try c.decodeIfPresent([DrillLog].self, forKey: .drillLogs) ?? []
        jumps = try c.decodeIfPresent([JumpEntry].self, forKey: .jumps) ?? []
        games = try c.decodeIfPresent([GameStats].self, forKey: .games) ?? []
    }
}

/// A shot on a FIBA half court, in metres: x across (0 = middle), y out from the baseline.
public struct Shot: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var sessionID: UUID?
    public var x: Double
    public var y: Double
    public var made: Bool
    public init(date: Date = .now, sessionID: UUID? = nil, x: Double, y: Double, made: Bool) {
        self.date = date
        self.sessionID = sessionID
        self.x = x
        self.y = y
        self.made = made
    }
}

public enum CourtZone: String, CaseIterable, Identifiable {
    case paint, midRange, corner3, aboveBreak3
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .paint: return "Paint"
        case .midRange: return "Mid-range"
        case .corner3: return "Corner 3"
        case .aboveBreak3: return "Above-the-break 3"
        }
    }

    /// FIBA: court 15 m wide, hoop 1.575 m from the baseline, 3-point line 6.75 m (6.6 m in the corners, up to 2.99 m out), key 4.9 × 5.8 m.
    public static let width = 15.0, halfLength = 14.0, hoopY = 1.575
    public static func of(x: Double, y: Double) -> CourtZone {
        let distance = ((x * x) + (y - hoopY) * (y - hoopY)).squareRoot()
        if y < 2.99 && abs(x) >= 6.6 { return .corner3 }
        if y >= 2.99 && distance >= 6.75 { return .aboveBreak3 }
        if abs(x) <= 2.45 && y <= 5.8 { return .paint }
        return .midRange
    }
    public var isThree: Bool { self == .corner3 || self == .aboveBreak3 }
}

public enum ShotStats {
    public static func byZone(_ shots: [Shot]) -> [(zone: CourtZone, made: Int, attempts: Int)] {
        CourtZone.allCases.map { zone in
            let inZone = shots.filter { CourtZone.of(x: $0.x, y: $0.y) == zone }
            return (zone, inZone.filter(\.made).count, inZone.count)
        }
    }
}

public struct Drill: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "B0B0B0B0-0000-4000-8000-%012d", n)) ?? UUID() }
    public static let starters: [Drill] = [
        Drill(id: id(1), name: "Free throws"), Drill(id: id(2), name: "Form shooting (close)"),
        Drill(id: id(3), name: "Mikan drill"), Drill(id: id(4), name: "Mid-range around the key"),
        Drill(id: id(5), name: "3s around the world"), Drill(id: id(6), name: "Catch and shoot 3s"),
    ]
}

public struct DrillLog: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var drillID: UUID
    public var makes: Int
    public var attempts: Int
    public init(date: Date = .now, drillID: UUID, makes: Int, attempts: Int) {
        self.date = date
        self.drillID = drillID
        self.makes = makes
        self.attempts = attempts
    }
    public var percent: Double { attempts > 0 ? Double(makes) / Double(attempts) * 100 : 0 }
}

public struct JumpEntry: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var cm: Double
    public var running: Bool
    public init(date: Date = .now, cm: Double, running: Bool = false) {
        self.date = date
        self.cm = cm
        self.running = running
    }
}

public struct GameStats: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var sessionID: UUID?
    public var points = 0, rebounds = 0, assists = 0, steals = 0, blocks = 0, turnovers = 0
    public var fgMade = 0, fgAttempts = 0, threeMade = 0, threeAttempts = 0, ftMade = 0, ftAttempts = 0
    public init(date: Date = .now, sessionID: UUID? = nil) {
        self.date = date
        self.sessionID = sessionID
    }
    /// Points from the shots, when you'd rather count makes than points.
    public var pointsFromShots: Int { (fgMade - threeMade) * 2 + threeMade * 3 + ftMade }
}

public enum GameAverages {
    public struct Line: Equatable {
        public var games: Int
        public var points, rebounds, assists: Double
        public var fgPercent, threePercent, ftPercent: Double?
    }

    public static func make(_ games: [GameStats]) -> Line? {
        guard !games.isEmpty else { return nil }
        let n = Double(games.count)
        func pct(_ made: Int, _ att: Int) -> Double? { att > 0 ? Double(made) / Double(att) * 100 : nil }
        return Line(games: games.count,
                    points: Double(games.reduce(0) { $0 + $1.points }) / n,
                    rebounds: Double(games.reduce(0) { $0 + $1.rebounds }) / n,
                    assists: Double(games.reduce(0) { $0 + $1.assists }) / n,
                    fgPercent: pct(games.reduce(0) { $0 + $1.fgMade }, games.reduce(0) { $0 + $1.fgAttempts }),
                    threePercent: pct(games.reduce(0) { $0 + $1.threeMade }, games.reduce(0) { $0 + $1.threeAttempts }),
                    ftPercent: pct(games.reduce(0) { $0 + $1.ftMade }, games.reduce(0) { $0 + $1.ftAttempts }))
    }
}

/// Work / rest intervals for drills (139).
public struct IntervalPlan: Codable, Equatable {
    public var workSeconds: Int
    public var restSeconds: Int
    public var rounds: Int
    public init(workSeconds: Int = 30, restSeconds: Int = 30, rounds: Int = 10) {
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.rounds = rounds
    }
    public var totalSeconds: Int { rounds * workSeconds + max(rounds - 1, 0) * restSeconds }

    /// Where you are `elapsed` seconds in: round (1-based), working or resting, and seconds left in that phase. nil = finished.
    public func phase(at elapsed: Double) -> (round: Int, working: Bool, left: Double)? {
        guard elapsed >= 0, elapsed < Double(totalSeconds) else { return nil }
        let cycle = Double(workSeconds + restSeconds)
        let round = Int(elapsed / cycle)
        let into = elapsed - Double(round) * cycle
        if into < Double(workSeconds) { return (round + 1, true, Double(workSeconds) - into) }
        return (round + 1, false, cycle - into)
    }
}

// MARK: - MK24 (128): sleep debt and consistency

public enum SleepMath {
    /// Hours your schedule allows, averaged over the week (8 without a schedule).
    public static func need(_ schedule: SleepSchedule?) -> Double {
        guard let schedule else { return 8 }
        let hours = (1...7).map { day -> Double in
            let bed = schedule.bedMinutes(day), wake = schedule.wakeMinutes(day)
            let span = (wake + 24 * 60 - bed) % (24 * 60)
            return Double(span) / 60
        }
        return hours.reduce(0, +) / 7
    }

    /// Hours short over the last `days` nights (a long night pays some back; never below zero). Nights not recorded are left out.
    public static func debt(_ nights: [SleepNight], need: Double, days: Int = 14, now: Date = .now) -> (hours: Double, nights: Int) {
        let recent = nights.filter { $0.date > now.addingTimeInterval(-Double(days) * 86_400) && $0.date <= now && $0.hoursAsleep > 0 }
        let total = recent.reduce(0) { $0 + (need - $1.hoursAsleep) }
        return (max(total, 0), recent.count)
    }

    /// How much your sleep time moves night to night: the spread (standard deviation, minutes) of when you fell asleep.
    public static func bedtimeSpread(_ nights: [SleepNight], days: Int = 14, now: Date = .now, calendar: Calendar = .current) -> Double? {
        let starts = nights.filter { $0.date > now.addingTimeInterval(-Double(days) * 86_400) }.compactMap(\.start)
        guard starts.count >= 4 else { return nil }
        // Minutes from 6 pm, so 11:30 pm and 12:30 am sit an hour apart.
        let minutes = starts.map { date -> Double in
            let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            return Double((m - 18 * 60 + 24 * 60) % (24 * 60))
        }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        return (minutes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(minutes.count)).squareRoot()
    }
}
