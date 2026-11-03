import Foundation

// "More Training" — a private section with its own encrypted storage.
// Nothing here is synced to the Watch, written to Apple Health, backed up, or used elsewhere in the app.
// Fields added after mk4 are Optionals so older saved data still loads.

enum MTType: String, Codable, CaseIterable, Identifiable {
    case allDayStretcher, highTensionExtender, pump, clamp, pac
    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDayStretcher: return "All Day Stretcher"
        case .highTensionExtender: return "High Tension Extender"
        case .pump: return "Pump"
        case .clamp: return "Clamp"
        case .pac: return "PAC"
        }
    }

    var shortTitle: String {
        switch self {
        case .allDayStretcher: return "ADS"
        case .highTensionExtender: return "HTE"
        case .pump: return "Pump"
        case .clamp: return "Clamp"
        case .pac: return "PAC"
        }
    }

    var symbol: String {
        switch self {
        case .allDayStretcher: return "stopwatch"
        case .highTensionExtender: return "arrow.left.and.right"
        case .pump: return "gauge.with.dots.needle.33percent"
        case .clamp: return "lock"
        case .pac: return "circle.circle"
        }
    }

    /// Pump and PAC log vacuum pressure.
    var usesPressure: Bool { self == .pump || self == .pac }
    /// High Tension Extender logs tension.
    var usesTension: Bool { self == .highTensionExtender }
    /// Types that can run as an interval timer / preset step.
    static var timed: [MTType] { allCases.filter { $0 != .allDayStretcher } }
}

/// Phallosan Forte tension levels.
enum MTLevel: String, Codable, CaseIterable, Identifiable {
    case green, highGreen, yellow, red
    var id: String { rawValue }
    /// Daily-goal weighting: an hour on Red counts as 3 green hours.
    var weight: Double {
        switch self {
        case .green: return 1
        case .highGreen, .yellow: return 1.5
        case .red: return 3
        }
    }

    var title: String {
        switch self {
        case .green: return "Green"
        case .highGreen: return "High Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        }
    }
}

enum MTWarning: String, Codable, CaseIterable, Identifiable {
    case discoloration, redSpots, numbness, pain, swelling, weakErections, skinIrritation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discoloration: return "Discoloration"
        case .redSpots: return "Red spots (petechiae)"
        case .numbness: return "Numbness / tingling / cold"
        case .pain: return "Pain"
        case .swelling: return "Swelling that lasts to the next session"
        case .weakErections: return "Weaker erections"
        case .skinIrritation: return "Irritated skin / blisters"
        }
    }
    /// Signs that mean "rest now" rather than "watch it".
    var isSerious: Bool { [.numbness, .pain, .swelling, .weakErections, .skinIrritation].contains(self) }
}

struct MTSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: MTType
    var start: Date
    var end: Date
    var notes: String?
    var pressureInHg: Double?
    /// Stored in kg.
    var tensionKg: Double?
    var level: MTLevel?
    var rounds: Int?
    /// Time under work for interval sessions (excludes rests). nil = end − start.
    var workSeconds: Double?
    var warnings: [MTWarning]?
    /// MK18: extending done with NIR.
    var nir: Bool?
    /// MK18: expansion straight after the session, % (girth after pump / PAC, stretched length after extending).
    var expansionPercent: Double?

    var duration: TimeInterval { workSeconds ?? max(0, end.timeIntervalSince(start)) }
    var warningList: [MTWarning] { warnings ?? [] }
}

/// A plain timed session in progress (no intervals).
struct MTActiveSession: Codable, Hashable {
    var type: MTType
    var start: Date
    var pressureInHg: Double?
    var tensionKg: Double?
    var nir: Bool?
}

// MARK: - Intervals & presets

