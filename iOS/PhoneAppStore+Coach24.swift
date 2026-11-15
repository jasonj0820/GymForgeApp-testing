import Foundation

/// MK24 (section E): lift goals, what changed this week, accessory rotation, busy weeks, and the context
/// handed to the on-device model for "Ask the coach".
extension PhoneAppStore {
    // MARK: Lift goals (72)

    func liftGoal(for exercise: ExerciseDefinition) -> Double? { extras.liftGoals[exercise.historyKey] }

    func setLiftGoal(_ kg: Double?, for exercise: ExerciseDefinition) {
        extras.liftGoals[exercise.historyKey] = kg.flatMap { $0 > 0 ? $0 : nil }
        saveExtras()
    }

    /// Heaviest weight of each session.
    func topSets(for exercise: ExerciseDefinition) -> [(date: Date, value: Double)] {
        history(for: exercise).compactMap { point in
            point.log.sets.map(\.weightKg).max().map { (date: point.date, value: $0) }
        }
    }

    func goalOutcome(for exercise: ExerciseDefinition) -> GoalProjection.Outcome? {
        guard let goal = liftGoal(for: exercise) else { return nil }
        return GoalProjection.project(topSets(for: exercise), target: goal)
    }

    /// Exercises with a goal, matched back to their definitions.
    var goalExercises: [ExerciseDefinition] {
        progressExercises.filter { extras.liftGoals[$0.historyKey] != nil }
    }

    // MARK: Week changes (73)

    struct WeekChange: Identifiable {
        let id: String
        let exercise: String
        let title: String
        let why: String
    }

    /// The coach's call for every lift in your routines: going up, holding, or coming down, and why.
    var weekChanges: (up: [WeekChange], hold: [WeekChange], down: [WeekChange]) {
        var up: [WeekChange] = [], hold: [WeekChange] = [], down: [WeekChange] = []
        var seen = Set<String>()
        for exercise in routines.flatMap({ $0.exercises.map(\.exercise) }) where !exercise.isCardio && seen.insert(exercise.historyKey).inserted {
            let effective = profile.effective(exercise)
            guard let previous = previousLog(for: effective) else { continue }
            let rec = ProgressionEngine.recommendation(for: effective, previous: previous)
            let change = WeekChange(id: exercise.historyKey, exercise: exercise.name, title: rec.title, why: rec.message)
            switch rec.action {
            case .increaseWeight: up.append(change)
            case .keepWeight: hold.append(change)
            case .reduceWeight: down.append(change)
            case .noHistory, .cardio: break
            }
        }
        return (up, hold, down)
    }

    /// Why this week's goal is what it is.
    var goalReasons: [String] {
        var reasons: [String] = []
        if let brk = GymBreakRules.breakInWeek(of: .now, breaks: extras.breaks) {
            reasons.append("Break week: goal \(brk.weekGoal(normal: weeklyGoal)) instead of \(weeklyGoal).")
        }
        let excused = extras.excusedDays(inWeekOf: .now)
        if excused > 0 { reasons.append("\(excused) sick or travel day\(excused == 1 ? "" : "s"): \(excused) fewer.") }
        if let busy = busyWeek(of: .now) {
            reasons.append("Busy week\(busy.reason.map { " (\($0))" } ?? ""): \(busy.fewer) fewer.")
        }
        return reasons
    }

    // MARK: Accessory rotation (74)

    static let rotatedBlockKey = "rotation.blockEnds"

    var accessoryRotationPlan: [AccessoryRotation.Swap] { AccessoryRotation.plan(routines) }

    /// A new training block has started and its accessories haven't been rotated yet.
    var rotationDue: Bool {
        guard let position = profile.program?.position(at: .now), position.block.phase != .deload, position.week == 1,
              !accessoryRotationPlan.isEmpty else { return false }
        let done = UserDefaults.standard.double(forKey: Self.rotatedBlockKey)
        return done != position.blockEnds.timeIntervalSince1970
    }

    func rotateAccessories(_ swaps: [AccessoryRotation.Swap]) {
        for swap in swaps { replaceExercise(routineID: swap.routineID, itemID: swap.itemID, with: swap.to) }
        markRotationHandled()
    }

