import Foundation

enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .daily: "sun.max.fill"
        case .weekly: "calendar.day.timeline.left"
        case .monthly: "calendar"
        case .yearly: "sparkles"
        }
    }
    var greeting: String {
        switch self {
        case .daily: "Every day,\na little care."
        case .weekly: "Once a week,\nkeep it steady."
        case .monthly: "Once a month,\nstay on top."
        case .yearly: "Once a year,\ndon't forget."
        }
    }
}

extension RoutineKind {
    // v1.0 files stored "morning"/"bedtime"; read them as daily so old data still loads.
    init(from decoder: Decoder) throws {
        self = RoutineKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .daily
    }
}

struct RoutineTask: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var routine: RoutineKind
    // Weekly only. Calendar weekday: Sunday = 1 ... Saturday = 7.
    var weekdays: Set<Int> = Set(1...7)
    // Monthly and yearly: day of month (clamped to the month's last day).
    var monthDay: Int = Calendar.current.component(.day, from: Date())
    // Yearly only: 1 = January.
    var month: Int = Calendar.current.component(.month, from: Date())
    var retryDays: Int = 1
    var order: Int = 0
    var createdAt: Date = Date()
    var enabled: Bool = true
    // Part of the before-bed checklist (GymForge's wind-down Live Activity).
    var bedtime: Bool = false
    // Part of the wake-up checklist.
    var wake: Bool = false
    // MK24: a built-in timer, a link or app to open, the step's own reminder (minutes after midnight),
    // "when I get home", and what the step does in Splitday (instead of guessing from its title).
    var timerMinutes: Int? = nil
    var link: String? = nil
    var reminderMinutes: Int? = nil
    var atHome: Bool = false
    var action: StepAction? = nil

    /// Weigh-in steps from before MK24 were found by the word "weigh" in the title.
    var isWeighIn: Bool { action == .weighIn || (action == nil && title.localizedCaseInsensitiveContains("weigh")) }

    var scheduleLabel: String {
        switch routine {
        case .daily: return "Every day"
        case .weekly:
            if weekdays.count == 7 { return "Every day" }
            return (1...7).filter { weekdays.contains($0) }
                .map { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][$0 - 1] }.joined(separator: ", ")
        case .monthly: return "Monthly · day \(monthDay)"
        case .yearly: return "Yearly · \(monthDay) \(Calendar.current.shortMonthSymbols[month - 1])"
        }
    }
}

extension RoutineTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        // Legacy morning/bedtime: all-week tasks become daily, the rest weekly.
        let raw = try c.decode(String.self, forKey: .routine)
        routine = RoutineKind(rawValue: raw) ?? (weekdays.count == 7 ? .daily : .weekly)
        bedtime = try c.decodeIfPresent(Bool.self, forKey: .bedtime) ?? (raw == "bedtime")
        wake = try c.decodeIfPresent(Bool.self, forKey: .wake) ?? (raw == "morning")
        monthDay = try c.decodeIfPresent(Int.self, forKey: .monthDay) ?? 1
        month = try c.decodeIfPresent(Int.self, forKey: .month) ?? 1
        retryDays = try c.decode(Int.self, forKey: .retryDays)
        order = try c.decode(Int.self, forKey: .order)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        atHome = try c.decodeIfPresent(Bool.self, forKey: .atHome) ?? false
        action = (try? c.decodeIfPresent(StepAction.self, forKey: .action)) ?? nil   // unknown values (newer build) read as none
    }
}

/// MK24 (124): what a step is linked to in Splitday.
enum StepAction: String, Codable, CaseIterable, Identifiable {
    case weighIn, creatine, packBag, protein, water
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weighIn: "Weigh-in (opens the weigh-in, ticks itself)"
        case .creatine: "Creatine (ticks the nutrition card too)"
        case .packBag: "Pack the gym bag"
        case .protein: "Protein target (ticks itself once hit)"
        case .water: "Water target (ticks itself once hit)"
        }
    }
}



struct RoutineSettings: Codable, Equatable {
    var kind: RoutineKind
    var remindersEnabled: Bool = false
    var hour: Int
    var minute: Int = 0
    // Optional per-weekday times, stored as minutes after midnight.
    var weekdayMinutes: [Int: Int] = [:]
    func time(for weekday: Int) -> (hour: Int, minute: Int) {
        let value = weekdayMinutes[weekday] ?? hour * 60 + minute
        return (value / 60, value % 60)
    }
}

struct DayfoldConfiguration: Codable, Equatable {
    var revision: Date = Date()
    var tasks: [RoutineTask]
    var routines: [RoutineSettings]
    static let defaultRoutines = [RoutineSettings(kind: .daily, hour: 8), RoutineSettings(kind: .weekly, hour: 9),
                                  RoutineSettings(kind: .monthly, hour: 9), RoutineSettings(kind: .yearly, hour: 9)]

