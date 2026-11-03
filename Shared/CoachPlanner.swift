import Foundation

// MK10: the coach as a planner — training blocks with effort targets, honest set counting,
// stall diagnosis, exercise swaps, pain, diet phase, runs/basketball fatigue and consistency.
// Still suggestions only: nothing in a routine changes until you accept it.

// MARK: - Effort targets

public enum EffortTarget {
    /// Reps to leave in the tank on working sets today: 3 → 2 → 1 through a block, easy in a deload,
    /// 2 when you aren't running a block.
    public static func reps(profile: UserProfile?, light: Bool = false, at date: Date = .now) -> Int {
        if light { return 4 }
        guard let profile else { return 2 }
        if profile.isDeloadActive(at: date) { return 4 }
        guard let position = profile.program?.position(at: date), position.block.phase != .deload else { return 2 }
        let weeks = Swift.max(position.block.weeks, 1)
        guard weeks > 1 else { return 2 }
        let progress = Double(position.week - 1) / Double(weeks - 1)
        if progress < 0.2 { return 3 }
        if progress < 0.6 { return 2 }
        return 1
    }

    /// "~2 reps left", "to failure", "easy (4+ left)".
    public static func text(_ rir: Int) -> String {
        if rir <= 0 { return "to failure" }
        if rir >= 4 { return "easy (4+ reps left)" }
        return "~\(rir) rep\(rir == 1 ? "" : "s") left"
    }

    /// "Block week 2 of 4" (nil without a program).
    public static func blockLabel(profile: UserProfile?, at date: Date = .now) -> String? {
        guard let position = profile?.program?.position(at: date) else { return nil }
        if position.block.phase == .deload { return "Deload week" }
        return "Block week \(position.week) of \(position.block.weeks)"
    }
}

public extension WorkoutSetLog {
    /// How much this set counts toward weekly volume: a set with 4+ reps left is only half a hard set.
    var hardSetValue: Double {
        guard reps > 0 else { return 0 }
        guard let rir else { return 1 }
        return rir >= 4 ? 0.5 : 1
    }
}

// MARK: - Runs and basketball: training load

public extension CardioSession {
    /// Session load (effort × minutes, the sports-science "session RPE"). Without a rating it's estimated
    /// from heart-rate zones, or a moderate effort when there's no heart rate either.
    var sessionLoad: Double {
        let minutes = kind == .basketball ? (minutesPlayed ?? activeSeconds / 60) : activeSeconds / 60
        if let effort { return Double(effort) * minutes }
        let zoneTotal = zoneSeconds.reduce(0, +)
        if zoneTotal > 300 {
            // Zone-weighted minutes (×1…×5) ≈ effort × minutes / 2.
            return zoneSeconds.enumerated().reduce(0.0) { $0 + $1.element / 60 * Double($1.offset + 1) } * 2
        }
        return 5 * minutes
    }

    /// Your rating, or the heart-rate estimate (nil when there's neither).
    var effortRating: Int? {
        if let effort { return effort }
        return zoneSeconds.reduce(0, +) > 300 ? effortScore : nil
    }

    /// Hard on the legs: a long run, or a big game / hard session.
    var isHardOnLegs: Bool {
        (kind == .run && (distanceKm ?? 0) >= 10) || sessionLoad >= 350
    }
}

// MARK: - Everything the coach looks at

public struct CoachInputs {
    public var priorities: [ExerciseCategory]
    public var readinessLow: Bool
    public var declined: Set<String>
    public var nutritionPhase: NutritionPhase?
    public var painFlags: [PainFlag]
    public var dayPlans: [DayPlan]
    public var cardio: [CardioSession]
    public var now: Date

    public init(priorities: [ExerciseCategory] = [], readinessLow: Bool = false, declined: Set<String> = [],
                nutritionPhase: NutritionPhase? = nil, painFlags: [PainFlag] = [], dayPlans: [DayPlan] = [],
                cardio: [CardioSession] = [], now: Date = .now) {
        self.priorities = priorities
        self.readinessLow = readinessLow
        self.declined = declined
        self.nutritionPhase = nutritionPhase
        self.painFlags = painFlags
        self.dayPlans = dayPlans
        self.cardio = cardio
        self.now = now
    }
}

