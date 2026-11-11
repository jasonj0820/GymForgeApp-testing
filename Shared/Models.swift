import Foundation

// New fields added after v1 are Optionals, so data saved by older builds still decodes.

// MARK: - Routine definitions

public enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, legs, calves, core, cardio, other
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// Muscle groups counted in weekly volume.
    public static var muscleGroups: [ExerciseCategory] {
        [.chest, .back, .shoulders, .biceps, .triceps, .legs, .calves, .core]
    }

    /// Best guess from an exercise name (used for imports and old logs).
    public static func guess(from name: String) -> ExerciseCategory {
        let n = name.lowercased()
        let rules: [(ExerciseCategory, [String])] = [
            (.cardio, ["run", "treadmill", "bike", "cycling", "rowing machine", "rower", "elliptical", "stair", "walk", "cardio", "jog", "swim", "ski erg", "assault"]),
            (.calves, ["calf"]),
            (.biceps, ["curl"]),
            (.triceps, ["tricep", "pushdown", "skull", "dip", "close grip", "kickback"]),
            (.shoulders, ["shoulder", "lateral", "overhead press", "military", "rear delt", "face pull", "upright row", "arnold", "delt"]),
            (.chest, ["bench", "chest", "fly", "flye", "pec", "push up", "push-up", "incline press", "decline"]),
            (.back, ["row", "pulldown", "pull up", "pull-up", "chin up", "chin-up", "lat ", "deadlift", "back extension", "shrug"]),
            (.legs, ["squat", "leg", "lunge", "hip thrust", "glute", "hamstring", "quad", "rdl", "split squat", "step up", "hack"]),
            (.core, ["crunch", "plank", "ab ", "abs", "sit up", "sit-up", "core", "oblique", "hanging leg", "russian twist"])
        ]
        if n.contains("leg curl") { return .legs }
        for (category, words) in rules where words.contains(where: { n.contains($0) }) {
            return category
        }
        return .other
    }
}

public struct ExerciseDefinition: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var category: ExerciseCategory
    public var repMin: Int
    public var repMax: Int
    public var defaultSets: Int
    public var restSeconds: Int
    public var weightIncrementKg: Double
    public var notes: String?
    /// Preset swaps (e.g. Chest Press → Bench Press, Incline Bench). Each keeps its own history.
    public var alternatives: [ExerciseDefinition]?
    /// Cardio only: target duration.
    public var targetMinutes: Int?
    /// Your own technique cues (replace the built-in ones on the session preview).
    public var formCues: [String]?
    /// The machine / brand ("Hammer Strength"): each machine keeps its own history and progression.
    public var equipment: String?
    /// What the typed number means on this machine (total, per side, per hand, pin-stack level).
    public var load: LoadConvention?

    public init(
        id: UUID = UUID(),
        name: String,
        category: ExerciseCategory,
        repMin: Int = 8,
        repMax: Int = 12,
        defaultSets: Int = 3,
        restSeconds: Int = 120,
        weightIncrementKg: Double = 2.5,
        notes: String? = nil,
        alternatives: [ExerciseDefinition]? = nil,
        targetMinutes: Int? = nil,
        formCues: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.repMin = repMin
        self.repMax = repMax
        self.defaultSets = defaultSets
        self.restSeconds = restSeconds
        self.weightIncrementKg = weightIncrementKg
        self.notes = notes
        self.alternatives = alternatives
        self.targetMinutes = targetMinutes
        self.formCues = formCues
    }

    /// Exercises with the same name share history across routines (e.g. "Incline Press" on Chest Day and Upper Day).
    public var historyKey: String { ExerciseLog.key(for: loggedName) }
    public var isCardio: Bool { category == .cardio }
    /// Assisted machines (e.g. Assisted Pull-up): the weight is help, so LESS weight = harder.
    public var isAssisted: Bool { ExerciseLog.isAssisted(name: name) }

    public var noteText: String {
        get { notes ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            notes = trimmed.isEmpty ? nil : newValue
        }
    }

    public var alternativeList: [ExerciseDefinition] {
        get { alternatives ?? [] }
        set { alternatives = newValue.isEmpty ? nil : newValue }
    }

    public var cardioMinutes: Int {
        get { targetMinutes ?? 20 }
        set { targetMinutes = newValue }
    }

    /// A new alternative pre-filled with this exercise's settings.
    public func makeAlternative(named name: String = "") -> ExerciseDefinition {
        ExerciseDefinition(
            name: name,
            category: category,
            repMin: repMin,
            repMax: repMax,
            defaultSets: defaultSets,
            restSeconds: restSeconds,
            weightIncrementKg: weightIncrementKg,
            targetMinutes: targetMinutes
        )
    }

    /// This exercise plus all of its alternatives.
    public var withAlternatives: [ExerciseDefinition] { [self] + alternativeList }
}

public struct RoutineExercise: Identifiable, Codable, Hashable {
    public var id: UUID
    public var exercise: ExerciseDefinition
    public var order: Int
    /// Alternate with the next exercise; rest only after both are done.
    public var supersetWithNext: Bool?

    public init(id: UUID = UUID(), exercise: ExerciseDefinition, order: Int, supersetWithNext: Bool? = nil) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.supersetWithNext = supersetWithNext
    }

    public var isSupersetWithNext: Bool {
        get { supersetWithNext ?? false }
        set { supersetWithNext = newValue ? true : nil }
    }
}

public struct WorkoutRoutine: Identifiable, Codable, Hashable {
    public var id: UUID
    public var name: String
    public var exercises: [RoutineExercise]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, exercises: [RoutineExercise], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.exercises = exercises.sorted { $0.order < $1.order }
        self.createdAt = createdAt
    }

    /// Every exercise in the routine including preset alternatives.
    public var allExercises: [ExerciseDefinition] {
        exercises.flatMap { $0.exercise.withAlternatives }
    }
}

// MARK: - Logged history (never rewritten when a routine changes)

public struct WorkoutSetLog: Identifiable, Codable, Hashable {
    public var id: UUID
    public var setNumber: Int
    public var weightKg: Double
    public var reps: Int
    public var completedAt: Date
    /// What the app suggested for this set (planned target), stored separately from the actual result.
    public var targetWeightKg: Double?
    public var targetReps: Int?
    public var isPR: Bool?
    /// Heart rate when the set was logged, and how far it dropped in the first 60 s of rest.
    public var heartRateAtEnd: Double?
    public var heartRateRecovery: Double?
    /// Cardio.
    public var durationSeconds: Double?
    public var distanceKm: Double?
    /// Effort: reps left in the tank (0 = failure, 4 = "4+"; sets with 4+ left count as half a hard set).
    public var rir: Int?

