import Foundation

public enum CoachAction: String, Hashable {
    case startDeloadWeek
    case endDeload
    case openMonthlyReport
}

public struct CoachInsight: Identifiable, Hashable {
    public enum Kind: String { case progress, consistency, plateau, recovery, body, motivation, program, volume }
    public var id = UUID()
    public var kind: Kind
    public var title: String
    public var message: String
    public var priority: Int = 0
    public var action: CoachAction? = nil

    public var systemImage: String {
        switch kind {
        case .progress: return "arrow.up.right.circle.fill"
        case .consistency: return "calendar.badge.checkmark"
        case .plateau: return "equal.circle.fill"
        case .recovery: return "bed.double.fill"
        case .body: return "figure"
        case .motivation: return "flame.fill"
        case .program: return "chart.bar.doc.horizontal"
        case .volume: return "square.stack.3d.up.fill"
        }
    }

    public var actionTitle: String? {
        switch action {
        case .startDeloadWeek: return "Start a deload week"
        case .endDeload: return "End deload now"
        case .openMonthlyReport: return "Open monthly report"
        case nil: return nil
        }
    }
}

public struct CoachContext {
    public var profile: UserProfile
    public var weeklyGoal: Int
    public var routines: [WorkoutRoutine]
    public var logs: [WorkoutLog]
    public var bodyWeight: [BodyMetricPoint]
    public var bodyFat: [BodyMetricPoint]
    public var readiness: Readiness?
    public var now: Date
    /// MK17: the app's own week numbers (breaks pause, sick / travel days lower this week's goal).
    /// nil = work it out from the logs and the normal goal.
    public var consistency: ConsistencyStats?

    public init(
        profile: UserProfile,
        weeklyGoal: Int,
        routines: [WorkoutRoutine],
        logs: [WorkoutLog],
        bodyWeight: [BodyMetricPoint] = [],
        bodyFat: [BodyMetricPoint] = [],
        readiness: Readiness? = nil,
        now: Date = .now,
        consistency: ConsistencyStats? = nil
    ) {
        self.profile = profile
        self.weeklyGoal = weeklyGoal
        self.routines = routines
        self.logs = logs
        self.bodyWeight = bodyWeight
        self.bodyFat = bodyFat
        self.readiness = readiness
        self.now = now
        self.consistency = consistency
    }

    /// Routine exercises (with today's program phase applied), de-duplicated by name.
    public var uniqueExercises: [ExerciseDefinition] {
        var seen = Set<String>()
        return routines.flatMap(\.exercises).map { profile.effective($0.exercise, at: now) }
            .filter { seen.insert($0.historyKey).inserted }
    }
}

/// Context-aware coaching: a plateau isn't automatically blamed on the program —
/// consistency, recovery, body-weight trend, goal and fatigue are checked first.
public enum CoachEngine {
    public static func insights(_ context: CoachContext) -> [CoachInsight] {
        let stats = context.consistency ?? ConsistencyCalculator.stats(logs: context.logs, weeklyGoal: context.weeklyGoal, now: context.now)
        let strength = StrengthAnalyzer.trend(logs: context.logs, now: context.now)
        let weightTrend = BodyTrendCalculator.weeklyChange(context.bodyWeight, now: context.now)
        let fatTrend = BodyTrendCalculator.weeklyChange(context.bodyFat, now: context.now)
        let deloadActive = context.profile.isDeloadActive(at: context.now)

        var result: [CoachInsight] = [consistencyInsight(stats, style: context.profile.coachStyle)]
        if let program = programInsight(context.profile, now: context.now) { result.append(program) }
        if let readiness = readinessInsight(context.readiness, style: context.profile.coachStyle) { result.append(readiness) }
        if let realism = goalRealismInsight(stats) { result.append(realism) }
        if let ready = progressionInsight(context) { result.append(ready) }
        result.append(contentsOf: plateauInsights(context, stats: stats, weightTrend: weightTrend))
        if !deloadActive {
            if let fatigue = fatigueInsight(context, stats: stats) { result.append(fatigue) }
        }
        if let recovery = heartRateRecoveryInsight(context.logs, deloadActive: deloadActive) { result.append(recovery) }
        if let volume = volumeInsight(context, stats: stats) { result.append(volume) }
        if let body = bodyInsight(goal: context.profile.goal, strength: strength, weightTrend: weightTrend, fatTrend: fatTrend) {
            result.append(body)
        }
        return result.sorted { $0.priority > $1.priority }
    }

    // MARK: Consistency & motivation