struct MTPresetStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var type: MTType
    var rounds: Int
    var workMinutes: Double
    var restMinutes: Double
    var pressureInHg: Double?
    var tensionKg: Double?
    /// MK18: extending with NIR.
    var nir: Bool?
    /// MK18.2: what to do in this step (guided PAC: vacuum and clamp settings). Shown in the app only, never on the Lock Screen.
    var cue: String?

    var summary: String {
        let work = MTStats.minutesText(workMinutes)
        let label = type.shortTitle + (nir == true ? " + NIR" : "")
        if rounds <= 1 { return "\(label) \(work)" }
        return "\(label) \(rounds)×\(work), \(MTStats.minutesText(restMinutes)) rest"
    }
}

struct MTPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var steps: [MTPresetStep]

    var summary: String { steps.map(\.summary).joined(separator: " → ") }
    var totalMinutes: Double {
        steps.reduce(0) { $0 + Double($1.rounds) * $1.workMinutes + Double(max($1.rounds - 1, 0)) * $1.restMinutes }
    }
}

struct MTPhase: Codable, Hashable {
    enum Kind: String, Codable { case work, rest }
    var stepIndex: Int
    var round: Int
    var kind: Kind
    var seconds: Double
}

/// An interval program in progress. Phases are flattened; times are wall-clock so it survives the app closing.
struct MTActiveInterval: Codable, Hashable {
    var name: String
    var steps: [MTPresetStep]
    var phases: [MTPhase]
    var index: Int
    var phaseStartedAt: Date
    /// Set while paused: seconds left in the current phase.
    var pausedRemaining: Double?
    /// When each step's first work phase started.
    var stepStarts: [Int: Date]
    /// Completed work seconds per step.
    var workDone: [Int: Double]

    var currentPhase: MTPhase? { index < phases.count ? phases[index] : nil }
    var isPaused: Bool { pausedRemaining != nil }

    func phaseEnd() -> Date? {
        guard let phase = currentPhase, pausedRemaining == nil else { return nil }
        return phaseStartedAt.addingTimeInterval(phase.seconds)
    }

    func remaining(at now: Date) -> Double {
        if let pausedRemaining { return pausedRemaining }
        guard let end = phaseEnd() else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    static func build(name: String, steps: [MTPresetStep], now: Date) -> MTActiveInterval {
        var phases: [MTPhase] = []
        for (stepIndex, step) in steps.enumerated() {
            let rounds = max(step.rounds, 1)
            for round in 1...rounds {
                phases.append(MTPhase(stepIndex: stepIndex, round: round, kind: .work, seconds: max(step.workMinutes, 0.1) * 60))
                let isLast = stepIndex == steps.count - 1 && round == rounds
                if !isLast, step.restMinutes > 0 {
                    phases.append(MTPhase(stepIndex: stepIndex, round: round, kind: .rest, seconds: step.restMinutes * 60))
                }
            }
        }
        return MTActiveInterval(name: name, steps: steps, phases: phases, index: 0, phaseStartedAt: now,
                                pausedRemaining: nil, stepStarts: [0: now], workDone: [:])
    }
}

// MARK: - Measurements, photos, check-ins

enum MTUnit: String, Codable, CaseIterable, Identifiable {
    case cm, inch
    var id: String { rawValue }
    var label: String { self == .cm ? "cm" : "in" }
    func display(_ cm: Double) -> Double { self == .cm ? cm : cm / 2.54 }
    func toCM(_ value: Double) -> Double { self == .cm ? value : value * 2.54 }
}

enum MTWeightUnit: String, Codable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    func display(_ kg: Double) -> Double { self == .kg ? kg : kg / 0.45359237 }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value * 0.45359237 }
}

enum MTMetric: String, CaseIterable, Identifiable {
    case bpel, bpfsl, nbpl, mg, bg
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var detail: String {
        switch self {
        case .bpel: return "Bone-pressed erect length"
        case .bpfsl: return "Bone-pressed flaccid stretched length"
        case .nbpl: return "Non-bone-pressed length"
        case .mg: return "Mid-shaft girth"
        case .bg: return "Base girth"
        }
    }
}

