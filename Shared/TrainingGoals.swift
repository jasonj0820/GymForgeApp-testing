import Foundation

/// MK11.1: separate weekly goals — lifting (the existing weekly goal), running, and basketball tracked on its own.
/// nil / 0 = no goal (basketball is still counted).
public struct TrainingGoals: Codable, Hashable {
    public var runsPerWeek: Int?
    public var runKmPerWeek: Double?
    public var basketballPerWeek: Int?

    public init(runsPerWeek: Int? = nil, runKmPerWeek: Double? = nil, basketballPerWeek: Int? = nil) {
        self.runsPerWeek = runsPerWeek
        self.runKmPerWeek = runKmPerWeek
        self.basketballPerWeek = basketballPerWeek
    }
}

public struct GoalProgress: Hashable, Identifiable {
    public enum Kind: String { case lifting, runs, runKm, basketball }
    public let kind: Kind
    public let title: String
    public let done: Double
    /// nil = tracked only.
    public let target: Double?
    public var id: String { kind.rawValue }
    public var met: Bool { target.map { done >= $0 } ?? false }
    public var fraction: Double { target.map { $0 > 0 ? min(done / $0, 1) : 0 } ?? 0 }

    public var text: String {
        let value = kind == .runKm ? String(format: "%.1f", done) : "\(Int(done))"
        let unit = kind == .runKm ? " km" : ""
        guard let target else { return "\(value)\(unit) this week" }
        let goal = kind == .runKm ? String(format: "%.0f", target) : "\(Int(target))"
        return "\(value) / \(goal)\(unit)"
    }
}

public enum TrainingGoalTracker {
    /// This week's progress: lifting always, running when a goal is set, basketball whenever you play or have a goal.
    public static func progress(goals: TrainingGoals?, liftGoal: Int, logs: [WorkoutLog], cardio: [CardioSession],
                                now: Date = .now, calendar: Calendar = .current) -> [GoalProgress] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let inWeek: (Date) -> Bool = { $0 >= week.start && $0 < week.end && $0 <= now }
        let lifts = logs.filter { $0.countsAsTraining && inWeek($0.startedAt) }.count
        let runs = cardio.filter { $0.kind == .run && inWeek($0.startedAt) }
        let games = cardio.filter { $0.kind == .basketball && inWeek($0.startedAt) }.count
        var result = [GoalProgress(kind: .lifting, title: "Lifting", done: Double(lifts), target: Double(max(liftGoal, 1)))]
        if let target = goals?.runsPerWeek, target > 0 {
            result.append(GoalProgress(kind: .runs, title: "Runs", done: Double(runs.count), target: Double(target)))
        }
        if let target = goals?.runKmPerWeek, target > 0 {
            result.append(GoalProgress(kind: .runKm, title: "Running distance", done: runs.reduce(0) { $0 + ($1.distanceKm ?? 0) }, target: target))
        }
        let ballGoal = goals?.basketballPerWeek ?? 0
        if ballGoal > 0 || games > 0 {
            result.append(GoalProgress(kind: .basketball, title: "Basketball", done: Double(games), target: ballGoal > 0 ? Double(ballGoal) : nil))
        }
        return result
    }
}
