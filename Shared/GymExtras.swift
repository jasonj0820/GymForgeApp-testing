import Foundation

/// Things tracked alongside workouts: rest days, pain flags, nutrition and tape measurements.
/// Stored in the iPhone snapshot (not sent to the Watch). Every field decodes as optional so
/// older backups still load.
public struct GymExtras: Codable, Equatable {
    public var restDays: [Date]
    public var painFlags: [PainFlag]
    public var nutrition: [NutritionDay]
    public var tape: [TapeEntry]
    public var nutritionPhase: NutritionPhase?
    /// Bulk / recomp / cut history (the last one without an end is the current phase).
    public var phases: [PhaseRecord]
    /// Mini-cut prompt when the 4-week body-fat average goes above this (%).
    public var miniCutThreshold: Double?
    /// Planned workouts, sick and travel days (rest days stay in `restDays`).
    public var dayPlans: [DayPlan]
    /// Coaching suggestions you accepted (followed up in the weekly review).
    public var suggestions: [CoachSuggestion]
    /// Muscles you want to bring up (the weekly review checks they got extra work).
    public var priorityMuscles: [ExerciseCategory]
    /// Coach suggestions you said "not now" to (hidden for 4 weeks), by suggestion id.
    public var declinedProposals: [String: Date]
    /// MK10: rest days planned ahead (the day before or earlier) — Sergeant Cluck is chill on these.
    public var plannedRestDays: [Date]
    /// MK11.3: "Give me a break" history (the newest may be running).
    public var breaks: [GymBreak]
    /// MK20.2: weight and body fat you typed in (the Sunday weigh-in), merged with Apple Health.
    public var weighIns: [WeighIn]

    public init(restDays: [Date] = [], painFlags: [PainFlag] = [], nutrition: [NutritionDay] = [],
                tape: [TapeEntry] = [], nutritionPhase: NutritionPhase? = nil, phases: [PhaseRecord] = [],
                miniCutThreshold: Double? = nil) {
        self.restDays = restDays
        self.painFlags = painFlags
        self.nutrition = nutrition
        self.tape = tape
        self.nutritionPhase = nutritionPhase
        self.phases = phases
        self.miniCutThreshold = miniCutThreshold
        self.dayPlans = []
        self.suggestions = []
        self.priorityMuscles = []
        self.declinedProposals = [:]
        self.plannedRestDays = []
        self.breaks = []
        self.weighIns = []
    }

    enum CodingKeys: String, CodingKey {
        case restDays, painFlags, nutrition, tape, nutritionPhase, phases, miniCutThreshold
        case dayPlans, suggestions, priorityMuscles, declinedProposals, plannedRestDays, breaks, weighIns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        restDays = try c.decodeIfPresent([Date].self, forKey: .restDays) ?? []
        painFlags = try c.decodeIfPresent([PainFlag].self, forKey: .painFlags) ?? []
        nutrition = try c.decodeIfPresent([NutritionDay].self, forKey: .nutrition) ?? []
        tape = try c.decodeIfPresent([TapeEntry].self, forKey: .tape) ?? []
        nutritionPhase = try c.decodeIfPresent(NutritionPhase.self, forKey: .nutritionPhase)
        phases = try c.decodeIfPresent([PhaseRecord].self, forKey: .phases) ?? []
        miniCutThreshold = try c.decodeIfPresent(Double.self, forKey: .miniCutThreshold)
        dayPlans = try c.decodeIfPresent([DayPlan].self, forKey: .dayPlans) ?? []
        suggestions = try c.decodeIfPresent([CoachSuggestion].self, forKey: .suggestions) ?? []
        priorityMuscles = try c.decodeIfPresent([ExerciseCategory].self, forKey: .priorityMuscles) ?? []
        declinedProposals = try c.decodeIfPresent([String: Date].self, forKey: .declinedProposals) ?? [:]
        plannedRestDays = try c.decodeIfPresent([Date].self, forKey: .plannedRestDays) ?? []
        breaks = try c.decodeIfPresent([GymBreak].self, forKey: .breaks) ?? []
        weighIns = try c.decodeIfPresent([WeighIn].self, forKey: .weighIns) ?? []
    }

