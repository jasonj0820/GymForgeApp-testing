import Foundation

/// Phase-aware analysis: plateaus (and why), muscle / strength trends, bulk & cut rate,
/// deload and mini-cut suggestions, weak points, weekly wins and phase report cards.
/// "Cautious" by design: 4-week averages, and muscle-loss warnings need strength to drop too.
struct PhaseCoach {
    let phase: NutritionPhase
    let phaseRecord: PhaseRecord?
    let logs: [WorkoutLog]
    let routines: [WorkoutRoutine]
    let weights: [BodyMetricPoint]
    let fats: [BodyMetricPoint]
    let sleep: [SleepNight]
    let nutrition: [NutritionDay]
    let proteinTarget: Double?
    let weeklyGoal: Int
    let deloadUntil: Date?
    let miniCutThreshold: Double
    var now: Date = .now

    private var cal: Calendar { .current }
    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    // MARK: - Generic helpers

    /// Least-squares slope in units per day.
    static func slopePerDay(_ points: [(date: Date, value: Double)]) -> Double? {
        guard points.count >= 2, let first = points.map({ $0.date }).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map { $0.value }
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) { num += (x - mx) * (y - my); den += (x - mx) * (x - mx) }
        return den > 0 ? num / den : nil
    }

    private func average(_ points: [BodyMetricPoint], from start: Date, to end: Date) -> Double? {
        let values = points.filter { $0.date >= start && $0.date < end }.map { $0.value }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Lean mass over the last ~15 months (keeps the weight × fat matching fast).
    var leanPoints: [BodyMetricPoint] {
        let cutoff = daysAgo(460)
        return BodyTrendCalculator.leanMass(weights: weights.filter { $0.date >= cutoff }, fats: fats.filter { $0.date >= cutoff })
    }

    /// History of one exercise (strength sessions only), oldest first — MK17: only sessions done the same
    /// way as the latest one, so a planned variation (paused, wide grip) isn't read as a plateau.
    func history(_ exercise: ExerciseDefinition) -> [(date: Date, log: ExerciseLog)] {
        let all: [(date: Date, log: ExerciseLog)] = logs.sorted { $0.startedAt < $1.startedAt }.compactMap { workout in
            guard !workout.isAtypical,
                  let match = workout.exercises.first(where: { $0.matches(exercise) }),
                  !match.isCardio, match.estimatedOneRepMaxKg > 0 else { return nil }
            return (workout.startedAt, match)
        }
        guard let key = all.last?.log.variationKey else { return all }
        return all.filter { $0.log.variationKey == key }
    }

    // MARK: - Body weight rate (bulk / cut monitor)

    struct RateStatus {
        enum Level { case good, low, high, needData }
        let level: Level
        let weeklyPercent: Double?
        let title: String
        let message: String
    }

    var weeklyWeightPercent: Double? {
        let recent = weights.filter { $0.date >= daysAgo(28) }
        guard recent.count >= 6, let first = recent.map(\.date).min(), let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= 14 * 86_400,
              let slope = Self.slopePerDay(recent.map { (date: $0.date, value: $0.value) }) else { return nil }
        let mean = recent.map(\.value).reduce(0, +) / Double(recent.count)
        return slope * 7 / mean * 100
    }

    var rate: RateStatus {
        guard let pct = weeklyWeightPercent else {
            return RateStatus(level: .needData, weeklyPercent: nil, title: "Need more weigh-ins",
                              message: "Weigh in at least 6 times over 2+ weeks (Body tab, or Apple Health) to track your rate.")
        }
        let text = String(format: "%+.2f%% body weight per week", pct)
        switch phase {
        case .bulking:
            if pct < 0.1 { return RateStatus(level: .low, weeklyPercent: pct, title: "Bulk too slow", message: "\(text). Aim for +0.25–0.5%. Add about 200 kcal a day (e.g. an extra snack) and re-check in 2 weeks.") }
            if pct > 0.6 { return RateStatus(level: .high, weeklyPercent: pct, title: "Bulk too fast", message: "\(text). Above ~0.5% a week it's mostly fat. Trim about 200 kcal a day.") }
            // MK17: only say "sweet spot" when it is one.
            if pct < 0.25 { return RateStatus(level: .good, weeklyPercent: pct, title: "Bulk on the slow side", message: "\(text) — a lean pace. Fine while your lifts go up; if they stall, add about 100–150 kcal a day.") }
            if pct > 0.5 { return RateStatus(level: .good, weeklyPercent: pct, title: "Bulk at the fast end", message: "\(text) — just above the 0.25–0.5% sweet spot. Fine for now; trim about 100 kcal a day if body fat starts climbing.") }
            return RateStatus(level: .good, weeklyPercent: pct, title: "Bulk on track", message: "\(text) — right in the 0.25–0.5% sweet spot.")
        case .cutting:
            if pct < -1.0 { return RateStatus(level: .high, weeklyPercent: pct, title: "Losing too fast", message: "\(text). Faster than ~1% a week risks muscle. Add 150–250 kcal a day and keep protein at 2.2 g/kg.") }
            if pct > -0.25 { return RateStatus(level: .low, weeklyPercent: pct, title: "Cut has stalled", message: "\(text). Aim for −0.5 to −1% a week: trim ~200 kcal or add 2–3k steps a day.") }
            return RateStatus(level: .good, weeklyPercent: pct, title: "Cut on track", message: "\(text) — steady loss that protects muscle.")
        case .recomp:
            if abs(pct) > 0.35 { return RateStatus(level: .high, weeklyPercent: pct, title: "Weight is moving", message: "\(text). A recomp keeps weight roughly stable — eat closer to maintenance.") }
            return RateStatus(level: .good, weeklyPercent: pct, title: "Weight stable", message: "\(text) — right for a recomp.")
        }
    }

    // MARK: - Muscle & strength trends (4-week averages)

    /// Lean mass: last 28 days' average minus the 28 days before (kg).
    var leanChange: Double? {
        let lean = leanPoints
        guard let recent = average(lean, from: daysAgo(28), to: now),
              let before = average(lean, from: daysAgo(56), to: daysAgo(28)) else { return nil }
        return recent - before
    }

    var fatAverage28: Double? { average(fats, from: daysAgo(28), to: now) }

    /// Average % change in best e1RM (last 4 weeks vs the 4 before) across lifts trained in both.
    var strengthChange: Double? {
        let recentStart = daysAgo(28), oldStart = daysAgo(56)
        var best: [String: (recent: Double, old: Double)] = [:]
        for workout in logs where workout.startedAt >= oldStart && !workout.isAtypical {
            for exercise in workout.exercises where !exercise.isCardio && exercise.estimatedOneRepMaxKg > 0 {
                let key = exercise.trendKey   // MK17: variations compared separately
                var entry = best[key] ?? (0, 0)
                if workout.startedAt >= recentStart { entry.recent = max(entry.recent, exercise.estimatedOneRepMaxKg) }
                else { entry.old = max(entry.old, exercise.estimatedOneRepMaxKg) }
                best[key] = entry
            }
        }
        let changes = best.values.filter { $0.recent > 0 && $0.old > 0 }.map { ($0.recent / $0.old - 1) * 100 }
        guard changes.count >= 2 else { return nil }
        return changes.reduce(0, +) / Double(changes.count)
    }

    struct Warning: Identifiable {
        let id: String
        let title: String
        let message: String
        let severe: Bool
    }

    /// Cautious muscle-loss warning: lean mass down 0.5+ kg AND strength down 3%+ (4-week averages,
    /// short / easy / tired sessions left out — MK11.1).
    var muscleWarning: Warning? {
        guard phase != .bulking, let lean = leanChange, let strength = strengthChange,
              lean <= -0.5, strength <= -3 else { return nil }
        let tips = phase == .cutting
            ? "Slow the cut (add 150–250 kcal), keep lifting heavy (cut sets, not weight), and hit 2.2 g/kg protein every day."
            : "Make sure protein is 2.2 g/kg, you're not in a big deficit, and you're progressing your lifts — recomp needs a training stimulus."
        return Warning(id: "muscle", title: "Possible muscle loss",
                       message: String(format: "Lean mass %.1f kg and strength %.0f%% over the last 4 weeks vs the 4 before. ", lean, strength) + tips,
                       severe: true)
    }

    // MARK: - Plateaus

    struct Plateau: Identifiable {
        let id: String
        let exercise: ExerciseDefinition
        let kind: Kind
        let headline: String
        let advice: [String]
        enum Kind { case stalled, strengthDrop }
    }

    /// Plateau / cut strength-drop check for one exercise (nil = fine).
    func plateau(for exercise: ExerciseDefinition) -> Plateau? {
        guard !exercise.isCardio else { return nil }
        // MK11.1: more cautious — 4 normal sessions spanning 3+ weeks before anything is called a plateau.
        let points = history(exercise).filter { $0.date >= daysAgo(84) }
        guard points.count >= 5, let last = points.last, last.date >= daysAgo(30) else { return nil }
        let recent = points.suffix(4)
        let earlier = points.dropLast(4)
        guard let firstRecent = recent.first?.date, last.date.timeIntervalSince(firstRecent) >= 21 * 86_400 else { return nil }
        let recentBest = recent.map { $0.log.estimatedOneRepMaxKg }.max() ?? 0
        let earlierBest = earlier.map { $0.log.estimatedOneRepMaxKg }.max() ?? 0
        guard earlierBest > 0 else { return nil }

        if phase == .cutting {
            // On a cut, flat strength is the goal. Only flag a real drop.
            let phaseStart = phaseRecord?.start ?? daysAgo(84)
            let reference = points.filter { $0.date <= phaseStart.addingTimeInterval(21 * 86_400) }
                .map { $0.log.estimatedOneRepMaxKg }.max() ?? earlierBest
            // Both of the last two sessions have to be down — one bad day isn't strength loss.
            let lastTwo = points.suffix(2).map { $0.log.estimatedOneRepMaxKg }.max() ?? 0
            guard lastTwo < reference * 0.95 else { return nil }
            let drop = (1 - lastTwo / reference) * 100
            return Plateau(id: exercise.historyKey, exercise: exercise, kind: .strengthDrop,
                           headline: String(format: "Strength down %.0f%% since the start of the cut", drop),
                           advice: Array(cutAdvice(exercise).prefix(3)))
        }

        guard recentBest <= earlierBest else { return nil }
        let weeks = Int(last.date.timeIntervalSince(firstRecent) / (7 * 86_400))
        return Plateau(id: exercise.historyKey, exercise: exercise, kind: .stalled,
                       headline: "No progress in \(recent.count) sessions over \(weeks) weeks",
                       advice: Array(stallCauses(exercise, recent: Array(recent.map { $0.log }), all: points).prefix(3)))
    }

    private func cutAdvice(_ exercise: ExerciseDefinition) -> [String] {
        var tips: [String] = []
        if let pct = weeklyWeightPercent, pct < -1.0 {
            tips.append("You're losing weight fast — add 150–250 kcal a day.")
        }
        if let protein = proteinShortfall { tips.append(protein) }
        tips.append("Keep the weight heavy; drop a set instead of dropping the load.")
        if fatigued { tips.append("Recovery is low — take a lighter session this week.") }
        return tips
    }

    /// Short-sleep / failure-heavy training signals.
    var fatigued: Bool { failureShare >= 0.5 || (averageSleep.map { $0 < 6.5 } ?? false) }

    var averageSleep: Double? {
        let nights = sleep.filter { $0.date >= daysAgo(7) && $0.hoursAsleep > 0 }
        guard nights.count >= 4 else { return nil }
        return nights.map(\.hoursAsleep).reduce(0, +) / Double(nights.count)
    }

    /// Share of effort-rated sets in the last 14 days taken to failure.
    var failureShare: Double {
        let rated = logs.filter { $0.startedAt >= daysAgo(14) }
            .flatMap { $0.exercises.flatMap(\.sets) }.compactMap(\.rir)
        guard rated.count >= 6 else { return 0 }
        return Double(rated.filter { $0 == 0 }.count) / Double(rated.count)
    }

    var proteinShortfall: String? {
        guard let target = proteinTarget, target > 0 else { return nil }
        let logged = nutrition.filter { $0.day >= daysAgo(14) && $0.proteinG > 0 }
        guard logged.count >= 5 else { return nil }
        let avg = logged.map(\.proteinG).reduce(0, +) / Double(logged.count)
        guard avg < target * 0.8 else { return nil }
        return "Protein is averaging \(Int(avg)) g vs your \(Int(target)) g target — fix that before changing the program."
    }

    private func stallCauses(_ exercise: ExerciseDefinition, recent: [ExerciseLog], all: [(date: Date, log: ExerciseLog)]) -> [String] {
        var tips: [String] = []
        let recentSets = recent.flatMap(\.sets)
        let rated = recentSets.compactMap(\.rir)
        if (rated.count >= 3 && Double(rated.filter { $0 == 0 }.count) / Double(rated.count) >= 0.5) || (averageSleep.map { $0 < 6.5 } ?? false) {
            tips.append("Fatigue, not strength: lots of sets to failure or short sleep. Take a light session (or a deload week), then come back.")
        }
        if phase == .bulking, let pct = weeklyWeightPercent, pct < 0.1 {
            tips.append("You're not actually gaining weight (\(String(format: "%+.2f", pct))%/week). Add about 200 kcal a day — muscle needs a surplus.")
        }
        if let protein = proteinShortfall { tips.append(protein) }
        if let first = all.first?.date, first <= daysAgo(56) {
            let swap = exercise.alternativeList.first?.name
            tips.append(swap.map { "You've done this for 8+ weeks — swap to \($0) for 4–6 weeks, then come back." }
                        ?? "You've done this for 8+ weeks — switch to a variation (incline, dumbbell, machine) for 4–6 weeks.")
        }
        let topReps = recent.map(\.repsAtBestWeight)
        if !topReps.isEmpty, topReps.allSatisfy({ $0 <= exercise.repMin + 1 }) {
            tips.append("Reps are stuck at the bottom of the range — drop the weight ~5–10% and rebuild to \(exercise.repMax) reps.")
        } else {
            tips.append("Add one set, or run a lower rep range (e.g. \(max(exercise.repMin - 3, 4))–\(max(exercise.repMax - 4, 6))) for 4 weeks with 3-second lowering.")
        }
        return tips
    }

    func plateaus(in routine: WorkoutRoutine) -> [Plateau] {
        var seen = Set<String>()
        return routine.exercises.compactMap { item in
            guard seen.insert(item.exercise.historyKey).inserted else { return nil }
            return plateau(for: item.exercise)
        }
    }

    /// All distinct exercises in your routines that are stalled.
    var allPlateaus: [Plateau] {
        var seen = Set<String>()
        return routines.flatMap(\.exercises).compactMap { item in
            guard seen.insert(item.exercise.historyKey).inserted else { return nil }
            return plateau(for: item.exercise)
        }
    }

    // MARK: - Auto deload

    var deloadSuggestion: Warning? {
        if let until = deloadUntil, until > daysAgo(28) { return nil }
        if logs.contains(where: { $0.isDeload == true && $0.startedAt >= daysAgo(28) }) { return nil }
        let trained = Set(logs.filter { $0.startedAt >= daysAgo(21) }.flatMap(\.exercises).filter { !$0.isCardio }
            .map { ExerciseLog.key(for: $0.exerciseName) })
        let stalled = allPlateaus.filter { $0.kind == .stalled && trained.contains($0.exercise.historyKey) }
        guard stalled.count >= 3 || (trained.count >= 4 && Double(stalled.count) / Double(trained.count) >= 0.4) else { return nil }
        var signals: [String] = []
        if failureShare >= 0.4 { signals.append("\(Int(failureShare * 100))% of rated sets to failure") }
        if let sleep = averageSleep, sleep < 6.5 { signals.append(String(format: "sleep averaging %.1f h", sleep)) }
        if let hr = RecoveryTrend.change(logs: logs), hr.recent < hr.baseline * 0.9 { signals.append("heart-rate recovery down") }
        guard !signals.isEmpty else { return nil }
        return Warning(id: "deload", title: "Time for a deload week",
                       message: "\(stalled.count) lifts have stalled and " + signals.joined(separator: ", ") + ". A week at one less set and ~10% lighter usually brings strength back.",
                       severe: false)
    }

    // MARK: - Weak points

    struct WeakPoint: Identifiable {
        let id: ExerciseCategory
        let sets: Double
        let progress: Double?
        let message: String
    }

    var weakPoints: [WeakPoint] {
        let lookup = MuscleVolume.lookup(from: routines)
        let volume = MuscleVolume.weeklyAverage(logs: logs, weeks: 4, now: now, categoryLookup: lookup)
        // Strength progress per muscle: best e1RM in the last 4 weeks vs weeks 5–8.
        var progress: [ExerciseCategory: [Double]] = [:]
        var best: [String: (category: ExerciseCategory, recent: Double, old: Double)] = [:]
        for workout in logs where workout.startedAt >= daysAgo(56) && !workout.isAtypical {
            for exercise in workout.exercises where !exercise.isCardio && exercise.estimatedOneRepMaxKg > 0 {
                let key = exercise.trendKey
                let category = exercise.category ?? lookup[ExerciseLog.key(for: exercise.exerciseName)] ?? ExerciseCategory.guess(from: exercise.exerciseName)
                var entry = best[key] ?? (category, 0, 0)
                if workout.startedAt >= daysAgo(28) { entry.recent = max(entry.recent, exercise.estimatedOneRepMaxKg) }
                else { entry.old = max(entry.old, exercise.estimatedOneRepMaxKg) }
                best[key] = entry
            }
        }
        for entry in best.values where entry.recent > 0 && entry.old > 0 {
            progress[entry.category, default: []].append((entry.recent / entry.old - 1) * 100)
        }
        let main: [ExerciseCategory] = [.chest, .back, .shoulders, .legs, .biceps, .triceps]
        let trainedGroups = main.filter { (volume[$0] ?? 0) > 0 || progress[$0] != nil }
        guard trainedGroups.count >= 3 else { return [] }
        let avgProgress: [ExerciseCategory: Double] = progress.mapValues { $0.reduce(0, +) / Double($0.count) }
        let overall = avgProgress.values.isEmpty ? 0 : avgProgress.values.reduce(0, +) / Double(avgProgress.count)

        var result: [WeakPoint] = []
        for group in main {
            let sets = volume[group] ?? 0
            let prog = avgProgress[group]
            let minimum: Double = (group == .biceps || group == .triceps) ? 6 : 10
            if sets < minimum {
                result.append(WeakPoint(id: group, sets: sets, progress: prog,
                    message: String(format: "%@: %.0f sets/week — below the ~%.0f that grows muscle. Add 2–3 sets (a new exercise or an extra set on an existing one).", group.title, sets, minimum)))
            } else if let prog, prog < overall - 3, prog < 1 {
                result.append(WeakPoint(id: group, sets: sets, progress: prog,
                    message: String(format: "%@: strength %+.1f%% vs %+.1f%% overall. Train it first in the session and add a set.", group.title, prog, overall)))
            }
        }
        return Array(result.sorted { ($0.progress ?? -99) < ($1.progress ?? -99) }.prefix(3))
    }

    // MARK: - Mini-cut

    var miniCutPrompt: Warning? {
        guard phase == .bulking, phaseRecord?.isMiniCut != true, let fat = fatAverage28, fat > miniCutThreshold else { return nil }
        return Warning(id: "minicut", title: "Mini-cut time?",
                       message: String(format: "Body fat is averaging %.1f%% (your limit: %.0f%%). A 4–6 week mini-cut at ~0.75%%/week brings it down and makes the next bulk leaner.", fat, miniCutThreshold),
                       severe: false)
    }

    /// Mini-cut has reached its planned end.
    var miniCutDone: Bool {
        guard let record = phaseRecord, record.isMiniCut else { return false }
        if let end = record.plannedEnd, now >= end { return true }
        // MK10.2: or body fat is back down ~5% under the limit (2+ weeks in).
        if now.timeIntervalSince(record.start) >= 14 * 86_400,
           let recent = average(fats, from: daysAgo(14), to: now), recent <= miniCutThreshold - 5 { return true }
        return false
    }

    // MARK: - Weekly wins (for Sergeant Cluck)

    struct Wins {
        let liftsUp: [String]
        let leanUp: Double?
        var any: Bool { !liftsUp.isEmpty || (leanUp ?? 0) >= 0.2 }
    }

    /// Lifts whose best e1RM this week beat the previous 4 weeks, and lean mass trend.
    var weeklyWins: Wins {
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return Wins(liftsUp: [], leanUp: nil) }
        let before = week.start.addingTimeInterval(-28 * 86_400)
        var thisWeek: [String: (name: String, value: Double)] = [:]
        var previous: [String: Double] = [:]
        for workout in logs where workout.startedAt >= before && workout.isDeload != true {
            for exercise in workout.exercises where !exercise.isCardio && exercise.estimatedOneRepMaxKg > 0 {
                let key = exercise.trendKey
                if workout.startedAt >= week.start {
                    if exercise.estimatedOneRepMaxKg > (thisWeek[key]?.value ?? 0) { thisWeek[key] = (exercise.trendName, exercise.estimatedOneRepMaxKg) }
                } else {
                    previous[key] = max(previous[key] ?? 0, exercise.estimatedOneRepMaxKg)
                }
            }
        }
        let up = thisWeek.compactMap { key, entry -> String? in
            guard let old = previous[key], old > 0, entry.value > old * 1.005 else { return nil }
            return entry.name
        }.sorted()
        return Wins(liftsUp: up, leanUp: leanChange)
    }

    // MARK: - Phase report card

    struct LiftChange: Identifiable {
        let id: String
        let start: Double
        let end: Double
        var percent: Double { start > 0 ? (end / start - 1) * 100 : 0 }
    }

    struct ReportCard {
        let record: PhaseRecord
        let weeks: Int
        let sessions: Int
        let adherence: Double
        let weightChange: Double?
        let leanChange: Double?
        let fatChange: Double?
        let lifts: [LiftChange]
        let grade: String
        let verdict: String
        var averageStrength: Double? {
            lifts.isEmpty ? nil : lifts.map(\.percent).reduce(0, +) / Double(lifts.count)
        }
    }

    func report(for record: PhaseRecord) -> ReportCard {
        let end = record.end ?? now
        let span = max(end.timeIntervalSince(record.start), 86_400)
        let weeks = max(Int((span / (7 * 86_400)).rounded()), 1)
        // MK17: gym sessions only — runs and basketball are extras, not sessions (same as everywhere else).
        let inPhase = logs.filter { $0.startedAt >= record.start && $0.startedAt <= end && $0.countsAsTraining }
        let adherence = min(Double(inPhase.count) / Double(max(weeks * weeklyGoal, 1)), 1)

        func edgeAverage(_ points: [BodyMetricPoint]) -> Double? {
            let window = min(10.0 * 86_400, span / 3)
            let first = points.filter { $0.date >= record.start && $0.date < record.start.addingTimeInterval(window) }.map(\.value)
            let last = points.filter { $0.date <= end && $0.date > end.addingTimeInterval(-window) }.map(\.value)
            guard !first.isEmpty, !last.isEmpty, span >= 14 * 86_400 else { return nil }
            return last.reduce(0, +) / Double(last.count) - first.reduce(0, +) / Double(first.count)
        }
        let weight = edgeAverage(weights)
        let lean = edgeAverage(leanPoints)
        let fat = edgeAverage(fats)

        // Main lifts: best e1RM in the first 3 weeks vs the last 3 weeks of the phase.
        let early = record.start.addingTimeInterval(21 * 86_400), late = end.addingTimeInterval(-21 * 86_400)
        var starts: [String: (name: String, value: Double)] = [:]
        var ends: [String: Double] = [:]
        for workout in inPhase where workout.isDeload != true {
            for exercise in workout.exercises where !exercise.isCardio && exercise.estimatedOneRepMaxKg > 0 {
                let key = exercise.trendKey
                if workout.startedAt <= early, exercise.estimatedOneRepMaxKg > (starts[key]?.value ?? 0) {
                    starts[key] = (exercise.trendName, exercise.estimatedOneRepMaxKg)
                }
                if workout.startedAt >= late { ends[key] = max(ends[key] ?? 0, exercise.estimatedOneRepMaxKg) }
            }
        }
        let lifts = starts.compactMap { key, start -> LiftChange? in
            guard let finish = ends[key], weeks >= 4 else { return nil }
            return LiftChange(id: start.name, start: start.value, end: finish)
        }.sorted { $0.percent > $1.percent }
        let strength = lifts.isEmpty ? nil : lifts.map(\.percent).reduce(0, +) / Double(lifts.count)

        var score = 0
        switch record.phase {
        case .bulking:
            if let strength { score += strength >= 5 ? 2 : (strength > 0 ? 1 : 0) }
            if let lean { score += lean >= 0.5 ? 2 : (lean > 0 ? 1 : 0) }
            if let weight { let perWeek = weight / Double(weeks); if perWeek > 0, (weights.last?.value).map({ perWeek / $0 * 100 <= 0.6 }) ?? true { score += 1 } }
        case .cutting:
            if let strength { score += strength >= -2 ? 2 : (strength >= -5 ? 1 : 0) }
            if let lean { score += lean >= -0.5 ? 2 : (lean >= -1.0 ? 1 : 0) }
            if let weight, weight < 0 { score += 1 }
        case .recomp:
            if let lean { score += lean >= 0.3 ? 2 : (lean >= 0 ? 1 : 0) }
            if let fat { score += fat <= -1 ? 2 : (fat < 0 ? 1 : 0) }
            if let strength, strength >= 0 { score += 1 }
        }
        if adherence >= 0.85 { score += 1 }
        let grade: String
        switch score {
        case 5...: grade = "A"
        case 4: grade = "B"
        case 3: grade = "C"
        case 2: grade = "D"
        default: grade = "F"
        }
        let verdicts: [String: String] = [
            "A": "Outstanding, recruit. The whole unit will tell stories about this \(record.title.lowercased()).",
            "B": "Solid work. Not perfect — but solid.",
            "C": "Average. You did the minimum and got the minimum.",
            "D": "That was a \(record.title.lowercased()) in name only. We go again — properly.",
            "F": "I've seen fresh recruits with more discipline. Fix the basics: show up, eat right, sleep."
        ]
        return ReportCard(record: record, weeks: weeks, sessions: inPhase.count, adherence: adherence,
                          weightChange: weight, leanChange: lean, fatChange: fat, lifts: lifts,
                          grade: grade, verdict: verdicts[grade] ?? "")
    }
}
