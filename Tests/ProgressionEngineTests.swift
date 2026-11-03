import Foundation

// Run on a Mac:  ./Scripts/run_checks.sh
@main
struct GymForgeChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        print("ok  \(message)")
    }

    static func log(_ exercise: ExerciseDefinition, _ sets: [(Double, Int)]) -> ExerciseLog {
        ExerciseLog(
            exerciseID: exercise.id, exerciseName: exercise.name,
            repMinAtTime: exercise.repMin, repMaxAtTime: exercise.repMax,
            weightIncrementKgAtTime: exercise.weightIncrementKg,
            sets: sets.enumerated().map { WorkoutSetLog(setNumber: $0.offset + 1, weightKg: $0.element.0, reps: $0.element.1) }
        )
    }

    static func main() {
        let press = ExerciseDefinition(name: "Incline Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5)

        check(ProgressionEngine.recommendation(for: press, previous: log(press, [(80, 12), (80, 12), (80, 12)])).action == .increaseWeight(suggestedKg: 82.5),
              "3x12 at 80 kg -> try 82.5 kg")
        check(ProgressionEngine.recommendation(for: press, previous: log(press, [(80, 12), (80, 11), (80, 9)])).action == .keepWeight(targetTotalReps: 33),
              "12/11/9 -> keep weight, beat 32 total reps")
        check(ProgressionEngine.recommendation(for: press, previous: log(press, [(80, 12), (80, 12)])).action == .keepWeight(targetTotalReps: 25),
              "only 2 of 3 planned sets -> don't increase yet")
        check(ProgressionEngine.recommendation(for: press, previous: log(press, [(81, 12), (81, 12), (81, 12)])).action == .increaseWeight(suggestedKg: 83.5),
              "odd starting weight still adds exactly one increment")

        let raise = ExerciseDefinition(name: "Lateral Raise", category: .shoulders, repMin: 12, repMax: 20, defaultSets: 3, restSeconds: 60, weightIncrementKg: 1)
        check(ProgressionEngine.recommendation(for: raise, previous: log(raise, [(10, 20), (10, 20), (10, 20)])).action == .increaseWeight(suggestedKg: 11),
              "12-20 exercise uses its own top of range")

        let lastTime = log(press, [(80, 10), (80, 9), (80, 8)])
        let today = log(press, [(80, 10), (80, 10), (80, 9)])
        check(ProgressionEngine.compare(current: today, previous: lastTime).kind == .improved,
              "10/9/8 -> 10/10/9 counts as progress")

        let prefill = ProgressionEngine.suggestedPrefill(for: press, previous: log(press, [(80, 11), (80, 10), (80, 9)]), setIndex: 1)
        check(prefill.weightKg == 80 && prefill.reps == 10, "prefill copies last session's set 2 (80 x 10)")

        // Live workout flow
        let routine = WorkoutRoutine(name: "Test", exercises: [RoutineExercise(exercise: press, order: 0), RoutineExercise(exercise: raise, order: 1)])
        var state = ActiveWorkoutState(routine: routine)
        check(state.completeSet(weightKg: 80, reps: 10, targetWeightKg: nil, targetReps: nil) == .rest(seconds: 120), "set 1 starts the exercise's rest timer")
        _ = state.completeSet(weightKg: 80, reps: 10, targetWeightKg: nil, targetReps: nil)
        _ = state.completeSet(weightKg: 80, reps: 9, targetWeightKg: nil, targetReps: nil)
        check(state.exerciseIndex == 1 && state.setIndex == 0, "after 3 sets it moves to the next exercise")
        for _ in 0..<2 { _ = state.completeSet(weightKg: 10, reps: 15, targetWeightKg: nil, targetReps: nil) }
        check(state.completeSet(weightKg: 10, reps: 15, targetWeightKg: nil, targetReps: nil) == .allDone && state.isComplete, "last set reports all done")
        check(state.makeLog().totalSets == 6, "workout log keeps every set")
        check(state.revision == 6, "each change bumps the sync revision")

        // Consistency
        let calendar = Calendar.current
        let now = Date()
        var logs: [WorkoutLog] = []
        for week in 1...4 {
            for day in 0..<3 {
                let date = calendar.date(byAdding: .day, value: -(7 * week) + day, to: now)!
                logs.append(WorkoutLog(routineID: routine.id, routineName: "Test", startedAt: date, endedAt: date.addingTimeInterval(3600), exercises: [log(press, [(80, 10)])]))
            }
        }
        let stats = ConsistencyCalculator.stats(logs: logs, weeklyGoal: 5, now: now)
        check(stats.averagePerWeek < 4.5, "3 sessions/week detected against a 5-day goal")
        let coach = CoachEngine.goalRealismInsight(stats)
        check(coach != nil, "coach suggests a more realistic weekly goal")

        // Supersets: A1 → A2 without rest, rest after the pair
        let curl = ExerciseDefinition(name: "Curl", category: .biceps, repMin: 10, repMax: 15, defaultSets: 2, restSeconds: 60, weightIncrementKg: 1)
        let pushdown = ExerciseDefinition(name: "Pushdown", category: .triceps, repMin: 10, repMax: 15, defaultSets: 2, restSeconds: 60, weightIncrementKg: 2.5)
        let arms = WorkoutRoutine(name: "Arms", exercises: [
            RoutineExercise(exercise: curl, order: 0, supersetWithNext: true),
            RoutineExercise(exercise: pushdown, order: 1)
        ])
        var ss = ActiveWorkoutState(routine: arms)
        check(ss.supersetLabel(for: 0) == "A1" && ss.supersetLabel(for: 1) == "A2", "superset labels A1/A2")
        check(ss.completeSet(weightKg: 15, reps: 12, targetWeightKg: nil, targetReps: nil) == .supersetNext && ss.exerciseIndex == 1, "A1 goes straight to A2")
        check(ss.completeSet(weightKg: 30, reps: 12, targetWeightKg: nil, targetReps: nil) == .rest(seconds: 60) && ss.exerciseIndex == 0, "rest after A2, back to A1")

        // Swap: Chest Press → Bench Press is logged separately
        let bench = ExerciseDefinition(name: "Bench Press", category: .chest, repMin: 6, repMax: 10, defaultSets: 2, restSeconds: 120, weightIncrementKg: 2.5)
        let chestPress = ExerciseDefinition(name: "Chest Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 2, restSeconds: 120, weightIncrementKg: 2.5, alternatives: [bench])
        var sw = ActiveWorkoutState(routine: WorkoutRoutine(name: "Chest", exercises: [RoutineExercise(exercise: chestPress, order: 0)]))
        _ = sw.completeSet(weightKg: 70, reps: 10, targetWeightKg: nil, targetReps: nil)
        check(sw.swapOptions(for: sw.routine.exercises[0]).map(\.name) == ["Bench Press"], "swap options come from presets")
        sw.swapExercise(at: 0, to: bench)
        _ = sw.completeSet(weightKg: 60, reps: 8, targetWeightKg: nil, targetReps: nil)
        let swLog = sw.makeLog()
        check(swLog.exercises.map(\.exerciseName) == ["Chest Press", "Bench Press"], "both exercises saved with their own sets")
        check(swLog.exercises.last?.swappedFromName == "Chest Press", "swap is recorded")

        // PR detection
        let historyLog = WorkoutLog(routineID: routine.id, routineName: "Test", startedAt: now.addingTimeInterval(-86_400 * 3),
                                    endedAt: now.addingTimeInterval(-86_400 * 3 + 3600), exercises: [log(press, [(80, 10), (80, 9)])])
        var prState = ActiveWorkoutState(routine: routine)
        _ = prState.completeSet(weightKg: 82.5, reps: 8, targetWeightKg: nil, targetReps: nil, history: [historyLog])
        check(prState.lastPR?.kind == .heaviestWeight, "heavier than ever = PR")
        var noPR = ActiveWorkoutState(routine: routine)
        _ = noPR.completeSet(weightKg: 80, reps: 9, targetWeightKg: nil, targetReps: nil, history: [historyLog])
        check(noPR.lastPR == nil, "matching last time isn't a PR")

        // Program phases & deload
        check(ProgramPhase.adjust(press, for: .strength).repMin == 5 && ProgramPhase.adjust(press, for: .strength).repMax == 8, "strength block: 8–12 → 5–8")
        check(ProgramPhase.deloadWeight(80, increment: 2.5) == 72.5, "deload ≈ 90% rounded to increment")
        check(ProgressionEngine.recommendation(for: ProgramPhase.adjust(press, for: .strength),
                                               previous: log(press, [(80, 12), (80, 12), (80, 12)])).action == .increaseWeight(suggestedKg: 90),
              "8–12 → 5–8 block re-aims from strength: 80 kg × 12 → ~90 kg")
        var profile = UserProfile()
        profile.deloadUntil = now.addingTimeInterval(86_400)
        let deloadState = ActiveWorkoutState.start(routine: routine, profile: profile)
        check(deloadState.deload && deloadState.routine.exercises[0].exercise.defaultSets == 2, "deload drops a set")
        let plan = ProgramPlan(name: "P", blocks: [ProgramBlock(phase: .hypertrophy, weeks: 2), ProgramBlock(phase: .strength, weeks: 1)],
                               startDate: now.addingTimeInterval(-15 * 86_400))
        check(plan.position(at: now)?.block.phase == .strength, "program position follows the calendar")

        // Strong import
        let csv = """
        "Workout #";"Date";"Workout Name";"Duration (sec)";"Exercise Name";"Set Order";"Weight (kg)";"Reps";"RPE";"Distance (meters)";"Seconds";"Notes";"Workout Notes"
        "1";"2025-04-29 12:00:00";"Chest";"3600";"Bench Press (Barbell)";"W";"40.0";"10";"";"";"";"";""
        "1";"2025-04-29 12:00:00";"Chest";"3600";"Bench Press (Barbell)";"1";"100.0";"10";"";"";"";"";""
        "1";"2025-04-29 12:00:00";"Chest";"3600";"Treadmill";"1";"0";"0";"";"2000";"900";"";""
        """
        if let parsed = try? StrongImporter.parse(csv) {
            check(parsed.rows.count == 2 && parsed.detectedUnit == .kg, "Strong CSV parsed, warm-up skipped")
            let built = StrongImporter.buildWorkouts(from: parsed, unit: .kg, mapping: ["Bench Press (Barbell)": bench], existing: [])
            check(built.workouts.count == 1 && built.workouts[0].exercises[0].exerciseName == "Bench Press", "mapped to your exercise")
            check(built.workouts[0].exercises[1].isCardio && built.workouts[0].exercises[1].totalDistanceKm == 2, "cardio row imported with distance")
            let again = StrongImporter.buildWorkouts(from: parsed, unit: .kg, mapping: [:], existing: built.workouts)
            check(again.workouts.isEmpty && again.duplicatesSkipped == 1, "re-import skips duplicates")
        } else {
            check(false, "Strong CSV parsed")
        }

        // Readiness
        let startOfToday = Calendar.current.startOfDay(for: now)
        let rested = ReadinessEngine.evaluate(sleep: [SleepNight(date: startOfToday, hoursAsleep: 4.5)], restingHR: [], hrv: [], now: now)
        check(rested?.level == .moderate || rested?.level == .low, "short sleep lowers readiness")

        // Monthly report + milestones
        let report = MonthlyReportBuilder.build(month: now, logs: logs + [historyLog], weeklyGoal: 3, style: .analytical, now: now)
        check(report.title.isEmpty == false, "monthly report builds")
        let milestones = Milestones.compute(logs: logs, weeklyGoal: 3, upTo: now)
        check(milestones.achieved.contains { $0.id == "w10" }, "10-workout milestone reached")

        // Skip an exercise and come back to it
        var skip = ActiveWorkoutState(routine: routine)
        skip.skipExercise(at: 0)
        check(skip.exerciseIndex == 1 && skip.isFinished(skip.routine.exercises[0]), "skip moves on and counts as done")
        skip.jump(toExercise: 0)
        check(!skip.isSkipped(skip.routine.exercises[0]) && skip.exerciseIndex == 0, "tapping a skipped exercise brings it back")

        // Watch sync codec
        if let packed = try? SyncCodec.pack(.snapshot, AppSnapshot(routines: SeedData.starterRoutines, workoutLogs: logs, weeklyGoal: 4)),
           let unpacked = try? SyncCodec.unpack(packed), let snap = try? unpacked.decode(AppSnapshot.self) {
            check(snap.routines.count == 3 && unpacked.type == .snapshot, "compressed sync payload round-trips")
        } else {
            check(false, "compressed sync payload round-trips")
        }

        // Assisted pull-ups: weight is assistance, so progress = LESS weight
        let assisted = ExerciseDefinition(name: "Assisted Pull-up", category: .back, repMin: 6, repMax: 10, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5)
        check(assisted.isAssisted, "assisted exercise detected by name")
        check(ProgressionEngine.recommendation(for: assisted, previous: log(assisted, [(30, 10), (30, 10), (30, 10)])).action == .increaseWeight(suggestedKg: 27.5),
              "assisted 3x10 at 30 kg -> 27.5 kg assistance (harder)")
        check(ProgressionEngine.recommendation(for: assisted, previous: log(assisted, [(30, 5), (30, 4), (30, 4)])).action == .reduceWeight(suggestedKg: 32.5),
              "assisted all below 6 reps -> more assistance")
        check(log(assisted, [(30, 8)]).estimatedOneRepMaxKg == 0, "assisted kept out of 1RM analytics")
        let assistedRoutine = WorkoutRoutine(name: "Back", exercises: [RoutineExercise(exercise: assisted, order: 0)])
        let past = WorkoutLog(routineID: assistedRoutine.id, routineName: "Back", startedAt: .now.addingTimeInterval(-86_400),
                              endedAt: .now.addingTimeInterval(-82_800), exercises: [log(assisted, [(30, 8), (30, 8), (30, 7)])])
        var assistedState = ActiveWorkoutState(routine: assistedRoutine)
        _ = assistedState.completeSet(weightKg: 27.5, reps: 7, targetWeightKg: nil, targetReps: nil, history: [past])
        check(assistedState.lastPR?.kind == .leastAssistance, "less assistance than ever = PR")
        var noAssistPR = ActiveWorkoutState(routine: assistedRoutine)
        _ = noAssistPR.completeSet(weightKg: 35, reps: 10, targetWeightKg: nil, targetReps: nil, history: [past])
        check(noAssistPR.lastPR == nil, "more assistance is never a PR")

        // Editing / deleting logged sets and changing the plan mid-workout
        var editState = ActiveWorkoutState(routine: assistedRoutine)
        _ = editState.completeSet(weightKg: 30, reps: 8, targetWeightKg: nil, targetReps: nil, history: [past])
        _ = editState.completeSet(weightKg: 30, reps: 8, targetWeightKg: nil, targetReps: nil, history: [past])
        let firstID = editState.sets(for: editState.routine.exercises[0])[0].id
        editState.editSet(id: firstID, weightKg: 25, reps: 7, rir: 1, history: [past])
        check(editState.sets(for: editState.routine.exercises[0])[0].isPR == true && editState.lastPR?.id == firstID,
              "editing a set to less assistance makes it a PR")
        editState.editSet(id: firstID, weightKg: 32.5, reps: 7, rir: 1, history: [past])
        check(editState.sets(for: editState.routine.exercises[0])[0].isPR == nil && editState.lastPR == nil,
              "editing a PR set back down removes the PR")
        editState.deleteSet(id: firstID, history: [past])
        let remaining = editState.sets(for: editState.routine.exercises[0])
        check(remaining.count == 1 && remaining[0].setNumber == 1, "deleting a set renumbers the rest")
        editState.setPlannedSets(1, at: 0)
        check(editState.routine.exercises[0].exercise.defaultSets == 1 && editState.isComplete, "dropping to 1 planned set finishes the exercise")
        editState.setPlannedSets(0, at: 0)
        check(editState.routine.exercises[0].exercise.defaultSets == 1, "planned sets never below what's logged")
        let newOption = assisted.makeAlternative(named: "Band Pull-up")
        editState.addSwapOption(newOption, at: 0)
        check(editState.swapOptions(for: editState.routine.exercises[0]).contains { $0.id == newOption.id }, "new swap option is offered")
        editState.swapExercise(at: 0, to: newOption)
        check(editState.swapOptions(for: editState.routine.exercises[0]).contains { $0.id == assisted.id }, "can swap back after using the new option")

        // iPhone and Watch both log a set at the same moment: the merge keeps both
        var phoneCopy = ActiveWorkoutState(routine: assistedRoutine)
        _ = phoneCopy.completeSet(weightKg: 30, reps: 8, targetWeightKg: nil, targetReps: nil, history: [past])
        var watchCopy = phoneCopy
        _ = phoneCopy.completeSet(weightKg: 30, reps: 8, targetWeightKg: nil, targetReps: nil, history: [past], now: .now.addingTimeInterval(60))
        _ = watchCopy.completeSet(weightKg: 32.5, reps: 7, targetWeightKg: nil, targetReps: nil, history: [past], now: .now.addingTimeInterval(61))
        let mergedCopy = phoneCopy.merged(with: watchCopy)
        let mergedSets = mergedCopy.sets(for: mergedCopy.routine.exercises[0])
        check(mergedSets.count == 3 && mergedSets.map(\.setNumber) == [1, 2, 3]
              && mergedCopy.revision > max(phoneCopy.revision, watchCopy.revision),
              "simultaneous sets on both devices are both kept")

        // MK9: per-set targets (same weight every set) and re-aiming after a set
        let last1098 = log(press, [(80, 10), (80, 9), (80, 8)])
        let keepPlan = ProgressionEngine.setPlan(for: press, previous: last1098, recent: [last1098])
        check(keepPlan.targets.map(\.reps) == [10, 10, 9] && keepPlan.targets.allSatisfy { $0.weightKg == 80 },
              "10/9/8 at 80 kg → plan 80 kg × 10/10/9")
        let topped = log(press, [(80, 12), (80, 12), (80, 12)])
        let upPlan = ProgressionEngine.setPlan(for: press, previous: topped, recent: [topped])
        check(upPlan.targets.allSatisfy { $0.weightKg == 82.5 && $0.reps == 8 }, "3×12 → 82.5 kg × 8 on every set")
        let shortSet = [WorkoutSetLog(setNumber: 1, weightKg: 80, reps: 7)]
        let lighter = keepPlan.adjusted(afterSet: 0, done: shortSet, exercise: press)
        check(lighter.targets[1].weightKg == 80 && lighter.suggestedWeightKg == 77.5 && lighter.adjustment != nil,
              "set 1 below the range → suggests one step lighter (MK10: you choose)")
        let twoShort = [WorkoutSetLog(setNumber: 1, weightKg: 80, reps: 8)]
        let fewer = keepPlan.adjusted(afterSet: 0, done: twoShort, exercise: press)
        check(fewer.targets[1].weightKg == 80 && fewer.targets[1].reps == 9 && fewer.targets[2].reps == 8,
              "set 1 two short → same weight, a rep less on the rest")

        // MK9: time budget trims sets before skipping exercises
        let budgetRoutine = WorkoutRoutine(name: "B", exercises: (0..<3).map { index in
            RoutineExercise(exercise: ExerciseDefinition(name: "Lift \(index)", category: .chest, defaultSets: 3, restSeconds: 120), order: index)
        })
        let budgetState = ActiveWorkoutState(routine: budgetRoutine)
        check(TimeBudget.estimateMinutes(budgetState) == 23, "3 exercises × 3 sets ≈ 23 min")
        let rank: (RoutineExercise) -> Double = { item in Double(3 - (budgetRoutine.exercises.firstIndex { $0.id == item.id } ?? 0)) }
        let trimmed = TimeBudget.fit(budgetState, minutes: 18, priority: rank).state
        check(trimmed.routine.exercises.map(\.exercise.defaultSets) == [3, 2, 2] && (trimmed.skippedItems ?? []).isEmpty,
              "18 min: sets come off the least important exercises first")
        let tight = TimeBudget.fit(budgetState, minutes: 5, priority: rank).state
        check(tight.isSkipped(tight.routine.exercises[2]) && !tight.isSkipped(tight.routine.exercises[0]),
              "5 min: only then is the least important exercise skipped")

        // MK9: corrected history re-checks PRs
        let day1 = WorkoutLog(routineID: routine.id, routineName: "P", startedAt: .now.addingTimeInterval(-7 * 86_400),
                              endedAt: .now.addingTimeInterval(-7 * 86_400 + 3600), exercises: [log(press, [(80, 8)])])
        let day2 = WorkoutLog(routineID: routine.id, routineName: "P", startedAt: .now.addingTimeInterval(-86_400),
                              endedAt: .now.addingTimeInterval(-86_400 + 3600), exercises: [log(press, [(85, 5)])])
        let fixed = [day2, day1].recomputingPRs()
        check(fixed[0].exercises[0].sets[0].isPR == true && fixed[1].exercises[0].sets[0].isPR == nil,
              "after a correction, 85 kg is a PR over the earlier 80 kg (first session never is)")

        // MK9.1: exercise library matching
        check(ExerciseLibrary.profile(for: "Incline DB Press")?.name == "Incline Dumbbell Press", "library: Incline DB Press")
        check(ExerciseLibrary.profile(for: "Lat Pulldown (Hammer Strength)")?.name == "Lat Pulldown", "library ignores the machine name")
        check(ExerciseLibrary.profile(for: "Leg Press Calf Raise")?.name == "Standing Calf Raise", "library: longest match wins")
        check(ExerciseLibrary.profile(for: "Assisted Pull-up")?.name == "Assisted Pull-up", "library: assisted pull-up")
        check(ExerciseLibrary.profile(for: "Dumbbell Shoulder Press")?.name == "Dumbbell Shoulder Press", "library: DB shoulder press")
        check(ExerciseLibrary.muscles(for: "Bench Press", category: .chest)[.triceps] == 0.5, "bench counts triceps as half a set")

        // MK9.1: autoregulation — every set had 3+ reps left → go up now
        let easySets = (1...3).map { WorkoutSetLog(setNumber: $0, weightKg: 80, reps: 10, rir: 3) }
        let easy = ExerciseLog(exerciseID: press.id, exerciseName: press.name, repMinAtTime: 8, repMaxAtTime: 12,
                               weightIncrementKgAtTime: 2.5, sets: easySets)
        check(ProgressionEngine.recommendation(for: press, previous: easy).action == .increaseWeight(suggestedKg: 82.5),
              "3 × 10 with 3+ reps left → 82.5 kg")

        // MK9.1: routine check and builder
        let libBench = ExerciseDefinition(name: "Barbell Bench Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 60)
        let auditRoutine = WorkoutRoutine(name: "Push", exercises: [RoutineExercise(exercise: libBench, order: 0)])
        let findings = CoachBrain.audit(routines: [auditRoutine], profile: UserProfile())
        check(findings.contains { if case .rest = $0.change { return true } else { return false } }, "audit: 60 s rest on bench is too short")
        check(findings.contains { $0.muscle == .hamstrings }, "audit: no hamstring work flagged")
        let built = RoutineBuilder.build(RoutineBuildRequest(daysPerWeek: 4, minutes: 60, focus: .size, priorities: []))
        check(built.count == 4 && built.allSatisfy { TimeBudget.estimateMinutes(ActiveWorkoutState(routine: $0)) <= 60 },
              "builder: 4 routines that fit 60 min")

        // MK9.1: run stats
        var run = CardioSession(id: UUID(), kind: .run, indoor: false, startedAt: .now, endedAt: .now, activeSeconds: 1780,
                                distanceKm: 6, splits: [300, 300, 300, 300, 300, 280])
        run.averageHeartRate = 150
        check(RunStats.best1k([run])?.seconds == 280 && RunStats.best5k([run])?.seconds == 1480, "best 1 km / 5 km from splits")
        check(CardioFormat.pace(312) == "5:12" && run.workoutLog.exercises.first?.isCardio == true, "pace format and run counts as cardio")

        // MARK: MK10 test bench — simulated training histories through the coach

        let day10: TimeInterval = 86_400
        let now10 = Calendar.current.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        func def(_ name: String, _ category: ExerciseCategory, sets: Int, step: Double = 2.5) -> ExerciseDefinition {
            let info = ExerciseLibrary.profile(named: name)
            return ExerciseDefinition(name: name, category: category, repMin: info?.repMin ?? 8, repMax: info?.repMax ?? 12,
                                      defaultSets: sets, restSeconds: info?.restSeconds ?? 120, weightIncrementKg: step)
        }
        func session(_ routine: WorkoutRoutine, _ date: Date, _ loads: [String: (Double, Int)], rir: Int? = nil) -> WorkoutLog {
            let exercises = routine.exercises.compactMap { item -> ExerciseLog? in
                guard let load = loads[item.exercise.name] else { return nil }
                let sets = (1...item.exercise.defaultSets).map {
                    WorkoutSetLog(setNumber: $0, weightKg: load.0, reps: load.1, completedAt: date, rir: rir)
                }
                return ExerciseLog(exerciseID: item.exercise.id, exerciseName: item.exercise.name, repMinAtTime: item.exercise.repMin,
                                   repMaxAtTime: item.exercise.repMax, weightIncrementKgAtTime: item.exercise.weightIncrementKg,
                                   sets: sets, category: item.exercise.category)
            }
            return WorkoutLog(routineID: routine.id, routineName: routine.name, startedAt: date, endedAt: date.addingTimeInterval(3600),
                              exercises: exercises)
        }

        // Stalled intermediate: 6 weeks, 2 sessions a week, chest volume very high, nothing moving.
        let benchDef = def("Barbell Bench Press", .chest, sets: 4)
        let lateralDef = def("Lateral Raise", .shoulders, sets: 5, step: 1)
        let push = WorkoutRoutine(name: "Push", exercises: [
            RoutineExercise(exercise: benchDef, order: 0),
            RoutineExercise(exercise: def("Incline Dumbbell Press", .chest, sets: 4), order: 1),
            RoutineExercise(exercise: def("Cable Fly", .chest, sets: 4), order: 2),
            RoutineExercise(exercise: def("Machine Chest Press", .chest, sets: 4), order: 3),
            RoutineExercise(exercise: lateralDef, order: 4)])
        var stuckLogs: [WorkoutLog] = []
        for index in 0..<12 {
            let date = now10.addingTimeInterval(-Double(42 - index * 3 - 1) * day10)
            let bench = index == 0 ? 95.0 : 100.0
            stuckLogs.append(session(push, date, ["Barbell Bench Press": (bench, 8), "Incline Dumbbell Press": (30, 10),
                                                  "Cable Fly": (20, 12), "Machine Chest Press": (60, 10), "Lateral Raise": (10, 15)]))
        }
        let benchID = push.exercises[0].id
        let lateralID = push.exercises[4].id
        let stallsFound = CoachBrain.stalls(routines: [push], logs: stuckLogs, now: now10)
        check(stallsFound.contains { $0.item.id == benchID && $0.weeks >= 3 }, "bench at 100 kg for 5+ weeks is a stall")
        let stuckIdeas = CoachBrain.proposals(routines: [push], logs: stuckLogs, profile: UserProfile(), context: CoachInputs(now: now10))
        check(stuckIdeas.contains { $0.id == "stall-\(benchID)-less" }, "stalled bench on ~32 chest sets a week → cut a set, not add one")
        check(stuckIdeas.contains { $0.id == "stall-\(lateralID)-swap" }, "stalled lateral raise (accessory) → swap it")
        check(!stuckIdeas.contains { proposal in
            if case let .sets(_, itemID, to) = proposal.change { return itemID == benchID && to > benchDef.defaultSets } else { return false }
        }, "never suggests more bench sets while chest volume is too high")

        // Same history on a cut: holding strength is fine.
        let cutIdeas = CoachBrain.proposals(routines: [push], logs: stuckLogs, profile: UserProfile(),
                                            context: CoachInputs(nutritionPhase: .cutting, now: now10))
        check(cutIdeas.contains { $0.id.hasPrefix("stall-cut") && $0.reason.contains("Barbell Bench Press") && $0.change == .info },
              "on a cut, plateaus are one 'hold steady' card, not changes")
        check(!cutIdeas.contains { if case .addExercise = $0.change { return true } else { return false } }, "no added exercises on a cut")

        // Grinding to failure: recovery comes first.
        let failLogs = stuckLogs.map { workout -> WorkoutLog in
            var copy = workout
            for e in copy.exercises.indices { for s in copy.exercises[e].sets.indices { copy.exercises[e].sets[s].rir = 0 } }
            return copy
        }
        let failIdeas = CoachBrain.proposals(routines: [push], logs: failLogs, profile: UserProfile(), context: CoachInputs(now: now10))
        check(failIdeas.contains { $0.id.hasPrefix("stall-recovery") && $0.reason.contains("Barbell Bench Press") },
              "every set to failure → one 'recover first' card")

        // Beginner adding weight every session: no stalls.
        var growingLogs: [WorkoutLog] = []
        for index in 0..<12 {
            let date = now10.addingTimeInterval(-Double(42 - index * 3 - 1) * day10)
            growingLogs.append(session(push, date, ["Barbell Bench Press": (60 + Double(index) * 2.5, 8), "Lateral Raise": (6 + Double(index), 12)]))
        }
        check(CoachBrain.stalls(routines: [push], logs: growingLogs, now: now10).isEmpty, "steady progress is never called a stall")

        // Pain: a sore shoulder on bench → gentler machine swap.
        let benchOnly = WorkoutRoutine(name: "Chest", exercises: [RoutineExercise(exercise: benchDef, order: 0)])
        let pain = PainFlag(exercise: benchDef, area: .shoulder, severity: 2)
        let painIdeas = CoachBrain.painProposals(routines: [benchOnly], flags: [pain])
        check(painIdeas.contains { proposal in
            if case let .swapExercise(_, _, name) = proposal.change { return name == "Machine Chest Press" } else { return false }
        },
              "shoulder pain on bench → Machine Chest Press while it heals")

        // Hard sets: 4+ reps left counts half.
        check(WorkoutSetLog(setNumber: 1, weightKg: 50, reps: 10, rir: 4).hardSetValue == 0.5
              && WorkoutSetLog(setNumber: 1, weightKg: 50, reps: 10, rir: 1).hardSetValue == 1, "easy sets count as half a hard set")

        // Blocks: effort 3 → 2 → 1 → 1 then a deload at 4+.
        func profileStarted(_ daysAgo: Int) -> UserProfile {
            var profile = UserProfile()
            profile.program = ProgramPlan.coachedBlock(focus: .size, buildWeeks: 4, start: now10.addingTimeInterval(-Double(daysAgo) * day10))
            return profile
        }
        check([0, 8, 15, 22, 29].map { EffortTarget.reps(profile: profileStarted($0), at: now10) } == [3, 2, 1, 1, 4],
              "block effort targets: 3, 2, 1, 1 reps left, then deload")
        check(EffortTarget.reps(profile: UserProfile(), at: now10) == 2, "no block: 2 reps left")

        // Block review during the deload week.
        let blockProfile = profileStarted(30)
        let blockStart = Calendar.current.startOfDay(for: now10.addingTimeInterval(-30 * day10))
        var blockLogs: [WorkoutLog] = []
        for index in 0..<8 {
            blockLogs.append(session(benchOnly, blockStart.addingTimeInterval(Double(index) * 3.5 * day10 + 3600),
                                     ["Barbell Bench Press": (100 + Double(index) * 1.25, 8)]))
        }
        let review = CoachBrain.blockReview(profile: blockProfile, logs: blockLogs, now: now10)
        check(review?.lifts.first { $0.name == "Barbell Bench Press" }.map { $0.percent > 3 } ?? false, "block review: bench up over the block")

        // First set short: suggest a lighter weight, don't change it.
        let short = SetPlan(targets: Array(repeating: SetTarget(weightKg: 100, reps: 8, rir: 2), count: 3), reason: "")
            .adjusted(afterSet: 0, done: [WorkoutSetLog(setNumber: 1, weightKg: 100, reps: 5)], exercise: benchDef)
        check(short.suggestedWeightKg == 97.5 && short.targets[1].weightKg == 100 && short.targets[1].rir == 2,
              "set 1 was 5 of 8 → suggest 97.5 kg, plan stays at 100 kg")

        // Basketball last night + leg day today.
        let legs = WorkoutRoutine(name: "Legs", exercises: [RoutineExercise(exercise: def("Back Squat", .legs, sets: 4), order: 0)])
        var game = CardioSession(id: UUID(), kind: .basketball, indoor: true, startedAt: now10.addingTimeInterval(-20 * 3600),
                                 endedAt: now10.addingTimeInterval(-18.5 * 3600), activeSeconds: 90 * 60)
        game.effort = 8
        check(game.sessionLoad == 720, "session load = effort 8 × 90 min")
        check(CoachBrain.cardioLegWarning(for: legs, cardio: [game], now: now10) != nil, "hard basketball yesterday → leg-day warning")
        check(CoachBrain.cardioLegWarning(for: benchOnly, cardio: [game], now: now10) == nil, "…but not before an upper-body day")

        // Consistency: 4-day routines, training once a week for 7 weeks.
        let fourDays = (1...4).map { WorkoutRoutine(name: "Day \($0)", exercises: [RoutineExercise(exercise: benchDef, order: 0)]) }
        let rare = (0..<7).map { session(fourDays[0], now10.addingTimeInterval(-Double(48 - $0 * 7) * day10), ["Barbell Bench Press": (100 + Double($0) * 2.5, 8)]) }
        check(CoachBrain.consistency(routines: fourDays, logs: rare, plans: [], now: now10).contains { $0.id.hasPrefix("fit-split") },
              "4 routines but training once a week → suggest a split that fits")

        // MARK: MK10.1 — set-by-set comparison, coach's brief, heart rate

        let curlDef = ExerciseDefinition(name: "Cable Curl", category: .biceps, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 75, weightIncrementKg: 2.5)
        let last888 = log(curlDef, [(20, 8), (20, 8), (20, 8)])
        let today996 = [(20.0, 9), (20.0, 9), (20.0, 6)].enumerated().map { WorkoutSetLog(setNumber: $0.offset + 1, weightKg: $0.element.0, reps: $0.element.1) }
        let lopsided = SetComparison.advice(current: today996, previous: last888, repMin: 8, repMax: 12, assisted: false) ?? ""
        check(lopsided.contains("Same total (24)") && lopsided.contains("9·8·8"), "9·9·6 vs 8·8·8 → same total, ran out on set 3, aim 9·8·8")
        check(SetComparison.evenTargets(total: 25, sets: 3) == [9, 8, 8], "25 reps over 3 sets → 9·8·8")
        let upAll = [(20.0, 9), (20.0, 9), (20.0, 9)].enumerated().map { WorkoutSetLog(setNumber: $0.offset + 1, weightKg: $0.element.0, reps: $0.element.1) }
        check(SetComparison.advice(current: upAll, previous: last888, repMin: 8, repMax: 12, assisted: false)?.hasPrefix("Up on every set") == true,
              "9·9·9 vs 8·8·8 → up on every set")
        check(SetComparison.arrow(set: today996[2], index: 2, previous: last888)?.arrow == .down, "set 3: 6 vs 8 ↓")
        let lopsidedLog = log(curlDef, [(20, 9), (20, 9), (20, 6)])
        let evenPlan = ProgressionEngine.setPlan(for: curlDef, previous: lopsidedLog, recent: [lopsidedLog])
        check(evenPlan.targets.map(\.reps) == [9, 8, 8] && evenPlan.targets.allSatisfy { $0.weightKg == 20 },
              "after 9·9·6 the next plan evens out: 20 kg × 9·8·8")

        let routineID101 = UUID()
        let start101 = now10.addingTimeInterval(-2 * 3600)
        var lastWeek = WorkoutLog(routineID: routineID101, routineName: "Arms", startedAt: start101.addingTimeInterval(-7 * day10),
                                  endedAt: start101.addingTimeInterval(-7 * day10 + 3000), exercises: [last888])
        lastWeek.maxHeartRateBPM = 150
        var older = lastWeek
        older.id = UUID()
        older.startedAt = start101.addingTimeInterval(-14 * day10)
        older.maxHeartRateBPM = 154
        var strongSets = upAll
        strongSets[0].isPR = true
        var todayLog = WorkoutLog(routineID: routineID101, routineName: "Arms", startedAt: start101, endedAt: start101.addingTimeInterval(3000),
                                  exercises: [ExerciseLog(exerciseID: curlDef.id, exerciseName: curlDef.name, repMinAtTime: 8, repMaxAtTime: 12,
                                                          weightIncrementKgAtTime: 2.5, sets: strongSets)])
        todayLog.maxHeartRateBPM = 171
        todayLog.heartRateSeries = (0..<30).map { HeartRatePoint(t: $0 * 10, bpm: 110 + $0 * 2) }
        let brief = WorkoutBriefBuilder.make(for: todayLog, logs: [older, lastWeek, todayLog], style: .analytical)
        check(brief.rating == "Strong session" || brief.rating == "Solid session", "up on every set + a PR → a good rating (\(brief.rating))")
        check(brief.lines.first?.contains("PR") == true, "brief leads with what went well")
        let hr = HeartRateAnalysis.summary(for: todayLog, logs: [older, lastWeek, todayLog], maxHeartRate: 190)
        check(hr.peak == 171 && hr.usualPeak == 152, "peak 171 vs usual 152 for this routine")

        // MK10.2: runs and basketball don't count as sessions
        let runLog = CardioSession(id: UUID(), kind: .run, indoor: false, startedAt: now10, endedAt: now10.addingTimeInterval(1800),
                                   activeSeconds: 1800, distanceKm: 5).workoutLog
        let liftLog = session(benchOnly, now10.addingTimeInterval(-3600), ["Barbell Bench Press": (100, 8)])
        check(!runLog.countsAsTraining && liftLog.countsAsTraining, "a run is an extra; a lifting session counts")
        check(ConsistencyCalculator.stats(logs: [runLog, liftLog], weeklyGoal: 4, now: now10).thisWeekCount == 1,
              "weekly goal counts only the lifting session")

        // MK11: sleep schedule and consistency
        let cal11 = Calendar.current
        let evening11 = cal11.startOfDay(for: now10.addingTimeInterval(-86_400))
        var schedule11 = SleepSchedule.standard
        schedule11.bedtime[cal11.component(.weekday, from: evening11)] = 30   // 00:30 after midnight
        check(schedule11.bedtime(forNightOf: evening11) == evening11.addingTimeInterval(24.5 * 3600), "after-midnight bedtime lands on the next day")
        let onTime = SleepNight(date: cal11.startOfDay(for: now10), hoursAsleep: 6.5,
                                start: evening11.addingTimeInterval(24.75 * 3600), end: evening11.addingTimeInterval(31.1 * 3600))
        let report11 = SleepAnalysis.report(nights: [onTime], schedule: schedule11, now: now10)
        check(report11.lastNight?.bedMinutesOff == 15 && report11.lastNight?.wakeMinutesOff == 6 && report11.onScheduleStreak == 1,
              "bed 00:45 vs 00:30 (+15), up 07:06 vs 07:00 (+6): on schedule")
        let late = SleepNight(date: cal11.startOfDay(for: now10), hoursAsleep: 5,
                              start: evening11.addingTimeInterval(26 * 3600), end: evening11.addingTimeInterval(31 * 3600))
        check(SleepAnalysis.report(nights: [late], schedule: schedule11, now: now10).lateNights7 == 1, "bed at 02:00 vs 00:30 is a late night")

        // MK11.1: like-for-like comparisons
        let press11 = ExerciseDefinition(name: "Bench Press", category: .chest, repMin: 6, repMax: 10, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5)
        let base11 = log(press11, [(80, 8), (80, 8), (80, 8)])
        check(ProgressionEngine.compare(current: log(press11, [(80, 8), (80, 8)]), previous: base11).kind == .matched,
              "two of three sets at the same reps is not a decline (fewer sets ≠ weaker)")
        check(ProgressionEngine.compare(current: log(press11, [(80, 8), (80, 8), (80, 8), (80, 6)]), previous: base11).kind == .matched,
              "an extra set is not 'improved'")
        check(ProgressionEngine.compare(current: log(press11, [(80, 8), (80, 8), (80, 7)]), previous: base11).kind == .matched,
              "one rep down is within noise")
        check(ProgressionEngine.compare(current: log(press11, [(80, 8), (80, 7), (80, 6)]), previous: base11).kind == .declined,
              "three reps down on matching sets is a decline")
        var easier = log(press11, [(80, 8), (80, 8), (80, 8)])
        var harder = base11
        for i in 0..<3 { easier.sets[i].rir = 3; harder.sets[i].rir = 1 }
        check(ProgressionEngine.compare(current: easier, previous: harder).kind == .improved,
              "same reps with more left in the tank counts as progress")
        check(ProgressionEngine.compare(current: harder, previous: easier).kind == .matched,
              "same reps but closer to failure is noted, not called progress")
        check(ProgressionEngine.compare(current: log(press11, [(75, 10), (75, 10), (75, 9)]), previous: base11).kind == .matched,
              "lighter for more reps at a similar est. 1RM is 'similar strength', not a decline")
        var newRange = log(press11, [(85, 5), (85, 5), (85, 5)])
        newRange.repMinAtTime = 4
        newRange.repMaxAtTime = 6
        check(ProgressionEngine.compare(current: newRange, previous: base11).kind == .matched,
              "a new rep range is judged on est. 1RM (85×5 ≈ 80×8)")
        let drop11 = log(press11, [(80, 5), (80, 5), (80, 5)])
        check(ProgressionEngine.compare(current: drop11, previous: base11, context: [.unusualFatigue]).kind == .matched,
              "a drop on a run-down day isn't called a decline")

        // MK11.1: session context keeps odd days out of 'last time'
        let normal11 = WorkoutLog(routineID: UUID(), routineName: "Push", startedAt: now10.addingTimeInterval(-3 * day10),
                                  endedAt: now10.addingTimeInterval(-3 * day10 + 3600), exercises: [base11])
        var tired11 = WorkoutLog(routineID: UUID(), routineName: "Push", startedAt: now10.addingTimeInterval(-day10),
                                 endedAt: now10.addingTimeInterval(-day10 + 3600), exercises: [drop11])
        tired11.sessionTags = [.unusualFatigue]
        check([normal11, tired11].previousLog(for: press11)?.sets.first?.reps == 8, "a run-down session isn't used as last time")
        var short11 = tired11
        short11.sessionTags = [.limitedTime]
        check(!short11.skipsProgression && short11.isAtypical, "short on time still counts as last time, but not for plateaus")
        var state11 = ActiveWorkoutState(routine: WorkoutRoutine(name: "Push", exercises: [RoutineExercise(exercise: press11, order: 0)]))
        state11.toggleTag(.equipmentUnavailable)
        check(state11.makeLog().sessionTags == [.equipmentUnavailable],
              "tags on the live workout are saved with it")

        // MK11.1: separate goals
        let run11 = CardioSession(id: UUID(), kind: .run, indoor: false, startedAt: now10, endedAt: now10.addingTimeInterval(1800),
                                  activeSeconds: 1800, distanceKm: 5)
        let goals11 = TrainingGoalTracker.progress(goals: TrainingGoals(runsPerWeek: 2, runKmPerWeek: 15), liftGoal: 4,
                                                   logs: [liftLog, runLog], cardio: [run11], now: now10)
        check(goals11.first { $0.kind == .lifting }?.done == 1 && goals11.first { $0.kind == .runs }?.done == 1
              && goals11.first { $0.kind == .runKm }?.done == 5 && !goals11.contains { $0.kind == .basketball },
              "lifting, runs and km tracked separately; no basketball row without games or a goal")

        // MK11.1: Cluck as coach
        let intro11 = CluckCoach.cue(state: state11, plan: SetPlan(targets: [SetTarget(weightKg: 80, reps: 8, rir: 2)], reason: "Beat 24 reps"),
                                     recommendation: nil, formCue: "Elbows at 45°.",
                                     suggestions: [CoachSuggestion(exerciseKey: press11.historyKey, exerciseName: press11.name, text: "Drop to 3 sets", kind: .other)])
        check(intro11.moment == .intro && intro11.headline.contains("First up: Bench Press") && intro11.reminders.count == 1,
              "session intro names the first exercise and reminds you of the accepted plan")
        check(intro11.reasons.contains("Beat 24 reps") && intro11.reasons.contains { $0.contains("equipment unavailable") },
              "Explain, Sergeant includes the plan reason and today's context")

        // MK11.2: bedtime nags
        check(BedtimeNag.offsets.first == 10 && BedtimeNag.offsets.last == 60 && BedtimeNag.offsets.contains(35),
              "nags every 10 min, every 5 after 30 min late, stop at an hour")
        check(BedtimeNag.message(minutesLate: 20).body.contains("20 minutes past your bedtime"), "the nag says how late you are")

        // MK11.3: variations only compare with the same variation
        var wide13 = log(press11, [(70, 8)])
        wide13.variation = "Wide grip"
        check(!wide13.matches(base11) && wide13.matches(wide13), "wide grip isn't compared with the usual grip")
        var state13 = ActiveWorkoutState(routine: WorkoutRoutine(name: "Push", exercises: [RoutineExercise(exercise: press11, order: 0)]))
        state13.setVariation(" Narrow grip ", for: press11.id)
        _ = state13.completeSet(weightKg: 70, reps: 8, targetWeightKg: nil, targetReps: nil)
        check(state13.makeLog().exercises.first?.variation == "Narrow grip", "today's variation is saved with the exercise")

        // MK11.3: Give me a break is hard to trigger
        let due13 = now10.addingTimeInterval(5 * day10)
        check(GymBreakRules.refusal(reason: .deadlines, count: 1, detail: "CIVL report", lastDue: due13, history: [], now: now10) != nil,
              "one assignment isn't a break")
        check(GymBreakRules.refusal(reason: .deadlines, count: 2, detail: "CIVL report + exam", lastDue: due13, history: [], now: now10) == nil,
              "two assignments due within 2 weeks is")
        check(GymBreakRules.refusal(reason: .deadlines, count: 2, detail: "CIVL report + exam", lastDue: now10.addingTimeInterval(20 * day10), history: [], now: now10) != nil,
              "a break is 14 days at most")
        let break13 = GymBreakRules.make(reason: .deadlines, count: 2, detail: "CIVL report + exam", mode: .maintenance,
                                         lastDue: now10.addingTimeInterval(-10 * day10), now: now10.addingTimeInterval(-20 * day10))
        check(GymBreakRules.refusal(reason: .deadlines, count: 3, detail: "More exams", lastDue: due13, history: [break13], now: now10) != nil,
              "only one break every 6 weeks")
        check(break13.weekGoal(normal: 5) == 2, "maintenance mode drops the goal to 2")
        check(GymBreakRules.comeback(breaks: [break13], logs: [], now: now10.addingTimeInterval(-7 * day10)),
              "first week back after a 10-day break offers a comeback session")
        var cluck13 = CluckSnapshot(goal: 2, workoutDates: [], snoozedDay: nil, coachStyle: "pushMe", enabled: true, updatedAt: now10)
        cluck13.breakUntil = now10.addingTimeInterval(day10)
        check(CluckEngine.evaluate(cluck13, at: now10).mood == .empathetic, "on a break Cluck stands down")

        // MK12: bedtime streak (nights in a row in bed by bedtime)
        let cal12 = Calendar.current
        let tonight12 = cal12.startOfDay(for: now10)
        func night12(_ back: Int) -> Date { cal12.date(byAdding: .day, value: -back, to: tonight12)! }
        check(BedtimeNag.streak(log: [night12(1): -3, night12(2): 0, night12(3): 12, night12(4): -1], today: tonight12) == 2,
              "streak counts back from last night and stops at a late night")
        check(BedtimeNag.streak(log: [night12(0): -5, night12(1): -3], today: tonight12) == 2, "tonight counts once logged")
        check(BedtimeNag.streak(log: [night12(2): -3], today: tonight12) == 0, "a skipped night breaks the streak")
        check(BedtimeNag.windowBefore == 10 * 60, "wind-down starts 10 minutes before bed")

        // MK14: protein nags only while behind pace
        check(ProteinNag.behind(eaten: 0, target: 160).count == 3, "nothing eaten: all three checkpoints nag")
        check(ProteinNag.behind(eaten: 60, target: 160).count == 2, "60 of 160 g clears the midday checkpoint (56 g)")
        check(ProteinNag.behind(eaten: 140, target: 160).isEmpty, "on pace for the evening: no nags")
        check(ProteinNag.behind(eaten: 0, target: 0).isEmpty, "no target (no body weight): no nags")
        check(ProteinNag.message(eaten: 100, target: 160, at: ProteinNag.checkpoints[2]).title.contains("60 g SHORT"), "evening nag says how short")

        // MK15: nightly recap
        let recap15 = DailyRecap.make(proteinG: 120, target: 165, creatine: false, trained: true, stepsDone: 5, stepsTotal: 6, gymTomorrow: "Push")
        check(recap15.title == "🪖 Day recap: 0 of 3 on target", "recap counts protein, creatine and Dayfold")
        check(recap15.advice.first?.contains("45 g short") == true, "recap says how much protein was missing")
        check(recap15.advice.count == 3, "recap keeps advice to 3 lines")
        check(DailyRecap.make(proteinG: 160, target: 165, creatine: true, trained: false, stepsDone: 2, stepsTotal: 2, gymTomorrow: nil).title
              == "🪖 Day recap: everything on target", "within 5% of target counts as hit")

        // MK16: meal prep and quotes
        check(MealPrep.title(target: 165) == "Meal prep · 5 lunches × 50 g protein", "meal prep lunches carry ~30% of the day's protein")
        check(MealPrep.title(target: nil) == "Meal prep · 5 protein lunches", "no target: still a meal-prep step")
        var cal16 = Calendar(identifier: .gregorian)
        cal16.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        func at16(_ day: Int, _ hour: Int) -> Date { cal16.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        check(QuotePicker.slot(at: at16(26, 13), calendar: cal16) == QuotePicker.slot(at: at16(26, 8), calendar: cal16) + 1, "13:00 is the next quote after 8:00")
        check(QuotePicker.slot(at: at16(27, 6), calendar: cal16) == QuotePicker.slot(at: at16(26, 20), calendar: cal16), "before 8 am keeps last night's quote")
        check(QuotePicker.nextSlotStart(after: at16(26, 19), calendar: cal16) == at16(27, 8), "after 18:00 the next change is 8 am")
        let pool16 = QuotePicker.pool(topics: [.gym, .rest], tough: false)
        check(!pool16.isEmpty && pool16.allSatisfy { [.gym, .rest].contains($0.topic) && !$0.tough }, "only chosen topics, calm lines only")
        check(zip(pool16, pool16.dropFirst()).allSatisfy { $0.topic != $1.topic } || pool16.count < 2, "topics take turns")
        check(Set((0..<pool16.count).map { QuotePicker.quote(slot: $0, offset: 0, topics: [.gym, .rest], tough: false).text }).count == pool16.count,
              "no repeats until the pool runs out")
        check(QuotePicker.pool(topics: [.gym], tough: true).contains { $0.tough }, "Tough adds Sergeant Cluck's lines")

        // MK17 logic review — 1: bodyweight at the top of its range progresses the movement, not "+2.5 kg"
        let pushup = ExerciseDefinition(name: "Push-up", category: .chest, repMin: 10, repMax: 20, defaultSets: 3, restSeconds: 60, weightIncrementKg: 0)
        let pushTop = log(pushup, [(0, 20), (0, 20), (0, 20)])
        let pushAdvice = ProgressionEngine.recommendation(for: pushup, previous: pushTop)
        check(pushAdvice.action == .keepWeight(targetTotalReps: 60) && pushAdvice.title == "Top of the range",
              "3 × 20 push-ups → harder variation / slower reps, never '+2.5 kg'")
        let pushPlan = ProgressionEngine.setPlan(for: pushup, previous: pushTop, recent: [pushTop])
        check(pushPlan.targets.allSatisfy { $0.weightKg == 0 && $0.reps == 20 } && pushPlan.reason.contains("hold it there"),
              "bodyweight set plan holds 20 reps at bodyweight")
        check(ProgressionEngine.recommendation(for: pushup, previous: log(pushup, [(0, 15), (0, 14), (0, 12)])).title == "Keep bodyweight",
              "mid-range bodyweight says 'Keep bodyweight', not 'Keep 0 kg'")
        check(ProgressionEngine.recommendation(for: press, previous: log(press, [(80, 12), (80, 12), (80, 12)])).action == .increaseWeight(suggestedKg: 82.5),
              "loaded lifts still add an increment at the top of the range")

        // 2 + 3: body advice follows the goal
        check(CoachEngine.bodyInsight(goal: .loseFat, strength: .flat, weightTrend: 0.3, fatTrend: 0.4)?.title == "Weight is trending up",
              "gaining (and fatter) on a Lose Fat goal is called out as such, not 'lean gain too fast'")
        check(CoachEngine.bodyInsight(goal: .buildMuscle, strength: .flat, weightTrend: 0.7, fatTrend: nil)?.title == "Weight gain may be too fast",
              "gaining 0.7 kg/week on a bulk is too fast")
        check(CoachEngine.bodyInsight(goal: .buildMuscle, strength: .flat, weightTrend: -0.3, fatTrend: nil)?.title == "Losing weight on a muscle-building goal",
              "losing weight while trying to build muscle is a problem, not 'still progress'")
        check(CoachEngine.bodyInsight(goal: .loseFat, strength: .flat, weightTrend: -0.3, fatTrend: nil)?.title == "Holding strength while losing weight",
              "losing weight on a cut with steady strength is still good news")

        // 4: strength trend skips deload / tagged sessions and keeps variations apart
        func benchLog(_ date: Date, _ kg: Double, _ variation: String? = nil) -> WorkoutLog {
            var lift = log(benchDef, [(kg, 8)])
            lift.variation = variation
            return WorkoutLog(routineID: push.id, routineName: "Push", startedAt: date, endedAt: date.addingTimeInterval(3600), exercises: [lift])
        }
        var trendLogs = [benchLog(now10.addingTimeInterval(-30 * day10), 100), benchLog(now10.addingTimeInterval(-3 * day10), 104)]
        var deloadDay = benchLog(now10.addingTimeInterval(-1 * day10), 85)
        deloadDay.isDeload = true
        trendLogs.append(deloadDay)
        check(StrengthAnalyzer.trend(logs: trendLogs, now: now10) == .up, "a deload session doesn't turn a rising lift into 'strength down'")
        trendLogs.append(benchLog(now10.addingTimeInterval(-20 * day10), 90, "Paused"))
        trendLogs.append(benchLog(now10.addingTimeInterval(-2 * day10), 92, "Paused"))
        check(StrengthAnalyzer.trend(logs: trendLogs, now: now10) == .up, "lighter paused bench is its own lift, not a drop in bench")

        // 5: breaks stay out of adherence and averages, and a week with no target has no 'X to go'
        let breakNow = Calendar.current.dateInterval(of: .weekOfYear, for: now10)!.start.addingTimeInterval(3 * day10)
        var breakLogs: [WorkoutLog] = []
        for week in [1, 4, 5, 6, 7, 8] {
            for d in 0..<3 {
                let date = breakNow.addingTimeInterval(-Double(7 * week - d) * day10)
                breakLogs.append(WorkoutLog(routineID: routine.id, routineName: "Test", startedAt: date, endedAt: date.addingTimeInterval(3600), exercises: [log(press, [(80, 10)])]))
            }
        }
        let breakWeeks = DateInterval(start: breakNow.addingTimeInterval(-3 * 7 * day10 - 3 * day10), end: breakNow.addingTimeInterval(-1 * 7 * day10 - 3 * day10))
        let withBreak = ConsistencyCalculator.stats(logs: breakLogs, weeklyGoal: 3, now: breakNow, breaks: [breakWeeks])
        let noBreak = ConsistencyCalculator.stats(logs: breakLogs, weeklyGoal: 3, now: breakNow)
        check(withBreak.last4WeeksAdherence == 1 && noBreak.last4WeeksAdherence < 0.6, "two break weeks don't count as missed sessions")
        check(withBreak.averagePerWeek == 3, "the weekly average leaves break weeks out")
        var offWeek = withBreak
        offWeek.weeklyGoal = 0
        check(CoachEngine.consistencyInsight(offWeek, style: .pushMe).title == "No target this week", "full break / sick week: no 'X to go'")

        // 8: a planned variation isn't a stall, and today's targets come from the same variation
        var variationLogs: [WorkoutLog] = []
        for index in 0..<4 { variationLogs.append(benchLog(now10.addingTimeInterval(-Double(60 - index * 7) * day10), 100 + Double(index) * 2.5)) }
        for index in 0..<6 { variationLogs.append(benchLog(now10.addingTimeInterval(-Double(32 - index * 6) * day10), 85 + Double(index) * 1.25, "Paused")) }
        let benchRoutine = WorkoutRoutine(name: "Bench", exercises: [RoutineExercise(exercise: benchDef, order: 0)])
        check(CoachBrain.stalls(routines: [benchRoutine], logs: variationLogs, now: now10).isEmpty,
              "a rising paused-bench block isn't called a bench stall")
        var flatPaused = variationLogs
        for index in 0..<6 { flatPaused[4 + index] = benchLog(now10.addingTimeInterval(-Double(32 - index * 6) * day10), 85, "Paused") }
        check(!CoachBrain.stalls(routines: [benchRoutine], logs: flatPaused, now: now10).isEmpty, "a paused bench that really is stuck is still a stall")
        let usual = benchLog(now10.addingTimeInterval(-6 * day10), 100)
        var usualTop = usual
        usualTop.exercises[0].sets = (1...4).map { WorkoutSetLog(setNumber: $0, weightKg: 100, reps: 12) }
        let wideDay = benchLog(now10.addingTimeInterval(-2 * day10), 80, "Wide grip")
        let todayBench = ActiveWorkoutState(routine: benchRoutine)
        let usualPlan = todayBench.setPlan(for: benchRoutine.exercises[0], logs: [usualTop, wideDay])
        check(usualPlan.targets.first?.weightKg == 102.5, "normal bench today aims off the last normal session, not the lighter wide-grip day")

        // 10: "Ready to add weight" says why
        let easyLog = WorkoutLog(routineID: routine.id, routineName: "Test", startedAt: now10.addingTimeInterval(-2 * day10),
                                 endedAt: now10.addingTimeInterval(-2 * day10 + 3600), exercises: [easy])
        let readyNote = CoachEngine.progressionInsight(CoachContext(profile: UserProfile(), weeklyGoal: 3, routines: [routine], logs: [easyLog], now: now10))
        check(readyNote?.message.contains("3+ reps left") == true && readyNote?.message.contains("top of the range") == false,
              "an easy-feeling increase isn't described as hitting the top of the range")

        print("PASS: all GymForge checks")
    }
}
