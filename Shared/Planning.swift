import Foundation

// MK9: equipment, per-set targets, time budget, week planning, coach follow-ups, weekly review,
// and history corrections. Shared by iPhone, Watch and the checks.

// MARK: - Equipment

/// How the number you type relates to the load on that machine.
public enum LoadConvention: String, Codable, CaseIterable, Identifiable {
    case total, perSide, perHand, stackLevel
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .total: return "Total weight"
        case .perSide: return "Per side (plate-loaded)"
        case .perHand: return "Per hand (dumbbells)"
        case .stackLevel: return "Pin-stack level"
        }
    }

    /// Short unit shown after a number.
    public var unit: String {
        switch self {
        case .total: return "kg"
        case .perSide: return "kg/side"
        case .perHand: return "kg each"
        case .stackLevel: return "lvl"
        }
    }

    /// From the typed number to total kg moved (0 = unknown, kept out of volume totals).
    public var volumeMultiplier: Double {
        switch self {
        case .total: return 1
        case .perSide, .perHand: return 2
        case .stackLevel: return 0
        }
    }

    /// "80 kg", "20 kg/side", "level 7".
    public func format(_ value: Double) -> String {
        self == .stackLevel ? "level \(GFFormat.kg(value))" : "\(GFFormat.kg(value)) \(unit)"
    }
}

