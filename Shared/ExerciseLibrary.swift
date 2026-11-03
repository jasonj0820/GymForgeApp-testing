import Foundation

// MK9.1: what the coach knows about common gym exercises — which muscles they train (secondary
// work counts half), sensible rep ranges, rest, weight steps, how tiring they are, warm-ups and swaps.
// Sources: hypertrophy / strength research consensus (weekly hard sets per muscle, proximity to
// failure, rest 2–3 min on big lifts, 2×/week frequency). These are starting points; the coach then
// adjusts to how *you* respond.

/// Muscles the coach tracks (finer than ExerciseCategory).
public enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, lats, upperBack, frontDelts, sideDelts, rearDelts, biceps, triceps
    case quads, hamstrings, glutes, calves, abs

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chest: return "Chest"
        case .lats: return "Lats"
        case .upperBack: return "Upper back"
        case .frontDelts: return "Front delts"
        case .sideDelts: return "Side delts"
        case .rearDelts: return "Rear delts"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .calves: return "Calves"
        case .abs: return "Abs"
        }
    }

    public var category: ExerciseCategory {
        switch self {
        case .chest: return .chest
        case .lats, .upperBack: return .back
        case .frontDelts, .sideDelts, .rearDelts: return .shoulders
        case .biceps: return .biceps
        case .triceps: return .triceps
        case .quads, .hamstrings, .glutes: return .legs
        case .calves: return .calves
        case .abs: return .core
        }
    }

    /// Weekly hard sets (direct + half of secondary) that most people grow on.
    /// Front delts get plenty from pressing, so they need little or no direct work.
    public var weeklyRange: (low: Double, high: Double) {
        switch self {
        case .chest, .lats, .quads: return (10, 20)
        case .upperBack, .sideDelts: return (8, 20)
        case .hamstrings, .calves: return (8, 16)
        case .rearDelts, .glutes, .biceps, .triceps: return (6, 16)
        case .frontDelts, .abs: return (0, 14)
        }
    }

    /// Where training it more than this per week is usually wasted (or hurts recovery).
    public var weeklyCeiling: Double { weeklyRange.high + 5 }
}

public enum MovementKind: String, Codable {
    case compound, isolation
}

public enum EquipmentKind: String, Codable {
    case barbell, dumbbell, machine, cable, bodyweight
}

public struct ExerciseProfile: Hashable {
    public let name: String
    /// Lower-case phrases that identify it in your exercise names (the longest match wins).
    public let keywords: [String]
    public let muscles: [Muscle: Double]
    public let kind: MovementKind
    public let equipment: EquipmentKind
    public let category: ExerciseCategory
    /// Size-focused rep range.
    public let repMin: Int
    public let repMax: Int
    /// Main lifts only: rep range when the focus is strength.
    public let strengthRange: ClosedRange<Int>?
    public let restSeconds: Int
    public let increment: Double
    /// 1 = barely tiring (curls), 3 = whole-body fatigue (squats, deadlifts).
    public let fatigue: Int
    /// Loads the muscle hard in the stretched position (some evidence it grows more).
    public let stretchFocus: Bool
    public let substitutes: [String]

    public var isMainLift: Bool { strengthRange != nil }
    /// Heavy compounds get ramp-up sets.
    public var needsRampUp: Bool { kind == .compound && fatigue >= 2 && equipment != .bodyweight }
    public var primaryMuscles: [Muscle] { muscles.filter { $0.value >= 1 }.map(\.key).sorted { $0.rawValue < $1.rawValue } }
    public func contribution(to muscle: Muscle) -> Double { muscles[muscle] ?? 0 }
}

public enum ExerciseLibrary {
    // swiftlint:disable function_body_length
    private static func p(_ name: String, _ keywords: [String], _ muscles: [Muscle: Double],
                          _ kind: MovementKind, _ equipment: EquipmentKind, _ category: ExerciseCategory,
                          reps: ClosedRange<Int>, strength: ClosedRange<Int>? = nil, rest: Int, step: Double,
                          fatigue: Int, stretch: Bool = false, swaps: [String] = []) -> ExerciseProfile {
        ExerciseProfile(name: name, keywords: keywords, muscles: muscles, kind: kind, equipment: equipment,
                        category: category, repMin: reps.lowerBound, repMax: reps.upperBound, strengthRange: strength,
                        restSeconds: rest, increment: step, fatigue: fatigue, stretchFocus: stretch, substitutes: swaps)
    }

    public static let all: [ExerciseProfile] = chest + back + shoulders + arms + legs + core + more