/// All values stored in centimetres.
struct MTMeasurement: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var bpel: Double?
    var bpfsl: Double?
    var nbpl: Double?
    var mg: Double?
    var bg: Double?
    var notes: String?

    func value(_ metric: MTMetric) -> Double? {
        switch metric {
        case .bpel: return bpel
        case .bpfsl: return bpfsl
        case .nbpl: return nbpl
        case .mg: return mg
        case .bg: return bg
        }
    }

    mutating func set(_ metric: MTMetric, _ value: Double?) {
        switch metric {
        case .bpel: bpel = value
        case .bpfsl: bpfsl = value
        case .nbpl: nbpl = value
        case .mg: mg = value
        case .bg: bg = value
        }
    }
}

struct MTPhoto: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var notes: String?
    /// nil = not in a folder.
    var folderID: UUID?
}

/// A photo album inside the vault, e.g. "Measurement" and "Pump".
struct MTPhotoFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

/// Daily check-in: erection quality 1–5 and morning wood.
struct MTCheckIn: Identifiable, Codable, Hashable {
    var id = UUID()
    var day: Date
    var eq: Int?
    var morningWood: Bool?
}

struct MTSettings: Codable, Hashable {
    var unit: MTUnit = .cm
    var targetDaysPerWeek: Int = 5
    /// Optional time-limit alert per type, in minutes (missing = off).
    var limitMinutes: [String: Int] = [:]
    var tensionUnit: MTWeightUnit?
    /// Measuring reminder every N weeks (nil/0 = off).
    var measureReminderWeeks: Int?
    var ghostOverlay: Bool?
    /// Hours worn before using the app (from the Phallosan log).
    var stretcherBaseHours: Double?
    /// Daily wear goal in green-equivalent hours.
    var stretcherDailyGoal: Double?
    var staminaGoalMinutes: Int?
    var staminaCooldownSeconds: Int?
    var staminaLastWithPorn: Bool?
    /// Goals per measurement (MTMetric raw value → cm), and the value / date when each goal was set.
    var goalsCM: [String: Double]?
    var goalStartCM: [String: Double]?
    var goalStartDates: [String: Date]?
    /// Average to compare against: "herbenick" (self-measured US men, default) or "veale" (clinician-measured).
    var averageReference: String?
    /// MK10.2: quiet "⏱" after 3 days without training (nil = on).
    var trainingNudge: Bool?

    /// MK11.3: daily routine (HTE 3×20 min + pump 2×5 min every day) instead of the PAC every-other-day plan.
    var dailyRoutine: Bool?
    /// Training-days goal from before the daily routine, restored when you switch back.
    var targetDaysBeforeRoutine: Int?

    var dailyRoutineOn: Bool { dailyRoutine ?? false }

    var trainingNudgeOn: Bool {
        get { trainingNudge ?? true }
        set { trainingNudge = newValue }
    }

    var baseHours: Double {
        get { stretcherBaseHours ?? 173 }
        set { stretcherBaseHours = newValue }
    }

    var dailyGoal: Double {
        get { stretcherDailyGoal ?? 6 }
        set { stretcherDailyGoal = newValue }
    }

    var staminaGoal: Int {
        get { staminaGoalMinutes ?? 20 }
        set { staminaGoalMinutes = newValue }
    }

    var cooldownSeconds: Int {
        get { staminaCooldownSeconds ?? 60 }
        set { staminaCooldownSeconds = newValue }
    }

    func limit(for type: MTType) -> Int? {
        guard let minutes = limitMinutes[type.rawValue], minutes > 0 else { return nil }
        return minutes
    }

    var weightUnit: MTWeightUnit {
        get { tensionUnit ?? .kg }
        set { tensionUnit = newValue }
    }

    var reminderWeeks: Int {
        get { measureReminderWeeks ?? 0 }
        set { measureReminderWeeks = newValue }
    }

    var showGhost: Bool {
        get { ghostOverlay ?? true }
        set { ghostOverlay = newValue }
    }
}