public extension ExerciseDefinition {
    /// The machine / brand, if set ("Hammer Strength").
    var equipmentName: String? {
        let trimmed = (equipment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Name used in history, so each machine keeps its own history: "Chest Press (Hammer Strength)".
    var loggedName: String { equipmentName.map { "\(name) (\($0))" } ?? name }

    var loadConvention: LoadConvention { load ?? .total }

    /// Push-ups etc.: no weight to type (a weight step of 0 marks it).
    var isBodyweight: Bool { !isCardio && weightIncrementKg <= 0 }

    func formatLoad(_ value: Double) -> String {
        if isBodyweight && value <= 0 { return "bodyweight" }
        return (isAssisted ? "\(GFFormat.kg(value)) kg assist" : loadConvention.format(value))
    }
}

public extension WorkoutSetLog {
    /// Like `summaryText`, with the machine's unit ("20 kg/side × 8", "level 7 × 10").
    func summary(load: LoadConvention?) -> String {
        guard let load, load != .total, !isCardio else { return summaryText }
        let effort = rir.map { $0 >= 3 ? " · 3+ left" : " · \($0) left" } ?? ""
        return "\(load.format(weightKg)) × \(reps)" + effort
    }
}

public extension ExerciseLog {
    func summary(_ set: WorkoutSetLog) -> String { set.summary(load: load) }
}

// MARK: - Per-set targets

public struct SetTarget: Hashable {
    public var weightKg: Double
    public var reps: Int
    /// MK10: reps to leave in the tank (nil = no target).
    public var rir: Int?
    public init(weightKg: Double, reps: Int, rir: Int? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
    }
}

/// Today's target for every set (same weight on every set), with the reason in plain words.
public struct SetPlan: Hashable {
    public var targets: [SetTarget]
    public var reason: String
    /// Set when a set went clearly better or worse than planned and the rest were re-aimed.
    public var adjustment: String?
    /// MK10: a lighter (or more assisted) weight suggested after a set fell short — you choose.
    public var suggestedWeightKg: Double?

    public init(targets: [SetTarget], reason: String, adjustment: String? = nil) {
        self.targets = targets
        self.reason = reason
        self.adjustment = adjustment
    }

    /// Target for set `index` (extra sets beyond the plan reuse the last one).
    public func target(at index: Int) -> SetTarget? {
        guard !targets.isEmpty else { return nil }
        return targets[Swift.min(Swift.max(index, 0), targets.count - 1)]
    }

    /// "80 kg × 10 · 10 · 9"
    public func compactText(for exercise: ExerciseDefinition) -> String {
        guard let first = targets.first else { return "" }
        let reps = targets.map { "\($0.reps)" }.joined(separator: " · ")
        let sameWeight = targets.allSatisfy { abs($0.weightKg - first.weightKg) < 0.001 }
        if first.weightKg <= 0 && !exercise.isBodyweight { return "Find your weight · reps \(reps)" }
        if sameWeight { return "\(exercise.formatLoad(first.weightKg)) × \(reps)" }
        return targets.map { "\(exercise.formatLoad($0.weightKg)) × \($0.reps)" }.joined(separator: ", ")
    }

    /// Re-aims the sets after set `index` from how that set actually went.
    public func adjusted(afterSet index: Int, done: [WorkoutSetLog], exercise: ExerciseDefinition) -> SetPlan {
        guard !exercise.isCardio, index >= 0, index < done.count, index + 1 < targets.count,
              let planned = target(at: index) else { return self }
        let actual = done[index]
        var result = self
        let step = exercise.weightIncrementKg > 0 ? exercise.weightIncrementKg : 2.5
        let weight = actual.weightKg   // carry what you're really using today
        var reps = Array(targets[(index + 1)...]).map(\.reps)
        let deficit = planned.reps - actual.reps
        var note = adjustment
        result.suggestedWeightKg = nil

        if planned.weightKg > 0, abs(actual.weightKg - planned.weightKg) > 0.001 {
            note = "Using \(exercise.formatLoad(weight)) from set \(index + 1) for the rest."
        }
        if deficit >= 2 {
            if actual.reps < exercise.repMin, !exercise.isBodyweight {
                // Suggest, don't change: you decide whether to drop the weight.
                let lighter = exercise.isAssisted ? weight + step : Swift.max(0, weight - step)
                result.suggestedWeightKg = lighter
                note = "Set \(index + 1) was \(actual.reps) (aim \(planned.reps)). "
                    + (exercise.isAssisted ? "Suggest more assistance" : "Suggest one step lighter")
                    + " — \(exercise.formatLoad(lighter)) — to keep the rest in \(exercise.repMin)–\(exercise.repMax). Or keep the weight."
            } else {
                reps = reps.map { Swift.max(exercise.repMin, $0 - (deficit - 1)) }
                note = "Set \(index + 1) was \(deficit) short — same weight, aim "
                    + reps.map { "\($0)" }.joined(separator: " · ") + " on the rest."
            }
        } else if deficit <= -2 {
            reps = reps.map { Swift.min(exercise.repMax, $0 + 1) }
            note = "Strong set \(index + 1) — one more rep on the rest."
        }
        for (offset, value) in reps.enumerated() {
            result.targets[index + 1 + offset].weightKg = weight
            result.targets[index + 1 + offset].reps = value
        }
        result.adjustment = note
        return result
    }
}

public extension ProgressionEngine {
    /// Reps usually lost from one set to the next at the same weight (recent sessions, 0–3, default 1).
    static func typicalDropPerSet(_ logs: [ExerciseLog]) -> Double {
        var drops: [Double] = []
        for log in logs.suffix(4) {
            let top = log.isAssisted ? (log.leastAssistanceKg ?? 0) : log.bestWeightKg
            let working = log.sets.filter { abs($0.weightKg - top) < 0.001 && $0.reps > 0 }
            guard working.count >= 2, let first = working.first?.reps, let last = working.last?.reps else { continue }
            drops.append(Double(first - last) / Double(working.count - 1))
        }
        guard !drops.isEmpty else { return 1 }
        return Swift.min(Swift.max(drops.reduce(0, +) / Double(drops.count), 0), 3)
    }

    /// Same weight on every set; reps per set from last time and how much you usually drop off.
    static func setPlan(for exercise: ExerciseDefinition, previous: ExerciseLog?, recent: [ExerciseLog]) -> SetPlan {
        let advice = Self.recommendation(for: exercise, previous: previous)
        guard !exercise.isCardio else { return SetPlan(targets: [], reason: advice.message) }
        let count = Swift.max(exercise.defaultSets, 1)
        let drop = typicalDropPerSet(recent)
        let range = "\(exercise.repMin)–\(exercise.repMax)"

        func ladder(_ weight: Double) -> [SetTarget] {
            let first = Swift.min(exercise.repMax, exercise.repMin + Int((drop * Double(count - 1)).rounded()))
            return (0..<count).map { index in
                SetTarget(weightKg: weight, reps: Swift.max(exercise.repMin, first - Int((drop * Double(index)).rounded())))
            }
        }
        func joined(_ values: [Int]) -> String { values.map { "\($0)" }.joined(separator: "/") }
        let dropNote = drop >= 0.5 ? " Your sets usually drop about \(Int(drop.rounded())) rep\(Int(drop.rounded()) == 1 ? "" : "s") each, so later sets aim a little lower." : ""

        // Bodyweight (no weight to add): at the top of the range, stay there rather than "add 2.5 kg".
        if exercise.isBodyweight, (previous?.bestWeightKg ?? 0) <= 0, advice.title == "Top of the range" {
            return SetPlan(targets: (0..<count).map { _ in SetTarget(weightKg: 0, reps: exercise.repMax) },
                           reason: "You hit \(exercise.repMax) on every set — hold it there, slow the reps down, or move to a harder variation.")
        }

        switch advice.action {
        case .noHistory, .cardio:
            let targets = (0..<count).map { _ in SetTarget(weightKg: 0, reps: exercise.repMin) }
            let text = exercise.isBodyweight
                ? "First time: do \(range) good reps on every set."
                : "First time: find a weight you can do \(range) times with good form, then keep it for every set."
            return SetPlan(targets: targets, reason: text)

        case .increaseWeight(let kg):
            let was = previous.map { exercise.isAssisted ? ($0.leastAssistanceKg ?? 0) : $0.bestWeightKg } ?? 0
            let text: String
            if advice.title == "New rep range" {
                text = advice.message + dropNote
            } else if advice.title == "Felt easy — go up" {
                text = "Every set had 3+ reps left last time, so it goes up to \(exercise.formatLoad(kg)) (was \(exercise.formatLoad(was))).\(dropNote)"
            } else if exercise.isAssisted {
                text = "You hit \(exercise.repMax) on every set last time, so less help: \(exercise.formatLoad(kg)) (was \(exercise.formatLoad(was))). Reps restart near \(exercise.repMin) and build back up.\(dropNote)"
            } else {
                text = "You hit \(exercise.repMax) on every set last time, so it goes up to \(exercise.formatLoad(kg)) (was \(exercise.formatLoad(was))). Reps restart near \(exercise.repMin) and build back up.\(dropNote)"
            }
            return SetPlan(targets: ladder(kg), reason: text)

        case .reduceWeight(let kg):
            let text = (advice.title == "New rep range")
                ? advice.message + dropNote
                : (exercise.isAssisted
                   ? "Every set fell short of \(exercise.repMin) last time, so more help today: \(exercise.formatLoad(kg)). Build back into \(range).\(dropNote)"
                   : "Every set fell short of \(exercise.repMin) last time, so a step lighter: \(exercise.formatLoad(kg)). Build back into \(range).\(dropNote)")
            return SetPlan(targets: ladder(kg), reason: text)

        case .keepWeight:
            guard let previous, !previous.sets.isEmpty else { return SetPlan(targets: ladder(0), reason: advice.message) }
            let weight = exercise.isAssisted ? (previous.leastAssistanceKg ?? previous.bestWeightKg) : previous.bestWeightKg
            var reps = previous.sets.filter { abs($0.weightKg - weight) < 0.001 && $0.reps > 0 }.map(\.reps)
            if reps.isEmpty { reps = [exercise.repMin] }
            while reps.count < count { reps.append(Swift.max(exercise.repMin, (reps.last ?? exercise.repMin) - Int(drop.rounded()))) }
            reps = Array(reps.prefix(count))
            let last = reps
            var added = 0
            // MK10.1: last time was lopsided (e.g. 9·9·6) — even the sets out with one more rep in total.
            if reps.count >= 2, let first = reps.first, let lastReps = reps.last, first - lastReps >= 3,
               reps.allSatisfy({ $0 < exercise.repMax }) {
                let total = reps.reduce(0, +) + 1
                let even = SetComparison.evenTargets(total: total, sets: reps.count)
                    .map { Swift.min(exercise.repMax, Swift.max(exercise.repMin, $0)) }
                return SetPlan(targets: even.map { SetTarget(weightKg: weight, reps: $0) },
                               reason: "Last time: \(joined(last)) at \(exercise.formatLoad(weight)) — the last set dropped off. Even it out: aim \(joined(even)), one more rep overall. Rest a little longer before the last set.")
            }
            if reps.allSatisfy({ $0 >= exercise.repMax }) {
                reps = reps.map { _ in exercise.repMax }
            } else {
                // Two more reps in total: one on each of the weakest sets.
                let order = reps.indices.sorted { reps[$0] < reps[$1] || (reps[$0] == reps[$1] && $0 > $1) }
                for index in order where added < 2 && reps[index] < exercise.repMax {
                    reps[index] += 1
                    added += 1
                }
            }
            let targets = reps.map { SetTarget(weightKg: weight, reps: $0) }
            let text: String
            if added == 0 {
                text = "Last time: \(joined(last)) at \(exercise.formatLoad(weight)), last set to failure. Repeat it with a rep in the tank on every set — then it goes up."
            } else {
                text = "Last time: \(joined(last)) at \(exercise.formatLoad(weight)). Same weight on every set, aim \(joined(reps)) — \(added) more rep\(added == 1 ? "" : "s") than last time.\(dropNote)"
            }
            return SetPlan(targets: targets, reason: text)
        }
    }
}

public extension ActiveWorkoutState {
    /// Today's per-set plan for an exercise, re-aimed after any set that went clearly better or worse.
    func setPlan(for item: RoutineExercise, logs: [WorkoutLog]) -> SetPlan {
        let exercise = item.exercise
        // MK17: aim from the last session done the same way as today (wide grip vs wide grip), if there is one.
        let todayWay = ExerciseLog.key(for: variations?[exercise.id] ?? "")
        let previous = logs.previousLog(where: { $0.matches(exercise) && $0.variationKey == todayWay }, before: startedAt)
            ?? logs.previousLog(for: exercise, before: startedAt)
        let earlier = logs.history(for: exercise).filter { $0.date < startedAt }.map(\.log)
        let sameWay = earlier.filter { $0.variationKey == todayWay }
        let recent = sameWay.isEmpty ? earlier : sameWay
        var plan = ProgressionEngine.setPlan(for: exercise, previous: previous, recent: Array(recent.suffix(4)))
        // MK10: effort target for every working set (isolation: the last set goes one rep closer).
        if let rir = targetRIR ?? (deload ? 4 : nil), !exercise.isCardio, !plan.targets.isEmpty {
            let isolation = ExerciseLibrary.profile(for: exercise.name)?.kind == .isolation
            for index in plan.targets.indices {
                let last = index == plan.targets.count - 1
                plan.targets[index].rir = (isolation && last && rir > 0 && rir < 4) ? rir - 1 : rir
            }
        }
        if deload, !exercise.isCardio {
            let step = exercise.weightIncrementKg > 0 ? exercise.weightIncrementKg : 2.5
            plan.targets = plan.targets.map { target in
                guard target.weightKg > 0 else { return target }
                var light = target
                light.weightKg = exercise.isAssisted
                    ? ((target.weightKg * 1.1) / step).rounded(.up) * step   // lighter session = MORE help
                    : ProgramPhase.deloadWeight(target.weightKg, increment: exercise.weightIncrementKg)
                return light
            }
            plan.reason = "Light session: about 10% easier and one less set — it won't affect progression. " + plan.reason
        }
        let done = sets(for: item)
        for index in done.indices {
            plan = plan.adjusted(afterSet: index, done: done, exercise: exercise)
        }
        return plan
    }
}

// MARK: - Time budget

public enum TimeBudget {
    /// Big multi-joint lifts get kept first.
    public static func isCompound(_ name: String) -> Bool {
        let n = name.lowercased()
        let words = ["bench", "press", "squat", "deadlift", "rdl", "row", "pull-up", "pull up", "pulldown",
                     "chin", "dip", "lunge", "hip thrust", "split squat", "clean", "push-up", "push up"]
        return words.contains { n.contains($0) } && !n.contains("leg extension") && !n.contains("curl")
    }

    /// Seconds for one superset group (or a single exercise) with the given set counts.
    static func seconds(for items: [RoutineExercise], sets: [Int]) -> Double {
        var total = 0.0
        for (item, count) in zip(items, sets) where item.exercise.isCardio {
            total += count > 0 ? Double(item.exercise.cardioMinutes * 60 + 60) : 0
        }
        let lifts = zip(items, sets).filter { !$0.0.exercise.isCardio && $0.1 > 0 }
        guard !lifts.isEmpty else { return total }
        let rounds = lifts.map(\.1).max() ?? 0
        let rest = Double(lifts.last?.0.exercise.restSeconds ?? 90)
        for round in 0..<rounds {
            total += Double(lifts.filter { $0.1 > round }.count) * 45
            if round < rounds - 1 { total += rest }
        }
        return total + Double(lifts.count) * 75   // set-up / walking between machines
    }

    private static func groups(_ state: ActiveWorkoutState) -> [[Int]] {
        var result: [[Int]] = []
        var index = 0
        while index < state.routine.exercises.count {
            let group = state.supersetGroup(of: index)
            result.append(group)
            index = (group.last ?? index) + 1
        }
        return result
    }

    /// Estimated minutes for what's planned (skipped exercises excluded).
    public static func estimateMinutes(_ state: ActiveWorkoutState) -> Int {
        var total = 0.0
        for group in groups(state) {
            let items = group.map { state.routine.exercises[$0] }
            let counts = items.map { state.isSkipped($0) ? 0 : $0.exercise.defaultSets }
            total += seconds(for: items, sets: counts)
        }
        return Swift.max(Int((total / 60).rounded()), 1)
    }

    /// Trims the plan to fit `minutes`: sets come off the least important exercises first (down to 2,
    /// then 1), and only then are whole exercises skipped. Superset partners are trimmed and dropped together.
    public static func fit(_ state: ActiveWorkoutState, minutes: Int,
                           priority: (RoutineExercise) -> Double) -> (state: ActiveWorkoutState, cuts: [String]) {
        var result = state
        let budget = Double(minutes) * 60
        let allGroups = groups(state).filter { group in !group.allSatisfy { state.isSkipped(state.routine.exercises[$0]) } }
        guard !allGroups.isEmpty else { return (state, []) }

        var counts: [Int: Int] = [:]
        for group in allGroups { for index in group { counts[index] = state.routine.exercises[index].exercise.defaultSets } }
        var dropped = Set<Int>()   // group positions in allGroups

        func total() -> Double {
            allGroups.enumerated().reduce(0.0) { sum, entry in
                guard !dropped.contains(entry.offset) else { return sum }
                let items = entry.element.map { state.routine.exercises[$0] }
                return sum + seconds(for: items, sets: entry.element.map { counts[$0] ?? 0 })
            }
        }
        let groupPriority: [Double] = allGroups.map { group in
            group.map { priority(state.routine.exercises[$0]) }.max() ?? 0
        }
        // Least important first.
        let order = allGroups.indices.sorted { groupPriority[$0] < groupPriority[$1] || (groupPriority[$0] == groupPriority[$1] && $0 > $1) }

        for minimum in [2, 1] {
            var changed = true
            while total() > budget && changed {
                changed = false
                for position in order where !dropped.contains(position) {
                    let lifts = allGroups[position].filter { !state.routine.exercises[$0].exercise.isCardio && (counts[$0] ?? 0) > minimum }
                    guard !lifts.isEmpty else { continue }
                    for index in lifts { counts[index] = (counts[index] ?? 1) - 1 }
                    changed = true
                    break
                }
            }
        }
        // Still over: skip whole exercises (never the most important one).
        for position in order.dropLast() where total() > budget {
            dropped.insert(position)
        }

        var cuts: [String] = []
        for (position, group) in allGroups.enumerated() {
            for index in group {
                let item = state.routine.exercises[index]
                if dropped.contains(position) {
                    var skipped = result.skippedItems ?? []
                    if !skipped.contains(item.id) { skipped.append(item.id) }
                    result.skippedItems = skipped
                    cuts.append("\(item.exercise.name): skipped")
                } else if let newCount = counts[index], newCount < item.exercise.defaultSets {
                    result.routine.exercises[index].exercise.defaultSets = newCount
                    cuts.append("\(item.exercise.name): \(item.exercise.defaultSets) → \(newCount) set\(newCount == 1 ? "" : "s")")
                }
            }
        }
        if let current = result.currentItem, result.isSkipped(current),
           let next = result.nextUnfinishedIndex(after: result.exerciseIndex) {
            result.exerciseIndex = next
            result.setIndex = 0
        }
        result.revision += 1
        return (result, cuts)
    }
}

// MARK: - Week planning

public enum DayPlanKind: String, Codable, CaseIterable, Identifiable {
    case workout, ill, travel
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .workout: return "Workout"
        case .ill: return "Sick"
        case .travel: return "Travel"
        }
    }
    /// Sick and travel days lower the week's goal and stand Sergeant Cluck down.
    public var isExcused: Bool { self != .workout }
}

