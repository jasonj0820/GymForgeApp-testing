import Foundation

// MK9.1: the coach's training brain. It never changes your routines by itself — it proposes changes
// you accept or decline, each with a one-line reason.

public enum TrainingFocus: String, Codable, CaseIterable, Identifiable {
    case size, strength
    public var id: String { rawValue }
    public var title: String { self == .size ? "Size" : "Strength" }
}

public extension UserProfile {
    var focus: TrainingFocus {
        get { TrainingFocus(rawValue: trainingFocus ?? "") ?? .size }
        set { trainingFocus = newValue.rawValue }
    }
}

/// One suggested change.
public struct CoachProposal: Identifiable, Hashable {
    public enum Change: Hashable {
        case sets(routineID: UUID, itemID: UUID, to: Int)
        case repRange(routineID: UUID, itemID: UUID, min: Int, max: Int)
        case rest(routineID: UUID, itemID: UUID, seconds: Int)
        case moveBefore(routineID: UUID, itemID: UUID, beforeItemID: UUID)
        case addExercise(routineID: UUID, name: String, sets: Int)
        /// Replace the exercise with a library one (the old one stays as a swap option).
        case swapExercise(routineID: UUID, itemID: UUID, name: String)
        case deload
        case info
    }

    /// Stable, so a declined suggestion stays hidden for a while.
    public let id: String
    public let title: String
    public let reason: String
    public let change: Change
    public let muscle: Muscle?
    /// Higher shows first.
    public let priority: Int

    public init(id: String, title: String, reason: String, change: Change, muscle: Muscle? = nil, priority: Int) {
        self.id = id
        self.title = title
        self.reason = reason
        self.change = change
        self.muscle = muscle
        self.priority = priority
    }
}

public struct MuscleStatus: Identifiable, Hashable {
    public let muscle: Muscle
    /// Hard sets per week (secondary work counts half): what you've actually done lately, and what's planned.
    public let actual: Double?
    public let planned: Double
    /// Strength change of the exercises that train it, % over the last ~4 weeks vs the 4 before.
    public let trend: Double?
    public var id: Muscle { muscle }
    public var low: Double { muscle.weeklyRange.low }
    public var high: Double { muscle.weeklyRange.high }
    public var current: Double { actual ?? planned }
}

public enum CoachBrain {
    static let day: TimeInterval = 86_400

    // MARK: Volume