    func markRotationHandled() {
        guard let position = profile.program?.position(at: .now) else { return }
        UserDefaults.standard.set(position.blockEnds.timeIntervalSince1970, forKey: Self.rotatedBlockKey)
        objectWillChange.send()
    }

    // MARK: Busy weeks (76)

    func weekStart(of date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    func busyWeek(of date: Date) -> BusyWeek? {
        let start = weekStart(of: date)
        return extras.busyWeeks.first { Calendar.current.isDate($0.weekStart, inSameDayAs: start) }
    }

    func setBusyWeek(of date: Date, fewer: Int, reason: String?) {
        let start = weekStart(of: date)
        extras.busyWeeks.removeAll { Calendar.current.isDate($0.weekStart, inSameDayAs: start) }
        if fewer > 0 { extras.busyWeeks.append(BusyWeek(weekStart: start, fewer: fewer, reason: reason)) }
        extras.busyWeeks.removeAll { $0.weekStart < Date.now.addingTimeInterval(-120 * 86_400) }   // keep it short
        saveExtras()
        rescheduleReminders()
    }

    /// Exams, assignments and deadlines in your calendar for the week containing `date`.
    func heavyEvents(inWeekOf date: Date) -> [DayAgenda.Item] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return DayAgenda.heavyEvents(in: week)
    }

    // MARK: Ask the coach (78)

    /// A short plain-text summary of the last 8 weeks for the on-device model.
    var coachContext: String {
        let cal = Calendar.current
        let since = Date.now.addingTimeInterval(-56 * 86_400)
        let recent = workoutLogs.filter { $0.countsAsTraining && $0.startedAt > since }
        var lines: [String] = []
        lines.append("Today is \(Date.now.formatted(date: .complete, time: .omitted)).")
        lines.append("Weekly goal: \(weeklyGoal) sessions (this week \(thisWeekGoal)). Sessions in the last 8 weeks: \(recent.count).")
        if let label = EffortTarget.blockLabel(profile: profile) { lines.append("Training block: \(label).") }
        lines.append("Nutrition phase: \(nutritionPhase.rawValue).")
        if let target = proteinTargetG { lines.append("Protein target: \(Int(target)) g a day.") }
        if let weight = healthKit.bodyWeight.max(by: { $0.date < $1.date }) {
            lines.append("Body weight: \(String(format: "%.1f", weight.value)) kg (\(weight.date.formatted(date: .abbreviated, time: .omitted))).")
        }
        if let ready = readiness { lines.append("Readiness today: \(ready.title) (\(ready.score)/100).") }
        lines.append("Routines: " + routines.map { "\($0.name) (\($0.exercises.map(\.exercise.name).joined(separator: ", ")))" }.joined(separator: "; ") + ".")
        lines.append("Lifts (heaviest set per session, oldest to newest, last 8 weeks):")
        var seen = Set<String>()
        for exercise in routines.flatMap({ $0.exercises.map(\.exercise) }) where !exercise.isCardio && seen.insert(exercise.historyKey).inserted {
            let points = history(for: exercise).filter { $0.date > since }
            guard !points.isEmpty else { continue }
            let sets = points.suffix(6).compactMap { p in p.log.sets.max(by: { $0.weightKg < $1.weightKg }).map { "\(GFFormat.kg($0.weightKg))×\($0.reps)" } }
            var line = "- \(exercise.name): " + sets.joined(separator: ", ")
            if let goal = liftGoal(for: exercise) { line += " (goal \(GFFormat.kg(goal)) kg)" }
            lines.append(line)
            if lines.count > 40 { break }
        }
        let changes = weekChanges
        if !changes.down.isEmpty { lines.append("Coming down this week: " + changes.down.map(\.exercise).joined(separator: ", ") + ".") }
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: .now)) }
        let plan = days.map { "\($0.formatted(.dateTime.weekday(.abbreviated))): \(plannedSessionName(on: $0) ?? "rest")" }
        lines.append("Next 7 days: " + plan.joined(separator: ", ") + ".")
        return lines.joined(separator: "\n")
    }
}