/// One planned day (rest days use the existing rest-day list).
public struct DayPlan: Codable, Equatable, Identifiable {
    public var day: Date
    public var kind: DayPlanKind
    public var routineID: UUID?
    public var routineName: String?
    public var id: Date { day }

    public init(day: Date, kind: DayPlanKind, routineID: UUID? = nil, routineName: String? = nil) {
        self.day = day
        self.kind = kind
        self.routineID = routineID
        self.routineName = routineName
    }
}

public extension GymExtras {
    func dayPlan(on date: Date, calendar: Calendar = .current) -> DayPlan? {
        dayPlans.last { calendar.isDate($0.day, inSameDayAs: date) }
    }

    func isExcused(_ date: Date, calendar: Calendar = .current) -> Bool {
        dayPlan(on: date, calendar: calendar)?.kind.isExcused ?? false
    }

    /// Sick / travel days in the week containing `date`.
    func excusedDays(inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return dayPlans.filter { $0.kind.isExcused && $0.day >= week.start && $0.day < week.end }.count
    }
}

/// A short no-equipment session for travel days (hotel room, no gym).
public enum TravelWorkout {
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "6A1F0000-0000-4000-8000-%012d", n)) ?? UUID() }

    public static var routine: WorkoutRoutine {
        func bodyweight(_ n: Int, _ name: String, _ category: ExerciseCategory, _ low: Int, _ high: Int) -> RoutineExercise {
            RoutineExercise(id: id(100 + n),
                            exercise: ExerciseDefinition(id: id(n), name: name, category: category, repMin: low, repMax: high,
                                                         defaultSets: 3, restSeconds: 60, weightIncrementKg: 0),
                            order: n)
        }
        return WorkoutRoutine(id: id(0), name: "Hotel Workout", exercises: [
            bodyweight(1, "Push-up", .chest, 10, 25),
            bodyweight(2, "Bodyweight Squat", .legs, 15, 30),
            bodyweight(3, "Pike Push-up", .shoulders, 6, 15),
            bodyweight(4, "Reverse Lunge", .legs, 10, 20),
            bodyweight(5, "Glute Bridge", .legs, 15, 30),
            bodyweight(6, "Plank (seconds)", .core, 30, 60)
        ])
    }
}