    /// Effective hard sets per muscle in a window (each set × the exercise's contribution: 1 or 0.5).
    public static func muscleSets(logs: [WorkoutLog], from start: Date, to end: Date) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for workout in logs where workout.startedAt >= start && workout.startedAt < end && workout.isDeload != true {
            for exercise in workout.exercises where !exercise.isCardio {
                let muscles = ExerciseLibrary.muscles(for: exercise.exerciseName, category: exercise.category)
                // Sets with 4+ reps left count as half (MK10).
                let sets = exercise.sets.reduce(0.0) { $0 + $1.hardSetValue }
                for (muscle, share) in muscles { result[muscle, default: 0] += sets * share }
            }
        }
        return result
    }

    /// Gym sessions only (no runs, basketball or deload weeks).
    static func liftLogs(_ logs: [WorkoutLog]) -> [WorkoutLog] {
        logs.filter { log in
            log.isDeload != true && log.routineID != CardioIDs.run && log.routineID != CardioIDs.basketball
                && log.exercises.contains { !$0.isCardio }
        }
    }

    /// Whole weeks of gym history up to `cap` (at least 1), so a new user isn't averaged over weeks they didn't train.
    static func historyWeeks(_ lifts: [WorkoutLog], window: Int, now: Date) -> Int {
        guard let first = lifts.map(\.startedAt).min() else { return 0 }
        let weeks = Int((now.timeIntervalSince(first) / (7 * day)).rounded(.up))
        return min(window, max(1, weeks))
    }

    /// How often each routine is done per week (last 4 weeks); 1 each if there's no history yet.
    public static func routineFrequency(routines: [WorkoutRoutine], logs: [WorkoutLog], now: Date = .now) -> [UUID: Double] {
        let lifts = liftLogs(logs)
        let start = now.addingTimeInterval(-28 * day)
        let recent = lifts.filter { $0.startedAt >= start && $0.startedAt <= now }
        let weeks = Double(historyWeeks(lifts.filter { $0.startedAt <= now }, window: 4, now: now))
        var result: [UUID: Double] = [:]
        for routine in routines where !routine.exercises.isEmpty
            && routine.id != CardioIDs.run && routine.id != CardioIDs.basketball {
            let count = recent.filter { $0.routineID == routine.id }.count
            result[routine.id] = recent.isEmpty ? 1 : Double(count) / max(weeks, 1)
        }
        return result
    }

    /// Planned weekly sets per muscle from your routines and how often you do them.
    public static func plannedSets(routines: [WorkoutRoutine], frequency: [UUID: Double]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for routine in routines {
            let times = frequency[routine.id] ?? 0
            guard times > 0 else { continue }
            for item in routine.exercises where !item.exercise.isCardio {
                let muscles = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)
                for (muscle, share) in muscles { result[muscle, default: 0] += Double(item.exercise.defaultSets) * share * times }
            }
        }
        return result
    }

    /// Strength trend for a muscle: best e1RM (or least assistance) of each exercise that trains it
    /// directly, last 28 days vs the 28 before, averaged. nil = not enough data.
    public static func strengthTrend(_ muscle: Muscle, logs: [WorkoutLog], now: Date = .now) -> Double? {
        var recent: [String: Double] = [:]
        var before: [String: Double] = [:]
        var assisted = Set<String>()
        for workout in logs where workout.startedAt >= now.addingTimeInterval(-56 * day) && !workout.isAtypical {
            for exercise in workout.exercises where !exercise.isCardio {
                guard ExerciseLibrary.muscles(for: exercise.exerciseName, category: exercise.category)[muscle] ?? 0 >= 1 else { continue }
                let key = exercise.trendKey   // MK17: a paused / wide-grip block isn't a strength drop
                let value: Double
                if exercise.isAssisted {
                    guard let least = exercise.leastAssistanceKg, least >= 0 else { continue }
                    value = least
                    assisted.insert(key)
                } else {
                    value = exercise.estimatedOneRepMaxKg
                    guard value > 0 else { continue }
                }
                let isRecent = workout.startedAt >= now.addingTimeInterval(-28 * day)
                if assisted.contains(key) {
                    if isRecent { recent[key] = min(recent[key] ?? .infinity, value) } else { before[key] = min(before[key] ?? .infinity, value) }
                } else {
                    if isRecent { recent[key] = max(recent[key] ?? 0, value) } else { before[key] = max(before[key] ?? 0, value) }
                }
            }
        }
        var changes: [Double] = []
        for (key, latest) in recent {
            guard let then = before[key], then > 0, then.isFinite, latest.isFinite else { continue }
            if assisted.contains(key) {
                guard latest >= 0 else { continue }
                changes.append((then - latest) / then * 100)   // less assistance = stronger
            } else {
                guard latest > 0 else { continue }
                changes.append((latest / then - 1) * 100)
            }
        }
        guard !changes.isEmpty else { return nil }
        return changes.reduce(0, +) / Double(changes.count)
    }

    /// Share of effort-rated sets in the last 14 days taken to failure.
    public static func failureShare(logs: [WorkoutLog], now: Date = .now) -> Double {
        let rated = logs.filter { $0.startedAt >= now.addingTimeInterval(-14 * day) }
            .flatMap { $0.exercises.flatMap(\.sets) }.compactMap(\.rir)
        guard rated.count >= 6 else { return 0 }
        return Double(rated.filter { $0 == 0 }.count) / Double(rated.count)
    }

    public static func status(routines: [WorkoutRoutine], logs: [WorkoutLog], now: Date = .now) -> [MuscleStatus] {
        let frequency = routineFrequency(routines: routines, logs: logs, now: now)
        let planned = plannedSets(routines: routines, frequency: frequency)
        let lifts = liftLogs(logs).filter { $0.startedAt <= now }
        let trainedLately = lifts.contains { $0.startedAt >= now.addingTimeInterval(-21 * day) }
        let historyWeeks = trainedLately ? Self.historyWeeks(lifts, window: 3, now: now) : 0
        let actual = historyWeeks > 0 ? muscleSets(logs: lifts, from: now.addingTimeInterval(-21 * day), to: now) : [:]
        return Muscle.allCases.map { muscle in
            MuscleStatus(muscle: muscle,
                         actual: historyWeeks > 0 ? (actual[muscle] ?? 0) / Double(historyWeeks) : nil,
                         planned: planned[muscle] ?? 0,
                         trend: strengthTrend(muscle, logs: logs, now: now))
        }
    }

    // MARK: Suggestions

    /// Changes worth making, most important first. `declined` hides ones you said no to recently.
    public static func proposals(routines: [WorkoutRoutine], logs: [WorkoutLog], profile: UserProfile,
                                 priorities: [ExerciseCategory], readinessLow: Bool = false,
                                 declined: Set<String> = [], now: Date = .now) -> [CoachProposal] {
        proposals(routines: routines, logs: logs, profile: profile,
                  context: CoachInputs(priorities: priorities, readinessLow: readinessLow, declined: declined, now: now))
    }

    /// MK10: everything — volume, blocks, stalls, pain, diet phase, consistency.
    public static func proposals(routines: [WorkoutRoutine], logs: [WorkoutLog], profile: UserProfile,
                                 context: CoachInputs) -> [CoachProposal] {
        let now = context.now
        let priorities = context.priorities
        let readinessLow = context.readinessLow
        let declined = context.declined
        let cutting = context.nutritionPhase == .cutting
        let bulking = context.nutritionPhase == .bulking
        var result: [CoachProposal] = []
        let statuses = status(routines: routines, logs: logs, now: now)
        let failure = failureShare(logs: logs, now: now)
        let recovering = failure < 0.4 && !readinessLow
        let lifts = liftLogs(logs)
        let enoughHistory = lifts.contains { $0.startedAt <= now.addingTimeInterval(-35 * day) }
            && lifts.contains { $0.startedAt >= now.addingTimeInterval(-10 * day) }

        // Volume and progress per muscle.
        var regressing = 0
        for status in statuses {
            let muscle = status.muscle
            let isPriority = priorities.contains(muscle.category)
            let middle = (status.low + status.high) / 2
            // On a cut, the bottom of the range is enough; on a bulk, priorities aim a little higher.
            let target = cutting ? status.low : (isPriority ? (bulking ? Swift.min(status.high, middle + 2) : middle) : status.low)
            if status.low > 0, status.current < target - 1 {
                let gap = Int((target - status.current).rounded(.up))
                result += addVolume(for: muscle, sets: min(max(gap, 1), 3), routines: routines,
                                    reason: "\(muscle.title): ~\(format(status.current)) sets/week — \(isPriority ? "a priority wants" : "most people grow from") \(format(target))+.",
                                    priority: isPriority ? 90 : 70)
                continue
            }
            guard enoughHistory, let trend = status.trend else { continue }
            if trend <= -3 {
                regressing += 1
                if status.current > status.low + 2 {
                    result += removeVolume(for: muscle, routines: routines,
                                           reason: String(format: "%@ strength down %.0f%% in 4 weeks with %@ sets/week — cut a little volume so you recover.",
                                                          muscle.title, -trend, format(status.current)),
                                           priority: 75)
                }
            } else if trend < 1, recovering, !cutting, status.low > 0,
                      max(status.actual ?? 0, status.planned) < status.muscle.weeklyCeiling - 2 {
                result += addVolume(for: muscle, sets: 2, routines: routines,
                                    reason: "\(muscle.title) strength has been flat for ~4 weeks and you're recovering well — 2 more sets a week.",
                                    priority: 65)
            } else if status.current > status.muscle.weeklyCeiling {
                result += removeVolume(for: muscle, routines: routines,
                                       reason: "\(muscle.title): ~\(format(status.current)) sets/week is past where extra sets help. Trim it and recover better.",
                                       priority: 55)
            }
        }
        if enoughHistory, regressing >= 3 || (readinessLow && failure >= 0.5) {
            result.append(CoachProposal(id: "deload", title: "Take a deload week",
                                        reason: regressing >= 3 ? "Strength is down on \(regressing) muscle groups — a lighter week usually brings it back."
                                                                : "Lots of sets to failure and low readiness — a lighter week will pay off.",
                                        change: .deload, priority: 95))
        }

        // Block weeks 2+: add a set a week where you're recovering well (up to 2 muscles a week).
        let deloadNow = profile.isDeloadActive(at: now)
        if let position = profile.program?.position(at: now), position.block.phase != .deload, position.week >= 2,
           recovering, !cutting, !deloadNow {
            let already = Set(result.compactMap(\.muscle))
            let candidates = statuses.filter { status in
                guard status.low > 0, !already.contains(status.muscle), (status.trend ?? 0) > -1 else { return false }
                let isPriority = priorities.contains(status.muscle.category)
                let cap = isPriority ? status.high - 2 : (status.low + status.high) / 2
                return Swift.max(status.actual ?? 0, status.planned) < cap
            }.sorted { a, b in
                let pa = priorities.contains(a.muscle.category), pb = priorities.contains(b.muscle.category)
                if pa != pb { return pa }
                return (a.current - a.low) < (b.current - b.low)
            }
            for status in candidates.prefix(2) {
                if let ramp = addVolume(for: status.muscle, sets: 1, routines: routines, reason: "", priority: 68).first {
                    result.append(ramp.with(id: "ramp-\(weekKey(now))-\(status.muscle.rawValue)",
                                            reason: "Block week \(position.week): you're recovering well, so one more \(status.muscle.title.lowercased()) set this week (~\(format(status.current)) now)."))
                }
            }
        }

        // Stuck lifts: one diagnosis each (the "recover first" / "fine on a cut" ones are combined into one card).
        var general: [String: (names: [String], proposal: CoachProposal)] = [:]
        for stall in stalls(routines: routines, logs: logs, now: now) {
            guard let proposal = diagnose(stall, routines: routines, statuses: statuses, profile: profile, failure: failure,
                                          readinessLow: readinessLow, cutting: cutting, deloadWeek: deloadNow) else { continue }
            if proposal.id.hasSuffix("-recovery") || proposal.id.hasSuffix("-cut") {
                let cause = proposal.id.hasSuffix("-cut") ? "cut" : "recovery"
                var entry = general[cause] ?? ([], proposal)
                entry.names.append(stall.item.exercise.name)
                general[cause] = entry
            } else {
                result.append(proposal)
            }
        }
        for (cause, entry) in general {
            if entry.names.count == 1 {
                result.append(entry.proposal)
            } else {
                let list = entry.names.prefix(4).joined(separator: ", ") + (entry.names.count > 4 ? "…" : "")
                result.append(entry.proposal.with(
                    id: "stall-\(cause)-\(entry.names.count)",
                    title: cause == "cut" ? "\(entry.names.count) lifts holding steady on your cut" : "\(entry.names.count) lifts stuck — recover first",
                    reason: cause == "cut"
                        ? "\(list): no progress for 3+ weeks — normal while cutting. Keeping your strength is the win."
                        : "\(list): no progress for 3+ weeks while \(Int(failure * 100))% of sets go to failure\(readinessLow ? " and recovery is low" : ""). Leave 1–2 reps in the tank for two weeks before changing anything."))
            }
        }
        result += painProposals(routines: routines, flags: context.painFlags)
        result += consistency(routines: routines, logs: logs, plans: context.dayPlans, now: now)
        result += audit(routines: routines, profile: profile, logs: logs, now: now)
        if cutting {
            // No extra volume while cutting (trims and fixes still show).
            result.removeAll { proposal in
                switch proposal.change {
                case .addExercise: return true
                case .sets(let routineID, let itemID, let to):
                    let current = routines.first { $0.id == routineID }?.exercises.first { $0.id == itemID }?.exercise.defaultSets ?? to
                    return to > current && !proposal.id.hasPrefix("pain-")
                default: return false
                }
            }
        }

        // One suggestion per id, and one set change per exercise (the most important one).
        var seen = Set<String>()
        var changedItems = Set<UUID>()
        return result.sorted { $0.priority > $1.priority }.filter { proposal in
            guard !declined.contains(proposal.id), seen.insert(proposal.id).inserted else { return false }
            if case let .sets(_, itemID, _) = proposal.change { return changedItems.insert(itemID).inserted }
            return true
        }
    }

    /// Problems in the routines themselves (works without any history).
    public static func audit(routines: [WorkoutRoutine], profile: UserProfile, logs: [WorkoutLog] = [], now: Date = .now) -> [CoachProposal] {
        var result: [CoachProposal] = []
        let active = routines.filter { !$0.exercises.isEmpty }
        guard !active.isEmpty else { return [] }
        let frequency = routineFrequency(routines: active, logs: logs, now: now)
        let planned = plannedSets(routines: active, frequency: frequency)

        for routine in active {
            for (index, item) in routine.exercises.enumerated() where !item.exercise.isCardio {
                let exercise = item.exercise
                guard let profileInfo = ExerciseLibrary.profile(for: exercise.name) else { continue }

                // Focus: main lifts heavy for strength, moderate for size.
                if let strength = profileInfo.strengthRange {
                    if profile.focus == .strength, exercise.repMin > strength.upperBound {
                        result.append(CoachProposal(
                            id: "focus-\(item.id)-\(strength.lowerBound)",
                            title: "\(exercise.name): \(exercise.repMin)–\(exercise.repMax) → \(strength.lowerBound)–\(strength.upperBound) reps",
                            reason: "Strength focus: heavier, lower-rep sets on main lifts build max strength.",
                            change: .repRange(routineID: routine.id, itemID: item.id, min: strength.lowerBound, max: strength.upperBound),
                            priority: 60))
                    } else if profile.focus == .size, exercise.repMax <= strength.upperBound {
                        result.append(CoachProposal(
                            id: "focus-\(item.id)-\(profileInfo.repMin)",
                            title: "\(exercise.name): \(exercise.repMin)–\(exercise.repMax) → \(profileInfo.repMin)–\(profileInfo.repMax) reps",
                            reason: "Size focus: a moderate range builds the same muscle with less joint strain.",
                            change: .repRange(routineID: routine.id, itemID: item.id, min: profileInfo.repMin, max: profileInfo.repMax),
                            priority: 50))
                    }
                }
                // Rest too short for a heavy lift.
                if profileInfo.fatigue >= 2, exercise.restSeconds + 45 <= profileInfo.restSeconds {
                    result.append(CoachProposal(
                        id: "rest-\(item.id)-\(profileInfo.restSeconds)",
                        title: "\(exercise.name): rest \(exercise.restSeconds / 60):\(String(format: "%02d", exercise.restSeconds % 60)) → \(profileInfo.restSeconds / 60):\(String(format: "%02d", profileInfo.restSeconds % 60))",
                        reason: "Heavy compounds grow more with 2–3 min rest — you'll keep more reps per set.",
                        change: .rest(routineID: routine.id, itemID: item.id, seconds: profileInfo.restSeconds),
                        priority: 40))
                }
                // Isolation for a muscle before the big lift that needs it.
                if profileInfo.kind == .isolation {
                    let muscles = Set(profileInfo.primaryMuscles)
                    if let later = routine.exercises[(index + 1)...].first(where: { other in
                        guard let otherInfo = ExerciseLibrary.profile(for: other.exercise.name) else { return false }
                        return otherInfo.kind == .compound && otherInfo.fatigue >= 2 && !muscles.isDisjoint(with: Set(otherInfo.primaryMuscles))
                    }) {
                        result.append(CoachProposal(
                            id: "order-\(later.id)-\(item.id)",
                            title: "\(routine.name): do \(later.exercise.name) before \(exercise.name)",
                            reason: "Tiring a muscle with isolation first costs reps on the big lift that needs it.",
                            change: .moveBefore(routineID: routine.id, itemID: later.id, beforeItemID: item.id),
                            priority: 45))
                    }
                }
            }
        }

        // Push / pull balance.
        let push = (planned[.chest] ?? 0) + (planned[.frontDelts] ?? 0)
        let pull = (planned[.lats] ?? 0) + (planned[.upperBack] ?? 0) + (planned[.rearDelts] ?? 0) * 0.5
        if push > 8, pull < push / 1.5 {
            result += addVolume(for: .upperBack, sets: 3, routines: active,
                                reason: "Pulling is well below pushing (\(format(pull)) vs \(format(push)) sets) — balanced backs keep shoulders healthy.",
                                priority: 80)
        }
        // Muscles with no direct work at all.
        for muscle in [Muscle.hamstrings, .sideDelts, .rearDelts, .calves] where (planned[muscle] ?? 0) < 1 {
            result += addVolume(for: muscle, sets: 3, routines: active,
                                reason: "No direct \(muscle.title.lowercased()) work in your routines.", priority: 72)
        }
        // A big muscle trained only once a week with lots of sets.
        let sessionsPerWeek = frequency.values.reduce(0, +)
        if sessionsPerWeek >= 3 {
            for muscle in [Muscle.chest, .lats, .quads, .hamstrings, .sideDelts] {
                let routinesHitting = active.filter { routine in
                    routine.exercises.contains { (ExerciseLibrary.muscles(for: $0.exercise.name, category: $0.exercise.category)[muscle] ?? 0) >= 1 }
                }
                let weekly = routinesHitting.reduce(0.0) { $0 + (frequency[$1.id] ?? 0) }
                if weekly > 0, weekly < 1.5, (planned[muscle] ?? 0) >= 8 {
                    result.append(CoachProposal(
                        id: "frequency-\(muscle.rawValue)",
                        title: "Split \(muscle.title.lowercased()) across two days",
                        reason: "Same sets spread over 2 sessions a week usually grows more than 1 big session.",
                        change: .info, muscle: muscle, priority: 35))
                }
            }
        }
        return result
    }

    /// +sets on the exercise that trains `muscle` most (up to 5 sets), or a new exercise if none does.
    static func addVolume(for muscle: Muscle, sets: Int, routines: [WorkoutRoutine], reason: String, priority: Int) -> [CoachProposal] {
        var best: (routine: WorkoutRoutine, item: RoutineExercise, share: Double)?
        for routine in routines {
            for item in routine.exercises where !item.exercise.isCardio && item.exercise.defaultSets < 5 {
                let share = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)[muscle] ?? 0
                if share >= 1, share > (best?.share ?? 0) || (share == best?.share && item.exercise.defaultSets < (best?.item.exercise.defaultSets ?? 99)) {
                    best = (routine, item, share)
                }
            }
        }
        if let best {
            let to = min(best.item.exercise.defaultSets + sets, 5)
            return [CoachProposal(id: "sets-\(best.item.id)-up",
                                  title: "\(best.item.exercise.name) (\(best.routine.name)): \(best.item.exercise.defaultSets) → \(to) sets",
                                  reason: reason, change: .sets(routineID: best.routine.id, itemID: best.item.id, to: to),
                                  muscle: muscle, priority: priority)]
        }
        guard let pick = suggestedExercise(for: muscle), let routine = routineFor(muscle, routines: routines) else { return [] }
        return [CoachProposal(id: "add-\(muscle.rawValue)-\(routine.id)",
                              title: "Add \(pick.name) to \(routine.name) (3 sets)",
                              reason: reason, change: .addExercise(routineID: routine.id, name: pick.name, sets: 3),
                              muscle: muscle, priority: priority)]
    }

    /// −1 set on the exercise with the most sets for that muscle (never below 2).
    static func removeVolume(for muscle: Muscle, routines: [WorkoutRoutine], reason: String, priority: Int) -> [CoachProposal] {
        var best: (routine: WorkoutRoutine, item: RoutineExercise)?
        for routine in routines {
            for item in routine.exercises where item.exercise.defaultSets > 2 {
                let share = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)[muscle] ?? 0
                if share >= 1, item.exercise.defaultSets > (best?.item.exercise.defaultSets ?? 0) { best = (routine, item) }
            }
        }
        guard let best else { return [] }
        let to = best.item.exercise.defaultSets - 1
        return [CoachProposal(id: "sets-\(best.item.id)-down",
                              title: "\(best.item.exercise.name) (\(best.routine.name)): \(best.item.exercise.defaultSets) → \(to) sets",
                              reason: reason, change: .sets(routineID: best.routine.id, itemID: best.item.id, to: to),
                              muscle: muscle, priority: priority)]
    }

    /// A good default exercise for a muscle.
    public static func suggestedExercise(for muscle: Muscle) -> ExerciseProfile? {
        let name: String
        switch muscle {
        case .chest: name = "Incline Dumbbell Press"
        case .lats: name = "Lat Pulldown"
        case .upperBack: name = "Chest-Supported Row"
        case .frontDelts: name = "Machine Shoulder Press"
        case .sideDelts: name = "Cable Lateral Raise"
        case .rearDelts: name = "Reverse Pec Deck"
        case .biceps: name = "Incline Dumbbell Curl"
        case .triceps: name = "Overhead Triceps Extension"
        case .quads: name = "Leg Extension"
        case .hamstrings: name = "Seated Leg Curl"
        case .glutes: name = "Hip Thrust"
        case .calves: name = "Standing Calf Raise"
        case .abs: name = "Cable Crunch"
        }
        return ExerciseLibrary.profile(named: name)
    }

    /// The routine that already trains that muscle's area (or the shortest one).
    static func routineFor(_ muscle: Muscle, routines: [WorkoutRoutine]) -> WorkoutRoutine? {
        let candidates = routines.filter { !$0.exercises.isEmpty && !$0.exercises.allSatisfy(\.exercise.isCardio) }
        let related = candidates.filter { routine in
            routine.exercises.contains { ExerciseLibrary.muscles(for: $0.exercise.name, category: $0.exercise.category)
                .keys.contains { $0.category == muscle.category } }
        }
        return (related.isEmpty ? candidates : related).min { $0.exercises.count < $1.exercises.count }
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    static func weekKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
    }

    // MARK: Warm-ups

    /// Ramp-up sets before a heavy compound (none for isolation work, which the first set warms up).
    public static func warmups(for exercise: ExerciseDefinition, working: Double) -> [SetTarget]? {
        guard let info = ExerciseLibrary.profile(for: exercise.name), !exercise.isAssisted else { return nil }
        guard info.needsRampUp else { return [] }
        let step = exercise.weightIncrementKg > 0 ? exercise.weightIncrementKg : 2.5
        func round(_ value: Double) -> Double { max(0, (value / step).rounded() * step) }
        guard working > 0 else { return [SetTarget(weightKg: 0, reps: 10)] }
        if working >= 60 { return [SetTarget(weightKg: round(working * 0.5), reps: 8), SetTarget(weightKg: round(working * 0.7), reps: 4),
                                   SetTarget(weightKg: round(working * 0.85), reps: 2)] }
        if working >= 30 { return [SetTarget(weightKg: round(working * 0.5), reps: 8), SetTarget(weightKg: round(working * 0.75), reps: 3)] }
        return [SetTarget(weightKg: round(working * 0.5), reps: 8)]
    }

    // MARK: Recovery

    /// "Quads were trained hard yesterday" style warnings for a routine you're about to do.
    public static func recoveryWarnings(for routine: WorkoutRoutine, logs: [WorkoutLog], cardio: [CardioSession] = [],
                                        now: Date = .now) -> [String] {
        var warnings = liftWarnings(for: routine, logs: logs, now: now)
        if let legs = cardioLegWarning(for: routine, cardio: cardio, now: now) { warnings.append(legs) }
        return warnings
    }

    static func liftWarnings(for routine: WorkoutRoutine, logs: [WorkoutLog], now: Date) -> [String] {
        var todayLoad: [Muscle: Double] = [:]
        var heavyHinge = false
        for item in routine.exercises where !item.exercise.isCardio {
            let muscles = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)
            for (muscle, share) in muscles where share >= 1 { todayLoad[muscle, default: 0] += Double(item.exercise.defaultSets) }
            if let info = ExerciseLibrary.profile(for: item.exercise.name), info.fatigue >= 3 { heavyHinge = true }
        }
        var warnings: [String] = []
        let recent = logs.filter { $0.startedAt >= now.addingTimeInterval(-40 * 3600) && $0.startedAt < now }
        guard !recent.isEmpty else { return [] }
        let recentSets = muscleSets(logs: recent, from: now.addingTimeInterval(-40 * 3600), to: now)
        let tired = Muscle.allCases.filter { (recentSets[$0] ?? 0) >= 6 && (todayLoad[$0] ?? 0) >= 4 }
        if !tired.isEmpty {
            warnings.append("\(tired.map(\.title).joined(separator: ", ")) trained hard in the last day or two — keep 2–3 reps in the tank today, or swap sessions.")
        }
        let recentHeavy = recent.contains { workout in
            workout.exercises.contains { (ExerciseLibrary.profile(for: $0.exerciseName)?.fatigue ?? 0) >= 3 }
        }
        if heavyHinge && recentHeavy {
            warnings.append("Heavy squats/deadlifts two days running is a lot for your lower back — go lighter on the big lift today.")
        }
        return warnings
    }

    // MARK: After a workout

    /// Up to three short lines: what went up, what's stuck, and the next step.
    public static func verdict(for log: WorkoutLog, logs: [WorkoutLog]) -> [String] {
        var up: [String] = []
        var flat: [String] = []
        for exercise in log.exercises where !exercise.isCardio {
            let previous = logs.previousLog(where: { $0.matches(exercise) }, before: log.startedAt)
            let comparison = ProgressionEngine.compare(current: exercise, previous: previous, context: log.tagSet)
            switch comparison.kind {
            case .improved: up.append(exercise.exerciseName)
            case .matched, .declined:
                // MK11.1: only normal sessions count, and it takes 4 of them in a row.
                guard !log.isAtypical else { continue }
                let history = logs.filter { $0.startedAt < log.startedAt && !$0.isAtypical }.sorted { $0.startedAt > $1.startedAt }
                    .compactMap { $0.exercises.first { $0.matches(exercise) } }.prefix(3)
                if !exercise.isAssisted, history.count == 3,
                   history.allSatisfy({ $0.estimatedOneRepMaxKg >= exercise.estimatedOneRepMaxKg - 0.01 }) {
                    flat.append(exercise.exerciseName)
                }
            case .firstTime: break
            }
        }
        var lines: [String] = []
        if !up.isEmpty { lines.append("Up: " + up.prefix(4).joined(separator: ", ") + ".") }
        if !flat.isEmpty { lines.append("Flat 4 sessions: " + flat.prefix(3).joined(separator: ", ") + " — see Coach for a suggested change.") }
        if up.isEmpty && flat.isEmpty { lines.append("Solid session — matched your last numbers.") }
        return lines
    }

    // MARK: Your personal response

    /// "Chest grew best around 12 sets/week" — from 8+ weeks of your own data (nil if not enough).
    public static func sweetSpot(_ muscle: Muscle, logs: [WorkoutLog], now: Date = .now) -> String? {
        var weeks: [(sets: Double, best: Double)] = []
        for offset in 0..<16 {
            let end = now.addingTimeInterval(-Double(offset) * 7 * day)
            let start = end.addingTimeInterval(-7 * day)
            let sets = muscleSets(logs: logs, from: start, to: end)[muscle] ?? 0
            var best = 0.0
            for workout in logs where workout.startedAt >= start && workout.startedAt < end && !workout.isAtypical {
                for exercise in workout.exercises where !exercise.isAssisted
                    && (ExerciseLibrary.muscles(for: exercise.exerciseName, category: exercise.category)[muscle] ?? 0) >= 1 {
                    best = max(best, exercise.estimatedOneRepMaxKg)
                }
            }
            if sets > 0, best > 0 { weeks.append((sets, best)) }
        }
        guard weeks.count >= 8 else { return nil }
        weeks.reverse()   // oldest first
        var gains: [(sets: Double, gain: Double)] = []
        for index in 1..<weeks.count { gains.append((weeks[index].sets, (weeks[index].best / weeks[index - 1].best - 1) * 100)) }
        let sortedSets = gains.map(\.sets).sorted()
        let median = sortedSets[sortedSets.count / 2]
        let low = gains.filter { $0.sets < median }
        let high = gains.filter { $0.sets >= median }
        guard low.count >= 3, high.count >= 3 else { return nil }
        let lowGain = low.map(\.gain).reduce(0, +) / Double(low.count)
        let highGain = high.map(\.gain).reduce(0, +) / Double(high.count)
        let lowSets = low.map(\.sets).reduce(0, +) / Double(low.count)
        let highSets = high.map(\.sets).reduce(0, +) / Double(high.count)
        if abs(highGain - lowGain) < 0.3 { return "\(muscle.title): similar progress at ~\(format(lowSets.rounded())) and ~\(format(highSets.rounded())) sets/week — the lower is enough." }
        return "\(muscle.title): your best progress came at ~\(format((highGain > lowGain ? highSets : lowSets).rounded())) sets/week."
    }
}