    /// MK20.2: the weigh-in logged on the same day as `date`, if any.
    public func weighIn(on date: Date, calendar: Calendar = .current) -> WeighIn? {
        weighIns.last { calendar.isDate($0.date, inSameDayAs: date) }
    }

    public var currentPhaseRecord: PhaseRecord? { phases.last(where: { $0.end == nil }) }

    public func isRestDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        restDays.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    /// A rest day you planned ahead (not one declared on the day).
    public func isPlannedRestDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        isRestDay(date, calendar: calendar) && plannedRestDays.contains { calendar.isDate($0, inSameDayAs: date) }
    }

    public func nutrition(on date: Date, calendar: Calendar = .current) -> NutritionDay? {
        nutrition.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// Unresolved pain flags for an exercise (by name, so swaps and routines share them).
    public func activePainFlags(for exercise: ExerciseDefinition) -> [PainFlag] {
        // Also matches flags saved before a machine name was added to the exercise.
        painFlags.filter { !$0.resolved && ($0.exerciseKey == exercise.historyKey || $0.exerciseKey == ExerciseLog.key(for: exercise.name)) }
    }
}

// MARK: - Pain flags

public enum PainArea: String, Codable, CaseIterable, Identifiable {
    case shoulder, elbow, wrist, neck, upperBack, lowerBack, hip, knee, ankle, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .shoulder: return "Shoulder"
        case .elbow: return "Elbow"
        case .wrist: return "Wrist"
        case .neck: return "Neck"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .hip: return "Hip"
        case .knee: return "Knee"
        case .ankle: return "Ankle"
        case .other: return "Other"
        }
    }
}

public struct PainFlag: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var exerciseKey: String
    public var exerciseName: String
    public var area: PainArea
    /// 1 = niggle, 2 = sore, 3 = sharp / had to stop.
    public var severity: Int
    public var note: String?
    public var resolved: Bool

    public init(id: UUID = UUID(), date: Date = .now, exercise: ExerciseDefinition, area: PainArea,
                severity: Int, note: String? = nil) {
        self.id = id
        self.date = date
        self.exerciseKey = exercise.historyKey
        self.exerciseName = exercise.name
        self.area = area
        self.severity = severity
        self.note = note
        self.resolved = false
    }

    public var severityText: String {
        switch severity {
        case 3: return "sharp"
        case 2: return "sore"
        default: return "niggle"
        }
    }

    /// What to do next time this exercise comes up.
    public func advice(swap: String?) -> String {
        switch severity {
        case 3:
            return swap.map { "Sharp \(area.title.lowercased()) pain last time — swap to \($0) today, or skip it." }
                ?? "Sharp \(area.title.lowercased()) pain last time — skip it today or go very light. See a physio if it persists."
        case 2:
            return "Sore \(area.title.lowercased()) last time — go ~20% lighter and stop if it hurts." + (swap.map { " Or try \($0)." } ?? "")
        default:
            return "\(area.title) niggle last time — warm up well and keep the reps smooth."
        }
    }
}

// MARK: - Nutrition

public enum NutritionPhase: String, Codable, CaseIterable, Identifiable {
    case cutting, recomp, bulking
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cutting: return "Cutting"
        case .recomp: return "Recomp"
        case .bulking: return "Bulking"
        }
    }
    /// Protein per kg of body weight.
    public var gramsPerKg: Double {
        switch self {
        case .cutting, .recomp: return 2.2
        case .bulking: return 1.6
        }
    }

    public static func from(goal: TrainingGoal) -> NutritionPhase {
        switch goal {
        case .loseFat: return .cutting
        case .recomposition, .maintain: return .recomp
        case .buildMuscle, .getStronger: return .bulking
        }
    }
}