// MARK: - Accepted coaching suggestions

public struct CoachSuggestion: Identifiable, Codable, Equatable {
    public enum Kind: String, Codable { case addSet, swap, deload, other }

    public var id: UUID
    public var acceptedAt: Date
    public var exerciseKey: String?
    public var exerciseName: String?
    public var text: String
    public var kind: Kind
    /// Best estimated 1RM (or least assistance) and sets per session when it was accepted.
    public var baselineStrength: Double?
    public var baselineSets: Double?
    public var resolved: Bool

    public init(id: UUID = UUID(), acceptedAt: Date = .now, exerciseKey: String? = nil, exerciseName: String? = nil,
                text: String, kind: Kind, baselineStrength: Double? = nil, baselineSets: Double? = nil) {
        self.id = id
        self.acceptedAt = acceptedAt
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.text = text
        self.kind = kind
        self.baselineStrength = baselineStrength
        self.baselineSets = baselineSets
        self.resolved = false
    }

    public static func kind(for text: String) -> Kind {
        let lower = text.lowercased()
        if lower.contains("deload") || lower.contains("light session") { return .deload }
        if lower.contains("swap") || lower.contains("switch to") || lower.contains("variation") { return .swap }
        if lower.contains("set") && (lower.contains("add") || lower.contains("extra")) { return .addSet }
        return .other
    }
}