public extension CoachProposal {
    func with(id newID: String, title newTitle: String? = nil, reason newReason: String? = nil, priority newPriority: Int? = nil) -> CoachProposal {
        CoachProposal(id: newID, title: newTitle ?? title, reason: newReason ?? reason, change: change,
                      muscle: muscle, priority: newPriority ?? priority)
    }
}

// MARK: - Stalls

public struct ExerciseStall: Hashable {
    public let routineID: UUID
    public let item: RoutineExercise
    /// Weeks since the last time it went up.
    public let weeks: Int
    public let sessions: Int
}

public extension CoachBrain {
    /// Strength of one session (higher = stronger): best estimated 1RM, or less assistance.
    static func strengthValue(_ log: ExerciseLog) -> Double? {
        if log.isAssisted {
            guard let least = log.leastAssistanceKg else { return nil }
            return -least
        }
        let value = log.estimatedOneRepMaxKg
        return value > 0 ? value : nil
    }

    /// Exercises in your routines that haven't gone up for 4+ weeks over 4+ sessions (normal sessions only).
    static func stalls(routines: [WorkoutRoutine], logs: [WorkoutLog], now: Date = .now) -> [ExerciseStall] {
        // MK11.1: short / kit-limited / easy / tired sessions aren't evidence of a stall.
        let lifts = liftLogs(logs).filter { !$0.isAtypical && $0.startedAt <= now && $0.startedAt >= now.addingTimeInterval(-84 * day) }
        var result: [ExerciseStall] = []
        var seen = Set<String>()
        for routine in routines {
            for item in routine.exercises where !item.exercise.isCardio && !item.exercise.isBodyweight {
                let key = item.exercise.historyKey
                guard seen.insert(key).inserted else { continue }
                // MK17: like with like — a planned variation (paused, wide grip) isn't a stall.
                let points = lifts.sameWayHistory(for: item.exercise).compactMap { point -> (Date, Double)? in
                    strengthValue(point.log).map { (point.date, $0) }
                }
                guard points.count >= 5 else { continue }
                var best = points[0].1
                var lastUp = points[0].0
                for (date, value) in points.dropFirst() {
                    let margin = Swift.max(abs(best) * 0.005, 0.01)
                    if value > best + margin {
                        best = value
                        lastUp = date
                    } else {
                        best = Swift.max(best, value)
                    }
                }
                let since = points.filter { $0.0 > lastUp }.count
                let weeks = Int(now.timeIntervalSince(lastUp) / (7 * day))
                if since >= 4, weeks >= 4 {
                    result.append(ExerciseStall(routineID: routine.id, item: item, weeks: weeks, sessions: since))
                }
            }
        }
        return result
    }

    /// A good swap from the library that isn't already in your routines (gentler kit first when it hurts).
    static func substitute(for exercise: ExerciseDefinition, routines: [WorkoutRoutine], gentle: Bool = false) -> ExerciseProfile? {
        guard let info = ExerciseLibrary.profile(for: exercise.name) else { return nil }
        let used = Set(routines.flatMap(\.exercises).compactMap { ExerciseLibrary.profile(for: $0.exercise.name)?.name })
        var options = info.substitutes.compactMap { ExerciseLibrary.profile(named: $0) }.filter { !used.contains($0.name) }
        if gentle {
            options.sort { rank($0.equipment) < rank($1.equipment) }
        }
        return options.first
    }

    private static func rank(_ equipment: EquipmentKind) -> Int {
        switch equipment {
        case .machine: return 0
        case .cable: return 1
        case .dumbbell: return 2
        case .bodyweight: return 3
        case .barbell: return 4
        }
    }

    // MARK: Diagnosis

