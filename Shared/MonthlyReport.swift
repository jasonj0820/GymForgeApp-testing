import Foundation

public struct ExerciseChange: Identifiable, Hashable {
    public var name: String
    public var before: Double
    public var after: Double
    public var id: String { name }
    public var percent: Double { before > 0 ? (after - before) / before : 0 }
}

public struct PRRecord: Identifiable, Hashable {
    public var id: UUID
    public var date: Date
    public var exerciseName: String
    public var set: WorkoutSetLog
}

public struct Milestone: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var systemImage: String
    public var date: Date
}

public struct MilestoneProgress: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var current: Double
    public var target: Double
    public var fraction: Double { target > 0 ? Swift.min(1, current / target) : 0 }
}

public struct MonthlyReport {
    public var monthStart: Date
    public var monthEnd: Date
    public var title: String
    public var headline: String
    public var highlights: [String]

    public var workouts: Int
    public var plannedWorkouts: Int
    public var previousWorkouts: Int
    public var totalVolumeKg: Double
    public var previousVolumeKg: Double
    public var totalSets: Int
    public var totalReps: Int
    public var totalTime: TimeInterval
    public var averageDuration: TimeInterval
    public var activeCalories: Double
    public var deloadSessions: Int

    public var prs: [PRRecord]
    public var strengthChanges: [ExerciseChange]
    public var topLifts: [ExerciseChange]

    public var cardioSeconds: Double
    public var cardioKm: Double

    public var bodyWeightStart: Double?
    public var bodyWeightEnd: Double?
    public var bodyFatStart: Double?
    public var bodyFatEnd: Double?
    public var averageSleep: Double?
    public var averageHRRecovery: Double?
    public var previousHRRecovery: Double?

    /// Day of month → workouts that day.
    public var trainingDays: [Int: Int]
    public var muscleSets: [ExerciseCategory: Int]
    public var newMilestones: [Milestone]
    public var nextMilestones: [MilestoneProgress]

    public var adherence: Double {
        plannedWorkouts > 0 ? Swift.min(1, Double(workouts) / Double(plannedWorkouts)) : 0
    }
    public var mostImproved: ExerciseChange? { strengthChanges.max { $0.percent < $1.percent } }
    public var isEmpty: Bool { workouts == 0 && bodyWeightEnd == nil }
}

