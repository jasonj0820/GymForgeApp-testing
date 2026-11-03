import Foundation

// MK9.1: runs (outdoor GPS or treadmill) and basketball as their own workouts — recorded by the Watch,
// or (MK10) by the iPhone or logged afterwards, with an effort rating instead of heart rate.

public enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case run, basketball
    public var id: String { rawValue }
}

public enum BasketballType: String, Codable, CaseIterable, Identifiable {
    case game, shooting, training
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .game: return "Pickup game"
        case .shooting: return "Shooting practice"
        case .training: return "Training session"
        }
    }
}

/// A run target: distance, time, or a pace to hold (seconds per km).
public struct RunGoal: Codable, Hashable {
    public enum Kind: String, Codable, CaseIterable, Identifiable {
        case open, distance, time, pace
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .open: return "Open"
            case .distance: return "Distance"
            case .time: return "Time"
            case .pace: return "Pace"
            }
        }
    }
    public var kind: Kind
    public var distanceKm: Double?
    public var minutes: Double?
    public var paceSeconds: Double?

    public init(kind: Kind = .open, distanceKm: Double? = nil, minutes: Double? = nil, paceSeconds: Double? = nil) {
        self.kind = kind
        self.distanceKm = distanceKm
        self.minutes = minutes
        self.paceSeconds = paceSeconds
    }

    public var title: String {
        switch kind {
        case .open: return "Open run"
        case .distance: return "\(GFFormat.km(distanceKm ?? 0)) km"
        case .time: return "\(Int(minutes ?? 0)) min"
        case .pace: return "Hold \(CardioFormat.pace(paceSeconds ?? 0)) /km"
        }
    }
}

/// iPhone → Watch (or made on the Watch): what to start.
public struct ActivityRequest: Codable, Hashable, Identifiable {
    public var id: UUID
    public var kind: ActivityKind
    public var indoor: Bool
    public var goal: RunGoal?
    public var basketballType: BasketballType?
    public var maxHeartRate: Double
    public var requestedAt: Date

    public init(id: UUID = UUID(), kind: ActivityKind, indoor: Bool, goal: RunGoal? = nil,
                basketballType: BasketballType? = nil, maxHeartRate: Double, requestedAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.indoor = indoor
        self.goal = goal
        self.basketballType = basketballType
        self.maxHeartRate = maxHeartRate
        self.requestedAt = requestedAt
    }

    public var title: String {
        switch kind {
        case .run: return indoor ? "Treadmill Run" : "Outdoor Run"
        case .basketball: return "Basketball"
        }
    }
}

/// Watch → iPhone every ~10 s while running (for the Lock Screen Live Activity).
public struct ActivityProgress: Codable, Hashable {
    public var id: UUID
    public var kind: ActivityKind
    public var title: String
    public var startedAt: Date
    public var elapsed: Double
    public var distanceKm: Double
    public var paceSeconds: Double?
    public var heartRate: Double
    public var isPaused: Bool

    public init(id: UUID, kind: ActivityKind, title: String, startedAt: Date, elapsed: Double, distanceKm: Double,
                paceSeconds: Double?, heartRate: Double, isPaused: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.elapsed = elapsed
        self.distanceKm = distanceKm
        self.paceSeconds = paceSeconds
        self.heartRate = heartRate
        self.isPaused = isPaused
    }
}

public struct RoutePoint: Codable, Hashable {
    public var lat: Double
    public var lon: Double
    public var t: Date
    public init(lat: Double, lon: Double, t: Date) {
        self.lat = lat
        self.lon = lon
        self.t = t
    }
}

/// A finished run or basketball session.
public struct CardioSession: Codable, Identifiable, Hashable {
    public var id: UUID
    public var kind: ActivityKind
    public var indoor: Bool
    public var startedAt: Date
    public var endedAt: Date
    /// Moving time (pauses excluded).
    public var activeSeconds: Double
    public var distanceKm: Double?
    public var activeCalories: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// Seconds for each full km.
    public var splits: [Double]
    public var route: [RoutePoint]?
    public var goal: RunGoal?
    /// Seconds in heart-rate zones 1–5.
    public var zoneSeconds: [Double]
    public var cadence: Double?
    public var powerWatts: Double?
    public var strideMeters: Double?
    public var basketballType: BasketballType?
    public var minutesPlayed: Double?
    public var shotsMade: Int?
    public var shotsAttempted: Int?
    /// Treadmill distance corrected by hand afterwards.
    public var distanceCorrected: Bool?
    /// MK10: how hard it felt, 1–10 (your rating; needed when there's no heart rate).
    public var effort: Int?
    /// "watch", "phone" or "manual" (nil = Watch, from before MK10).
    public var recordedOn: String?

    public init(id: UUID, kind: ActivityKind, indoor: Bool, startedAt: Date, endedAt: Date, activeSeconds: Double,
                distanceKm: Double? = nil, activeCalories: Double? = nil, averageHeartRate: Double? = nil,
                maxHeartRate: Double? = nil, splits: [Double] = [], route: [RoutePoint]? = nil, goal: RunGoal? = nil,
                zoneSeconds: [Double] = [0, 0, 0, 0, 0], basketballType: BasketballType? = nil) {
        self.id = id
        self.kind = kind
        self.indoor = indoor
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeSeconds = activeSeconds
        self.distanceKm = distanceKm
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.splits = splits
        self.route = route
        self.goal = goal
        self.zoneSeconds = zoneSeconds
        self.basketballType = basketballType
    }