    // Chewing routine for an uneven bite: train the weaker side, keep the jaw tracking straight.
    static func jawTasks(now: Date = Date(), startOrder: Int = 0) -> [RoutineTask] {
        [
            RoutineTask(title: "Jaw · Chew on weaker side, 10 min (sugar-free gum)", routine: .daily, order: startOrder, createdAt: now),
            RoutineTask(title: "Jaw · Weaker-side chewing for one meal", routine: .daily, order: startOrder + 1, createdAt: now),
            RoutineTask(title: "Jaw · Straight opening ×10, tongue on roof of mouth, in mirror", routine: .daily, order: startOrder + 2, createdAt: now, bedtime: true),
            RoutineTask(title: "Jaw · Front photo to compare symmetry", routine: .weekly, weekdays: [1], order: startOrder + 1, createdAt: now)
        ]
    }

    static func initial(now: Date = Date()) -> DayfoldConfiguration {
        DayfoldConfiguration(tasks: [
            RoutineTask(title: "Skincare", routine: .daily, order: 0, createdAt: now, bedtime: true),
            RoutineTask(title: "Hair care", routine: .daily, order: 1, createdAt: now, bedtime: true),
            RoutineTask(title: "Check the door", routine: .daily, order: 2, createdAt: now, bedtime: true),
            RoutineTask(title: "Measure body weight", routine: .weekly, weekdays: [1], order: 0, createdAt: now)
        ] + jawTasks(now: now, startOrder: 3), routines: defaultRoutines)
    }
}

extension RoutineTask {
    static let absID = UUID(uuidString: "D4F01D00-0000-4000-8000-000000000002")!
    static let mealPrepID = UUID(uuidString: "D4F01D00-0000-4000-8000-000000000003")!
    /// Every Sunday, carried forward until done; the title comes from GymForge's protein target.
    static func mealPrep(_ title: String) -> RoutineTask {
        RoutineTask(id: mealPrepID, title: title, routine: .weekly, weekdays: [1], order: -2,
                    createdAt: Date(timeIntervalSince1970: 1_767_225_600))   // 1 Jan 2026
    }
    /// Starter wake-up steps, added once to existing setups that have none.
    static func wakeStarters(startOrder: Int, now: Date = Date()) -> [RoutineTask] {
        ["Drink a glass of water", "Make the bed", "5 min of daylight outside"].enumerated().map {
            RoutineTask(title: $1, routine: .daily, order: startOrder + $0, createdAt: now, wake: true)
        }
    }

    // Fixed ID so tonight's "pack your bag" check-off is remembered like any other task.
    static let gymPackID = UUID(uuidString: "D4F01D00-0000-4000-8000-000000000001")!
    /// Added to tonight's checklist by GymForge when a session is planned for tomorrow.
    static func gymPack(_ session: String, now: Date = Date()) -> RoutineTask {
        RoutineTask(id: gymPackID, title: "Pack gym bag · \(session) tomorrow", routine: .daily, order: -1,
                    createdAt: Calendar.current.startOfDay(for: now), bedtime: true)
    }
}

// Immutable identity per occurrence, with last-write-wins completion/undo state.
struct DayfoldCompletion: Codable, Identifiable, Equatable {
    var id: String
    var taskID: UUID
    var occurrence: Date
    var done: Bool
    var changedAt: Date
    var mutationID: UUID = UUID()
    /// MK24 (118): skipped for today: off the list and the streak carries on, but it isn't counted as done.
    var skipped: Bool? = nil
}

struct DayfoldSnapshot: Codable {
    var configuration: DayfoldConfiguration
    var completions: [String: DayfoldCompletion] = [:]
}

struct TaskOccurrence: Identifiable {
    var task: RoutineTask
    var due: Date
    var day: Date
    var done: Bool
    var completedAt: Date?
    var overdue: Bool
    var retryToday: Bool
    /// MK24 (118): skipped for today (shown with the done ones; the streak carries on).
    var skipped: Bool = false
    var id: String { ScheduleEngine.key(task.id, due) }
}

enum ScheduleEngine {
    static func key(_ taskID: UUID, _ due: Date) -> String {
        // Civil date avoids timezone changes breaking the identity of a scheduled day.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: due)
        return "\(taskID.uuidString):\(c.year!)-\(c.month!)-\(c.day!)"
    }