public struct NutritionDay: Codable, Equatable {
    public var day: Date
    public var creatine: Bool
    public var proteinG: Double
    /// MK10.2: calories eaten (nil = not logged that day).
    public var calories: Double?

    public init(day: Date, creatine: Bool = false, proteinG: Double = 0, calories: Double? = nil) {
        self.day = day
        self.creatine = creatine
        self.proteinG = proteinG
        self.calories = calories
    }
}

/// One bulk / recomp / cut block.
public struct PhaseRecord: Identifiable, Codable, Equatable {
    public var id: UUID
    public var phase: NutritionPhase
    public var start: Date
    public var end: Date?
    /// Mini-cut: a short cut with a planned end, then back to bulking.
    public var isMiniCut: Bool
    public var plannedEnd: Date?

    public init(id: UUID = UUID(), phase: NutritionPhase, start: Date, end: Date? = nil,
                isMiniCut: Bool = false, plannedEnd: Date? = nil) {
        self.id = id
        self.phase = phase
        self.start = start
        self.end = end
        self.isMiniCut = isMiniCut
        self.plannedEnd = plannedEnd
    }

    public var title: String { isMiniCut ? "Mini-cut" : phase.title }
}

extension NutritionPhase {
    /// The training goal the coach uses for this phase.
    public var trainingGoal: TrainingGoal {
        switch self {
        case .cutting: return .loseFat
        case .recomp: return .recomposition
        case .bulking: return .buildMuscle
        }
    }
}

// MARK: - Tape measurements

public enum TapeSite: String, Codable, CaseIterable, Identifiable {
    case neck, chest, shoulders, arm, forearm, waist, hips, thigh, calf
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .neck: return "Neck"
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .arm: return "Arm (flexed)"
        case .forearm: return "Forearm"
        case .waist: return "Waist (navel)"
        case .hips: return "Hips"
        case .thigh: return "Thigh"
        case .calf: return "Calf"
        }
    }
}

/// MK20.2: a weigh-in you typed in yourself — weight (kg), body fat (%), or both.
public struct WeighIn: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    public var weightKg: Double?
    public var bodyFatPercent: Double?

    public init(id: UUID = UUID(), date: Date = .now, weightKg: Double?, bodyFatPercent: Double?) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
    }

    public var points: [BodyMetricPoint] {
        [weightKg.map { BodyMetricPoint(id: id, metric: .bodyWeight, date: date, value: $0) },
         bodyFatPercent.map { BodyMetricPoint(metric: .bodyFatPercentage, date: date, value: $0) }].compactMap { $0 }
    }

    /// The Sunday this weigh-in is for: today if it's Sunday, otherwise the most recent Sunday.
    public static func sunday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - 1 + 7) % 7   // weekday 1 = Sunday
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }
}

public struct TapeEntry: Identifiable, Codable, Equatable {
    public var id: UUID
    public var date: Date
    /// Centimetres by TapeSite raw value.
    public var values: [String: Double]

    public init(id: UUID = UUID(), date: Date = .now, values: [String: Double]) {
        self.id = id
        self.date = date
        self.values = values
    }

    public func value(_ site: TapeSite) -> Double? { values[site.rawValue] }
}

/// MK14: Sergeant Cluck chases your protein. Each checkpoint expects a share of the day's target by then;
/// a nag is scheduled only while you're behind it, and logging protein reschedules them all.
public enum ProteinNag {
    public struct Checkpoint: Equatable {
        public let hour: Int
        public let minute: Int
        /// Share of the target that should be eaten by this time.
        public let share: Double
    }

    public static let checkpoints = [Checkpoint(hour: 12, minute: 0, share: 0.35),
                                     Checkpoint(hour: 16, minute: 0, share: 0.6),
                                     Checkpoint(hour: 19, minute: 30, share: 0.85)]