    private static let chest: [ExerciseProfile] = [
        p("Barbell Bench Press", ["bench press", "barbell bench", "flat bench"], [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
          .compound, .barbell, .chest, reps: 6...10, strength: 3...6, rest: 180, step: 2.5, fatigue: 2,
          swaps: ["Dumbbell Bench Press", "Machine Chest Press"]),
        p("Incline Barbell Press", ["incline bench", "incline barbell"], [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
          .compound, .barbell, .chest, reps: 6...10, strength: 4...6, rest: 180, step: 2.5, fatigue: 2,
          swaps: ["Incline Dumbbell Press", "Incline Machine Press"]),
        p("Close-Grip Bench Press", ["close grip bench", "close-grip bench"], [.triceps: 1, .chest: 0.5, .frontDelts: 0.5],
          .compound, .barbell, .triceps, reps: 6...10, strength: 4...6, rest: 150, step: 2.5, fatigue: 2,
          swaps: ["Dips", "Machine Dip"]),
        p("Dumbbell Bench Press", ["dumbbell bench", "db bench", "dumbbell press", "db press", "flat dumbbell"],
          [.chest: 1, .triceps: 0.5, .frontDelts: 0.5], .compound, .dumbbell, .chest, reps: 8...12, rest: 150, step: 2, fatigue: 2,
          stretch: true, swaps: ["Barbell Bench Press", "Machine Chest Press"]),
        p("Incline Dumbbell Press", ["incline dumbbell", "incline db"], [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
          .compound, .dumbbell, .chest, reps: 8...12, rest: 150, step: 2, fatigue: 2, stretch: true,
          swaps: ["Incline Barbell Press", "Incline Machine Press"]),
        p("Machine Chest Press", ["chest press", "machine press", "seated press", "hammer strength press"],
          [.chest: 1, .triceps: 0.5, .frontDelts: 0.5], .compound, .machine, .chest, reps: 8...12, rest: 120, step: 2.5, fatigue: 1,
          swaps: ["Dumbbell Bench Press", "Barbell Bench Press"]),
        p("Incline Machine Press", ["incline machine", "incline chest press", "incline press"], [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
          .compound, .machine, .chest, reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Incline Dumbbell Press"]),
        p("Decline Press", ["decline"], [.chest: 1, .triceps: 0.5], .compound, .barbell, .chest, reps: 8...12, rest: 150, step: 2.5,
          fatigue: 2, swaps: ["Dips", "Machine Chest Press"]),
        p("Smith Machine Bench Press", ["smith bench", "smith machine bench", "smith press"], [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
          .compound, .machine, .chest, reps: 6...10, rest: 150, step: 2.5, fatigue: 2, swaps: ["Barbell Bench Press"]),
        p("Cable Fly", ["cable fly", "cable flye", "cable crossover", "crossover", "low to high", "high to low"], [.chest: 1],
          .isolation, .cable, .chest, reps: 10...15, rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Pec Deck", "Dumbbell Fly"]),
        p("Pec Deck", ["pec deck", "pec fly", "machine fly", "butterfly"], [.chest: 1], .isolation, .machine, .chest,
          reps: 10...15, rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Cable Fly", "Dumbbell Fly"]),
        p("Dumbbell Fly", ["dumbbell fly", "db fly", "dumbbell flye"], [.chest: 1], .isolation, .dumbbell, .chest,
          reps: 10...15, rest: 90, step: 2, fatigue: 1, stretch: true, swaps: ["Cable Fly", "Pec Deck"]),
        p("Push-up", ["push up", "pushup", "push-up"], [.chest: 1, .triceps: 0.5, .frontDelts: 0.5], .compound, .bodyweight, .chest,
          reps: 10...25, rest: 90, step: 0, fatigue: 1, swaps: ["Machine Chest Press"]),
        p("Dips", ["dip"], [.chest: 1, .triceps: 1, .frontDelts: 0.5], .compound, .bodyweight, .chest,
          reps: 6...12, rest: 150, step: 2.5, fatigue: 2, stretch: true, swaps: ["Machine Dip", "Decline Press"]),
        p("Machine Dip", ["machine dip", "seated dip", "assisted dip"], [.triceps: 1, .chest: 0.5], .compound, .machine, .triceps,
          reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Dips"])
    ]

    private static let back: [ExerciseProfile] = [
        p("Deadlift", ["deadlift"], [.hamstrings: 1, .glutes: 1, .upperBack: 0.5, .quads: 0.5], .compound, .barbell, .back,
          reps: 4...8, strength: 2...5, rest: 210, step: 5, fatigue: 3, swaps: ["Romanian Deadlift", "Trap Bar Deadlift"]),
        p("Trap Bar Deadlift", ["trap bar", "hex bar", "trap bar deadlift", "hex bar deadlift"], [.quads: 1, .glutes: 1, .hamstrings: 0.5, .upperBack: 0.5],
          .compound, .barbell, .legs, reps: 4...8, strength: 3...5, rest: 210, step: 5, fatigue: 3, swaps: ["Deadlift", "Back Squat"]),
        p("Barbell Row", ["barbell row", "bent over row", "bent-over row", "pendlay"], [.upperBack: 1, .lats: 1, .biceps: 0.5, .rearDelts: 0.5],
          .compound, .barbell, .back, reps: 6...10, strength: 4...6, rest: 150, step: 2.5, fatigue: 2,
          swaps: ["Chest-Supported Row", "Seated Cable Row"]),
        p("Dumbbell Row", ["dumbbell row", "db row", "one arm row", "single arm row", "kroc"], [.lats: 1, .upperBack: 1, .biceps: 0.5],
          .compound, .dumbbell, .back, reps: 8...12, rest: 120, step: 2, fatigue: 1, stretch: true, swaps: ["Seated Cable Row"]),
        p("Seated Cable Row", ["seated row", "cable row", "seated cable row", "low row"], [.upperBack: 1, .lats: 1, .biceps: 0.5, .rearDelts: 0.5],
          .compound, .cable, .back, reps: 8...12, rest: 120, step: 2.5, fatigue: 1, stretch: true, swaps: ["Chest-Supported Row", "Machine Row"]),
        p("Chest-Supported Row", ["chest supported", "chest-supported", "t-bar", "t bar", "seal row", "incline row"],
          [.upperBack: 1, .lats: 0.5, .rearDelts: 0.5, .biceps: 0.5], .compound, .machine, .back, reps: 8...12, rest: 120, step: 2.5, fatigue: 1,
          swaps: ["Seated Cable Row", "Barbell Row"]),
        p("Machine Row", ["machine row", "hammer strength row", "iso row", "high row", "lateral row"], [.upperBack: 1, .lats: 1, .biceps: 0.5],
          .compound, .machine, .back, reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Seated Cable Row"]),
        p("Lat Pulldown", ["pulldown", "pull down", "pull-down", "lat pull"], [.lats: 1, .biceps: 0.5, .upperBack: 0.5],
          .compound, .cable, .back, reps: 8...12, rest: 120, step: 2.5, fatigue: 1, stretch: true, swaps: ["Pull-up", "Machine Pulldown"]),
        p("Machine Pulldown", ["machine pulldown", "iso pulldown"], [.lats: 1, .biceps: 0.5], .compound, .machine, .back,
          reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Lat Pulldown"]),
        p("Pull-up", ["pull up", "pull-up", "pullup", "chin up", "chin-up", "chinup"], [.lats: 1, .biceps: 0.5, .upperBack: 0.5],
          .compound, .bodyweight, .back, reps: 5...10, strength: 3...6, rest: 150, step: 2.5, fatigue: 2, stretch: true,
          swaps: ["Lat Pulldown", "Assisted Pull-up"]),
        p("Assisted Pull-up", ["assisted pull", "assisted chin"], [.lats: 1, .biceps: 0.5, .upperBack: 0.5],
          .compound, .machine, .back, reps: 6...10, rest: 120, step: 2.5, fatigue: 1, stretch: true, swaps: ["Lat Pulldown"]),
        p("Straight-Arm Pulldown", ["straight arm", "straight-arm", "pullover"], [.lats: 1], .isolation, .cable, .back,
          reps: 10...15, rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Lat Pulldown"]),
        p("Face Pull", ["face pull"], [.rearDelts: 1, .upperBack: 0.5], .isolation, .cable, .shoulders,
          reps: 12...20, rest: 75, step: 2.5, fatigue: 1, swaps: ["Reverse Pec Deck", "Rear Delt Fly"]),
        p("Shrug", ["shrug"], [.upperBack: 1], .isolation, .dumbbell, .back, reps: 10...15, rest: 90, step: 2, fatigue: 1,
          swaps: ["Barbell Row"]),
        p("Back Extension", ["back extension", "hyperextension", "45 degree"], [.glutes: 1, .hamstrings: 0.5],
          .isolation, .bodyweight, .legs, reps: 10...15, rest: 90, step: 2.5, fatigue: 1, swaps: ["Romanian Deadlift"])
    ]

    private static let shoulders: [ExerciseProfile] = [
        p("Overhead Press", ["overhead press", "military press", "ohp", "barbell shoulder press", "standing press"],
          [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5], .compound, .barbell, .shoulders, reps: 6...10, strength: 3...6,
          rest: 180, step: 2.5, fatigue: 2, swaps: ["Dumbbell Shoulder Press", "Machine Shoulder Press"]),
        p("Dumbbell Shoulder Press", ["dumbbell shoulder", "db shoulder", "db shoulder press", "dumbbell shoulder press", "seated dumbbell press", "arnold"],
          [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5], .compound, .dumbbell, .shoulders, reps: 8...12, rest: 150, step: 2, fatigue: 2,
          swaps: ["Machine Shoulder Press", "Overhead Press"]),
        p("Machine Shoulder Press", ["shoulder press", "machine shoulder"], [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5],
          .compound, .machine, .shoulders, reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Dumbbell Shoulder Press"]),
        p("Lateral Raise", ["lateral raise", "side raise", "lat raise", "lateral"], [.sideDelts: 1], .isolation, .dumbbell, .shoulders,
          reps: 12...20, rest: 75, step: 1, fatigue: 1, swaps: ["Cable Lateral Raise", "Machine Lateral Raise"]),
        p("Cable Lateral Raise", ["cable lateral", "cable lateral raise", "cable side raise", "y raise"], [.sideDelts: 1], .isolation, .cable, .shoulders,
          reps: 12...20, rest: 75, step: 1.25, fatigue: 1, stretch: true, swaps: ["Lateral Raise"]),
        p("Machine Lateral Raise", ["machine lateral", "lateral raise machine"], [.sideDelts: 1], .isolation, .machine, .shoulders,
          reps: 12...20, rest: 75, step: 2.5, fatigue: 1, swaps: ["Lateral Raise"]),
        p("Upright Row", ["upright row"], [.sideDelts: 1, .upperBack: 0.5], .compound, .cable, .shoulders, reps: 10...15,
          rest: 90, step: 2.5, fatigue: 1, swaps: ["Lateral Raise"]),
        p("Rear Delt Fly", ["rear delt", "reverse fly", "reverse flye", "bent over raise"], [.rearDelts: 1], .isolation, .dumbbell, .shoulders,
          reps: 12...20, rest: 75, step: 1, fatigue: 1, swaps: ["Reverse Pec Deck", "Face Pull"]),
        p("Reverse Pec Deck", ["reverse pec", "reverse machine fly", "rear delt machine"], [.rearDelts: 1], .isolation, .machine, .shoulders,
          reps: 12...20, rest: 75, step: 2.5, fatigue: 1, swaps: ["Rear Delt Fly", "Face Pull"]),
        p("Front Raise", ["front raise"], [.frontDelts: 1], .isolation, .dumbbell, .shoulders, reps: 10...15, rest: 75, step: 1,
          fatigue: 1, swaps: ["Overhead Press"])
    ]

    private static let arms: [ExerciseProfile] = [
        p("Barbell Curl", ["barbell curl", "ez bar curl", "ez-bar curl", "ez curl", "standing curl"], [.biceps: 1],
          .isolation, .barbell, .biceps, reps: 8...12, rest: 90, step: 2.5, fatigue: 1, swaps: ["Dumbbell Curl", "Cable Curl"]),
        p("Dumbbell Curl", ["dumbbell curl", "db curl", "alternating curl", "bicep curl", "biceps curl"], [.biceps: 1],
          .isolation, .dumbbell, .biceps, reps: 10...15, rest: 75, step: 1, fatigue: 1, swaps: ["Cable Curl", "Barbell Curl"]),
        p("Incline Dumbbell Curl", ["incline curl", "incline dumbbell curl"], [.biceps: 1], .isolation, .dumbbell, .biceps,
          reps: 10...15, rest: 75, step: 1, fatigue: 1, stretch: true, swaps: ["Cable Curl"]),
        p("Hammer Curl", ["hammer curl", "rope curl", "cross body curl"], [.biceps: 1], .isolation, .dumbbell, .biceps,
          reps: 10...15, rest: 75, step: 1, fatigue: 1, swaps: ["Dumbbell Curl"]),
        p("Preacher Curl", ["preacher", "scott curl", "machine curl"], [.biceps: 1], .isolation, .machine, .biceps,
          reps: 10...15, rest: 75, step: 2.5, fatigue: 1, stretch: true, swaps: ["Dumbbell Curl"]),
        p("Cable Curl", ["cable curl", "bayesian"], [.biceps: 1], .isolation, .cable, .biceps, reps: 10...15, rest: 75,
          step: 2.5, fatigue: 1, stretch: true, swaps: ["Dumbbell Curl"]),
        p("Triceps Pushdown", ["pushdown", "push down", "tricep pressdown", "rope pushdown"], [.triceps: 1], .isolation, .cable, .triceps,
          reps: 10...15, rest: 75, step: 2.5, fatigue: 1, swaps: ["Overhead Triceps Extension"]),
        p("Overhead Triceps Extension", ["overhead extension", "overhead tricep", "overhead triceps", "french press", "cable overhead"],
          [.triceps: 1], .isolation, .cable, .triceps, reps: 10...15, rest: 75, step: 2.5, fatigue: 1, stretch: true,
          swaps: ["Skull Crusher", "Triceps Pushdown"]),
        p("Skull Crusher", ["skull crusher", "skullcrusher", "lying tricep", "lying extension"], [.triceps: 1], .isolation, .barbell, .triceps,
          reps: 8...12, rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Overhead Triceps Extension"]),
        p("Triceps Kickback", ["kickback"], [.triceps: 1], .isolation, .dumbbell, .triceps, reps: 12...20, rest: 60, step: 1,
          fatigue: 1, swaps: ["Triceps Pushdown"]),
        p("Wrist Curl", ["wrist curl", "forearm"], [:], .isolation, .dumbbell, .other, reps: 12...20, rest: 60, step: 1, fatigue: 1)
    ]

    private static let legs: [ExerciseProfile] = [
        p("Back Squat", ["back squat", "barbell squat", "high bar", "low bar", "squat"], [.quads: 1, .glutes: 1, .hamstrings: 0.5, .abs: 0.5],
          .compound, .barbell, .legs, reps: 5...10, strength: 3...6, rest: 210, step: 2.5, fatigue: 3, stretch: true,
          swaps: ["Hack Squat", "Leg Press"]),
        p("Front Squat", ["front squat"], [.quads: 1, .glutes: 0.5, .abs: 0.5], .compound, .barbell, .legs, reps: 5...10, strength: 3...6,
          rest: 180, step: 2.5, fatigue: 3, stretch: true, swaps: ["Hack Squat"]),
        p("Hack Squat", ["hack squat", "hack"], [.quads: 1, .glutes: 0.5], .compound, .machine, .legs, reps: 6...12, rest: 180,
          step: 5, fatigue: 2, stretch: true, swaps: ["Leg Press", "Back Squat"]),
        p("Smith Squat", ["smith squat", "smith machine squat"], [.quads: 1, .glutes: 0.5], .compound, .machine, .legs,
          reps: 6...12, rest: 180, step: 2.5, fatigue: 2, swaps: ["Hack Squat"]),
        p("Leg Press", ["leg press"], [.quads: 1, .glutes: 0.5], .compound, .machine, .legs, reps: 8...15, rest: 150, step: 5,
          fatigue: 2, swaps: ["Hack Squat", "Back Squat"]),
        p("Pendulum Squat", ["pendulum", "belt squat", "v squat"], [.quads: 1, .glutes: 0.5], .compound, .machine, .legs,
          reps: 8...12, rest: 150, step: 5, fatigue: 2, stretch: true, swaps: ["Hack Squat"]),
        p("Bulgarian Split Squat", ["bulgarian", "split squat", "rear foot elevated"], [.quads: 1, .glutes: 1], .compound, .dumbbell, .legs,
          reps: 8...12, rest: 120, step: 2, fatigue: 2, stretch: true, swaps: ["Walking Lunge", "Leg Press"]),
        p("Walking Lunge", ["lunge", "step up", "step-up"], [.quads: 1, .glutes: 1], .compound, .dumbbell, .legs, reps: 8...12,
          rest: 120, step: 2, fatigue: 2, swaps: ["Bulgarian Split Squat"]),
        p("Leg Extension", ["leg extension", "quad extension"], [.quads: 1], .isolation, .machine, .legs, reps: 10...15, rest: 90,
          step: 2.5, fatigue: 1, swaps: ["Sissy Squat"]),
        p("Sissy Squat", ["sissy", "sissy squat"], [.quads: 1], .isolation, .bodyweight, .legs, reps: 10...20, rest: 90, step: 0, fatigue: 1,
          stretch: true, swaps: ["Leg Extension"]),
        p("Romanian Deadlift", ["romanian", "romanian deadlift", "rdl", "stiff leg", "stiff-leg", "stiff leg deadlift", "sldl"], [.hamstrings: 1, .glutes: 1, .upperBack: 0.5],
          .compound, .barbell, .legs, reps: 6...10, rest: 180, step: 2.5, fatigue: 2, stretch: true, swaps: ["Seated Leg Curl", "Good Morning"]),
        p("Good Morning", ["good morning"], [.hamstrings: 1, .glutes: 0.5], .compound, .barbell, .legs, reps: 8...12, rest: 150,
          step: 2.5, fatigue: 2, stretch: true, swaps: ["Romanian Deadlift"]),
        p("Seated Leg Curl", ["seated leg curl", "seated hamstring"], [.hamstrings: 1], .isolation, .machine, .legs, reps: 10...15,
          rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Lying Leg Curl"]),
        p("Lying Leg Curl", ["lying leg curl", "leg curl", "hamstring curl", "nordic"], [.hamstrings: 1], .isolation, .machine, .legs,
          reps: 10...15, rest: 90, step: 2.5, fatigue: 1, swaps: ["Seated Leg Curl"]),
        p("Hip Thrust", ["hip thrust", "glute bridge", "glute drive"], [.glutes: 1, .hamstrings: 0.5], .compound, .barbell, .legs,
          reps: 8...12, rest: 120, step: 5, fatigue: 2, swaps: ["Glute Kickback", "Back Extension"]),
        p("Glute Kickback", ["kickback machine", "glute kickback", "cable kickback"], [.glutes: 1], .isolation, .cable, .legs,
          reps: 12...15, rest: 75, step: 2.5, fatigue: 1, swaps: ["Hip Thrust"]),
        p("Hip Abduction", ["abduction", "abductor"], [.glutes: 1], .isolation, .machine, .legs, reps: 12...20, rest: 75,
          step: 2.5, fatigue: 1, swaps: ["Glute Kickback"]),
        p("Hip Adduction", ["adduction", "adductor"], [:], .isolation, .machine, .legs, reps: 12...20, rest: 75, step: 2.5, fatigue: 1),
        p("Standing Calf Raise", ["standing calf", "calf raise", "smith calf", "leg press calf", "donkey calf"], [.calves: 1],
          .isolation, .machine, .calves, reps: 10...20, rest: 75, step: 5, fatigue: 1, stretch: true, swaps: ["Seated Calf Raise"]),
        p("Seated Calf Raise", ["seated calf"], [.calves: 1], .isolation, .machine, .calves, reps: 12...20, rest: 60, step: 2.5,
          fatigue: 1, swaps: ["Standing Calf Raise"])
    ]

    private static let core: [ExerciseProfile] = [
        p("Cable Crunch", ["cable crunch", "kneeling crunch", "rope crunch"], [.abs: 1], .isolation, .cable, .core, reps: 10...20,
          rest: 60, step: 2.5, fatigue: 1, swaps: ["Hanging Leg Raise"]),
        p("Hanging Leg Raise", ["hanging leg", "leg raise", "knee raise", "captain"], [.abs: 1], .isolation, .bodyweight, .core,
          reps: 10...20, rest: 60, step: 0, fatigue: 1, swaps: ["Cable Crunch"]),
        p("Crunch", ["crunch", "sit up", "sit-up", "ab machine", "ab crunch"], [.abs: 1], .isolation, .machine, .core, reps: 12...20,
          rest: 60, step: 2.5, fatigue: 1, swaps: ["Cable Crunch"]),
        p("Plank", ["plank", "dead bug", "pallof", "ab wheel", "rollout"], [.abs: 1], .isolation, .bodyweight, .core, reps: 30...60,
          rest: 60, step: 0, fatigue: 1, swaps: ["Cable Crunch"])
    ]

    private static let more: [ExerciseProfile] = [
        p("Incline Smith Press", ["incline smith", "smith incline"], [.chest: 1, .frontDelts: 0.5, .triceps: 0.5], .compound, .machine, .chest,
          reps: 6...10, rest: 150, step: 2.5, fatigue: 2, swaps: ["Incline Dumbbell Press"]),
        p("Landmine Press", ["landmine press", "landmine"], [.frontDelts: 1, .chest: 0.5, .triceps: 0.5], .compound, .barbell, .shoulders,
          reps: 8...12, rest: 120, step: 2.5, fatigue: 1, swaps: ["Dumbbell Shoulder Press"]),
        p("Cable Chest Press", ["cable chest press", "cable press"], [.chest: 1, .triceps: 0.5], .compound, .cable, .chest,
          reps: 10...15, rest: 90, step: 2.5, fatigue: 1, swaps: ["Machine Chest Press"]),
        p("Meadows Row", ["meadows", "landmine row"], [.lats: 1, .upperBack: 1, .biceps: 0.5], .compound, .barbell, .back,
          reps: 8...12, rest: 120, step: 2.5, fatigue: 1, stretch: true, swaps: ["Dumbbell Row"]),
        p("Rack Pull", ["rack pull", "block pull"], [.upperBack: 1, .glutes: 0.5, .hamstrings: 0.5], .compound, .barbell, .back,
          reps: 4...8, rest: 180, step: 5, fatigue: 3, swaps: ["Barbell Row"]),
        p("Inverted Row", ["inverted row", "australian pull", "body row"], [.upperBack: 1, .lats: 0.5, .biceps: 0.5],
          .compound, .bodyweight, .back, reps: 8...15, rest: 90, step: 0, fatigue: 1, swaps: ["Seated Cable Row"]),
        p("Single-Arm Cable Row", ["single arm cable", "one arm cable", "single-arm cable"], [.lats: 1, .upperBack: 0.5, .biceps: 0.5],
          .compound, .cable, .back, reps: 10...15, rest: 90, step: 2.5, fatigue: 1, stretch: true, swaps: ["Dumbbell Row"]),
        p("Cable Rear Delt Fly", ["cable rear delt", "cable reverse fly", "reverse cable"], [.rearDelts: 1], .isolation, .cable, .shoulders,
          reps: 12...20, rest: 60, step: 1.25, fatigue: 1, swaps: ["Reverse Pec Deck"]),
        p("Behind-the-Neck Press", ["behind the neck", "behind-the-neck", "btn press"], [.frontDelts: 1, .sideDelts: 1, .triceps: 0.5],
          .compound, .barbell, .shoulders, reps: 6...10, rest: 150, step: 2.5, fatigue: 2, swaps: ["Overhead Press"]),
        p("Lu Raise", ["lu raise", "lu raises"], [.sideDelts: 1, .frontDelts: 0.5], .isolation, .dumbbell, .shoulders,
          reps: 10...15, rest: 75, step: 1, fatigue: 1, swaps: ["Lateral Raise"]),
        p("Concentration Curl", ["concentration curl"], [.biceps: 1], .isolation, .dumbbell, .biceps, reps: 10...15, rest: 60,
          step: 1, fatigue: 1, swaps: ["Preacher Curl"]),
        p("Spider Curl", ["spider curl"], [.biceps: 1], .isolation, .dumbbell, .biceps, reps: 10...15, rest: 60, step: 1, fatigue: 1,
          swaps: ["Preacher Curl"]),
        p("Reverse Curl", ["reverse curl", "reverse grip curl"], [.biceps: 0.5], .isolation, .barbell, .biceps, reps: 10...15,
          rest: 60, step: 2.5, fatigue: 1, swaps: ["Hammer Curl"]),
        p("JM Press", ["jm press"], [.triceps: 1, .chest: 0.5], .compound, .barbell, .triceps, reps: 8...12, rest: 120, step: 2.5,
          fatigue: 1, swaps: ["Close-Grip Bench Press"]),
        p("Dumbbell Overhead Extension", ["dumbbell overhead extension", "db overhead extension", "seated tricep extension", "single arm overhead"],
          [.triceps: 1], .isolation, .dumbbell, .triceps, reps: 10...15, rest: 75, step: 1, fatigue: 1, stretch: true,
          swaps: ["Overhead Triceps Extension"]),
        p("Diamond Push-up", ["diamond push", "close grip push", "close-grip push"], [.triceps: 1, .chest: 0.5], .compound, .bodyweight, .triceps,
          reps: 8...20, rest: 75, step: 0, fatigue: 1, swaps: ["Triceps Pushdown"]),
        p("Goblet Squat", ["goblet"], [.quads: 1, .glutes: 0.5], .compound, .dumbbell, .legs, reps: 8...15, rest: 120, step: 2,
          fatigue: 2, swaps: ["Leg Press"]),
        p("Sumo Deadlift", ["sumo", "sumo deadlift"], [.glutes: 1, .quads: 0.5, .hamstrings: 0.5, .upperBack: 0.5], .compound, .barbell, .legs,
          reps: 4...8, strength: 2...5, rest: 210, step: 5, fatigue: 3, swaps: ["Deadlift"]),
        p("Box Squat", ["box squat", "safety bar", "ssb"], [.quads: 1, .glutes: 1, .hamstrings: 0.5], .compound, .barbell, .legs,
          reps: 5...10, rest: 180, step: 2.5, fatigue: 3, swaps: ["Back Squat"]),
        p("Single-Leg Press", ["single leg press", "single-leg press", "one leg press"], [.quads: 1, .glutes: 0.5], .compound, .machine, .legs,
          reps: 10...15, rest: 90, step: 2.5, fatigue: 1, swaps: ["Leg Press"]),
        p("Glute-Ham Raise", ["glute ham", "glute-ham", "ghr"], [.hamstrings: 1, .glutes: 0.5], .isolation, .bodyweight, .legs,
          reps: 6...12, rest: 120, step: 0, fatigue: 2, swaps: ["Lying Leg Curl"]),
        p("Reverse Hyper", ["reverse hyper"], [.glutes: 1, .hamstrings: 0.5], .isolation, .machine, .legs, reps: 12...15,
          rest: 75, step: 2.5, fatigue: 1, swaps: ["Back Extension"]),
        p("Tibialis Raise", ["tibialis", "tib raise"], [:], .isolation, .bodyweight, .legs, reps: 15...25, rest: 60, step: 0, fatigue: 1),
        p("Cable Pull-Through", ["pull through", "pull-through"], [.glutes: 1, .hamstrings: 0.5], .compound, .cable, .legs,
          reps: 12...15, rest: 75, step: 2.5, fatigue: 1, swaps: ["Hip Thrust"]),
        p("Russian Twist", ["russian twist", "woodchop", "wood chop", "side plank", "oblique"], [.abs: 1], .isolation, .bodyweight, .core,
          reps: 12...20, rest: 60, step: 0, fatigue: 1, swaps: ["Cable Crunch"]),
        p("Decline Sit-up", ["decline sit", "decline crunch"], [.abs: 1], .isolation, .bodyweight, .core, reps: 10...20,
          rest: 60, step: 0, fatigue: 1, swaps: ["Cable Crunch"])
    ]
    // swiftlint:enable function_body_length

    // MARK: Matching

    /// "Incline DB Press (Hammer Strength)" → "incline db press".
    static func normalize(_ name: String) -> String {
        var text = name.lowercased()
        if let open = text.firstIndex(of: "(") { text = String(text[..<open]) }
        text = text.replacingOccurrences(of: "_", with: " ")
        return " " + text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") + " "
    }

    /// Best match for one of your exercise names (longest keyword wins), or nil if unknown.
    public static func profile(for name: String) -> ExerciseProfile? {
        let text = normalize(name)
        var best: (profile: ExerciseProfile, length: Int)?
        for profile in all {
            for keyword in profile.keywords where text.contains(keyword) || text.contains(keyword.replacingOccurrences(of: "-", with: " ")) {
                if keyword.count > (best?.length ?? 0) { best = (profile, keyword.count) }
            }
        }
        return best?.profile
    }

    public static func profile(named exact: String) -> ExerciseProfile? {
        all.first { $0.name == exact }
    }

    /// Muscle contributions for an exercise name (falls back to its category when it isn't in the library).
    public static func muscles(for name: String, category: ExerciseCategory?) -> [Muscle: Double] {
        if let profile = profile(for: name), !profile.muscles.isEmpty { return profile.muscles }
        switch category ?? ExerciseCategory.guess(from: name) {
        case .chest: return [.chest: 1]
        case .back: return [.lats: 1, .upperBack: 1]
        case .shoulders: return [.sideDelts: 1]
        case .biceps: return [.biceps: 1]
        case .triceps: return [.triceps: 1]
        case .legs: return [.quads: 1, .glutes: 0.5]
        case .calves: return [.calves: 1]
        case .core: return [.abs: 1]
        case .cardio, .other: return [:]
        }
    }

    /// Library defaults for a new exercise (rep range, rest, step), when the name is recognised.
    public static func apply(defaultsTo exercise: inout ExerciseDefinition) {
        guard let profile = profile(for: exercise.name) else { return }
        exercise.category = profile.category
        exercise.repMin = profile.repMin
        exercise.repMax = profile.repMax
        exercise.restSeconds = profile.restSeconds
        exercise.weightIncrementKg = profile.increment
    }
}