// MARK: - Routine builder

public struct RoutineBuildRequest {
    public var daysPerWeek: Int
    public var minutes: Int
    public var focus: TrainingFocus
    public var priorities: [ExerciseCategory]
    public init(daysPerWeek: Int, minutes: Int, focus: TrainingFocus, priorities: [ExerciseCategory]) {
        self.daysPerWeek = daysPerWeek
        self.minutes = minutes
        self.focus = focus
        self.priorities = priorities
    }
}

public enum RoutineBuilder {
    /// Split by days per week.
    public static func splitName(days: Int) -> String {
        switch days {
        case ...2: return "Full body ×2"
        case 3: return "Full body ×3"
        case 4: return "Upper / Lower ×2"
        case 5: return "Upper / Lower + Push / Pull / Legs"
        default: return "Push / Pull / Legs ×2"
        }
    }

    public static func build(_ request: RoutineBuildRequest) -> [WorkoutRoutine] {
        let fullA = ["Back Squat", "Barbell Bench Press", "Lat Pulldown", "Seated Leg Curl", "Lateral Raise", "Triceps Pushdown"]
        let fullB = ["Romanian Deadlift", "Incline Dumbbell Press", "Seated Cable Row", "Leg Extension", "Reverse Pec Deck", "Incline Dumbbell Curl"]
        let fullC = ["Leg Press", "Machine Shoulder Press", "Chest-Supported Row", "Lying Leg Curl", "Cable Fly", "Standing Calf Raise"]
        let upperA = ["Barbell Bench Press", "Seated Cable Row", "Machine Shoulder Press", "Lat Pulldown", "Lateral Raise", "Incline Dumbbell Curl", "Triceps Pushdown"]
        let lowerA = ["Back Squat", "Romanian Deadlift", "Leg Extension", "Seated Leg Curl", "Standing Calf Raise", "Cable Crunch"]
        let upperB = ["Incline Dumbbell Press", "Pull-up", "Chest-Supported Row", "Cable Fly", "Cable Lateral Raise", "Overhead Triceps Extension", "Hammer Curl"]
        let lowerB = ["Hack Squat", "Hip Thrust", "Lying Leg Curl", "Leg Extension", "Seated Calf Raise", "Hanging Leg Raise"]
        let push = ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press", "Cable Lateral Raise", "Overhead Triceps Extension", "Triceps Pushdown"]
        let pull = ["Pull-up", "Barbell Row", "Seated Cable Row", "Reverse Pec Deck", "Incline Dumbbell Curl", "Hammer Curl"]
        let legs = ["Back Squat", "Romanian Deadlift", "Leg Press", "Seated Leg Curl", "Standing Calf Raise", "Cable Crunch"]
        let pushB = ["Incline Barbell Press", "Dumbbell Shoulder Press", "Machine Chest Press", "Lateral Raise", "Skull Crusher", "Cable Fly"]
        let pullB = ["Lat Pulldown", "Chest-Supported Row", "Dumbbell Row", "Face Pull", "Barbell Curl", "Preacher Curl"]
        let legsB = ["Hack Squat", "Hip Thrust", "Leg Extension", "Lying Leg Curl", "Seated Calf Raise", "Hanging Leg Raise"]

        let plan: [(String, [String])]
        switch request.daysPerWeek {
        case ...2: plan = [("Full Body A", fullA), ("Full Body B", fullB)]
        case 3: plan = [("Full Body A", fullA), ("Full Body B", fullB), ("Full Body C", fullC)]
        case 4: plan = [("Upper A", upperA), ("Lower A", lowerA), ("Upper B", upperB), ("Lower B", lowerB)]
        case 5: plan = [("Upper", upperA), ("Lower", lowerA), ("Push", push), ("Pull", pull), ("Legs", legsB)]
        default: plan = [("Push A", push), ("Pull A", pull), ("Legs A", legs), ("Push B", pushB), ("Pull B", pullB), ("Legs B", legsB)]
        }
        return plan.map { name, exercises in routine(name: name, exercises: exercises, request: request) }
    }