    static func key(_ taskID: UUID, _ due: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: due)
        return "\(taskID.uuidString):\(c.year!)-\(c.month!)-\(c.day!)"
    }

    // A date in year/month with the day clamped to that month's length (31st -> 30th/28th, Feb 29 -> 28).
    static func clamped(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let last = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(from: DateComponents(year: year, month: month, day: min(max(day, 1), last)))!
    }

    // The most recent scheduled day on or before `today`. Missed cycles never duplicate.
    static func latestDue(_ task: RoutineTask, onOrBefore today: Date, calendar: Calendar) -> Date? {
        let c = calendar.dateComponents([.year, .month], from: today)
        switch task.routine {
        case .daily:
            return today
        case .weekly:
            return (0...6).lazy.map { calendar.date(byAdding: .day, value: -$0, to: today)! }
                .first { task.weekdays.contains(calendar.component(.weekday, from: $0)) }
        case .monthly:
            let this = clamped(year: c.year!, month: c.month!, day: task.monthDay, calendar: calendar)
            if this <= today { return this }
            let prev = calendar.date(byAdding: .month, value: -1, to: this)!
            let p = calendar.dateComponents([.year, .month], from: prev)
            return clamped(year: p.year!, month: p.month!, day: task.monthDay, calendar: calendar)
        case .yearly:
            let this = clamped(year: c.year!, month: task.month, day: task.monthDay, calendar: calendar)
            return this <= today ? this : clamped(year: c.year! - 1, month: task.month, day: task.monthDay, calendar: calendar)
        }
    }

    static func occurrence(_ task: RoutineTask, on day: Date, completions: [String: DayfoldCompletion], calendar: Calendar = .current) -> TaskOccurrence? {
        guard task.enabled, task.routine != .weekly || !task.weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: day)
        guard let due = latestDue(task, onOrBefore: today, calendar: calendar),
              due >= calendar.startOfDay(for: task.createdAt) else { return nil }
        let record = completions[key(task.id, due, calendar: calendar)]
        let isSkipped = record?.skipped == true
        let isDone = record?.done == true || isSkipped
        let age = calendar.dateComponents([.day], from: due, to: today).day ?? 0
        return TaskOccurrence(task: task, due: due, day: today, done: isDone,
                              completedAt: isDone ? record?.changedAt : nil,
                              overdue: age > 0, retryToday: age % max(1, task.retryDays) == 0, skipped: isSkipped)
    }

    static func rows(_ snapshot: DayfoldSnapshot, kind: RoutineKind, now: Date, calendar: Calendar = .current) -> [TaskOccurrence] {
        snapshot.configuration.tasks.filter { $0.routine == kind }
            .sorted { $0.order == $1.order ? $0.title < $1.title : $0.order < $1.order }
            .compactMap { occurrence($0, on: now, completions: snapshot.completions, calendar: calendar) }
    }

    /// Follow-ups after a reminder while its steps stay undone: +1 h and +3 h, never after 21:00
    /// (the evening belongs to the before-bed checklist). Each check-off reschedules, so they stop once done.
    static func followUps(after fire: Date, calendar: Calendar = .current) -> [Date] {
        guard let cutoff = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: fire) else { return [] }
        return [3600.0, 3 * 3600.0].map { fire.addingTimeInterval($0) }.filter { $0 <= cutoff }
    }

    /// Abs once a week on a rest day: shown on the first rest day of the week, kept (done) once you've
    /// ticked it, and back the next week. `restDay` = no session planned or logged today.
    static func absTask(completions: [String: DayfoldCompletion], restDay: Bool, now: Date, calendar: Calendar = .current) -> RoutineTask? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        let doneDay = completions.values.first { $0.taskID == RoutineTask.absID && $0.done && week.contains($0.occurrence) }?.occurrence
        guard let day = doneDay ?? (restDay ? calendar.startOfDay(for: now) : nil) else { return nil }
        return RoutineTask(id: RoutineTask.absID, title: "Abs · 10 min (rest-day core)", routine: .weekly,
                           weekdays: [calendar.component(.weekday, from: day)], order: -1, createdAt: day)
    }

    // MARK: MK24 — history, streaks, stats, what's coming up

    /// Every scheduled day of a task in [start, end), oldest first.
    static func dueDays(_ task: RoutineTask, from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: max(start, task.createdAt))
        while day < end {
            if latestDue(task, onOrBefore: day, calendar: calendar).map({ calendar.isDate($0, inSameDayAs: day) }) == true {
                days.append(day)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return days
    }

    enum DayState: Equatable { case done, skipped, missed, paused, due }

    static func state(_ task: RoutineTask, due: Date, completions: [String: DayfoldCompletion], now: Date,
                      paused: (Date) -> Bool = { _ in false }, calendar: Calendar = .current) -> DayState {
        let record = completions[key(task.id, due, calendar: calendar)]
        if record?.skipped == true { return .skipped }
        if record?.done == true { return .done }
        if paused(due) { return .paused }
        // Still inside its retry window (today, or a step that carries forward until done).
        let today = calendar.startOfDay(for: now)
        if let current = latestDue(task, onOrBefore: today, calendar: calendar), calendar.isDate(current, inSameDayAs: due) { return .due }
        return .missed
    }

    /// Done (or skipped / paused) in a row, counting back from the latest scheduled day; one that's still due doesn't break it.
    static func streak(_ task: RoutineTask, completions: [String: DayfoldCompletion], now: Date,
                       paused: (Date) -> Bool = { _ in false }, calendar: Calendar = .current) -> (current: Int, best: Int) {
        let start = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let days = dueDays(task, from: start, to: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now, calendar: calendar)
        var best = 0, run = 0
        var current = 0
        for day in days {
            switch state(task, due: day, completions: completions, now: now, paused: paused, calendar: calendar) {
            case .done: run += 1
            case .skipped, .paused, .due: break   // keeps the run going, adds nothing
            case .missed: run = 0
            }
            best = max(best, run)
        }
        current = run
        return (current, best)
    }

    /// Steps due on their scheduled days in [start, end) and how many were done (skipped and paused ones don't count).
    static func stats(_ snapshot: DayfoldSnapshot, from start: Date, to end: Date, now: Date = Date(),
                      paused: (Date) -> Bool = { _ in false }, calendar: Calendar = .current) -> (done: Int, due: Int, perTask: [(title: String, done: Int, due: Int)]) {
        var done = 0, due = 0
        var perTask: [(title: String, done: Int, due: Int)] = []
        for task in snapshot.configuration.tasks where task.enabled {
            var d = 0, n = 0
            for day in dueDays(task, from: start, to: min(end, now), calendar: calendar) {
                switch state(task, due: day, completions: snapshot.completions, now: now, paused: paused, calendar: calendar) {
                case .done: d += 1; n += 1
                case .missed: n += 1
                case .due, .skipped, .paused: break
                }
            }
            if n > 0 { perTask.append((task.title, d, n)) }
            done += d
            due += n
        }
        return (done, due, perTask.sorted { Double($0.done) / Double($0.due) < Double($1.done) / Double($1.due) })
    }

    /// The next scheduled day after today (monthly and yearly steps on the Routine screen).
    static func nextDue(_ task: RoutineTask, after now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 1...370 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if latestDue(task, onOrBefore: day, calendar: calendar).map({ calendar.isDate($0, inSameDayAs: day) }) == true { return day }
        }
        return nil
    }

    /// MK24 (122): ready-made sets of steps.
    static func readyMade(_ name: String, startOrder: Int, now: Date = Date()) -> [RoutineTask] {
        func step(_ title: String, _ kind: RoutineKind = .daily, wake: Bool = false, bedtime: Bool = false,
                  weekdays: Set<Int> = Set(1...7), action: StepAction? = nil, timer: Int? = nil, offset: Int) -> RoutineTask {
            var task = RoutineTask(title: title, routine: kind, weekdays: weekdays, order: startOrder + offset, createdAt: now, bedtime: bedtime, wake: wake)
            task.action = action
            task.timerMinutes = timer
            return task
        }
        switch name {
        case "morning":
            return [step("Glass of water", wake: true, action: .water, offset: 0), step("Creatine", wake: true, action: .creatine, offset: 1),
                    step("10 min of daylight outside", wake: true, timer: 10, offset: 2), step("Make the bed", wake: true, offset: 3)]
        case "evening":
            return [step("Phone on the charger, away from bed", bedtime: true, offset: 0), step("Lay out tomorrow's clothes", bedtime: true, offset: 1),
                    step("Stretch", bedtime: true, timer: 10, offset: 2), step("Skincare", bedtime: true, offset: 3)]
        case "sunday":
            return [step("Weigh in", .weekly, weekdays: [1], action: .weighIn, offset: 0), step("Laundry", .weekly, weekdays: [1], offset: 1),
                    step("Clean the kitchen", .weekly, weekdays: [1], timer: 20, offset: 2), step("Plan the week", .weekly, weekdays: [1], offset: 3)]
        default:
            return []
        }
    }

    static func merge(_ local: [String: DayfoldCompletion], _ incoming: [String: DayfoldCompletion]) -> [String: DayfoldCompletion] {
        var result = local
        for (key, value) in incoming {
            if let existing = result[key] {
                if existing.changedAt > value.changedAt { continue }
                if existing.changedAt == value.changedAt && existing.mutationID.uuidString >= value.mutationID.uuidString { continue }
            }
            result[key] = value
        }
        return result
    }
}