struct MTData: Codable {
    var sessions: [MTSession] = []
    var measurements: [MTMeasurement] = []
    var photos: [MTPhoto] = []
    var settings = MTSettings()
    /// All Day Stretcher stopwatch: when the current wear segment started (nil = not wearing).
    var stretcherStartedAt: Date?
    var stretcherLevel: MTLevel?
    var activeSession: MTActiveSession?
    var activeInterval: MTActiveInterval?
    var presets: [MTPreset]?
    var checkIns: [MTCheckIn]?
    var staminaSessions: [MTStaminaSession]?
    var activeStamina: MTActiveStamina?
    /// nil until first opened, then seeded with Measurement + Pump.
    var photoFolders: [MTPhotoFolder]?
    /// Days marked as planned rest (shown grey instead of a red cross).
    var restDays: [Date]?
    /// MK19: sessions still waiting for the after-session measuring screen (kept until it's filled in).
    var pendingReview: [UUID]?

    var restDayList: [Date] {
        get { restDays ?? [] }
        set { restDays = newValue }
    }

    var folderList: [MTPhotoFolder] {
        get { photoFolders ?? [] }
        set { photoFolders = newValue }
    }

    var staminaList: [MTStaminaSession] {
        get { staminaSessions ?? [] }
        set { staminaSessions = newValue }
    }

    var presetList: [MTPreset] {
        get { presets ?? [] }
        set { presets = newValue }
    }

    var checkInList: [MTCheckIn] {
        get { checkIns ?? [] }
        set { checkIns = newValue }
    }

    var isBusy: Bool { activeSession != nil || activeInterval != nil }

    /// Last pressure/tension used for a type (pre-fills the next session).
    func lastPressure(for type: MTType) -> Double? {
        sessions.last { $0.type == type && $0.pressureInHg != nil }?.pressureInHg
    }

    func lastTension(for type: MTType) -> Double? {
        sessions.last { $0.type == type && $0.tensionKg != nil }?.tensionKg
    }
}

// MARK: - Daily routine: see MTPlan (MTProgression.swift)

// MARK: - PAC every other day

enum MTPACStatus: Equatable {
    case neverDone
    case doneToday(next: Date)
    case restDay(next: Date)
    case due(overdueDays: Int)
}

enum MTPACSchedule {
    static let gapDays = 2

    static func lastPACDay(_ sessions: [MTSession], calendar: Calendar = .current) -> Date? {
        sessions.filter { $0.type == .pac }.map { calendar.startOfDay(for: $0.start) }.max()
    }

    static func status(_ sessions: [MTSession], now: Date = .now, calendar: Calendar = .current) -> MTPACStatus {
        let today = calendar.startOfDay(for: now)
        guard let last = lastPACDay(sessions, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: gapDays, to: last) else { return .neverDone }
        if last == today { return .doneToday(next: next) }
        if today < next { return .restDay(next: next) }
        let overdue = calendar.dateComponents([.day], from: next, to: today).day ?? 0
        return .due(overdueDays: overdue)
    }

    /// Planned PAC days from today onwards (today if due), every other day.
    static func plannedDays(_ sessions: [MTSession], through end: Date, now: Date = .now, calendar: Calendar = .current) -> Set<Date> {
        let today = calendar.startOfDay(for: now)
        var next: Date
        switch status(sessions, now: now, calendar: calendar) {
        case .neverDone, .due: next = today
        case .doneToday(let date), .restDay(let date): next = date
        }
        var result = Set<Date>()
        while next <= end {
            result.insert(next)
            guard let following = calendar.date(byAdding: .day, value: gapDays, to: next) else { break }
            next = following
        }
        return result
    }

    /// PAC days done in the last 28 days vs the 14 an every-other-day rhythm would give.
    static func consistency(_ sessions: [MTSession], now: Date = .now, calendar: Calendar = .current) -> (done: Int, planned: Int) {
        let start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: now)) ?? now
        let days = Set(sessions.filter { $0.type == .pac && $0.start >= start }.map { calendar.startOfDay(for: $0.start) })
        return (days.count, 14)
    }
}

// MARK: - Safety

struct MTSafetyAdvice: Identifiable, Hashable {
    enum Level: Int { case watch, rest }
    var id: String { title }
    var level: Level
    var title: String
    var message: String
}