    static func routine(name: String, exercises: [String], request: RoutineBuildRequest) -> WorkoutRoutine {
        let priority = Set(request.priorities)
        var items: [ExerciseDefinition] = exercises.compactMap { exerciseName in
            guard let info = ExerciseLibrary.profile(named: exerciseName) else { return nil }
            var exercise = ExerciseDefinition(name: info.name, category: info.category, repMin: info.repMin, repMax: info.repMax,
                                              defaultSets: 3, restSeconds: info.restSeconds, weightIncrementKg: info.increment)
            if request.focus == .strength, let strength = info.strengthRange {
                exercise.repMin = strength.lowerBound
                exercise.repMax = strength.upperBound
                exercise.restSeconds = max(info.restSeconds, 180)
            }
            if info.muscles.contains(where: { $0.value >= 1 && priority.contains($0.key.category) }) { exercise.defaultSets = 4 }
            return exercise
        }
        // Priority muscles' isolation work moves up, right after the first big lift.
        if let firstPriority = items.indices.dropFirst().first(where: { index in
            items[index].defaultSets == 4 && ExerciseLibrary.profile(named: items[index].name)?.kind == .isolation
        }), firstPriority > 1 {
            let moved = items.remove(at: firstPriority)
            items.insert(moved, at: 1)
        }
        // Fit the time: trim isolation sets to 2, then drop the last exercises.
        func estimate(_ list: [ExerciseDefinition]) -> Int {
            let routine = WorkoutRoutine(name: name, exercises: list.enumerated().map { RoutineExercise(exercise: $1, order: $0) })
            return TimeBudget.estimateMinutes(ActiveWorkoutState(routine: routine))
        }
        var index = items.count - 1
        while estimate(items) > request.minutes, index >= 0 {
            if ExerciseLibrary.profile(named: items[index].name)?.kind == .isolation {
                while items[index].defaultSets > 2, estimate(items) > request.minutes {
                    items[index].defaultSets -= 1
                }
            }
            index -= 1
        }
        while estimate(items) > request.minutes, items.count > 3 {
            items.removeLast()
        }
        return WorkoutRoutine(name: name, exercises: items.enumerated().map { RoutineExercise(exercise: $1, order: $0) })
    }
}