// MARK: - Weekly review

public struct MuscleWeek: Identifiable, Equatable {
    public let id: ExerciseCategory
    public let direct: Double
    public let secondary: Double
    public let low: Double
    public let high: Double
    /// Direct sets plus half of the secondary ones.
    public var effective: Double { direct + secondary * 0.5 }
    public var status: String {
        if effective < low { return "Low" }
        if effective > high { return "High" }
        return "On target"
    }
}

public struct SuggestionFollowUp: Identifiable, Equatable {
    public let suggestion: CoachSuggestion
    public let done: Bool
    public let status: String
    public var id: UUID { suggestion.id }
}

public enum WeeklyReviewBuilder {
    /// Muscles that also work hard in an exercise (counted as half a set each).
    public static func secondaryMuscles(name: String, category: ExerciseCategory) -> [ExerciseCategory] {
        let n = name.lowercased()
        let isPress = n.contains("press") || n.contains("push-up") || n.contains("push up") || n.contains("dip")
        switch category {
        case .chest:
            return isPress || n.contains("bench") ? [.triceps, .shoulders] : []
        case .back:
            if n.contains("deadlift") || n.contains("rdl") { return [.legs] }
            return (n.contains("row") || n.contains("pull") || n.contains("chin")) ? [.biceps] : []
        case .shoulders:
            return (n.contains("press") || n.contains("military") || n.contains("arnold")) ? [.triceps] : []
        case .legs:
            if n.contains("deadlift") || n.contains("rdl") || n.contains("good morning") { return [.back] }
            return (n.contains("squat") || n.contains("lunge") || n.contains("leg press")) ? [.core] : []
        case .triceps:
            return (n.contains("close grip") || n.contains("dip")) ? [.chest] : []
        default:
            return []
        }
    }