    public init(
        id: UUID = UUID(),
        setNumber: Int,
        weightKg: Double,
        reps: Int,
        completedAt: Date = .now,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        isPR: Bool? = nil,
        heartRateAtEnd: Double? = nil,
        heartRateRecovery: Double? = nil,
        durationSeconds: Double? = nil,
        distanceKm: Double? = nil,
        rir: Int? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.completedAt = completedAt
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.isPR = isPR
        self.heartRateAtEnd = heartRateAtEnd
        self.heartRateRecovery = heartRateRecovery
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
        self.rir = rir
    }

    public var volumeKg: Double { weightKg * Double(reps) }
    public var isCardio: Bool { (durationSeconds ?? 0) > 0 && reps == 0 }

    /// Epley estimate.
    public var estimatedOneRepMaxKg: Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    public var summaryText: String {
        if isCardio {
            var text = GFFormat.minutes(durationSeconds ?? 0)
            if let km = distanceKm, km > 0 { text += " · \(GFFormat.km(km)) km" }
            return text
        }
        let effort = rir.map { $0 >= 3 ? " · 3+ left" : " · \($0) left" } ?? ""
        return "\(GFFormat.kg(weightKg)) kg × \(reps)" + effort
    }
}

public struct ExerciseLog: Identifiable, Codable, Hashable {
    public var id: UUID
    public var exerciseID: UUID
    public var exerciseName: String
    public var repMinAtTime: Int
    public var repMaxAtTime: Int
    public var weightIncrementKgAtTime: Double
    public var sets: [WorkoutSetLog]
    public var category: ExerciseCategory?
    /// Set when this exercise replaced the planned one mid-workout.
    public var swappedFromName: String?
    /// What the typed numbers meant (per side, per hand, pin-stack level). nil = total kg.
    public var load: LoadConvention?
    /// MK11.3: today's variation ("Wide grip", "Paused"). Sessions only compare with the same variation.
    public var variation: String?

    public init(
        id: UUID = UUID(),
        exerciseID: UUID,
        exerciseName: String,
        repMinAtTime: Int,
        repMaxAtTime: Int,
        weightIncrementKgAtTime: Double,
        sets: [WorkoutSetLog],
        category: ExerciseCategory? = nil,
        swappedFromName: String? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.repMinAtTime = repMinAtTime
        self.repMaxAtTime = repMaxAtTime
        self.weightIncrementKgAtTime = weightIncrementKgAtTime
        self.sets = sets
        self.category = category
        self.swappedFromName = swappedFromName
    }

    public var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
    /// Total kg moved (per-side and per-hand numbers doubled; pin-stack levels left out).
    public var volumeKg: Double { sets.reduce(0) { $0 + $1.volumeKg } * (load?.volumeMultiplier ?? 1) }
    public var bestWeightKg: Double { sets.map(\.weightKg).max() ?? 0 }
    /// Not meaningful for assisted exercises (less weight = stronger), so 0 keeps them out of 1RM analytics.
    public var estimatedOneRepMaxKg: Double { isAssisted ? 0 : (sets.map(\.estimatedOneRepMaxKg).max() ?? 0) }
    public var isAssisted: Bool { ExerciseLog.isAssisted(name: exerciseName) }
    /// Assisted: the least assistance used for a full working set (lower = better).
    public var leastAssistanceKg: Double? { sets.filter { $0.reps > 0 }.map(\.weightKg).min() }
    public var bestSet: WorkoutSetLog? { sets.max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg } }
    public var isCardio: Bool { category == .cardio || (!sets.isEmpty && sets.allSatisfy(\.isCardio)) }
    public var totalDurationSeconds: Double { sets.reduce(0) { $0 + ($1.durationSeconds ?? 0) } }
    public var totalDistanceKm: Double { sets.reduce(0) { $0 + ($1.distanceKm ?? 0) } }
    public var hasPR: Bool { sets.contains { $0.isPR == true } }

    /// Most reps achieved at the heaviest weight used.
    public var repsAtBestWeight: Int {
        let top = bestWeightKg
        return sets.filter { abs($0.weightKg - top) < 0.001 }.map(\.reps).max() ?? 0
    }

    public func matches(_ exercise: ExerciseDefinition) -> Bool {
        exerciseID == exercise.id || ExerciseLog.key(for: exerciseName) == exercise.historyKey
    }

    /// Same exercise AND same variation (no note = the usual way), so wide grip isn't compared with narrow.
    public func matches(_ other: ExerciseLog) -> Bool {
        (exerciseID == other.exerciseID || ExerciseLog.key(for: exerciseName) == ExerciseLog.key(for: other.exerciseName))
            && variationKey == other.variationKey
    }

    public var variationKey: String { ExerciseLog.key(for: variation ?? "") }

    /// MK17: strength trends keep each variation separate ("bench press|wide grip"), so a planned grip
    /// or tempo change is never read as strength going up or down.
    public var trendKey: String { ExerciseLog.key(for: exerciseName) + "|" + variationKey }

    /// "Bench Press" or "Bench Press (wide grip)".
    public var trendName: String { variation.map { "\(exerciseName) (\($0.lowercased()))" } ?? exerciseName }

    public var resolvedCategory: ExerciseCategory {
        category ?? ExerciseCategory.guess(from: exerciseName)
    }

    public static func isAssisted(name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("assisted") || lower.contains("assist ")
    }

    public static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct WorkoutLog: Identifiable, Codable, Hashable {
    public var id: UUID
    public var routineID: UUID
    public var routineName: String
    public var startedAt: Date
    public var endedAt: Date
    public var exercises: [ExerciseLog]
    public var activeCaloriesKcal: Double?
    public var averageHeartRateBPM: Double?
    public var maxHeartRateBPM: Double?
    /// Deload / light sessions are kept out of progression decisions.
    public var isDeload: Bool?
    /// "strong" for imported workouts.
    public var source: String?
    public var phaseName: String?
    /// Logged by hand afterwards (a missed session) — no heart rate, not in Apple Health.
    public var isManual: Bool?
    /// MK10.1: heart rate every ~10 s from the Watch (for the graph and per-exercise peaks).
    public var heartRateSeries: [HeartRatePoint]?
    /// MK10.1: the session's effort target (reps left), for the coach's brief.
    public var targetRIR: Int?
    /// MK11.1: why this wasn't a normal session (short on time, kit taken, easy on purpose, run down).
    public var sessionTags: [SessionTag]?
    public var sessionNote: String?

    public init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        endedAt: Date,
        exercises: [ExerciseLog],
        activeCaloriesKcal: Double? = nil,
        averageHeartRateBPM: Double? = nil,
        maxHeartRateBPM: Double? = nil,
        isDeload: Bool? = nil,
        source: String? = nil,
        phaseName: String? = nil
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.activeCaloriesKcal = activeCaloriesKcal
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maxHeartRateBPM = maxHeartRateBPM
        self.isDeload = isDeload
        self.source = source
        self.phaseName = phaseName
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    public var tagSet: Set<SessionTag> { Set(sessionTags ?? []) }
    /// MK11.1: not used as "last time" for next session's targets (like a deload).
    public var skipsProgression: Bool {
        isDeload == true || tagSet.contains(.intentionallyEasier) || tagSet.contains(.unusualFatigue) || tagSet.contains(.sick)
    }
    /// MK11.1: kept out of plateau / strength-loss trends.
    public var isAtypical: Bool { isDeload == true || !tagSet.isEmpty }
    public var totalVolumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    public var totalReps: Int { exercises.reduce(0) { $0 + $1.totalReps } }
    public var prCount: Int { exercises.reduce(0) { $0 + $1.sets.filter { $0.isPR == true }.count } }
    public var cardioSeconds: Double { exercises.filter(\.isCardio).reduce(0) { $0 + $1.totalDurationSeconds } }
    public var cardioKm: Double { exercises.filter(\.isCardio).reduce(0) { $0 + $1.totalDistanceKm } }

    /// Average heart-rate drop in the first minute of rest (bpm).
    public var averageHeartRateRecovery: Double? {
        let values = exercises.flatMap(\.sets).compactMap(\.heartRateRecovery)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// MK11.1: session context, so a short, kit-limited, easy or tired day isn't read as lost strength.
public enum SessionTag: String, Codable, CaseIterable, Identifiable, Hashable {
    case limitedTime, equipmentUnavailable, intentionallyEasier, unusualFatigue
    /// MK20.9: under the weather — read like a run-down day (no progression pressure, lower numbers excused).
    case sick
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .limitedTime: return "Short on time"
        case .equipmentUnavailable: return "Equipment unavailable"
        case .intentionallyEasier: return "Easier on purpose"
        case .unusualFatigue: return "Unusually tired"
        case .sick: return "Feeling sick"
        }
    }

    public var icon: String {
        switch self {
        case .limitedTime: return "clock"
        case .equipmentUnavailable: return "wrench.and.screwdriver"
        case .intentionallyEasier: return "tortoise"
        case .unusualFatigue: return "battery.25"
        case .sick: return "facemask"
        }
    }

    /// How the coach reads a lower result on a day like this.
    public var excuse: String {
        switch self {
        case .limitedTime: return "you were short on time"
        case .equipmentUnavailable: return "the kit wasn't free"
        case .intentionallyEasier: return "easy on purpose"
        case .unusualFatigue: return "you were run down"
        case .sick: return "you were sick"
        }
    }

    /// The tag that best explains a lower number (most specific first).
    public static func explaining(_ tags: Set<SessionTag>) -> SessionTag? {
        [.sick, .unusualFatigue, .intentionallyEasier, .equipmentUnavailable, .limitedTime].first { tags.contains($0) }
    }
}