public enum MonthlyReportBuilder {
    public static func build(
        month date: Date,
        logs: [WorkoutLog],
        weeklyGoal: Int,
        style: CoachStyle,
        bodyWeight: [BodyMetricPoint] = [],
        bodyFat: [BodyMetricPoint] = [],
        sleep: [SleepNight] = [],
        categoryLookup: [String: ExerciseCategory] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MonthlyReport {
        let interval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 30 * 86_400)
        let start = interval.start
        let end = interval.end
        let effectiveEnd = Swift.min(end, now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: start) ?? start

        let inMonth = logs.filter { $0.startedAt >= start && $0.startedAt < end }.sorted { $0.startedAt < $1.startedAt }
        let previousMonth = logs.filter { $0.startedAt >= previousStart && $0.startedAt < start }
        let before = logs.filter { $0.startedAt < start }

        let daysElapsed = Swift.max(1.0, effectiveEnd.timeIntervalSince(start) / 86_400)
        let planned = Int((Double(weeklyGoal) * daysElapsed / 7).rounded())

        // PRs logged this month
        var prs: [PRRecord] = []
        for workout in inMonth {
            for exercise in workout.exercises {
                for set in exercise.sets where set.isPR == true {
                    prs.append(PRRecord(id: set.id, date: workout.startedAt, exerciseName: exercise.exerciseName, set: set))
                }
            }
        }

        // Strength: best estimated 1RM this month vs best before this month.
        var monthBest: [String: (String, Double)] = [:]
        for workout in inMonth where workout.isDeload != true {
            for exercise in workout.exercises where !exercise.isCardio {
                let key = ExerciseLog.key(for: exercise.exerciseName)
                let value = exercise.estimatedOneRepMaxKg
                if value > (monthBest[key]?.1 ?? 0) { monthBest[key] = (exercise.exerciseName, value) }
            }
        }
        var priorBest: [String: Double] = [:]
        for workout in before {
            for exercise in workout.exercises where !exercise.isCardio {
                let key = ExerciseLog.key(for: exercise.exerciseName)
                priorBest[key] = Swift.max(priorBest[key] ?? 0, exercise.estimatedOneRepMaxKg)
            }
        }
        var changes: [ExerciseChange] = []
        var topLifts: [ExerciseChange] = []
        for (key, entry) in monthBest {
            topLifts.append(ExerciseChange(name: entry.0, before: priorBest[key] ?? 0, after: entry.1))
            if let prior = priorBest[key], prior > 0 {
                changes.append(ExerciseChange(name: entry.0, before: prior, after: entry.1))
            }
        }
        changes.sort { $0.percent > $1.percent }
        topLifts.sort { $0.after > $1.after }

        func average(_ points: [BodyMetricPoint], around day: Date) -> Double? {
            let values = points.filter { abs($0.date.timeIntervalSince(day)) <= 4 * 86_400 }.map(\.value)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        func monthAverage(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        var trainingDays: [Int: Int] = [:]
        for workout in inMonth {
            trainingDays[calendar.component(.day, from: workout.startedAt), default: 0] += 1
        }

        let volume = inMonth.reduce(0) { $0 + $1.totalVolumeKg }
        let previousVolume = previousMonth.reduce(0) { $0 + $1.totalVolumeKg }
        let time = inMonth.reduce(0) { $0 + $1.duration }
        let sleepInMonth = sleep.filter { $0.date >= start && $0.date < end }.map(\.hoursAsleep)
        let milestones = Milestones.compute(logs: logs, weeklyGoal: weeklyGoal, upTo: effectiveEnd, calendar: calendar)
        let newMilestones = milestones.achieved.filter { $0.date >= start && $0.date < end }

        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"

        var report = MonthlyReport(
            monthStart: start,
            monthEnd: end,
            title: formatter.string(from: start),
            headline: "",
            highlights: [],
            workouts: inMonth.count,
            plannedWorkouts: planned,
            previousWorkouts: previousMonth.count,
            totalVolumeKg: volume,
            previousVolumeKg: previousVolume,
            totalSets: inMonth.reduce(0) { $0 + $1.totalSets },
            totalReps: inMonth.reduce(0) { $0 + $1.totalReps },
            totalTime: time,
            averageDuration: inMonth.isEmpty ? 0 : time / Double(inMonth.count),
            activeCalories: inMonth.compactMap(\.activeCaloriesKcal).reduce(0, +),
            deloadSessions: inMonth.filter { $0.isDeload == true }.count,
            prs: prs,
            strengthChanges: changes,
            topLifts: Array(topLifts.prefix(5)),
            cardioSeconds: inMonth.reduce(0) { $0 + $1.cardioSeconds },
            cardioKm: inMonth.reduce(0) { $0 + $1.cardioKm },
            bodyWeightStart: average(bodyWeight, around: start),
            bodyWeightEnd: average(bodyWeight, around: effectiveEnd),
            bodyFatStart: average(bodyFat, around: start),
            bodyFatEnd: average(bodyFat, around: effectiveEnd),
            averageSleep: monthAverage(sleepInMonth),
            averageHRRecovery: monthAverage(inMonth.compactMap(\.averageHeartRateRecovery)),
            previousHRRecovery: monthAverage(previousMonth.compactMap(\.averageHeartRateRecovery)),
            trainingDays: trainingDays,
            muscleSets: MuscleVolume.sets(logs: inMonth, from: start, to: end, categoryLookup: categoryLookup),
            newMilestones: newMilestones,
            nextMilestones: milestones.next
        )
        report.headline = headline(for: report, style: style)
        report.highlights = highlights(for: report)
        return report
    }

    static func headline(for report: MonthlyReport, style: CoachStyle) -> String {
        let done = report.workouts
        let planned = report.plannedWorkouts
        let percent = GFFormat.percent(report.adherence)
        if done == 0 { return "No workouts logged in \(report.title)." }
        switch style {
        case .pushMe:
            return report.adherence >= 0.9
                ? "\(done)/\(planned) sessions. Solid — now raise the bar."
                : "\(done)/\(planned) sessions. You left \(Swift.max(planned - done, 0)) on the table. Fix it next month."
        case .motivating:
            return report.adherence >= 0.9
                ? "Huge month! \(done) workouts and \(report.prs.count) PRs."
                : "\(done) workouts this month — every one of them counts. Let's build on it."
        case .analytical:
            return "\(done)/\(planned) sessions (\(percent)), \(GFFormat.volume(report.totalVolumeKg)) volume, \(report.prs.count) PRs."
        case .supportive:
            return "You showed up \(done) times this month. That's worth being proud of."
        case .heartbreak:
            return report.adherence >= 0.9
                ? "\(done)/\(planned). You turned the hurt into work. Keep going — the comeback is happening."
                : "\(done)/\(planned). The nights you skipped were the nights it won. Take them back next month."
        case .hardTruth:
            return report.adherence >= 0.9
                ? "\(done)/\(planned). You kept your word to yourself. Now raise the standard."
                : "\(done)/\(planned). The plan didn't fail — you skipped it. Next month you don't."
        }
    }

    static func highlights(for report: MonthlyReport) -> [String] {
        var lines: [String] = []
        if report.previousWorkouts > 0 {
            let diff = report.workouts - report.previousWorkouts
            if diff != 0 { lines.append("\(diff > 0 ? "+" : "")\(diff) workouts vs last month") }
        }
        if report.previousVolumeKg > 0 {
            let change = (report.totalVolumeKg - report.previousVolumeKg) / report.previousVolumeKg
            lines.append("Volume \(change >= 0 ? "up" : "down") \(GFFormat.percent(abs(change))) vs last month")
        }
        if let best = report.mostImproved, best.percent > 0.005 {
            lines.append("Most improved: \(best.name) (+\(GFFormat.percent(best.percent)) est. 1RM)")
        }
        if let start = report.bodyWeightStart, let end = report.bodyWeightEnd {
            lines.append("Body weight \(GFFormat.signed(end - start)) kg")
        }
        if let now = report.averageHRRecovery, let then = report.previousHRRecovery, then > 0 {
            let change = (now - then) / then
            if abs(change) >= 0.05 {
                lines.append("Heart-rate recovery \(change > 0 ? "improved" : "dropped") \(GFFormat.percent(abs(change)))")
            }
        }
        if report.cardioSeconds > 0 {
            var text = "Cardio: \(GFFormat.minutes(report.cardioSeconds))"
            if report.cardioKm > 0 { text += ", \(GFFormat.km(report.cardioKm)) km" }
            lines.append(text)
        }
        return lines
    }
}

public enum Milestones {
    static let workoutTargets: [Double] = [1, 10, 25, 50, 75, 100, 150, 200, 250, 300, 400, 500, 750, 1000]
    static let setTargets: [Double] = [100, 250, 500, 1000, 2500, 5000, 10_000, 25_000]
    static let tonneTargets: [Double] = [1, 10, 25, 50, 100, 250, 500, 1000, 2500]
    static let streakTargets: [Double] = [2, 4, 8, 12, 26, 52]

    public static func compute(
        logs: [WorkoutLog],
        weeklyGoal: Int,
        upTo end: Date,
        calendar: Calendar = .current
    ) -> (achieved: [Milestone], next: [MilestoneProgress]) {
        let sorted = logs.filter { $0.startedAt < end }.sorted { $0.startedAt < $1.startedAt }
        var achieved: [Milestone] = []
        var workoutIndex = 0
        var sets = 0.0
        var volume = 0.0
        var nextSet = 0
        var nextTonne = 0

        for workout in sorted {
            workoutIndex += 1
            if workoutTargets.contains(Double(workoutIndex)) {
                achieved.append(Milestone(id: "w\(workoutIndex)", title: workoutIndex == 1 ? "First workout" : "\(workoutIndex) workouts",
                                          systemImage: "figure.strengthtraining.traditional", date: workout.startedAt))
            }
            sets += Double(workout.totalSets)
            while nextSet < setTargets.count, sets >= setTargets[nextSet] {
                achieved.append(Milestone(id: "s\(Int(setTargets[nextSet]))", title: "\(Int(setTargets[nextSet])) sets logged",
                                          systemImage: "square.stack.3d.up.fill", date: workout.startedAt))
                nextSet += 1
            }
            volume += workout.totalVolumeKg
            while nextTonne < tonneTargets.count, volume / 1000 >= tonneTargets[nextTonne] {
                achieved.append(Milestone(id: "t\(Int(tonneTargets[nextTonne]))", title: "\(Int(tonneTargets[nextTonne])) tonnes lifted",
                                          systemImage: "scalemass.fill", date: workout.startedAt))
                nextTonne += 1
            }
        }

        // Weekly streaks of hitting the goal.
        let goal = Swift.max(weeklyGoal, 1)
        var weekCounts: [Date: Int] = [:]
        for workout in sorted {
            if let week = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start {
                weekCounts[week, default: 0] += 1
            }
        }
        var streak = 0
        var bestStreak = 0
        var nextStreak = 0
        if let firstWeek = weekCounts.keys.min() {
            var week = firstWeek
            while week < end {
                guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
                if (weekCounts[week] ?? 0) >= goal {
                    streak += 1
                    bestStreak = Swift.max(bestStreak, streak)
                    while nextStreak < streakTargets.count, Double(streak) >= streakTargets[nextStreak] {
                        let value = Int(streakTargets[nextStreak])
                        achieved.append(Milestone(id: "k\(value)", title: "\(value)-week goal streak",
                                                  systemImage: "flame.fill", date: Swift.min(weekEnd, end)))
                        nextStreak += 1
                    }
                } else if weekEnd <= end {
                    streak = 0
                }
                week = weekEnd
            }
        }

        var next: [MilestoneProgress] = []
        if let target = workoutTargets.first(where: { $0 > Double(workoutIndex) }) {
            next.append(MilestoneProgress(id: "nw", title: "\(Int(target)) workouts", current: Double(workoutIndex), target: target))
        }
        if nextSet < setTargets.count {
            next.append(MilestoneProgress(id: "ns", title: "\(Int(setTargets[nextSet])) sets", current: sets, target: setTargets[nextSet]))
        }
        if nextTonne < tonneTargets.count {
            next.append(MilestoneProgress(id: "nt", title: "\(Int(tonneTargets[nextTonne])) tonnes lifted", current: volume / 1000, target: tonneTargets[nextTonne]))
        }
        if nextStreak < streakTargets.count {
            next.append(MilestoneProgress(id: "nk", title: "\(Int(streakTargets[nextStreak]))-week streak", current: Double(streak), target: streakTargets[nextStreak]))
        }
        return (achieved.sorted { $0.date < $1.date }, next)
    }
}
