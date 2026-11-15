import Foundation

/// MK23: demo mode. Launching with `-demo YES` shows made-up data (never yours), asks for no permissions,
/// sends no notifications and writes to its own file. GitHub uses it to take a picture of each screen on
/// every build (`-screen today`, `-screen progress`, …), so a build can be looked at before it's installed.
enum Demo {
    static let isOn = UserDefaults.standard.bool(forKey: "demo")
    /// Which screen to open straight away (see `DemoScreen`).
    static let screen = UserDefaults.standard.string(forKey: "screen")

    /// Six months of training on the starter routines: most lifts climbing, one flat, one slipping.
    static func snapshot(now: Date = Date()) -> AppSnapshot {
        let calendar = Calendar.current
        var random = Seeded(seed: 20261115)
        let routines = SeedData.starterRoutines
        let chest = routines[0], back = routines[1], legs = routines[2]
        // weekday (1 = Sunday) → routine: Mon chest, Tue back, Wed legs, Fri chest, Sat back.
        let split: [Int: WorkoutRoutine] = [2: chest, 3: back, 4: legs, 6: chest, 7: back]
        // Starting weight, and kg gained per session done.
        let plan: [String: (start: Double, gain: Double)] = [
            "Incline Machine Press": (50, 0.45), "Chest Press": (60, 0.5), "Cable Fly": (15, 0.12),
            "Lateral Raise": (8, 0.0), "Tricep Pushdown": (25, 0.2),
            "Lat Pulldown": (55, 0.4), "Seated Cable Row": (50, 0.35), "Rear Delt Fly": (10, -0.04), "Bicep Curl": (12, 0.08),
            "Leg Press": (120, 1.6), "Romanian Deadlift": (60, 0.7), "Leg Extension": (45, 0.4), "Calf Raise": (60, 0.5)
        ]
        var done: [String: Int] = [:]
        var best: [String: Double] = [:]
        var logs: [WorkoutLog] = []
        let today = calendar.startOfDay(for: now)
        for offset in stride(from: 182, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let routine = split[calendar.component(.weekday, from: day)],
                  random.unit() < 0.86,
                  let start = calendar.date(bySettingHour: 17, minute: 30 + Int(random.unit() * 25), second: 0, of: day) else { continue }
            var clock = start
            var exercises: [ExerciseLog] = []
            for item in routine.exercises where !item.exercise.isCardio {
                let exercise = item.exercise
                guard let lift = plan[exercise.name] else { continue }
                let count = done[exercise.name, default: 0]
                done[exercise.name] = count + 1
                let step = exercise.weightIncrementKg
                let weight = max(step, ((lift.start + lift.gain * Double(count)) / step).rounded() * step)
                var sets: [WorkoutSetLog] = []
                for number in 1...exercise.defaultSets {
                    clock = clock.addingTimeInterval(Double(exercise.restSeconds) + 45)
                    let reps = max(exercise.repMin - 1, exercise.repMax - 3 + Int(random.unit() * 4) - (number - 1))
                    var set = WorkoutSetLog(setNumber: number, weightKg: weight, reps: reps, completedAt: clock,
                                            targetWeightKg: weight, targetReps: exercise.repMax, rir: number == exercise.defaultSets ? 1 : 2)
                    if set.estimatedOneRepMaxKg > best[exercise.name, default: 0] + 0.01 {
                        if best[exercise.name] != nil { set.isPR = true }
                        best[exercise.name] = set.estimatedOneRepMaxKg
                    }
                    sets.append(set)
                }
                exercises.append(ExerciseLog(exerciseID: exercise.id, exerciseName: exercise.name, repMinAtTime: exercise.repMin,
                                             repMaxAtTime: exercise.repMax, weightIncrementKgAtTime: step, sets: sets,
                                             category: exercise.category))
            }
            logs.append(WorkoutLog(routineID: routine.id, routineName: routine.name, startedAt: start,
                                   endedAt: clock.addingTimeInterval(120), exercises: exercises,
                                   activeCaloriesKcal: 380 + random.unit() * 90, averageHeartRateBPM: 118 + random.unit() * 10,
                                   maxHeartRateBPM: 150 + random.unit() * 14))
        }

        var profile = UserProfile(goal: .buildMuscle, coachStyle: .motivating)
        profile.heightCm = 178
        profile.birthDate = calendar.date(byAdding: .year, value: -24, to: today)
        profile.sex = "male"

        var extras = GymExtras()
        extras.nutritionPhase = .bulk
        extras.phases = [PhaseRecord(phase: .bulk, start: calendar.date(byAdding: .day, value: -70, to: today) ?? today)]
        // A weigh-in every Sunday for 26 weeks: slow bulk.
        for week in 0..<26 {
            guard let date = calendar.date(byAdding: .day, value: -7 * week - (calendar.component(.weekday, from: today) - 1), to: today),
                  let morning = calendar.date(bySettingHour: 9, minute: 5, second: 0, of: date), morning <= now else { continue }
            extras.weighIns.append(WeighIn(date: morning, weightKg: (77.4 - Double(week) * 0.16 + (random.unit() - 0.5) * 0.5).rounded(toPlaces: 1),
                                           bodyFatPercent: (15.6 - Double(week) * 0.03 + (random.unit() - 0.5) * 0.4).rounded(toPlaces: 1)))
        }
        for offset in 0..<10 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            extras.nutrition.append(NutritionDay(day: day, creatine: offset != 3, proteinG: offset == 0 ? 85 : 120 + Double(Int(random.unit() * 40)),
                                                 calories: offset == 0 ? 1450 : 2500 + Double(Int(random.unit() * 500))))
        }
        var snapshot = AppSnapshot(routines: routines, workoutLogs: logs, weeklyGoal: 5, profile: profile, extras: extras)
        snapshot.cardioSessions = []
        return snapshot
    }

    /// Small repeatable generator, so every build's pictures show the same numbers.
    struct Seeded {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func unit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(UInt64(1) << 31)
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}