    /// One stalled exercise → the most likely cause, checked in order: diet phase, recovery, too much
    /// volume, too little volume, a stale accessory, then a new rep range for a main lift.
    static func diagnose(_ stall: ExerciseStall, routines: [WorkoutRoutine], statuses: [MuscleStatus], profile: UserProfile,
                         failure: Double, readinessLow: Bool, cutting: Bool, deloadWeek: Bool) -> CoachProposal? {
        let exercise = stall.item.exercise
        let name = exercise.name
        let info = ExerciseLibrary.profile(for: name)
        let stuck = "\(name): no progress for \(stall.weeks) weeks (\(stall.sessions) sessions)"
        let primary = info?.primaryMuscles ?? []
        let status = statuses.first { primary.contains($0.muscle) }

        if cutting {
            return CoachProposal(id: "stall-\(stall.item.id)-cut", title: "\(name): holding steady on a cut",
                                 reason: "\(stuck) — normal while cutting. Keeping your strength is the win; no change needed.",
                                 change: .info, priority: 15)
        }
        if failure >= 0.4 || readinessLow {
            return CoachProposal(id: "stall-\(stall.item.id)-recovery", title: "\(name): recover before changing anything",
                                 reason: "\(stuck). You're taking \(Int(failure * 100))% of sets to failure"
                                    + (readinessLow ? " and recovery is low" : "")
                                    + " — leave 1–2 reps in the tank for two weeks; the weight usually moves again.",
                                 change: .info, priority: 62)
        }
        if let status, status.current > status.high, exercise.defaultSets > 2 {
            return CoachProposal(id: "stall-\(stall.item.id)-less",
                                 title: "\(name): \(exercise.defaultSets) → \(exercise.defaultSets - 1) sets",
                                 reason: "\(stuck) with ~\(format(status.current)) \(status.muscle.title.lowercased()) sets a week — more than you can recover from. One less set lets you push the weight.",
                                 change: .sets(routineID: stall.routineID, itemID: stall.item.id, to: exercise.defaultSets - 1),
                                 muscle: status.muscle, priority: 66)
        }
        if let status, status.low > 0, status.current < status.low, exercise.defaultSets < 5 {
            return CoachProposal(id: "stall-\(stall.item.id)-more",
                                 title: "\(name): \(exercise.defaultSets) → \(exercise.defaultSets + 1) sets",
                                 reason: "\(stuck) on only ~\(format(status.current)) \(status.muscle.title.lowercased()) sets a week — a bit more work should get it moving.",
                                 change: .sets(routineID: stall.routineID, itemID: stall.item.id, to: exercise.defaultSets + 1),
                                 muscle: status.muscle, priority: 64)
        }
        let isMain = info?.isMainLift ?? TimeBudget.isCompound(name)
        if !isMain || (deloadWeek && stall.weeks >= 6), let swap = substitute(for: exercise, routines: routines) {
            return CoachProposal(id: "stall-\(stall.item.id)-swap", title: "Swap \(name) → \(swap.name)",
                                 reason: "\(stuck). A similar exercise gives the muscle a fresh challenge; \(name) stays as a swap option.",
                                 change: .swapExercise(routineID: stall.routineID, itemID: stall.item.id, name: swap.name),
                                 muscle: primary.first, priority: 58)
        }
        // Main lift: a new rep range is a new stimulus.
        let low: Int
        let high: Int
        if exercise.repMin >= 8 {
            low = Swift.max(4, exercise.repMin - 2)
            high = Swift.max(low + 2, exercise.repMax - 2)
        } else {
            low = exercise.repMin + 2
            high = exercise.repMax + 2
        }
        return CoachProposal(id: "stall-\(stall.item.id)-range", title: "\(name): \(exercise.repMin)–\(exercise.repMax) → \(low)–\(high) reps",
                             reason: "\(stuck). Recovery and volume look fine, so change the rep range for a block — a new stimulus usually breaks a plateau.",
                             change: .repRange(routineID: stall.routineID, itemID: stall.item.id, min: low, max: high),
                             muscle: primary.first, priority: 56)
    }

    // MARK: Pain

    static func painProposals(routines: [WorkoutRoutine], flags: [PainFlag]) -> [CoachProposal] {
        var result: [CoachProposal] = []
        let open = flags.filter { !$0.resolved }
        for routine in routines {
            for item in routine.exercises where !item.exercise.isCardio {
                let key = item.exercise.historyKey
                let nameKey = ExerciseLog.key(for: item.exercise.name)
                guard let flag = open.filter({ $0.exerciseKey == key || $0.exerciseKey == nameKey }).max(by: { $0.severity < $1.severity }) else { continue }
                if flag.severity >= 2, let swap = substitute(for: item.exercise, routines: routines, gentle: true) {
                    result.append(CoachProposal(
                        id: "pain-\(item.id)-\(flag.id)", title: "Swap \(item.exercise.name) → \(swap.name) while it heals",
                        reason: "You flagged \(flag.area.title.lowercased()) pain on it. Train around it with a gentler option; swap back once it feels fine for 2 weeks.",
                        change: .swapExercise(routineID: routine.id, itemID: item.id, name: swap.name), priority: 92))
                } else {
                    result.append(CoachProposal(
                        id: "pain-\(item.id)-\(flag.id)", title: "\(item.exercise.name): go gently",
                        reason: "You flagged a \(flag.area.title.lowercased()) niggle. Keep the weight, leave 3 reps in the tank and lower slowly until it settles.",
                        change: .info, priority: 50))
                }
            }
        }
        return result
    }