enum MTSafety {
    static func advice(_ data: MTData, now: Date = .now, calendar: Calendar = .current) -> [MTSafetyAdvice] {
        var result: [MTSafetyAdvice] = []
        let twoDays = now.addingTimeInterval(-2 * 86_400)
        let week = now.addingTimeInterval(-7 * 86_400)

        let recentSerious = data.sessions.filter { $0.end >= twoDays && $0.warningList.contains(where: \.isSerious) }
        if !recentSerious.isEmpty {
            let signs = Set(recentSerious.flatMap(\.warningList).filter(\.isSerious)).map(\.title).sorted().joined(separator: ", ")
            result.append(MTSafetyAdvice(level: .rest, title: "Take a rest day",
                                         message: "You logged \(signs.lowercased()) in the last 2 days. Rest until it's fully gone; see a doctor if it doesn't settle."))
        }

        let warnedSessions = data.sessions.filter { $0.end >= week && !$0.warningList.isEmpty }
        if warnedSessions.count >= 2 {
            result.append(MTSafetyAdvice(level: .watch, title: "Consider an easier week",
                                         message: "\(warnedSessions.count) sessions with warning signs in the last 7 days. Lower pressure or time for a week."))
        }

        // MK10.1: intensity caps — high pressure and long clamp sets are where injuries come from.
        // MK19.1: "high" means above your plan's top setting (static pump 8.5, guided PAC −10 inHg), so it only shows when it matters.
        let highPressure = data.sessions.filter { $0.end >= week && $0.type.usesPressure
            && ($0.pressureInHg ?? 0) > MTPlan.maxPressure(for: $0.type) + 0.05 }
        if let worst = highPressure.max(by: { ($0.pressureInHg ?? 0) < ($1.pressureInHg ?? 0) }), let pressure = worst.pressureInHg {
            result.append(MTSafetyAdvice(level: .watch, title: "Pressure is high",
                                         message: String(format: "You used %.1f inHg on %@ this week — above your plan's %.1f inHg. Most injuries (red spots, blisters, fluid) come from high pressure: go back to your plan's settings.",
                                                         pressure, worst.type.title, MTPlan.maxPressure(for: worst.type))))
        }
        let longClamps = data.sessions.filter { $0.end >= week && $0.type == .clamp && $0.duration > 15 * 60 }
        if !longClamps.isEmpty {
            result.append(MTSafetyAdvice(level: .watch, title: "Long clamp sets",
                                         message: "\(longClamps.count) clamp set\(longClamps.count == 1 ? "" : "s") over 15 minutes this week. Keep sets short (≤10–15 min) with full breaks; stop at any coldness, numbness or dark colour."))
        }

        // PAC is hard on the small blood vessels: no more than 3–4 times a week.
        let pacDays = Set(data.sessions.filter { $0.type == .pac && $0.start >= week }.map { calendar.startOfDay(for: $0.start) })
        if pacDays.count > 4 {
            result.append(MTSafetyAdvice(level: .watch, title: "Too much PAC this week",
                                         message: "PAC on \(pacDays.count) of the last 7 days. Keep it to 3–4 times a week (every other day, or Monday to Friday with weekends off)."))
        }

        let checkIns = data.checkInList.sorted { $0.day < $1.day }
        let today = calendar.startOfDay(for: now)
        let recentCut = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        let baselineCut = calendar.date(byAdding: .day, value: -24, to: today) ?? today
        let recent = checkIns.filter { $0.day >= recentCut }.compactMap(\.eq)
        let baseline = checkIns.filter { $0.day < recentCut && $0.day >= baselineCut }.compactMap(\.eq)
        if recent.count >= 2 {
            let recentAverage = Double(recent.reduce(0, +)) / Double(recent.count)
            if baseline.count >= 5 {
                let baseAverage = Double(baseline.reduce(0, +)) / Double(baseline.count)
                if baseAverage - recentAverage >= 1 {
                    result.append(MTSafetyAdvice(level: .rest, title: "EQ is down",
                                                 message: String(format: "Your EQ has averaged %.1f the last few days vs %.1f before. That's a classic overtraining sign — take 2–3 days off.", recentAverage, baseAverage)))
                }
            } else if recentAverage <= 2 {
                result.append(MTSafetyAdvice(level: .rest, title: "EQ is low",
                                             message: "Low EQ ratings lately. Rest a few days before training again."))
            }
        }

        let lastFive = Array(checkIns.suffix(5)).compactMap(\.morningWood)
        if lastFive.count >= 4, lastFive.filter({ !$0 }).count >= 3 {
            result.append(MTSafetyAdvice(level: .watch, title: "Fewer morning erections",
                                         message: "Missing on \(lastFive.filter { !$0 }.count) of your last \(lastFive.count) check-ins. Worth easing off while it recovers."))
        }
        return result.sorted { $0.level.rawValue > $1.level.rawValue }
    }
}

