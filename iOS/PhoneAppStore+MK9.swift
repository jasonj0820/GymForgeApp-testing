import Foundation

/// MK9: week planning, workout corrections, accepted coaching, time budget and the weekly review.
extension PhoneAppStore {

    // MARK: Week planning

    /// This week's goal after sick / travel days (each one takes a session off), or a break's goal (MK11.3).
    var thisWeekGoal: Int {
        let goal = GymBreakRules.breakInWeek(of: .now, breaks: extras.breaks)?.weekGoal(normal: weeklyGoal) ?? weeklyGoal
        return max(goal - extras.excusedDays(inWeekOf: .now), 0)
    }

    enum DayChoice: Hashable {
        case unplanned, rest, ill, travel, run, basketball
        case routine(UUID)
    }

    func dayChoice(on date: Date) -> DayChoice {
        if let plan = extras.dayPlan(on: date) {
            switch plan.kind {
            case .ill: return .ill
            case .travel: return .travel
            case .workout:
                if plan.routineID == CardioIDs.run { return .run }
                if plan.routineID == CardioIDs.basketball { return .basketball }
                if let id = plan.routineID { return .routine(id) }
            }
        }
        return extras.isRestDay(date) ? .rest : .unplanned
    }

    /// Plans one day (rest days use the existing rest-day list, so the Today row and Cluck see them).
    func setDay(_ date: Date, to choice: DayChoice) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        extras.dayPlans.removeAll { cal.isDate($0.day, inSameDayAs: day) }
        extras.restDays.removeAll { cal.isDate($0, inSameDayAs: day) }
        extras.plannedRestDays.removeAll { cal.isDate($0, inSameDayAs: day) }
        switch choice {
        case .unplanned:
            break
        case .rest:
            extras.restDays.append(day)
            // Planned ahead (not on the day itself): Sergeant Cluck is chill about it.
            if day > cal.startOfDay(for: .now) { extras.plannedRestDays.append(day) }
        case .ill:
            extras.dayPlans.append(DayPlan(day: day, kind: .ill))
        case .travel:
            extras.dayPlans.append(DayPlan(day: day, kind: .travel))
        case .run:
            extras.dayPlans.append(DayPlan(day: day, kind: .workout, routineID: CardioIDs.run, routineName: "Run"))
        case .basketball:
            extras.dayPlans.append(DayPlan(day: day, kind: .workout, routineID: CardioIDs.basketball, routineName: "Basketball"))
        case .routine(let id):
            let name = routines.first { $0.id == id }?.name
            extras.dayPlans.append(DayPlan(day: day, kind: .workout, routineID: id, routineName: name))
        }
        // Keep the list small: plans older than ~3 months are no longer needed.
        if let old = cal.date(byAdding: .day, value: -100, to: .now) {
            extras.dayPlans.removeAll { $0.day < old }
            extras.plannedRestDays.removeAll { $0 < old }
        }
        saveExtras()
    }

    /// Clears every plan in the week containing `date` ("plan each week from scratch").
    func clearWeekPlan(containing date: Date) {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: date) else { return }
        // Days already gone stay as they were (clearing shouldn't change this week's goal after the fact).
        let today = Calendar.current.startOfDay(for: .now)
        extras.dayPlans.removeAll { $0.day >= week.start && $0.day < week.end && $0.day >= today }
        extras.restDays.removeAll { $0 >= week.start && $0 < week.end && $0 >= Calendar.current.startOfDay(for: .now) }
        extras.plannedRestDays.removeAll { $0 >= week.start && $0 < week.end && $0 >= Calendar.current.startOfDay(for: .now) }
        saveExtras()
    }

    // MARK: MK10 — planning helpers

    /// The weekdays you usually train (1 = Sunday … 7 = Saturday), as many as your weekly goal.
    func usualTrainingWeekdays(calendar: Calendar = .current) -> Set<Int> {
        let goal = Swift.min(Swift.max(weeklyGoal, 1), 7)
        let since = Date.now.addingTimeInterval(-56 * 86_400)
        var counts: [Int: Int] = [:]
        for log in workoutLogs where log.startedAt >= since && log.routineID != CardioIDs.run && log.routineID != CardioIDs.basketball {
            counts[calendar.component(.weekday, from: log.startedAt), default: 0] += 1
        }
        if counts.count >= goal {
            return Set(counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(goal).map(\.key))
        }
        // No history yet: spread them out (Mon = 2).
        let spread: [Int: [Int]] = [1: [2], 2: [3, 6], 3: [2, 4, 6], 4: [2, 3, 5, 6], 5: [2, 3, 4, 5, 6],
                                    6: [2, 3, 4, 5, 6, 7], 7: [1, 2, 3, 4, 5, 6, 7]]
        return Set(spread[goal] ?? [2, 4, 6])
    }

    // MARK: MK20 — fixed-day split (Shared/Planning.swift → FixedSplit)

    /// On by default; Settings → Weekly split turns it off (back to rotating routines).
    var fixedSplitOn: Bool {
        get { UserDefaults.standard.object(forKey: "split.fixed") as? Bool ?? true }
        set { objectWillChange.send(); UserDefaults.standard.set(newValue, forKey: "split.fixed") }
    }

    func splitRoutine(_ slot: FixedSplit.Slot) -> WorkoutRoutine? {
        routines.first { !$0.exercises.isEmpty && FixedSplit.slot(of: $0) == slot }
    }

    /// What you trained, as split slots (basketball and runs don't count).
    var splitDone: [(date: Date, slot: FixedSplit.Slot)] {
        workoutLogs.compactMap { log in
            if log.routineID == FixedSplit.microChestID { return (log.startedAt, .chest) }
            guard let routine = routines.first(where: { $0.id == log.routineID }), let slot = FixedSplit.slot(of: routine) else { return nil }
            return (log.startedAt, slot)
        }
    }

    /// Friday's answer, kept for that day only.
    var courtToday: FixedSplit.Court? {
        get {
            let today = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
            guard let saved = UserDefaults.standard.string(forKey: "split.court"), saved.hasPrefix("\(today)|") else { return nil }
            return FixedSplit.Court(rawValue: String(saved.dropFirst("\(today)|".count)))
        }
        set {
            objectWillChange.send()
            let today = Int(Calendar.current.startOfDay(for: .now).timeIntervalSince1970)
            UserDefaults.standard.set(newValue.map { "\(today)|\($0.rawValue)" }, forKey: "split.court")
            if newValue == .fullCourt { setDay(.now, to: .basketball) }   // the week plan and Sergeant Cluck see it too
        }
    }

    var splitToday: FixedSplit.Day { FixedSplit.day(.now, done: splitDone, court: courtToday) }

    /// Today's split session, already adjusted (extra sets, lower-back swaps, micro chest). nil once done or on rest days.
    var splitRoutineToday: WorkoutRoutine? {
        guard fixedSplitOn else { return nil }
        let day = splitToday
        let doneToday = splitDone.filter { Calendar.current.isDateInToday($0.date) }.map(\.slot)
        switch day.kind {
        case .train(let slot):
            guard !doneToday.contains(slot), var routine = splitRoutine(slot) else { return nil }
            if day.compensate { routine = FixedSplit.compensated(routine, slot: slot) }
            if day.protectLowerBack { routine = FixedSplit.protectingLowerBack(routine) }
            return routine
        case .microChest:
            guard !doneToday.contains(.chest), let chest = splitRoutine(.chest) else { return nil }
            return FixedSplit.microChest(from: chest)
        case .basketball, .rest, .askCourt:
            return nil
        }
    }

    /// Fills the open days: your routines in order on training days (continuing from the last one you did),
    /// and rest on the others if you want. Days already planned, and days gone, are left alone.
    func autoPlan(days: [Date], trainingWeekdays: Set<Int>, restOthers: Bool, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: .now)
        // MK20: fixed days — Mon/Fri chest, Tue/Sat back, Wed legs, Sunday rest; Thursday stays open (buffer or makeup legs).
        if fixedSplitOn, FixedSplit.Slot.allCases.allSatisfy({ splitRoutine($0) != nil }) {
            for day in days.sorted() where calendar.startOfDay(for: day) >= today && dayChoice(on: day) == .unplanned {
                let weekday = calendar.component(.weekday, from: day)
                if let slot = FixedSplit.plannedSlot(weekday: weekday), let routine = splitRoutine(slot) {
                    setDay(day, to: .routine(routine.id))
                } else if weekday == 1, restOthers {
                    setDay(day, to: .rest)
                }
            }
            return
        }
        let rotation = routines.filter { !$0.exercises.isEmpty && $0.exercises.contains { !$0.exercise.isCardio } }
        var next = 0
        if let last = workoutLogs.filter({ log in rotation.contains { $0.id == log.routineID } }).max(by: { $0.startedAt < $1.startedAt }),
           let index = rotation.firstIndex(where: { $0.id == last.routineID }) {
            next = index + 1
        }
        for day in days.sorted() where calendar.startOfDay(for: day) >= today && dayChoice(on: day) == .unplanned {
            if trainingWeekdays.contains(calendar.component(.weekday, from: day)), !rotation.isEmpty {
                setDay(day, to: .routine(rotation[next % rotation.count].id))
                next += 1
            } else if restOthers {
                setDay(day, to: .rest)
            }
        }
    }

    /// Same plan as the week before, on the same weekdays (open days from today on only).
    func copyPreviousWeek(into days: [Date], calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: .now)
        for day in days where calendar.startOfDay(for: day) >= today && dayChoice(on: day) == .unplanned {
            guard let before = calendar.date(byAdding: .day, value: -7, to: day) else { continue }
            let choice = dayChoice(on: before)
            if case .routine(let id) = choice, !routines.contains(where: { $0.id == id }) { continue }
            if choice != .unplanned { setDay(day, to: choice) }
        }
    }

    /// Nothing planned for the rest of this week yet.
    var weekNeedsPlan: Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return false }
        let left = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }.filter { $0 < week.end }
        return left.count >= 2 && left.allSatisfy { dayChoice(on: $0) == .unplanned }
    }

    var plannedRoutineToday: WorkoutRoutine? {
        guard let plan = extras.dayPlan(on: .now), plan.kind == .workout, let id = plan.routineID,
              !workoutLogs.contains(where: { $0.routineID == id && Calendar.current.isDateInToday($0.startedAt) }) else { return nil }
        return routines.first { $0.id == id && !$0.exercises.isEmpty }
    }

    var todayPlanKind: DayPlanKind? { extras.dayPlan(on: .now)?.kind }

    func startTravelWorkout() async {
        await startWorkout(TravelWorkout.routine)
    }

    // MARK: Workout corrections

    /// Saves an edited past workout (or a missed one logged by hand) and re-checks every PR.
    func saveCorrectedWorkout(_ log: WorkoutLog) {
        var logs = workoutLogs
        if let index = logs.firstIndex(where: { $0.id == log.id }) {
            logs[index] = log
        } else if log.isManual == true {
            logs.append(log)
        } else {
            return   // it was deleted meanwhile: don't bring it back
        }
        logs.removeAll { $0.exercises.allSatisfy(\.sets.isEmpty) }
        logs.sort { $0.startedAt < $1.startedAt }
        workoutLogs = logs.recomputingPRs()
        persistAndSync()
        rescheduleReminders()
    }

    /// Every exercise you could add to a corrected workout (routines, swaps and anything logged before).
    var correctionExercises: [ExerciseDefinition] { progressExercises }

    // MARK: Accepted coaching suggestions

    func isAccepted(_ text: String, exerciseKey: String?) -> Bool {
        extras.suggestions.contains { !$0.resolved && $0.text == text && $0.exerciseKey == exerciseKey }
    }

    /// "I'll do that": remembered and followed up in the weekly review.
    func acceptSuggestion(_ text: String, exercise: ExerciseDefinition?) {
        let key = exercise?.historyKey
        guard !isAccepted(text, exerciseKey: key) else { return }
        var strength: Double?
        var sets: Double?
        if let exercise {
            let recent = workoutLogs.history(for: exercise).suffix(3).map(\.log)
            if !recent.isEmpty {
                strength = exercise.isAssisted ? recent.compactMap(\.leastAssistanceKg).min()
                                               : recent.map(\.estimatedOneRepMaxKg).max()
                sets = Double(recent.reduce(0) { $0 + $1.sets.count }) / Double(recent.count)
            }
        }
        extras.suggestions.append(CoachSuggestion(exerciseKey: key, exerciseName: exercise?.name, text: text,
                                                  kind: CoachSuggestion.kind(for: text),
                                                  baselineStrength: strength, baselineSets: sets))
        saveExtras()
    }

    /// A weak-point tip: followed up by that muscle's weekly sets.
    func acceptMuscleTip(_ muscle: ExerciseCategory) {
        let key = "muscle:\(muscle.rawValue)"
        let text = "\(muscle.title): add 2–3 sets a week"
        guard !isAccepted(text, exerciseKey: key) else { return }
        let weekly = MuscleVolume.weeklyAverage(logs: workoutLogs, weeks: 4, categoryLookup: categoryLookup)[muscle] ?? 0
        extras.suggestions.append(CoachSuggestion(exerciseKey: key, exerciseName: muscle.title, text: text,
                                                  kind: .addSet, baselineSets: weekly))
        saveExtras()
    }

    func resolveSuggestion(_ id: UUID) {
        guard let index = extras.suggestions.firstIndex(where: { $0.id == id }) else { return }
        extras.suggestions[index].resolved = true
        saveExtras()
    }

    func togglePriorityMuscle(_ muscle: ExerciseCategory) {
        if extras.priorityMuscles.contains(muscle) {
            extras.priorityMuscles.removeAll { $0 == muscle }
        } else {
            extras.priorityMuscles.append(muscle)
        }
        saveExtras()
    }

    // MARK: Time budget

    /// How important each exercise is when time is short: big compound lifts, weak / priority muscles,
    /// muscles behind on this week's sets, and earlier exercises come first. Cardio goes first.
    func budgetPriority(for state: ActiveWorkoutState) -> (RoutineExercise) -> Double {
        let weak = Set(phaseCoach.weakPoints.map(\.id))
        let priorities = Set(extras.priorityMuscles)
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let thisWeek = MuscleVolume.sets(logs: workoutLogs, from: start, to: .now, categoryLookup: categoryLookup)
        let count = Double(max(state.routine.exercises.count, 1))
        var position: [UUID: Int] = [:]
        for (index, item) in state.routine.exercises.enumerated() { position[item.id] = index }
        return { item in
            let exercise = item.exercise
            var score = 0.0
            if TimeBudget.isCompound(exercise.name) { score += 3 }
            if weak.contains(exercise.category) || priorities.contains(exercise.category) { score += 2 }
            if Double(thisWeek[exercise.category] ?? 0) < WeeklyReviewBuilder.targetRange(exercise.category).low { score += 1 }
            if exercise.isCardio { score -= 10 }   // MK10.2: optional — always cut first
            score += (1 - Double(position[item.id] ?? 0) / count) * 0.5
            return score
        }
    }

    /// What a time budget would cut, for the preview before you start.
    func timeBudgetPreview(_ routine: WorkoutRoutine, minutes: Int?, light: Bool = false) -> (minutes: Int, cuts: [String]) {
        let state = ActiveWorkoutState.start(routine: routine, profile: profile, light: light)
        guard let minutes else { return (TimeBudget.estimateMinutes(state), []) }
        let result = TimeBudget.fit(state, minutes: minutes, priority: budgetPriority(for: state))
        return (TimeBudget.estimateMinutes(result.state), result.cuts)
    }

    // MARK: Weekly review

    struct WeeklyReview {
        let weekStart: Date
        let weekEnd: Date
        let sessions: Int
        let goal: Int
        let excusedDays: Int
        let planned: Int
        let plannedDone: Int
        let prs: Int
        let muscles: [MuscleWeek]
        let priorities: [ExerciseCategory]
        let followUps: [SuggestionFollowUp]
    }

    /// The week to review: on Sunday it's this week, on other days last week.
    func reviewWeekStart(offset: Int = 0) -> Date {
        let cal = Calendar.current
        let now = Date()
        let base = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let isSunday = cal.component(.weekday, from: now) == 1
        let start = isSunday ? base : (cal.date(byAdding: .weekOfYear, value: -1, to: base) ?? base)
        return cal.date(byAdding: .weekOfYear, value: offset, to: start) ?? start
    }

    func weeklyReview(weekStart: Date) -> WeeklyReview {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let logs = workoutLogs.filter { $0.startedAt >= weekStart && $0.startedAt < end }
        let excused = extras.excusedDays(inWeekOf: weekStart)
        let plans = extras.dayPlans.filter { $0.kind == .workout && $0.day >= weekStart && $0.day < end }
        let plannedDone = plans.filter { plan in logs.contains { cal.isDate($0.startedAt, inSameDayAs: plan.day) } }.count
        let followUps = extras.suggestions.filter { !$0.resolved && $0.acceptedAt < end }
            .map { WeeklyReviewBuilder.followUp($0, logs: workoutLogs, now: min(end, .now)) }
        return WeeklyReview(
            weekStart: weekStart, weekEnd: end,
            sessions: logs.count, goal: max(weeklyGoal - excused, 0), excusedDays: excused,
            planned: plans.count, plannedDone: plannedDone,
            prs: logs.reduce(0) { $0 + $1.prCount },
            muscles: WeeklyReviewBuilder.muscles(logs: workoutLogs, from: weekStart, to: end, lookup: categoryLookup),
            priorities: extras.priorityMuscles,
            followUps: followUps
        )
    }

    /// Sunday from 6pm until Tuesday night: the review card shows on Today.
    var weeklyReviewDue: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        return (weekday == 1 && hour >= 18) || weekday == 2 || weekday == 3
    }
}