public struct BodyMetricPoint: Identifiable, Codable, Hashable {
    public enum Metric: String, Codable { case bodyWeight, bodyFatPercentage, leanMass, restingHeartRate, heartRateVariability }
    public var id: UUID
    public var metric: Metric
    public var date: Date
    public var value: Double

    public init(id: UUID = UUID(), metric: Metric, date: Date, value: Double) {
        self.id = id
        self.metric = metric
        self.date = date
        self.value = value
    }
}

public struct SleepNight: Identifiable, Codable, Hashable {
    /// Wake-up day.
    public var date: Date
    public var hoursAsleep: Double
    /// MK11: when you fell asleep and woke up (first / last asleep sample of the night).
    public var start: Date?
    public var end: Date?
    public var id: Date { date }

    public init(date: Date, hoursAsleep: Double, start: Date? = nil, end: Date? = nil) {
        self.date = date
        self.hoursAsleep = hoursAsleep
        self.start = start
        self.end = end
    }
}

// MARK: - Profile

public enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case buildMuscle, getStronger, loseFat, recomposition, maintain
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .buildMuscle: return "Build Muscle"
        case .getStronger: return "Get Stronger"
        case .loseFat: return "Lose Fat"
        case .recomposition: return "Recomposition"
        case .maintain: return "Maintain"
        }
    }
}

public enum CoachStyle: String, Codable, CaseIterable, Identifiable {
    case pushMe, motivating, analytical, supportive, hardTruth, heartbreak
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pushMe: return "Push Me"
        case .motivating: return "Motivating"
        case .analytical: return "Analytical"
        case .supportive: return "Supportive"
        case .hardTruth: return "Hard Truth"
        case .heartbreak: return "Heartbreak"
        }
    }
}

public struct UserProfile: Codable, Hashable {
    public var goal: TrainingGoal
    public var coachStyle: CoachStyle
    public var deloadUntil: Date?
    public var autoRestEnabled: Bool?
    public var autoRestHeartRate: Int?
    public var program: ProgramPlan?
    public var remindersEnabled: Bool?
    public var reminderHour: Int?
    public var reminderMinute: Int?
    /// Sergeant Cluck quota nags (nil = on).
    public var sergeantCluck: Bool?
    /// "size" (default) or "strength": what the coach tunes suggestions for.
    public var trainingFocus: String?
    /// Your max heart rate for zones (nil = estimated from your workouts).
    public var maxHeartRateSetting: Int?
    /// MK11: bedtime and wake time per night (nil = no schedule yet).
    public var sleepSchedule: SleepSchedule?
    /// MK11.1: running and basketball goals (lifting stays the weekly goal).
    public var trainingGoals: TrainingGoals?
    /// MK20.3: your details, typed in (Apple Health isn't available). nil = not set.
    public var heightCm: Double?
    public var birthDate: Date?
    /// "male" or "female" — only used for the calorie formula.
    public var sex: String?

    public init(goal: TrainingGoal = .buildMuscle, coachStyle: CoachStyle = .motivating) {
        self.goal = goal
        self.coachStyle = coachStyle
    }

    public func isDeloadActive(at date: Date = .now) -> Bool {
        if let until = deloadUntil, until > date { return true }
        return program?.position(at: date)?.block.phase == .deload
    }

    public func currentPhase(at date: Date = .now) -> ProgramPhase? {
        program?.position(at: date)?.block.phase
    }

    public var autoRest: Bool {
        get { autoRestEnabled ?? false }
        set { autoRestEnabled = newValue }
    }

    public var autoRestBPM: Int {
        get { autoRestHeartRate ?? 110 }
        set { autoRestHeartRate = newValue }
    }

    public var reminders: Bool {
        get { remindersEnabled ?? false }
        set { remindersEnabled = newValue }
    }