    // MARK: Runs and basketball

    /// A leg-heavy session after a long run or a big game.
    static func cardioLegWarning(for routine: WorkoutRoutine, cardio: [CardioSession], now: Date = .now) -> String? {
        var legSets = 0.0
        for item in routine.exercises where !item.exercise.isCardio {
            let muscles = ExerciseLibrary.muscles(for: item.exercise.name, category: item.exercise.category)
            if [Muscle.quads, .hamstrings, .glutes, .calves].contains(where: { (muscles[$0] ?? 0) >= 1 }) {
                legSets += Double(item.exercise.defaultSets)
            }
        }
        guard legSets >= 4 else { return nil }
        let recent = cardio.filter { $0.endedAt <= now && now.timeIntervalSince($0.endedAt) < 30 * 3600 && $0.isHardOnLegs }
        guard let hardest = recent.max(by: { $0.sessionLoad < $1.sessionLoad }) else { return nil }
        let what = hardest.kind == .run ? "\(GFFormat.km(hardest.distanceKm ?? 0)) km run" : "hard basketball"
        return "Your \(what) in the last day is still in your legs — leave 2–3 reps in the tank on leg work today, or swap to an upper-body day."
    }

    // MARK: Consistency

    /// A plan you keep missing is the wrong plan: spots skipped weekdays, and routines that need more days than you train.
    static func consistency(routines: [WorkoutRoutine], logs: [WorkoutLog], plans: [DayPlan], now: Date = .now,
                            calendar: Calendar = .current) -> [CoachProposal] {
        var result: [CoachProposal] = []
        let lifts = liftLogs(logs).filter { $0.startedAt <= now }
        let today = calendar.startOfDay(for: now)
        let window = today.addingTimeInterval(-56 * day)

        var planned: [Int: Int] = [:]
        var done: [Int: Int] = [:]
        for plan in plans where plan.kind == .workout && plan.day < today && plan.day >= window {
            let weekday = calendar.component(.weekday, from: plan.day)
            planned[weekday, default: 0] += 1
            if lifts.contains(where: { calendar.isDate($0.startedAt, inSameDayAs: plan.day) }) { done[weekday, default: 0] += 1 }
        }
        for (weekday, count) in planned where count >= 3 {
            let made = done[weekday] ?? 0
            if Double(made) / Double(count) <= 0.4 {
                let name = calendar.weekdaySymbols[(weekday - 1) % 7]
                result.append(CoachProposal(id: "missed-\(weekday)", title: "\(name) sessions keep getting missed",
                                            reason: "Done \(made) of \(count) planned. Plan that session on a day that suits you, or use a split with one less day.",
                                            change: .info, priority: 38))
            }
        }

        let active = routines.filter { routine in
            routine.id != CardioIDs.run && routine.id != CardioIDs.basketball
                && routine.exercises.contains { !$0.exercise.isCardio }
        }
        if let first = lifts.map(\.startedAt).min(), now.timeIntervalSince(first) >= 42 * day, active.count >= 3 {
            let recent = lifts.filter { $0.startedAt >= now.addingTimeInterval(-42 * day) }.count
            let perWeek = Double(recent) / 6
            if perWeek < Double(active.count) * 0.6 {
                let days = Swift.max(2, Int(perWeek.rounded()))
                result.append(CoachProposal(id: "fit-split-\(days)", title: "Your routines need \(active.count) days — you train ~\(format(perWeek))",
                                            reason: "Some muscles go a week or more untouched. A \(days)-day split covers everything: Coach → Build a routine.",
                                            change: .info, priority: 48))
            }
        }
        return result
    }
}

// MARK: - Block review

public struct BlockReview: Hashable {
    public struct LiftChange: Hashable {
        public let name: String
        public let percent: Double
    }
    public let start: Date
    public let end: Date
    public let weeks: Int
    public let sessions: Int
    public let lifts: [LiftChange]
    /// Average hard sets per week for each muscle trained.
    public let muscleSets: [Muscle: Double]
    public let headline: String
    public let nextBlock: String
}