    public static func targetRange(_ muscle: ExerciseCategory) -> (low: Double, high: Double) {
        switch muscle {
        case .chest, .back, .shoulders, .legs: return (10, 20)
        case .biceps, .triceps: return (6, 14)
        default: return (4, 12)
        }
    }

    public static func muscles(logs: [WorkoutLog], from start: Date, to end: Date,
                               lookup: [String: ExerciseCategory]) -> [MuscleWeek] {
        var direct: [ExerciseCategory: Double] = [:]
        var secondary: [ExerciseCategory: Double] = [:]
        for workout in logs where workout.startedAt >= start && workout.startedAt < end {
            for exercise in workout.exercises where !exercise.isCardio {
                let category = exercise.category ?? lookup[ExerciseLog.key(for: exercise.exerciseName)]
                    ?? ExerciseCategory.guess(from: exercise.exerciseName)
                guard category != .cardio, category != .other else { continue }
                let count = Double(exercise.sets.count)
                if let profile = ExerciseLibrary.profile(for: exercise.exerciseName), !profile.muscles.isEmpty {
                    // From the exercise library: biggest share per muscle group (1 = direct, 0.5 = secondary).
                    var share: [ExerciseCategory: Double] = [:]
                    for (muscle, value) in profile.muscles { share[muscle.category] = Swift.max(share[muscle.category] ?? 0, value) }
                    for (group, value) in share {
                        if value >= 1 { direct[group, default: 0] += count } else { secondary[group, default: 0] += count }
                    }
                } else {
                    direct[category, default: 0] += count
                    for other in secondaryMuscles(name: exercise.exerciseName, category: category) {
                        secondary[other, default: 0] += count
                    }
                }
            }
        }
        return ExerciseCategory.muscleGroups.map { muscle in
            let range = targetRange(muscle)
            return MuscleWeek(id: muscle, direct: direct[muscle] ?? 0, secondary: secondary[muscle] ?? 0,
                              low: range.low, high: range.high)
        }
    }