    public var title: String {
        switch kind {
        case .run: return indoor ? "Treadmill Run" : "Outdoor Run"
        case .basketball: return "Basketball"
        }
    }

    /// Average pace, seconds per km.
    public var averagePace: Double? {
        guard let distanceKm, distanceKm > 0.05, activeSeconds > 0 else { return nil }
        return activeSeconds / distanceKm
    }

    /// Metres per heartbeat: goes up as you get fitter (same pace for less heart rate).
    public var efficiency: Double? {
        guard let distanceKm, distanceKm > 0.5, let hr = averageHeartRate, hr > 0, activeSeconds > 0 else { return nil }
        return distanceKm * 1000 / (hr * activeSeconds / 60)
    }

    /// 1–10 from time in each zone (higher zones count more).
    public var effortScore: Int {
        let weighted = zoneSeconds.enumerated().reduce(0.0) { $0 + $1.element / 60 * Double($1.offset + 1) }
        return Swift.min(10, Swift.max(1, Int((weighted / 25).rounded())))
    }

    public var shootingPercent: Double? {
        guard let made = shotsMade, let attempted = shotsAttempted, attempted > 0 else { return nil }
        return Double(made) / Double(attempted) * 100
    }

    /// Same session as a workout log, so it shows on the week row (MK10.2: as an extra, not a session).
    public var workoutLog: WorkoutLog {
        let routineID = kind == .run ? CardioIDs.run : CardioIDs.basketball
        let set = WorkoutSetLog(setNumber: 1, weightKg: 0, reps: 0, completedAt: endedAt,
                                durationSeconds: activeSeconds, distanceKm: (distanceKm ?? 0) > 0 ? distanceKm : nil)
        let exercise = ExerciseLog(exerciseID: routineID, exerciseName: title, repMinAtTime: 0, repMaxAtTime: 0,
                                   weightIncrementKgAtTime: 0, sets: [set], category: .cardio)
        return WorkoutLog(id: id, routineID: routineID, routineName: kind == .run ? "Run" : "Basketball",
                          startedAt: startedAt, endedAt: endedAt, exercises: [exercise],
                          activeCaloriesKcal: activeCalories, averageHeartRateBPM: averageHeartRate,
                          maxHeartRateBPM: maxHeartRate, source: kind.rawValue)
    }
}

public enum CardioIDs {
    public static let run = UUID(uuidString: "6A1F0000-0000-4000-8000-0000000C0001") ?? UUID()
    public static let basketball = UUID(uuidString: "6A1F0000-0000-4000-8000-0000000C0002") ?? UUID()
}

public enum CardioFormat {
    /// 312 → "5:12".
    public static func pace(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "–:––" }
        let total = Int(seconds.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

public enum HeartZones {
    /// 0…4 for zones 1–5 (50–60, 60–70, 70–80, 80–90, 90%+ of max), or nil below zone 1.
    public static func zone(heartRate: Double, max: Double) -> Int? {
        guard heartRate > 0, max > 0 else { return nil }
        let percent = heartRate / max
        switch percent {
        case ..<0.5: return nil
        case ..<0.6: return 0
        case ..<0.7: return 1
        case ..<0.8: return 2
        case ..<0.9: return 3
        default: return 4
        }
    }

    /// Your setting, or the highest heart rate seen in the last year (at least 180), or 190.
    public static func estimatedMax(profile: UserProfile?, logs: [WorkoutLog], sessions: [CardioSession] = [], now: Date = .now) -> Double {
        if let set = profile?.maxHeartRateSetting, set > 120 { return Double(set) }
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let seen = (logs.filter { $0.startedAt >= yearAgo }.compactMap(\.maxHeartRateBPM)
                    + sessions.filter { $0.startedAt >= yearAgo }.compactMap(\.maxHeartRate)).max() ?? 0
        return seen >= 150 ? Swift.max(seen, 180) : 190
    }
}

public enum RunStats {
    /// Fastest single km split.
    public static func best1k(_ sessions: [CardioSession]) -> (seconds: Double, date: Date)? {
        var best: (Double, Date)?
        for session in sessions where session.kind == .run {
            for split in session.splits where split > 120 && split < (best?.0 ?? .infinity) { best = (split, session.startedAt) }
        }
        return best.map { (seconds: $0.0, date: $0.1) }
    }

    /// Fastest 5 consecutive km.
    public static func best5k(_ sessions: [CardioSession]) -> (seconds: Double, date: Date)? {
        var best: (Double, Date)?
        for session in sessions where session.kind == .run && session.splits.count >= 5 {
            for start in 0...(session.splits.count - 5) {
                let total = session.splits[start..<(start + 5)].reduce(0, +)
                if total < (best?.0 ?? .infinity) { best = (total, session.startedAt) }
            }
        }
        return best.map { (seconds: $0.0, date: $0.1) }
    }
}


// MARK: - MK10.2: only weight training counts as a session

public extension WorkoutLog {
    /// A gym session with at least one strength exercise. Runs, basketball and cardio-only sessions
    /// are extras: they show on the week row but don't count toward the weekly goal, streak or Sergeant Cluck.
    var countsAsTraining: Bool {
        routineID != CardioIDs.run && routineID != CardioIDs.basketball && exercises.contains { !$0.isCardio }
    }
}