public extension CoachBrain {
    /// The build block that just finished: shown during the deload and the first week after.
    static func blockReview(profile: UserProfile, logs: [WorkoutLog], now: Date = .now, calendar: Calendar = .current) -> BlockReview? {
        guard let plan = profile.program, let position = plan.position(at: now, calendar: calendar) else { return nil }
        let blocks = plan.blocks
        guard blocks.count >= 2 else { return nil }
        let currentStart = calendar.date(byAdding: .day, value: -7 * Swift.max(position.block.weeks, 1), to: position.blockEnds) ?? now
        var index = position.blockIndex
        var end = currentStart
        if position.block.phase != .deload {
            // Only in the first week of a new block, right after a deload.
            guard position.week == 1 else { return nil }
            let previous = (index - 1 + blocks.count) % blocks.count
            guard blocks[previous].phase == .deload else { return nil }
            end = calendar.date(byAdding: .day, value: -7 * Swift.max(blocks[previous].weeks, 1), to: currentStart) ?? currentStart
            index = previous
        }
        let buildIndex = (index - 1 + blocks.count) % blocks.count
        let build = blocks[buildIndex]
        guard build.phase != .deload else { return nil }
        let weeks = Swift.max(build.weeks, 1)
        let start = calendar.date(byAdding: .day, value: -7 * weeks, to: end) ?? end
        guard start >= calendar.startOfDay(for: plan.startDate).addingTimeInterval(-3600) else { return nil }

        let lifts = liftLogs(logs).filter { $0.startedAt >= start && $0.startedAt < end }
        guard lifts.count >= 3 else { return nil }
        let earlyEnd = start.addingTimeInterval(14 * day)
        let lateStart = end.addingTimeInterval(-14 * day)

        var changes: [BlockReview.LiftChange] = []
        var names: [String: String] = [:]
        for workout in lifts { for exercise in workout.exercises where !exercise.isCardio { names[exercise.trendKey] = exercise.trendName } }
        for (key, name) in names {
            func best(_ from: Date, _ to: Date) -> Double? {
                lifts.filter { $0.startedAt >= from && $0.startedAt < to }
                    .flatMap(\.exercises).filter { $0.trendKey == key }
                    .compactMap { strengthValue($0) }.max()
            }
            guard let early = best(start, earlyEnd), let late = best(lateStart, end), early != 0 else { continue }
            // Works for both: heavier e1RM, or less assistance (stored as a negative number).
            changes.append(.init(name: name, percent: (late - early) / abs(early) * 100))
        }
        changes.sort { abs($0.percent) > abs($1.percent) }
        let up = changes.filter { $0.percent >= 1 }.count
        let down = changes.filter { $0.percent <= -2 }.count
        let sets = muscleSets(logs: lifts, from: start, to: end).mapValues { $0 / Double(weeks) }

        let headline: String
        if changes.isEmpty {
            headline = "\(lifts.count) sessions in \(weeks) weeks."
        } else {
            headline = "\(lifts.count) sessions in \(weeks) weeks · \(up) of \(changes.count) lifts up" + (down > 0 ? ", \(down) down" : "") + "."
        }
        let next: String
        if down >= 3 {
            next = "Several lifts dropped — next block keeps the same sets and the coach will add volume more slowly."
        } else if up * 2 >= changes.count {
            next = "Good block. Next block starts at the same sets; from week 2 the coach suggests adding a set where you're recovering well."
        } else {
            next = "Mixed block — check the suggestions for stalled lifts before the next block starts."
        }
        return BlockReview(start: start, end: end, weeks: weeks, sessions: lifts.count, lifts: Array(changes.prefix(8)),
                           muscleSets: sets, headline: headline, nextBlock: next)
    }
}

// MARK: - Templates

public extension ProgramPlan {
    /// A fixed-length coached block: build weeks then a deload, repeating.
    static func coachedBlock(focus: TrainingFocus, buildWeeks: Int = 4, start: Date = .now) -> ProgramPlan {
        ProgramPlan(name: focus == .strength ? "Coached strength block" : "Coached block",
                    blocks: [ProgramBlock(phase: focus == .strength ? .strength : .hypertrophy, weeks: buildWeeks),
                             ProgramBlock(phase: .deload, weeks: 1)],
                    startDate: Calendar.current.startOfDay(for: start))
    }
}