// MARK: - Stats

enum MTStats {
    /// Minutes trained per day (start of day → minutes), all types or one type.
    static func minutesByDay(_ sessions: [MTSession], type: MTType? = nil, calendar: Calendar = .current) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for session in sessions where type == nil || session.type == type {
            result[calendar.startOfDay(for: session.start), default: 0] += session.duration / 60
        }
        return result
    }

    /// Consecutive days with any training, counting back from today (or yesterday if nothing yet today).
    static func streak(_ sessions: [MTSession], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(sessions.map { calendar.startOfDay(for: $0.start) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func daysTrained(_ sessions: [MTSession], in interval: DateInterval, calendar: Calendar = .current) -> Int {
        Set(sessions.filter { interval.contains($0.start) }.map { calendar.startOfDay(for: $0.start) }).count
    }

    /// Monday–Sunday of the week containing `date`.
    static func mondayWeek(containing date: Date) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func minutesText(_ minutes: Double) -> String {
        minutes == minutes.rounded() ? "\(Int(minutes))m" : String(format: "%.1fm", minutes)
    }
}

// MARK: - Stamina training

struct MTStaminaSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var goalSeconds: Double
    var activeSeconds: Double
    var pauses: Int
    var notes: String?
    /// With porn (true) / without (false); nil for sessions logged before this was added.
    var withPorn: Bool?

    var reachedGoal: Bool { activeSeconds >= goalSeconds }
}

struct MTActiveStamina: Codable, Hashable {
    var start: Date
    var goalSeconds: Double
    var withPorn: Bool?
    var accumulated: Double = 0
    /// Counting while non-nil.
    var runningSince: Date?
    /// Cool-down ends at this time (while cooling down).
    var cooldownUntil: Date?
    var pauses: Int = 0
    var goalAnnounced: Bool = false
    var cooldownAnnounced: Bool = false

    func active(at now: Date) -> Double {
        accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    var isCoolingDown: Bool { cooldownUntil != nil }
}

enum MTStamina {
    /// Suggest a higher goal after 3 sessions in a row at the current goal reached with 0–1 pauses.
    static func suggestedGoal(_ sessions: [MTStaminaSession], currentMinutes: Int, withPorn: Bool? = nil) -> Int? {
        let matching = withPorn == nil ? sessions : sessions.filter { ($0.withPorn ?? false) == withPorn }
        let recent = matching.sorted { $0.start < $1.start }.suffix(3)
        guard recent.count == 3,
              recent.allSatisfy({ $0.reachedGoal && $0.pauses <= 1 && Int($0.goalSeconds / 60) >= currentMinutes }) else { return nil }
        return currentMinutes + (currentMinutes < 30 ? 2 : 5)
    }
}

// MARK: - Stretcher totals

struct MTStretcherTotals {
    var lifetimeHours: Double
    var appHours: Double
    var weekHours: Double
    var monthHours: Double
    var todayWeighted: Double
    var goalStreak: Int
    var byLevel: [MTLevel: Double]

    static let milestones: [Double] = [50, 100, 250, 500, 750, 1000, 1500, 2000, 3000, 5000]

    var nextMilestone: Double? { Self.milestones.first { $0 > lifetimeHours } }
    var reachedMilestones: [Double] { Self.milestones.filter { $0 <= lifetimeHours } }

    static func compute(_ data: MTData, now: Date = .now, calendar: Calendar = .current) -> MTStretcherTotals {
        let goal = data.settings.dailyGoal
        // Segments including the one running now.
        var segments: [(start: Date, end: Date, level: MTLevel?)] = data.sessions
            .filter { $0.type == .allDayStretcher }
            .map { ($0.start, $0.end, $0.level) }
        if let running = data.stretcherStartedAt {
            segments.append((running, now, data.stretcherLevel))
        }

        func hours(from start: Date, to end: Date, weighted: Bool) -> Double {
            segments.reduce(0) { total, segment in
                let overlap = min(segment.end, end).timeIntervalSince(max(segment.start, start))
                guard overlap > 0 else { return total }
                return total + overlap / 3600 * (weighted ? (segment.level?.weight ?? 1) : 1)
            }
        }

        let appHours = segments.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) / 3600 }
        var byLevel: [MTLevel: Double] = [:]
        for segment in segments {
            if let level = segment.level { byLevel[level, default: 0] += max(0, segment.end.timeIntervalSince(segment.start)) / 3600 }
        }
        let today = calendar.startOfDay(for: now)
        let week = MTStats.mondayWeek(containing: now).first ?? today
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? today

        // Streak of days hitting the weighted goal (today counts once it's hit).
        var streak = 0
        var day = today
        let todayHit = hours(from: today, to: now, weighted: true) >= goal
        if !todayHit, let yesterday = calendar.date(byAdding: .day, value: -1, to: today) { day = yesterday }
        while true {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            if hours(from: day, to: min(next, now), weighted: true) >= goal {
                streak += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            } else {
                break
            }
            if streak > 3650 { break }
        }

        return MTStretcherTotals(
            lifetimeHours: data.settings.baseHours + appHours,
            appHours: appHours,
            weekHours: hours(from: week, to: now, weighted: false),
            monthHours: hours(from: month, to: now, weighted: false),
            todayWeighted: hours(from: today, to: now, weighted: true),
            goalStreak: streak,
            byLevel: byLevel
        )
    }
}