    /// Did you act on an accepted suggestion, and is it working?
    public static func followUp(_ suggestion: CoachSuggestion, logs: [WorkoutLog], now: Date = .now) -> SuggestionFollowUp {
        let since = logs.filter { $0.startedAt >= suggestion.acceptedAt && $0.startedAt <= now }
        let weeks = Swift.max(1, Int(now.timeIntervalSince(suggestion.acceptedAt) / (7 * 86_400)))
        let key = suggestion.exerciseKey

        // A weak-point tip ("muscle:chest"): weekly sets for that muscle since, vs before.
        if let key, key.hasPrefix("muscle:"), let muscle = ExerciseCategory(rawValue: String(key.dropFirst(7))) {
            let sets = since.flatMap(\.exercises).filter { ($0.category ?? ExerciseCategory.guess(from: $0.exerciseName)) == muscle }
                .reduce(0) { $0 + $1.sets.count }
            let elapsedWeeks = Swift.max(1, now.timeIntervalSince(suggestion.acceptedAt) / (7 * 86_400))
            let perWeek = Double(sets) / elapsedWeeks
            let base = suggestion.baselineSets ?? 0
            let done = perWeek >= base + 1.5
            return SuggestionFollowUp(suggestion: suggestion, done: done,
                                      status: String(format: "Accepted %d week%@ ago — %@: %.0f sets/week (was %.0f).",
                                                     weeks, weeks == 1 ? "" : "s", muscle.title, perWeek, base))
        }
        let matching = since.compactMap { workout in workout.exercises.first { key != nil && ExerciseLog.key(for: $0.exerciseName) == key } }
        let ageText = "Accepted \(weeks) week\(weeks == 1 ? "" : "s") ago"

        switch suggestion.kind {
        case .deload:
            let done = since.contains { $0.isDeload == true }
            return SuggestionFollowUp(suggestion: suggestion, done: done,
                                      status: done ? "\(ageText) — light session done." : "\(ageText) — no light session yet.")
        case .swap:
            let name = suggestion.exerciseName ?? ""
            let swapped = since.flatMap(\.exercises).contains { $0.swappedFromName == name }
                || (!since.isEmpty && matching.isEmpty)
            return SuggestionFollowUp(suggestion: suggestion, done: swapped,
                                      status: swapped ? "\(ageText) — you've switched it up." : "\(ageText) — still doing the same exercise.")
        case .addSet:
            guard !matching.isEmpty else {
                return SuggestionFollowUp(suggestion: suggestion, done: false, status: "\(ageText) — not trained since.")
            }
            let average = Double(matching.reduce(0) { $0 + $1.sets.count }) / Double(matching.count)
            let base = suggestion.baselineSets ?? 0
            let done = average > base + 0.5
            return SuggestionFollowUp(suggestion: suggestion, done: done,
                                      status: String(format: "%@ — %.1f sets/session (was %.1f).", ageText, average, base))
        case .other:
            guard !matching.isEmpty else {
                return SuggestionFollowUp(suggestion: suggestion, done: false, status: "\(ageText) — not trained since.")
            }
            if let base = suggestion.baselineStrength, base > 0 {
                let assisted = matching.first?.isAssisted ?? false
                let current = assisted ? (matching.compactMap(\.leastAssistanceKg).min() ?? base)
                                       : (matching.map(\.estimatedOneRepMaxKg).max() ?? base)
                let change = assisted ? (base - current) / base * 100 : (current / base - 1) * 100
                return SuggestionFollowUp(suggestion: suggestion, done: true,
                                          status: String(format: "%@ — %d session%@ since, strength %+.0f%%.", ageText,
                                                         matching.count, matching.count == 1 ? "" : "s", change))
            }
            return SuggestionFollowUp(suggestion: suggestion, done: true,
                                      status: "\(ageText) — \(matching.count) session\(matching.count == 1 ? "" : "s") since.")
        }
    }
}