    /// Whole years old, from your birthday.
    public func age(at date: Date = .now) -> Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: date).year
    }

    /// Body-mass index for a weight (kg), if your height is set.
    public func bmi(weightKg: Double) -> Double? {
        guard let heightCm, heightCm > 100 else { return nil }
        let m = heightCm / 100
        return weightKg / (m * m)
    }

    public var cluckEnabled: Bool {
        get { sergeantCluck ?? true }
        set { sergeantCluck = newValue }
    }

    /// Exercise with the current program phase's rep range applied.
    public func effective(_ exercise: ExerciseDefinition, at date: Date = .now) -> ExerciseDefinition {
        ProgramPhase.adjust(exercise, for: currentPhase(at: date))
    }
}

// MARK: - Snapshot (persistence + iPhone -> Watch sync)

public struct AppSnapshot: Codable {
    public var routines: [WorkoutRoutine]
    public var workoutLogs: [WorkoutLog]
    public var weeklyGoal: Int
    public var profile: UserProfile?
    /// Rest days, pain flags, nutrition, tape measurements (iPhone only).
    public var extras: GymExtras?
    /// Runs and basketball (details: route, splits, zones). iPhone only.
    public var cardioSessions: [CardioSession]?

    public init(routines: [WorkoutRoutine], workoutLogs: [WorkoutLog], weeklyGoal: Int, profile: UserProfile? = nil,
                extras: GymExtras? = nil) {
        self.routines = routines
        self.workoutLogs = workoutLogs
        self.weeklyGoal = weeklyGoal
        self.profile = profile
        self.extras = extras
    }

    /// The Watch only needs recent sessions of each exercise (for prefill and PR checks).
    /// Sending the full history every time makes WatchConnectivity payloads grow forever.
    /// What the Watch needs: for every exercise, the last normal (non-deload) session (for targets)
    /// plus the sessions holding its bests (so PRs on the Watch are judged against all-time bests).
    public func trimmedForWatch(maxLogs: Int = 120) -> AppSnapshot {
        let newestFirst = workoutLogs.sorted { $0.startedAt > $1.startedAt }
        var latest = Set<UUID>()
        var bests = Set<UUID>()
        var seenKeys = Set<String>()
        for exercise in routines.flatMap(\.allExercises) where seenKeys.insert(exercise.historyKey).inserted {
            var lastNormal: UUID?
            var lastAny: UUID?
            var heaviest: (id: UUID, kg: Double)?
            var strongest: (id: UUID, e1rm: Double)?
            var leastHelp: (id: UUID, kg: Double)?
            for workout in newestFirst {
                guard let log = workout.exercises.first(where: { $0.matches(exercise) && !$0.sets.isEmpty }) else { continue }
                if lastAny == nil { lastAny = workout.id }
                if lastNormal == nil, !workout.skipsProgression { lastNormal = workout.id }
                if log.isAssisted {
                    // Same rule as the PR check: only full sets (reps in range) count.
                    if let kg = log.sets.filter({ $0.reps >= exercise.repMin }).map(\.weightKg).min(),
                       kg < (leastHelp?.kg ?? .infinity) { leastHelp = (workout.id, kg) }
                } else if !log.isCardio {
                    if log.bestWeightKg > (heaviest?.kg ?? 0) { heaviest = (workout.id, log.bestWeightKg) }
                    if log.estimatedOneRepMaxKg > (strongest?.e1rm ?? 0) { strongest = (workout.id, log.estimatedOneRepMaxKg) }
                }
            }
            if let id = lastNormal ?? lastAny { latest.insert(id) }
            if let lastAny { latest.insert(lastAny) }
            for id in [heaviest?.id, strongest?.id, leastHelp?.id].compactMap({ $0 }) { bests.insert(id) }
        }
        // If it ever has to be capped, the most recent sessions win, then the best ones.
        var keep: [UUID] = newestFirst.map(\.id).filter { latest.contains($0) }
        keep += newestFirst.map(\.id).filter { bests.contains($0) && !latest.contains($0) }
        let kept = Set(keep.prefix(maxLogs))
        var copy = self
        // The heart-rate graph stays on the iPhone (the Watch doesn't need it).
        copy.workoutLogs = workoutLogs.filter { kept.contains($0.id) }.sorted { $0.startedAt < $1.startedAt }
            .map { log in
                var light = log
                light.heartRateSeries = nil
                return light
            }
        copy.extras = nil
        copy.cardioSessions = nil
        return copy
    }
}

// MARK: - History lookups

public struct ExerciseHistoryPoint: Identifiable, Hashable {
    public let workoutID: UUID
    public let date: Date
    public let log: ExerciseLog
    public var id: UUID { workoutID }

    public init(workoutID: UUID, date: Date, log: ExerciseLog) {
        self.workoutID = workoutID
        self.date = date
        self.log = log
    }
}

/// Best performances before a workout, used for PR detection.
public struct PersonalBests: Equatable {
    public var estimatedOneRepMaxKg: Double = 0
    public var heaviestWeightKg: Double = 0
    public var hasHistory: Bool = false
    public init() {}
}

public extension Array where Element == WorkoutLog {
    /// Most recent matching log. Deload/light, easy-on-purpose and run-down sessions are skipped so they don't reset progression.
    func previousLog(where predicate: (ExerciseLog) -> Bool, before date: Date? = nil) -> ExerciseLog? {
        var bestDate = Date.distantPast
        var best: ExerciseLog?
        for workout in self where !workout.skipsProgression {
            if let date, workout.startedAt >= date { continue }
            guard let match = workout.exercises.first(where: predicate) else { continue }
            if best == nil || workout.startedAt > bestDate {
                best = match
                bestDate = workout.startedAt
            }
        }
        return best
    }

    func previousLog(for exercise: ExerciseDefinition, before date: Date? = nil) -> ExerciseLog? {
        previousLog(where: { $0.matches(exercise) }, before: date)
    }

    /// MK17: like with like for plateau / stall checks: only sessions done the same way as the latest one.
    func sameWayHistory(for exercise: ExerciseDefinition) -> [ExerciseHistoryPoint] {
        let all = history(for: exercise)
        guard let key = all.last?.log.variationKey else { return all }
        return all.filter { $0.log.variationKey == key }
    }