// MARK: - Saving interval steps (MK19.1)

extension MTData {
    /// Saves a finished interval step as a session. Back-to-back steps of the same kind with no rest between
    /// (guided PAC) fold into one session at the top pressure, so the log, stats and progression see one PAC,
    /// not five. Returns the new session's id, or nil when the step was folded into the one before.
    mutating func logStep(_ run: MTActiveInterval, stepIndex: Int, end: Date) -> UUID? {
        guard stepIndex < run.steps.count else { return nil }
        let step = run.steps[stepIndex]
        let work = run.workDone[stepIndex] ?? 0
        guard work > 0 else { return nil }
        let start = run.stepStarts[stepIndex] ?? end.addingTimeInterval(-work)
        if stepIndex > 0 {
            let before = run.steps[stepIndex - 1]
            if before.restMinutes == 0, before.type == step.type, before.nir == step.nir,
               let index = sessions.lastIndex(where: { $0.type == step.type && $0.nir == step.nir && abs($0.end.timeIntervalSince(start)) < 1 }) {
                sessions[index].workSeconds = sessions[index].duration + work
                sessions[index].end = end
                sessions[index].pressureInHg = [sessions[index].pressureInHg, step.pressureInHg].compactMap { $0 }.max()
                sessions[index].tensionKg = [sessions[index].tensionKg, step.tensionKg].compactMap { $0 }.max()
                return nil
            }
        }
        let completedRounds = run.phases[..<min(run.index + 1, run.phases.count)]
            .filter { $0.stepIndex == stepIndex && $0.kind == .work }.count
        let session = MTSession(type: step.type, start: start, end: end,
                                pressureInHg: step.pressureInHg, tensionKg: step.tensionKg,
                                rounds: completedRounds, workSeconds: work, nir: step.nir)
        sessions.append(session)
        return session.id
    }
}
