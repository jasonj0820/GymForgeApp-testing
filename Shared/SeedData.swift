import Foundation

public enum SeedData {
    public static var starterRoutines: [WorkoutRoutine] { [chestRoutine, backRoutine, legRoutine] }

    private static func routine(_ name: String, _ exercises: [ExerciseDefinition]) -> WorkoutRoutine {
        WorkoutRoutine(
            name: name,
            exercises: exercises.enumerated().map { RoutineExercise(exercise: $0.element, order: $0.offset) }
        )
    }

    public static let chestRoutine: WorkoutRoutine = routine("Chest Day", [
        ExerciseDefinition(name: "Incline Machine Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Chest Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5,
                           notes: "Seat so handles line up mid-chest.",
                           alternatives: [
                               ExerciseDefinition(name: "Bench Press", category: .chest, repMin: 6, repMax: 10, defaultSets: 3, restSeconds: 150, weightIncrementKg: 2.5),
                               ExerciseDefinition(name: "Incline Bench Press", category: .chest, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5)
                           ]),
        ExerciseDefinition(name: "Cable Fly", category: .chest, repMin: 10, repMax: 15, defaultSets: 3, restSeconds: 90, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Lateral Raise", category: .shoulders, repMin: 12, repMax: 20, defaultSets: 3, restSeconds: 60, weightIncrementKg: 1),
        ExerciseDefinition(name: "Tricep Pushdown", category: .triceps, repMin: 10, repMax: 15, defaultSets: 3, restSeconds: 90, weightIncrementKg: 2.5)
    ])

    public static let backRoutine: WorkoutRoutine = routine("Back Day", [
        ExerciseDefinition(name: "Lat Pulldown", category: .back, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Seated Cable Row", category: .back, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 120, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Rear Delt Fly", category: .shoulders, repMin: 12, repMax: 20, defaultSets: 3, restSeconds: 60, weightIncrementKg: 1),
        ExerciseDefinition(name: "Bicep Curl", category: .biceps, repMin: 10, repMax: 15, defaultSets: 3, restSeconds: 90, weightIncrementKg: 1)
    ])

    public static let legRoutine: WorkoutRoutine = routine("Leg Day", [
        ExerciseDefinition(name: "Leg Press", category: .legs, repMin: 8, repMax: 12, defaultSets: 3, restSeconds: 150, weightIncrementKg: 5),
        ExerciseDefinition(name: "Romanian Deadlift", category: .legs, repMin: 6, repMax: 10, defaultSets: 3, restSeconds: 150, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Leg Extension", category: .legs, repMin: 10, repMax: 15, defaultSets: 3, restSeconds: 90, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Calf Raise", category: .calves, repMin: 12, repMax: 20, defaultSets: 3, restSeconds: 60, weightIncrementKg: 2.5),
        ExerciseDefinition(name: "Incline Treadmill Walk", category: .cardio, repMin: 1, repMax: 1, defaultSets: 1, restSeconds: 0, weightIncrementKg: 0, targetMinutes: 15)
    ])
}