    func history(for exercise: ExerciseDefinition) -> [ExerciseHistoryPoint] {
        var points: [ExerciseHistoryPoint] = []
        for workout in self {
            if let match = workout.exercises.first(where: { $0.matches(exercise) }) {
                points.append(ExerciseHistoryPoint(workoutID: workout.id, date: workout.startedAt, log: match))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    func personalBests(for exercise: ExerciseDefinition, before date: Date? = nil) -> PersonalBests {
        var bests = PersonalBests()
        for workout in self {
            if let date, workout.startedAt >= date { continue }
            for log in workout.exercises where log.matches(exercise) && !log.isCardio {
                guard !log.sets.isEmpty else { continue }
                bests.hasHistory = true
                bests.estimatedOneRepMaxKg = Swift.max(bests.estimatedOneRepMaxKg, log.estimatedOneRepMaxKg)
                bests.heaviestWeightKg = Swift.max(bests.heaviestWeightKg, log.bestWeightKg)
            }
        }
        return bests
    }

    /// Every exercise name ever logged, with its most recent log (for imported or retired exercises).
    func loggedExercises() -> [ExerciseLog] {
        var latest: [String: (Date, ExerciseLog)] = [:]
        for workout in self {
            for log in workout.exercises {
                let key = ExerciseLog.key(for: log.exerciseName)
                if let existing = latest[key], existing.0 > workout.startedAt { continue }
                latest[key] = (workout.startedAt, log)
            }
        }
        return latest.values.map(\.1).sorted { $0.exerciseName < $1.exerciseName }
    }
}

// MARK: - Live workout state (shared by iPhone and Watch so both apply identical rules)

public struct PRHit: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable { case heaviestWeight, estimatedOneRepMax, leastAssistance }
    /// Same as the set's id.
    public var id: UUID
    public var exerciseName: String
    public var weightKg: Double
    public var reps: Int
    public var kind: Kind
    public var previousBest: Double
    public var newBest: Double

    public init(id: UUID, exerciseName: String, weightKg: Double, reps: Int, kind: Kind, previousBest: Double, newBest: Double) {
        self.id = id
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.kind = kind
        self.previousBest = previousBest
        self.newBest = newBest
    }

    public var headline: String {
        switch kind {
        case .heaviestWeight: return "Heaviest ever"
        case .estimatedOneRepMax: return "Strength PR"
        case .leastAssistance: return "Least assistance ever"
        }
    }

    public var detail: String {
        switch kind {
        case .heaviestWeight:
            return "+\(GFFormat.kg(newBest - previousBest)) kg over your previous best"
        case .estimatedOneRepMax:
            return "Est. 1RM \(GFFormat.kg(newBest.rounded())) kg (was \(GFFormat.kg(previousBest.rounded())))"
        case .leastAssistance:
            return "\(GFFormat.kg(newBest)) kg assist (was \(GFFormat.kg(previousBest)) kg) — less help, more you"
        }
    }
}

public struct ActiveWorkoutState: Codable, Hashable {
    public var workoutID: UUID
    public var routine: WorkoutRoutine
    public var startedAt: Date
    public var exerciseIndex: Int
    public var setIndex: Int
    public var completedSets: [UUID: [WorkoutSetLog]]
    public var isResting: Bool
    public var restEndDate: Date?
    /// Incremented on every change. The device receiving an update ignores anything older than what it has.
    public var revision: Int
    /// Set by the iPhone to ask the Watch (which owns the HealthKit session) to finish and save.
    public var finishRequested: Bool
    /// Routine item id → the exercise that was planned before a swap.
    public var swaps: [UUID: ExerciseDefinition]?
    /// Exercises swapped out after some sets were logged (kept so those sets are saved).
    public var retiredExercises: [ExerciseDefinition]?
    public var lastPR: PRHit?
    public var isDeload: Bool?
    public var phaseName: String?
    public var restStartedAt: Date?
    /// Routine items skipped for today (treated as done; tap them to come back).
    public var skippedItems: [UUID]?
    /// MK10: reps to leave in the tank on working sets today (from the training block).
    public var targetRIR: Int?
    /// "Block week 2 of 4" / "Deload week".
    public var blockLabel: String?
    /// MK11.1: session context tags (carried into the saved log).
    public var sessionTags: [SessionTag]?
    /// MK11.3: exercise id → today's variation note.
    public var variations: [UUID: String]?

    public init(
        workoutID: UUID = UUID(),
        routine: WorkoutRoutine,
        startedAt: Date = .now,
        exerciseIndex: Int = 0,
        setIndex: Int = 0,
        completedSets: [UUID: [WorkoutSetLog]] = [:],
        isResting: Bool = false,
        restEndDate: Date? = nil,
        revision: Int = 0,
        finishRequested: Bool = false
    ) {
        self.workoutID = workoutID
        self.routine = routine
        self.startedAt = startedAt
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
        self.completedSets = completedSets
        self.isResting = isResting
        self.restEndDate = restEndDate
        self.revision = revision
        self.finishRequested = finishRequested
    }

    /// Builds a new workout, applying the program phase's rep ranges and deload / light-session reductions.
    public static func start(routine: WorkoutRoutine, profile: UserProfile?, light: Bool = false, now: Date = .now) -> ActiveWorkoutState {
        var adjusted = routine
        let phase = profile?.currentPhase(at: now)
        let deload = light || (profile?.isDeloadActive(at: now) ?? false)
        for index in adjusted.exercises.indices {
            var exercise = ProgramPhase.adjust(adjusted.exercises[index].exercise, for: phase)
            if deload {
                exercise = ProgramPhase.reduceSets(exercise)
            }
            adjusted.exercises[index].exercise = exercise
        }
        var state = ActiveWorkoutState(routine: adjusted, startedAt: now)
        state.revision = 1
        state.isDeload = deload ? true : nil
        state.phaseName = phase?.title
        state.targetRIR = EffortTarget.reps(profile: profile, light: deload, at: now)
        state.blockLabel = EffortTarget.blockLabel(profile: profile, at: now)
        return state
    }
}

public enum SetCompletionResult: Equatable {
    case rest(seconds: Int)
    /// Superset: go straight to the next exercise without resting.
    case supersetNext
    case allDone
}

public extension ActiveWorkoutState {
    var currentItem: RoutineExercise? {
        guard exerciseIndex >= 0, exerciseIndex < routine.exercises.count else { return nil }
        return routine.exercises[exerciseIndex]
    }

    func sets(for item: RoutineExercise) -> [WorkoutSetLog] {
        completedSets[item.exercise.id] ?? []
    }

    func isFinished(_ item: RoutineExercise) -> Bool {
        sets(for: item).count >= item.exercise.defaultSets || isSkipped(item)
    }

    func isSkipped(_ item: RoutineExercise) -> Bool {
        skippedItems?.contains(item.id) ?? false
    }

    /// Skips an exercise for today and moves to the next one not done yet.
    mutating func skipExercise(at index: Int) {
        guard index >= 0, index < routine.exercises.count else { return }
        var skipped = skippedItems ?? []
        if !skipped.contains(routine.exercises[index].id) { skipped.append(routine.exercises[index].id) }
        skippedItems = skipped
        isResting = false
        restEndDate = nil
        restStartedAt = nil
        if let next = nextUnfinishedIndex(after: index) {
            exerciseIndex = next
            setIndex = sets(for: routine.exercises[next]).count
        }
        revision += 1
    }

    var totalCompletedSets: Int { completedSets.values.reduce(0) { $0 + $1.count } }
    var totalPlannedSets: Int { routine.exercises.reduce(0) { $0 + $1.exercise.defaultSets } }
    /// MK10.2: cardio in a gym routine is optional — the workout is complete when the weights are done.
    var isComplete: Bool {
        guard !routine.exercises.isEmpty else { return false }
        let required = routine.exercises.filter { !$0.exercise.isCardio }
        return (required.isEmpty ? routine.exercises : required).allSatisfy { isFinished($0) }
    }
    var deload: Bool { isDeload ?? false }

    /// MK11.3: today's variation for an exercise (nil / empty clears it).
    mutating func setVariation(_ text: String?, for exerciseID: UUID) {
        var all = variations ?? [:]
        let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        all[exerciseID] = clean.isEmpty ? nil : clean
        variations = all.isEmpty ? nil : all
        revision += 1
    }

    /// MK11.1: turns a session-context tag on or off.
    mutating func toggleTag(_ tag: SessionTag) {
        var tags = sessionTags ?? []
        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
        sessionTags = tags.isEmpty ? nil : tags
        revision += 1
    }

    func nextUnfinishedIndex(after index: Int) -> Int? {
        let count = routine.exercises.count
        guard count > 0 else { return nil }
        for offset in 1...count {
            let candidate = (index + offset) % count
            if !isFinished(routine.exercises[candidate]) { return candidate }
        }
        return nil
    }

    // MARK: Supersets

    /// Indices of the exercises linked into a superset with `index` (just `[index]` if none).
    func supersetGroup(of index: Int) -> [Int] {
        guard index >= 0, index < routine.exercises.count else { return [] }
        var start = index
        while start > 0, routine.exercises[start - 1].isSupersetWithNext { start -= 1 }
        var end = index
        while end < routine.exercises.count - 1, routine.exercises[end].isSupersetWithNext { end += 1 }
        return Array(start...end)
    }

    /// "A1", "A2", "B1"… for exercises in a superset, nil otherwise.
    func supersetLabel(for index: Int) -> String? {
        let group = supersetGroup(of: index)
        guard group.count > 1, let position = group.firstIndex(of: index) else { return nil }
        var letterIndex = 0
        var cursor = 0
        while cursor < routine.exercises.count {
            let current = supersetGroup(of: cursor)
            if current.first == group.first { break }
            if current.count > 1 { letterIndex += 1 }
            cursor = (current.last ?? cursor) + 1
        }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return "\(letters[letterIndex % letters.count])\(position + 1)"
    }

    // MARK: Logging

    /// Logs a set, detects PRs, advances (handling supersets) and starts the rest timer.
    mutating func completeSet(
        weightKg: Double,
        reps: Int,
        durationSeconds: Double? = nil,
        distanceKm: Double? = nil,
        rir: Int? = nil,
        targetWeightKg: Double?,
        targetReps: Int?,
        history: [WorkoutLog] = [],
        heartRate: Double? = nil,
        now: Date = .now
    ) -> SetCompletionResult {
        guard let item = currentItem else { return .allDone }
        let exercise = item.exercise
        var list = sets(for: item)
        var newSet = WorkoutSetLog(
            setNumber: list.count + 1,
            weightKg: weightKg,
            reps: reps,
            completedAt: now,
            targetWeightKg: targetWeightKg,
            targetReps: targetReps,
            heartRateAtEnd: (heartRate ?? 0) > 0 ? heartRate : nil,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            rir: rir
        )

        if let hit = prHit(for: exercise, set: newSet, earlier: list, history: history) {
            newSet.isPR = true
            lastPR = hit
        }

        list.append(newSet)
        completedSets[exercise.id] = list
        revision += 1

        let group = supersetGroup(of: exerciseIndex)
        if group.count > 1 {
            let round = list.count
            if let next = group.first(where: { candidate in
                candidate > exerciseIndex
                    && !isFinished(routine.exercises[candidate])
                    && sets(for: routine.exercises[candidate]).count < round
            }) {
                exerciseIndex = next
                setIndex = sets(for: routine.exercises[next]).count
                isResting = false
                restEndDate = nil
                restStartedAt = nil
                return .supersetNext
            }
            if let first = group.first(where: { !isFinished(routine.exercises[$0]) }) {
                exerciseIndex = first
                setIndex = sets(for: routine.exercises[first]).count
                return beginRest(seconds: exercise.restSeconds, now: now)
            }
        } else if list.count < exercise.defaultSets {
            setIndex = list.count
            return beginRest(seconds: exercise.restSeconds, now: now)
        }

        if let next = nextUnfinishedIndex(after: exerciseIndex) {
            exerciseIndex = next
            setIndex = sets(for: routine.exercises[next]).count
            return beginRest(seconds: exercise.restSeconds, now: now)
        }
        setIndex = list.count
        isResting = false
        restEndDate = nil
        restStartedAt = nil
        return .allDone
    }

    /// The PR a set counts as (if any), compared with history and the sets logged before it today.
    func prHit(for exercise: ExerciseDefinition, set: WorkoutSetLog, earlier: [WorkoutSetLog], history: [WorkoutLog]) -> PRHit? {
        guard !deload, !exercise.isCardio else { return nil }
        let weightKg = set.weightKg
        let reps = set.reps
        if exercise.isAssisted {
            // Assisted: a PR is doing a full set with less help than ever before.
            guard reps >= exercise.repMin else { return nil }
            let previous = history.filter { $0.startedAt < startedAt }
                .flatMap { $0.exercises.filter { $0.matches(exercise) } }
                .flatMap(\.sets).filter { $0.reps >= exercise.repMin }.map(\.weightKg)
            let earlierToday = earlier.filter { $0.reps >= exercise.repMin }.map(\.weightKg)
            guard let best = (previous + earlierToday).min(), weightKg < best - 0.001 else { return nil }
            return PRHit(id: set.id, exerciseName: exercise.name, weightKg: weightKg, reps: reps,
                         kind: .leastAssistance, previousBest: best, newBest: weightKg)
        }
        guard reps > 0, weightKg > 0 else { return nil }
        var bests = history.personalBests(for: exercise, before: startedAt)
        for previousSet in earlier {
            bests.estimatedOneRepMaxKg = Swift.max(bests.estimatedOneRepMaxKg, previousSet.estimatedOneRepMaxKg)
            bests.heaviestWeightKg = Swift.max(bests.heaviestWeightKg, previousSet.weightKg)
        }
        guard bests.hasHistory else { return nil }
        if weightKg > bests.heaviestWeightKg + 0.001 {
            return PRHit(id: set.id, exerciseName: exercise.name, weightKg: weightKg, reps: reps,
                         kind: .heaviestWeight, previousBest: bests.heaviestWeightKg, newBest: weightKg)
        }
        if set.estimatedOneRepMaxKg > bests.estimatedOneRepMaxKg + 0.001 {
            return PRHit(id: set.id, exerciseName: exercise.name, weightKg: weightKg, reps: reps,
                         kind: .estimatedOneRepMax, previousBest: bests.estimatedOneRepMaxKg,
                         newBest: set.estimatedOneRepMaxKg)
        }
        return nil
    }

    // MARK: Editing logged sets & the plan

    /// The exercise a set list belongs to (in today's routine, or swapped out after logging).
    func exerciseDefinition(id: UUID) -> ExerciseDefinition? {
        routine.exercises.first { $0.exercise.id == id }?.exercise ?? retiredExercises?.first { $0.id == id }
    }

    /// Changes a logged set's numbers (PRs are re-checked).
    mutating func editSet(id: UUID, weightKg: Double, reps: Int, durationSeconds: Double? = nil,
                          distanceKm: Double? = nil, rir: Int?, history: [WorkoutLog]) {
        guard let key = completedSets.first(where: { $0.value.contains { $0.id == id } })?.key,
              var list = completedSets[key],
              let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].weightKg = weightKg
        list[index].reps = reps
        list[index].durationSeconds = durationSeconds
        list[index].distanceKm = distanceKm
        list[index].rir = rir
        completedSets[key] = list
        recomputePRs(exerciseID: key, changedSetID: id, history: history)
        revision += 1
    }

    /// Removes a logged set (the rest are renumbered and PRs re-checked).
    mutating func deleteSet(id: UUID, history: [WorkoutLog]) {
        guard let key = completedSets.first(where: { $0.value.contains { $0.id == id } })?.key,
              var list = completedSets[key] else { return }
        list.removeAll { $0.id == id }
        for index in list.indices { list[index].setNumber = index + 1 }
        completedSets[key] = list.isEmpty ? nil : list
        if lastPR?.id == id { lastPR = nil }
        recomputePRs(exerciseID: key, changedSetID: nil, history: history)
        refreshPosition()
        revision += 1
    }

    /// Changes how many sets are planned for an exercise today (never below what's already logged, minimum 1).
    mutating func setPlannedSets(_ count: Int, at index: Int) {
        guard index >= 0, index < routine.exercises.count else { return }
        let logged = sets(for: routine.exercises[index]).count
        routine.exercises[index].exercise.defaultSets = Swift.max(count, logged, 1)
        refreshPosition()
        revision += 1
    }

    /// Adds a new swap option to a slot (to the planned exercise, so it stays available after swapping).
    mutating func addSwapOption(_ option: ExerciseDefinition, at index: Int) {
        guard index >= 0, index < routine.exercises.count else { return }
        let item = routine.exercises[index]
        var clean = option
        clean.alternatives = nil
        if var planned = swaps?[item.id] {
            planned.alternativeList.append(clean)
            swaps?[item.id] = planned
        } else {
            routine.exercises[index].exercise.alternativeList.append(clean)
        }
        revision += 1
    }

    /// After a plan change: if the exercise you're on is now done, move to the next one not done.
    private mutating func refreshPosition() {
        guard let item = currentItem else { return }
        if isFinished(item), let next = nextUnfinishedIndex(after: exerciseIndex) {
            exerciseIndex = next
        }
        if let current = currentItem { setIndex = sets(for: current).count }
    }

    private mutating func recomputePRs(exerciseID: UUID, changedSetID: UUID?, history: [WorkoutLog]) {
        guard var list = completedSets[exerciseID], let exercise = exerciseDefinition(id: exerciseID) else { return }
        for index in list.indices {
            let hit = prHit(for: exercise, set: list[index], earlier: Array(list[..<index]), history: history)
            list[index].isPR = hit == nil ? nil : true
            if let hit, list[index].id == changedSetID {
                lastPR = hit
            } else if hit == nil, lastPR?.id == list[index].id {
                lastPR = nil
            }
        }
        completedSets[exerciseID] = list
    }

    /// Two copies of the same workout that changed on both devices at the same time (same revision,
    /// or an older copy carrying a Finish): keep this one, add any sets only the other has, and keep a Finish.
    func merged(with other: ActiveWorkoutState) -> ActiveWorkoutState {
        var result = self
        for (key, theirs) in other.completedSets {
            var list = result.completedSets[key] ?? []
            let known = Set(list.map(\.id))
            let missing = theirs.filter { !known.contains($0.id) }
            guard !missing.isEmpty else { continue }
            list += missing
            list.sort { $0.completedAt < $1.completedAt }
            for index in list.indices { list[index].setNumber = index + 1 }
            result.completedSets[key] = list
            // An exercise only the other device knows about (swapped there): keep its sets saveable.
            if result.exerciseDefinition(id: key) == nil, let exercise = other.exerciseDefinition(id: key) {
                result.retiredExercises = (result.retiredExercises ?? []) + [exercise]
            }
        }
        result.finishRequested = finishRequested || other.finishRequested
        if let current = result.currentItem { result.setIndex = result.sets(for: current).count }
        result.revision = Swift.max(revision, other.revision) + 1
        return result
    }

    /// The most recently logged set across all exercises.
    var lastLoggedSet: WorkoutSetLog? {
        completedSets.values.flatMap { $0 }.max { $0.completedAt < $1.completedAt }
    }

    mutating func updateSet(id: UUID, _ change: (inout WorkoutSetLog) -> Void) {
        for (key, var list) in completedSets {
            if let index = list.firstIndex(where: { $0.id == id }) {
                change(&list[index])
                completedSets[key] = list
                revision += 1
                return
            }
        }
    }

    /// Adds an extra set to an exercise beyond the plan.
    mutating func addExtraSet(to index: Int) {
        guard index >= 0, index < routine.exercises.count else { return }
        routine.exercises[index].exercise.defaultSets += 1
        jump(toExercise: index)
    }

    mutating func jump(toExercise index: Int) {
        guard index >= 0, index < routine.exercises.count else { return }
        let id = routine.exercises[index].id
        skippedItems?.removeAll { $0 == id }
        if skippedItems?.isEmpty == true { skippedItems = nil }
        exerciseIndex = index
        setIndex = sets(for: routine.exercises[index]).count
        isResting = false
        restEndDate = nil
        restStartedAt = nil
        revision += 1
    }

    mutating func endRest() {
        isResting = false
        restEndDate = nil
        restStartedAt = nil
        revision += 1
    }

    mutating func extendRest(by seconds: Int, now: Date = .now) {
        let base = Swift.max(restEndDate ?? now, now)
        restEndDate = base.addingTimeInterval(TimeInterval(seconds))
        if restStartedAt == nil { restStartedAt = now }
        isResting = true
        revision += 1
    }

    private mutating func beginRest(seconds: Int, now: Date) -> SetCompletionResult {
        isResting = true
        restStartedAt = now
        restEndDate = now.addingTimeInterval(TimeInterval(Swift.max(seconds, 0)))
        return .rest(seconds: seconds)
    }

    // MARK: Swapping

    /// The exercise the routine planned for this slot (before any swap).
    func plannedExercise(for item: RoutineExercise) -> ExerciseDefinition {
        swaps?[item.id] ?? item.exercise
    }

    /// Exercises this slot can be swapped to (the planned one and its presets, minus the current one).
    func swapOptions(for item: RoutineExercise) -> [ExerciseDefinition] {
        plannedExercise(for: item).withAlternatives.filter { $0.id != item.exercise.id }
    }

    func swappedFrom(_ item: RoutineExercise) -> ExerciseDefinition? {
        guard let planned = swaps?[item.id], planned.id != item.exercise.id else { return nil }
        return planned
    }

    /// MK10.1: adds an exercise to today's workout (at the end).
    mutating func appendExercise(_ exercise: ExerciseDefinition, itemID: UUID = UUID()) {
        routine.exercises.append(RoutineExercise(id: itemID, exercise: exercise, order: routine.exercises.count))
        // Everything else done (or nothing on screen): go straight to it.
        if currentItem.map({ isFinished($0) }) ?? true, !isResting {
            exerciseIndex = routine.exercises.count - 1
            setIndex = 0
        }
        revision += 1
    }

    /// Replaces the exercise in a slot for today only. Sets already logged on the old exercise are kept,
    /// and the new exercise is recorded separately with its own history.
    mutating func swapExercise(at index: Int, to replacement: ExerciseDefinition) {
        guard index >= 0, index < routine.exercises.count else { return }
        let item = routine.exercises[index]
        let current = item.exercise
        let planned = plannedExercise(for: item)
        guard replacement.id != current.id else { return }

        var retired = retiredExercises ?? []
        if !(completedSets[current.id] ?? []).isEmpty, !retired.contains(where: { $0.id == current.id }) {
            retired.append(current)
        }
        retired.removeAll { $0.id == replacement.id }
        retiredExercises = retired.isEmpty ? nil : retired

        var map = swaps ?? [:]
        if replacement.id == planned.id {
            map[item.id] = nil
            routine.exercises[index].exercise = planned
        } else {
            map[item.id] = planned
            var swapped = replacement
            swapped.alternatives = nil
            routine.exercises[index].exercise = swapped
        }
        swaps = map.isEmpty ? nil : map

        exerciseIndex = index
        setIndex = sets(for: routine.exercises[index]).count
        isResting = false
        restEndDate = nil
        restStartedAt = nil
        revision += 1
    }

    mutating func updateNotes(exerciseID: UUID, notes: String?) {
        for index in routine.exercises.indices where routine.exercises[index].exercise.id == exerciseID {
            routine.exercises[index].exercise.notes = notes
        }
        revision += 1
    }

    // MARK: Suggestions & saving

    /// Suggested weight/reps for the next set of `item`: today's per-set plan (same weight every set,
    /// re-aimed after a set that went clearly better or worse; deload already applied).
    func prefill(for item: RoutineExercise, logs: [WorkoutLog]) -> (weightKg: Double, reps: Int) {
        let today = sets(for: item)
        guard let target = setPlan(for: item, logs: logs).target(at: today.count) else {
            return (today.last?.weightKg ?? 0, item.exercise.repMin)
        }
        var weight = target.weightKg
        // First time (no planned weight yet): carry the weight you picked on your first set.
        if weight <= 0, let last = today.last, last.weightKg > 0 { weight = last.weightKg }
        return (weight, target.reps)
    }

    /// Last session's cardio for this exercise (minutes, km).
    func cardioPrefill(for item: RoutineExercise, logs: [WorkoutLog]) -> (minutes: Double, km: Double?) {
        if let previous = logs.previousLog(for: item.exercise, before: startedAt),
           let set = previous.sets.first(where: { ($0.durationSeconds ?? 0) > 0 }) {
            return ((set.durationSeconds ?? 0) / 60, set.distanceKm)
        }
        return (Double(item.exercise.cardioMinutes), nil)
    }

    func makeLog(
        endedAt: Date = .now,
        activeCalories: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil
    ) -> WorkoutLog {
        func log(for exercise: ExerciseDefinition, swappedFrom: String?) -> ExerciseLog? {
            let list = completedSets[exercise.id] ?? []
            guard !list.isEmpty else { return nil }
            var entry = ExerciseLog(
                exerciseID: exercise.id,
                exerciseName: exercise.loggedName,
                repMinAtTime: exercise.repMin,
                repMaxAtTime: exercise.repMax,
                weightIncrementKgAtTime: exercise.weightIncrementKg,
                sets: list,
                category: exercise.category,
                swappedFromName: swappedFrom
            )
            entry.load = exercise.load
            entry.variation = variations?[exercise.id]
            return entry
        }

        var exerciseLogs: [ExerciseLog] = []
        var included = Set<UUID>()
        for item in routine.exercises {
            if let retiredHere = retiredExercises?.filter({ retired in
                plannedExercise(for: item).withAlternatives.contains { $0.id == retired.id }
            }) {
                for retired in retiredHere where !included.contains(retired.id) {
                    let planned = plannedExercise(for: item)
                    if let entry = log(for: retired, swappedFrom: retired.id == planned.id ? nil : planned.name) {
                        exerciseLogs.append(entry)
                        included.insert(retired.id)
                    }
                }
            }
            if !included.contains(item.exercise.id),
               let entry = log(for: item.exercise, swappedFrom: swappedFrom(item)?.name) {
                exerciseLogs.append(entry)
                included.insert(item.exercise.id)
            }
        }
        for retired in retiredExercises ?? [] where !included.contains(retired.id) {
            if let entry = log(for: retired, swappedFrom: nil) {
                exerciseLogs.append(entry)
                included.insert(retired.id)
            }
        }

        return WorkoutLog(
            id: workoutID,
            routineID: routine.id,
            routineName: routine.name,
            startedAt: startedAt,
            endedAt: endedAt,
            exercises: exerciseLogs,
            activeCaloriesKcal: activeCalories,
            averageHeartRateBPM: averageHeartRate,
            maxHeartRateBPM: maxHeartRate,
            isDeload: isDeload,
            phaseName: phaseName
        ).withTarget(targetRIR).withTags(sessionTags)
    }
}

extension WorkoutLog {
    func withTarget(_ rir: Int?) -> WorkoutLog {
        var copy = self
        copy.targetRIR = rir
        return copy
    }

    func withTags(_ tags: [SessionTag]?) -> WorkoutLog {
        var copy = self
        copy.sessionTags = (tags?.isEmpty ?? true) ? nil : tags
        return copy
    }
}