    static func consistencyInsight(_ stats: ConsistencyStats, style: CoachStyle) -> CoachInsight {
        let done = stats.thisWeekCount
        let goal = stats.weeklyGoal
        let remaining = max(goal - done, 0)
        // MK17: a full break, or a week of sick / travel days, has no target — no "X to go".
        if goal <= 0 {
            return CoachInsight(kind: .consistency, title: "No target this week",
                                message: "You're on a break or off sick / travelling, so nothing is due. \(done > 0 ? "\(done) done anyway — nice. " : "")Rest up; the streak is paused, not broken.",
                                priority: 2)
        }
        let streakNote = stats.streakWeeks >= 2 ? " \(stats.streakWeeks) weeks in a row hitting your target." : ""
        var trendNote = ""
        if let previous = stats.previous4WeeksAdherence, abs(previous - stats.last4WeeksAdherence) >= 0.1 {
            let direction = stats.last4WeeksAdherence > previous ? "up" : "down"
            trendNote = " Adherence is \(direction) from \(GFFormat.percent(previous)) to \(GFFormat.percent(stats.last4WeeksAdherence)) over the last month."
        }

        if done >= goal {
            let message: String
            switch style {
            case .pushMe: message = "\(done)/\(goal) done. Don't coast — keep the standard next week."
            case .motivating: message = "\(done) of \(goal) workouts done this week. That's how progress compounds!"
            case .analytical: message = "\(done)/\(goal) sessions (\(GFFormat.percent(stats.thisWeekAdherence))). Last 4 weeks: \(stats.last4WeeksCount)/\(stats.last4WeeksTarget)."
            case .supportive: message = "You hit your goal of \(goal) this week. Nice work looking after yourself."
            case .hardTruth: message = "\(done)/\(goal). Good. That's the minimum, not a medal. Do it again next week."
            case .heartbreak: message = "\(done)/\(goal). Every session is a version of you she never met. Keep building him."
            }
            return CoachInsight(kind: .consistency, title: "Weekly goal hit", message: message + streakNote + trendNote, priority: 3)
        }

        let message: String
        switch style {
        case .pushMe: message = "\(done)/\(goal). \(remaining) to go — get in today."
        case .motivating: message = "You're at \(done) / \(goal) this week. One workout today gets you moving again."
        case .analytical: message = "Week adherence \(GFFormat.percent(stats.thisWeekAdherence)). Last 4 weeks: \(stats.last4WeeksCount)/\(stats.last4WeeksTarget) (\(GFFormat.percent(stats.last4WeeksAdherence)))."
        case .supportive: message = "\(remaining) more this week would hit your goal — and any session counts."
        case .hardTruth: message = "\(done)/\(goal). Nobody is coming to do your \(remaining) remaining sessions for you. Today."
        case .heartbreak: message = "\(done)/\(goal). Missing her won't add a rep. \(remaining) more sessions will."
        }
        return CoachInsight(kind: .consistency, title: "\(done) / \(goal) workouts this week", message: message + streakNote + trendNote, priority: 6)
    }

    static func goalRealismInsight(_ stats: ConsistencyStats) -> CoachInsight? {
        guard stats.weeksTracked >= 3, stats.averagePerWeek + 0.75 < Double(stats.weeklyGoal) else { return nil }
        let suggested = max(1, Int(stats.averagePerWeek.rounded()))
        return CoachInsight(
            kind: .motivation,
            title: "Make the goal realistic",
            message: "You've averaged \(String(format: "%.1f", stats.averagePerWeek)) sessions/week against a \(stats.weeklyGoal)-day target. Consider \(suggested) days/week, hit it consistently, then build up.",
            priority: 5
        )
    }

    // MARK: Program, deload & readiness

    static func programInsight(_ profile: UserProfile, now: Date) -> CoachInsight? {
        if let until = profile.deloadUntil, until > now {
            return CoachInsight(
                kind: .program,
                title: "Deload week",
                message: "Until \(until.formatted(.dateTime.weekday(.wide))): one less set per exercise and ~10% lighter. These sessions won't count against your progression.",
                priority: 9,
                action: .endDeload
            )
        }
        guard let plan = profile.program, let position = plan.position(at: now) else { return nil }
        let block = position.block
        let message = "Week \(position.week) of \(block.weeks) in your \(block.phase.title.lowercased()) block. \(block.phase.summary)"
        return CoachInsight(kind: .program, title: "\(plan.name): \(block.phase.title)", message: message, priority: block.phase == .deload ? 9 : 2)
    }

    static func readinessInsight(_ readiness: Readiness?, style: CoachStyle) -> CoachInsight? {
        guard let readiness else { return nil }
        let why = readiness.reasons.prefix(2).joined(separator: ", ")
        switch readiness.level {
        case .low:
            let advice = (style == .pushMe || style == .hardTruth || style == .heartbreak)
                ? "Still train — but keep the weights and drop a set, or start a light session."
                : "Consider a light session today (one less set, ~10% lighter), or swap in some easy cardio."
            return CoachInsight(kind: .recovery, title: "Recovery is low today", message: "\(why). \(advice)", priority: 8)
        case .moderate:
            return CoachInsight(kind: .recovery, title: "Moderately recovered", message: "\(why). Train as planned but don't force extra sets.", priority: 4)
        case .ready:
            return CoachInsight(kind: .recovery, title: "Recovered and ready", message: "\(why). A good day to push for reps.", priority: 1)
        }
    }