    /// Checkpoints you'd miss at the current intake.
    public static func behind(eaten: Double, target: Double) -> [Checkpoint] {
        guard target > 0 else { return [] }
        return checkpoints.filter { eaten < target * $0.share }
    }

    public static func message(eaten: Double, target: Double, at checkpoint: Checkpoint) -> (title: String, body: String) {
        let left = Int((target - eaten).rounded())
        let should = Int((target * checkpoint.share).rounded())
        if checkpoint == checkpoints.last {
            return ("🪖 PROTEIN: \(left) g SHORT", "\(Int(eaten)) of \(Int(target)) g and the kitchen closes soon. Shake, yoghurt, chicken — now.")
        }
        if eaten <= 0 {
            return ("🪖 No protein logged", "Target \(Int(target)) g. You should be at \(should) g by now, recruit.")
        }
        return ("🪖 Protein behind", "\(Int(eaten)) g so far — should be \(should) g by now. \(left) g to go.")
    }
}

/// MK15: the recap you get when you go to bed: what you hit today and what to do tomorrow.
public enum DailyRecap {
    public struct Recap: Equatable {
        public let title: String
        public let lines: [String]
        public let advice: [String]
        public var text: String { (lines + [""] + advice.map { "→ " + $0 }).joined(separator: "\n") }
    }

    public static func make(proteinG: Double, target: Double?, creatine: Bool, trained: Bool,
                            stepsDone: Int, stepsTotal: Int, gymTomorrow: String?) -> Recap {
        var lines: [String] = []
        var advice: [String] = []
        var hits = 0, goals = 2

        if let target, target > 0 {
            let pct = Int((proteinG / target * 100).rounded())
            lines.append("Protein \(Int(proteinG)) / \(Int(target)) g (\(pct)%)")
            if proteinG >= target * 0.95 {
                hits += 1
                advice.append("Protein on target. Keep it boring and repeat it tomorrow.")
            } else {
                let short = Int((target - proteinG).rounded())
                advice.append("\(short) g short. Tomorrow: protein at breakfast (eggs or Greek yoghurt) and a shake \(gymTomorrow == nil ? "with lunch" : "after training").")
            }
        } else {
            goals -= 1
            lines.append("Protein \(Int(proteinG)) g (no target yet)")
            advice.append("Log your weight in Apple Health to get a protein target.")
        }

        lines.append(creatine ? "Creatine ✓" : "Creatine ✗")
        if creatine { hits += 1 } else { advice.append("Creatine missed: take 5 g with breakfast. Every day matters more than timing.") }

        lines.append(trained ? "Trained today ✓" : "Rest day")

        if stepsTotal > 0 {
            goals += 1
            lines.append("Dayfold \(stepsDone) / \(stepsTotal) steps")
            if stepsDone >= stepsTotal { hits += 1 } else { advice.append("\(stepsTotal - stepsDone) Dayfold step\(stepsTotal - stepsDone == 1 ? "" : "s") left. They're back on tomorrow's list.") }
        }

        if let gymTomorrow { advice.append("\(gymTomorrow) tomorrow. Bag packed, lights out on time.") }

        let title = hits == goals ? "🪖 Day recap: everything on target" : "🪖 Day recap: \(hits) of \(goals) on target"
        return Recap(title: title, lines: lines, advice: Array(advice.prefix(3)))
    }
}

/// MK16: Sunday's meal-prep step, sized from your protein target (5 weekday lunches at ~30% of the day each).
public enum MealPrep {
    public static let lunches = 5
    public static func title(target: Double?) -> String {
        guard let target, target > 0 else { return "Meal prep · \(lunches) protein lunches" }
        let grams = Int((target * 0.3 / 5).rounded()) * 5
        return "Meal prep · \(lunches) lunches × \(grams) g protein"
    }
}
