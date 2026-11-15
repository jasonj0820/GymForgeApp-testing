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
    /// MK21: nights logged with "Going to sleep" / "I'm awake" that Apple Health couldn't take (no Health
    /// access on this install), kept here so sleep and the recovery score still work.
    public var manualSleep: [DateInterval]
    /// MK24: the 10-second "how do you feel" check-in (one per day).
    public var checkIns: [ReadinessCheckIn]
    /// MK24: quick notes from Today's + button.
    public var dayNotes: [DayNote]
    /// MK24: lift goals, exercise history key → target estimated one-rep max (kg).
    public var liftGoals: [String: Double]
    /// MK24: weeks marked busy (exams, a heavy work week): Monday of the week → sessions taken off the goal.
    public var busyWeeks: [BusyWeek]
    /// MK24 (G): what you ate, saved meals, the recipe book and this week's meal prep.
    public var foodLog: [FoodEntry]
    public var savedMeals: [SavedMeal]
    public var recipes: [Recipe]
    public var prepPlan: [PrepItem]
    /// Day ("yyyy-MM-dd") → millilitres of water.
    public var water: [String: Int]
    public var caffeine: [CaffeineEntry]
    public var dayTags: [DayTag]
    public var goalWeight: GoalWeight?
    /// MK24 (I): shot charts, drills, jumps and game stats.
    public var hoops: Hoops

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
        self.manualSleep = []
        self.checkIns = []
        self.dayNotes = []
        self.liftGoals = [:]
        self.busyWeeks = []
        self.foodLog = []
        self.savedMeals = []
        self.recipes = []
        self.prepPlan = []
        self.water = [:]
        self.caffeine = []
        self.dayTags = []
        self.goalWeight = nil
        self.hoops = Hoops()
    }

    enum CodingKeys: String, CodingKey {
        case restDays, painFlags, nutrition, tape, nutritionPhase, phases, miniCutThreshold
        case dayPlans, suggestions, priorityMuscles, declinedProposals, plannedRestDays, breaks, weighIns, manualSleep
        case checkIns, dayNotes, liftGoals, busyWeeks
        case foodLog, savedMeals, recipes, prepPlan, water, caffeine, dayTags, goalWeight, hoops
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
        manualSleep = try c.decodeIfPresent([DateInterval].self, forKey: .manualSleep) ?? []
        checkIns = try c.decodeIfPresent([ReadinessCheckIn].self, forKey: .checkIns) ?? []
        dayNotes = try c.decodeIfPresent([DayNote].self, forKey: .dayNotes) ?? []
        liftGoals = try c.decodeIfPresent([String: Double].self, forKey: .liftGoals) ?? [:]
        busyWeeks = try c.decodeIfPresent([BusyWeek].self, forKey: .busyWeeks) ?? []
        foodLog = try c.decodeIfPresent([FoodEntry].self, forKey: .foodLog) ?? []
        savedMeals = try c.decodeIfPresent([SavedMeal].self, forKey: .savedMeals) ?? []
        recipes = try c.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        prepPlan = try c.decodeIfPresent([PrepItem].self, forKey: .prepPlan) ?? []
        water = try c.decodeIfPresent([String: Int].self, forKey: .water) ?? [:]
        caffeine = try c.decodeIfPresent([CaffeineEntry].self, forKey: .caffeine) ?? []
        dayTags = try c.decodeIfPresent([DayTag].self, forKey: .dayTags) ?? []
        goalWeight = try c.decodeIfPresent(GoalWeight.self, forKey: .goalWeight)
        hoops = try c.decodeIfPresent(Hoops.self, forKey: .hoops) ?? Hoops()
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

    /// The weigh-in day this is for: today if it's the weigh-in day (Sunday unless changed, MK24), otherwise the most recent one.
    public static func sunday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - weekday + 7) % 7   // weekday 1 = Sunday
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

    /// 12:00, 16:00 and 19:30 unless changed (MK24: Settings → Notifications).
    public static var checkpoints: [Checkpoint] {
        zip(NotificationTimes.proteinTimes, [0.35, 0.6, 0.85]).map { Checkpoint(hour: $0.0.hour, minute: $0.0.minute, share: $0.1) }
    }

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
            advice.append("Log your weight on the Body tab to get a protein target.")
        }

        lines.append(creatine ? "Creatine ✓" : "Creatine ✗")
        if creatine { hits += 1 } else { advice.append("Creatine missed: take 5 g with breakfast. Every day matters more than timing.") }

        lines.append(trained ? "Trained today ✓" : "Rest day")

        if stepsTotal > 0 {
            goals += 1
            lines.append("Routine \(stepsDone) / \(stepsTotal) steps")
            if stepsDone >= stepsTotal { hits += 1 } else { advice.append("\(stepsTotal - stepsDone) routine step\(stepsTotal - stepsDone == 1 ? "" : "s") left. They're back on tomorrow's list.") }
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


// MARK: - MK24

/// "How do you feel?" in three taps, for days without sleep or heart-rate data.
public struct ReadinessCheckIn: Codable, Equatable {
    public var date: Date
    public var sleepHours: Double
    /// 1 = fresh, 2 = a bit sore, 3 = very sore.
    public var soreness: Int
    /// 1 = low, 2 = normal, 3 = high.
    public var energy: Int

    public init(date: Date, sleepHours: Double, soreness: Int, energy: Int) {
        self.date = date
        self.sleepHours = sleepHours
        self.soreness = soreness
        self.energy = energy
    }

    /// Same scale as the Health-based score: 75+ ready, 55+ moderate, below that take it easier.
    public var readiness: Readiness {
        var score = 100
        var reasons: [String] = []
        let text = String(format: "%.1f h", sleepHours)
        if sleepHours < 5 { score -= 35; reasons.append("Only \(text) sleep") }
        else if sleepHours < 6 { score -= 20; reasons.append("Short sleep (\(text))") }
        else if sleepHours < 7 { score -= 8; reasons.append("Slightly short sleep (\(text))") }
        else { reasons.append("Good sleep (\(text))") }
        switch soreness {
        case 3: score -= 25; reasons.append("Very sore")
        case 2: score -= 10; reasons.append("A bit sore")
        default: reasons.append("Not sore")
        }
        switch energy {
        case 1: score -= 25; reasons.append("Low energy")
        case 3: score = min(100, score + 5); reasons.append("High energy")
        default: reasons.append("Normal energy")
        }
        score = max(0, min(100, score))
        let level: Readiness.Level = score >= 75 ? .ready : (score >= 55 ? .moderate : .low)
        return Readiness(level: level, score: score, reasons: reasons + ["from your check-in"], sleepHours: sleepHours)
    }
}

public struct DayNote: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var text: String
    public init(id: UUID = UUID(), date: Date, text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

public struct BusyWeek: Codable, Equatable {
    /// Start of the week (as the app's calendar has it).
    public var weekStart: Date
    /// Sessions taken off the weekly goal.
    public var fewer: Int
    public var reason: String?
    public init(weekStart: Date, fewer: Int, reason: String? = nil) {
        self.weekStart = weekStart
        self.fewer = fewer
        self.reason = reason
    }
}