    // MARK: Progression

    static func progressionInsight(_ context: CoachContext) -> CoachInsight? {
        var ready: [String] = []
        for exercise in context.uniqueExercises where !exercise.isCardio {
            let recommendation = ProgressionEngine.recommendation(for: exercise, previous: context.logs.previousLog(for: exercise))
            if case .increaseWeight(let kg) = recommendation.action {
                let why: String
                switch recommendation.title {
                case "Felt easy — go up": why = "3+ reps left on every set"
                case "New rep range": why = "new rep range"
                default: why = "top of the range on every set"
                }
                ready.append("\(exercise.name) → \(exercise.formatLoad(kg)) (\(why))")
            }
        }
        guard !ready.isEmpty else { return nil }
        return CoachInsight(
            kind: .progress,
            title: "Ready to add weight",
            message: ready.joined(separator: "; ") + ".",
            priority: 7
        )
    }

    static func isPlateau(_ history: [ExerciseHistoryPoint], increment: Double) -> Bool {
        let recent = Array(history.filter { !$0.log.isCardio }.suffix(4))
        guard recent.count >= 4 else { return false }
        let totals = recent.map(\.log.totalReps)
        let weights = recent.map(\.log.bestWeightKg)
        let repSpread = (totals.max() ?? 0) - (totals.min() ?? 0)
        let weightSpread = (weights.max() ?? 0) - (weights.min() ?? 0)
        let improving = (totals.last ?? 0) > (totals.first ?? 0) || (weights.last ?? 0) > (weights.first ?? 0)
        return !improving && repSpread <= 1 && weightSpread < max(increment, 0.1)
    }

    static func plateauInsights(_ context: CoachContext, stats: ConsistencyStats, weightTrend: Double?) -> [CoachInsight] {
        var result: [CoachInsight] = []
        let progressionLogs = context.logs.filter { !$0.isAtypical }
        for exercise in context.uniqueExercises where !exercise.isCardio {
            let history = progressionLogs.sameWayHistory(for: exercise)
            guard isPlateau(history, increment: exercise.weightIncrementKg) else { continue }

            let message: String
            if let readiness = context.readiness, readiness.level == .low {
                message = "\(exercise.name) has been flat for 4 sessions, and your recovery markers are low. Sort sleep first before changing the program."
            } else if stats.weeksTracked >= 2, stats.last4WeeksAdherence < 0.75 {
                message = "\(exercise.name) has been flat for 4 sessions, but you've only hit \(GFFormat.percent(stats.last4WeeksAdherence)) of planned workouts recently. Keep your current program — focus on hitting your sessions first."
            } else if let trend = weightTrend, trend < -0.15,
                      context.profile.goal == .loseFat || context.profile.goal == .recomposition {
                message = "\(exercise.name) is holding steady while body weight drops ~\(String(format: "%.1f", abs(trend))) kg/week. Maintaining strength while losing weight is still progress."
            } else {
                let options = exercise.alternativeList.map(\.name).prefix(2).joined(separator: " or ")
                let swap = options.isEmpty ? "swap to a similar variation" : "try your preset swap (\(options)) for a few weeks"
                message = "\(exercise.name) has been flat for 4 sessions. Options: add one rep per set before adding weight, add a set, shift the rep range (e.g. \(max(exercise.repMin - 2, 1))–\(max(exercise.repMax - 2, 2))), or \(swap)."
            }
            result.append(CoachInsight(kind: .plateau, title: "Plateau: \(exercise.name)", message: message, priority: 5))
            if result.count == 3 { break }
        }
        return result
    }

    // MARK: Fatigue & recovery

    static func fatigueInsight(_ context: CoachContext, stats: ConsistencyStats) -> CoachInsight? {
        let recent = context.logs.filter { !$0.isAtypical }.sorted { $0.startedAt > $1.startedAt }.prefix(3)
        guard recent.count == 3 else { return nil }
        var declines = 0
        var comparisons = 0
        for workout in recent {
            for exercise in workout.exercises {
                guard let previous = context.logs.previousLog(where: { $0.matches(exercise) }, before: workout.startedAt) else { continue }
                comparisons += 1
                if ProgressionEngine.compare(current: exercise, previous: previous, context: workout.tagSet).kind == .declined { declines += 1 }
            }
        }
        let trainingHard = stats.weeklyGoal > 0
            && (stats.thisWeekCount >= stats.weeklyGoal || stats.last4WeeksAdherence >= 0.95)
        guard trainingHard, comparisons >= 4, Double(declines) / Double(comparisons) >= 0.5 else { return nil }
        return CoachInsight(
            kind: .recovery,
            title: "Fatigue may be building",
            message: "Performance dropped on \(declines) of your last \(comparisons) exercise comparisons while training frequency is high. A deload week (one less set, ~10% lighter) usually brings strength back up.",
            priority: 8,
            action: .startDeloadWeek
        )
    }