// MARK: - History corrections

/// Running bests per exercise while re-marking PRs (top level: Swift doesn't allow a type
/// nested inside a function of a generic extension).
struct PRBests {
    var heaviest = 0.0
    var e1rm = 0.0
    var leastAssist: Double?
    var hasHistory = false
}

public extension Array where Element == WorkoutLog {
    /// Re-marks every set's PR flag from scratch, oldest first — after editing a past workout
    /// or adding a missed one. Same rules as during a workout (deload sessions never set PRs).
    func recomputingPRs() -> [WorkoutLog] {
        var bests: [String: PRBests] = [:]
        var updated: [UUID: WorkoutLog] = [:]
        // Same exercise under a new name (e.g. a machine was added): keep one history, like the live check.
        var aliases: [UUID: String] = [:]
        for var workout in self.sorted(by: { $0.startedAt < $1.startedAt }) {
            for e in workout.exercises.indices {
                var exercise = workout.exercises[e]
                let key = aliases[exercise.exerciseID] ?? ExerciseLog.key(for: exercise.exerciseName)
                aliases[exercise.exerciseID] = key
                var best = bests[key] ?? PRBests()
                let deload = workout.isDeload == true
                for s in exercise.sets.indices {
                    let set = exercise.sets[s]
                    var pr = false
                    if exercise.isCardio {
                        pr = false
                    } else if exercise.isAssisted {
                        if set.reps >= exercise.repMinAtTime {
                            if !deload, let least = best.leastAssist, set.weightKg < least - 0.001 { pr = true }
                            best.leastAssist = Swift.min(best.leastAssist ?? set.weightKg, set.weightKg)
                        }
                    } else if set.reps > 0, set.weightKg > 0 {
                        if !deload, best.hasHistory,
                           set.weightKg > best.heaviest + 0.001 || set.estimatedOneRepMaxKg > best.e1rm + 0.001 {
                            pr = true
                        }
                        best.heaviest = Swift.max(best.heaviest, set.weightKg)
                        best.e1rm = Swift.max(best.e1rm, set.estimatedOneRepMaxKg)
                    }
                    exercise.sets[s].isPR = pr ? true : nil
                }
                if !exercise.sets.isEmpty { best.hasHistory = true }
                bests[key] = best
                workout.exercises[e] = exercise
            }
            updated[workout.id] = workout
        }
        return self.map { updated[$0.id] ?? $0 }
    }
}
