import Foundation

// MARK: - MK24 (72): a goal per lift, with the date you'll get there at your current rate

public enum GoalProjection {
    public enum Outcome: Equatable {
        /// Already lifted it (first time).
        case reached(Date)
        /// On track: the projected date and the rate (kg per week).
        case onTrack(Date, perWeek: Double)
        /// Not climbing (or too slowly to say).
        case flat(perWeek: Double)
        /// Fewer than 3 sessions over 2+ weeks in the last 12.
        case tooFew
    }

    /// `points`: the heaviest weight of each session. Least-squares trend over the last 12 weeks.
    public static func project(_ points: [(date: Date, value: Double)], target: Double, now: Date = .now) -> Outcome {
        let sorted = points.filter { $0.value > 0 }.sorted { $0.date < $1.date }
        if let hit = sorted.first(where: { $0.value >= target }) { return .reached(hit.date) }
        let recent = sorted.filter { $0.date > now.addingTimeInterval(-84 * 86_400) && $0.date <= now }
        guard recent.count >= 3, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 14 * 86_400 else { return .tooFew }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map(\.value)
        let n = Double(recent.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
        guard sxx > 0 else { return .tooFew }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx   // kg per day
        let perWeek = slope * 7
        guard perWeek >= 0.1 else { return .flat(perWeek: perWeek) }
        let nowX = now.timeIntervalSince(first.date) / 86_400
        let current = max(my + slope * (nowX - mx), last.value)
        let days = (target - current) / slope
        guard days.isFinite, days <= 730 else { return .flat(perWeek: perWeek) }
        return .onTrack(now.addingTimeInterval(max(days, 0) * 86_400), perWeek: perWeek)
    }
}

// MARK: - MK24 (74): accessory rotation each training block

public enum AccessoryRotation {
    public struct Swap: Identifiable, Equatable {
        public let routineID: UUID
        public let itemID: UUID
        public let routineName: String
        public let from: String
        public let to: ExerciseDefinition
        public var id: UUID { itemID }
    }

    static let isolation: Set<ExerciseCategory> = [.biceps, .triceps, .shoulders, .calves, .core]

    /// Isolation work, or anything from the 4th exercise on. Main lifts stay put so they keep progressing.
    public static func isAccessory(_ item: RoutineExercise, position: Int) -> Bool {
        !item.exercise.isCardio && (isolation.contains(item.exercise.category) || position >= 3)
    }

    /// Each accessory with a swap option moves to its last option (the one used longest ago), so
    /// A → C → B → A cycles through all of them.
    public static func plan(_ routines: [WorkoutRoutine]) -> [Swap] {
        routines.flatMap { routine in
            routine.exercises.enumerated().compactMap { position, item -> Swap? in
                guard isAccessory(item, position: position),
                      let next = item.exercise.alternativeList.last(where: { !$0.isCardio }) else { return nil }
                return Swap(routineID: routine.id, itemID: item.id, routineName: routine.name, from: item.exercise.name, to: next)
            }
        }
    }
}