    static func heartRateRecoveryInsight(_ logs: [WorkoutLog], deloadActive: Bool) -> CoachInsight? {
        guard let change = RecoveryTrend.change(logs: logs), change.baseline >= 8 else { return nil }
        let ratio = change.recent / change.baseline
        if ratio < 0.8 {
            return CoachInsight(
                kind: .recovery,
                title: "Heart-rate recovery is down",
                message: "Your HR drops \(Int(change.recent.rounded())) bpm in the first minute of rest lately, vs \(Int(change.baseline.rounded())) normally. That's an early fatigue sign.",
                priority: 7,
                action: deloadActive ? nil : .startDeloadWeek
            )
        }
        if ratio > 1.15 {
            return CoachInsight(
                kind: .recovery,
                title: "Recovering faster between sets",
                message: "Heart-rate recovery is up to \(Int(change.recent.rounded())) bpm/min from \(Int(change.baseline.rounded())). Your conditioning is improving.",
                priority: 2
            )
        }
        return nil
    }

    // MARK: Volume per muscle

    static func volumeInsight(_ context: CoachContext, stats: ConsistencyStats) -> CoachInsight? {
        guard stats.weeksTracked >= 2 else { return nil }
        let lookup = MuscleVolume.lookup(from: context.routines)
        let averages = MuscleVolume.weeklyAverage(logs: context.logs, weeks: 2, now: context.now, categoryLookup: lookup)
        let trained = Set(context.routines.flatMap(\.exercises).map(\.exercise.category))
        let low = ExerciseCategory.muscleGroups
            .filter { trained.contains($0) && (averages[$0] ?? 0) < 6 }
            .map { "\($0.title) (~\(Int((averages[$0] ?? 0).rounded())))" }
        guard !low.isEmpty else { return nil }
        return CoachInsight(
            kind: .volume,
            title: "Low weekly volume",
            message: "Sets per week over the last 2 weeks: \(low.prefix(3).joined(separator: ", ")). Around 10–20 hard sets per muscle per week is a common range for growth.",
            priority: 3
        )
    }

    // MARK: Body composition

    static func bodyInsight(goal: TrainingGoal, strength: StrengthTrend, weightTrend: Double?, fatTrend: Double?) -> CoachInsight? {
        guard let weight = weightTrend else { return nil }
        let gaining = weight > 0.15
        let losing = weight < -0.15
        let fatRising = (fatTrend ?? 0) > 0.25
        let rate = "\(GFFormat.signed(weight, decimals: 2)) kg/week"

        // MK17: the goal decides what a trend means (gaining on a cut isn't "lean gain"; losing on a bulk isn't progress).
        if gaining && goal == .loseFat {
            return CoachInsight(kind: .body, title: "Weight is trending up", message: "Body weight is \(rate)\(fatRising ? " and body fat is rising" : "") while your goal is Lose Fat. Worth checking intake before changing training.", priority: 6)
        }
        if gaining && (fatRising || weight > 0.5) {
            return CoachInsight(kind: .body, title: "Weight gain may be too fast", message: "Body weight is trending \(rate)\(fatRising ? " and body fat is rising" : ""). Your body-weight increase may be happening faster than intended for lean gain.", priority: 6)
        }
        if gaining && strength == .up {
            return CoachInsight(kind: .body, title: "Productive gain", message: "Body weight \(rate) while strength is rising — consistent with productive mass gain.", priority: 4)
        }
        if losing && (goal == .buildMuscle || goal == .getStronger) {
            return CoachInsight(kind: .body, title: "Losing weight on a muscle-building goal", message: "Body weight is \(rate) while your goal is \(goal.title). Building muscle needs a small surplus — add about 200–300 kcal a day and re-check in 2 weeks.", priority: 6)
        }
        if losing && strength == .down {
            return CoachInsight(kind: .body, title: "Strength dipping in a deficit", message: "Weight is \(rate) and strength is slipping. Consider a slower rate of loss and prioritise protein and sleep.", priority: 6)
        }
        if losing && (strength == .flat || strength == .up) {
            return CoachInsight(kind: .body, title: "Holding strength while losing weight", message: "Body weight \(rate) while strength is \(strength == .up ? "rising" : "stable"). That's still positive progress.", priority: 4)
        }
        return nil
    }
}
