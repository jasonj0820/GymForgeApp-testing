import Foundation
import EventKit
import UserNotifications

// MARK: - What's planned on a day (MK24)

extension PhoneAppStore {
    /// The session planned on a date, by name: Plan week first, then the fixed split. nil = rest or nothing known.
    func plannedSessionName(on date: Date) -> String? {
        let cal = Calendar.current
        if let plan = extras.dayPlan(on: date) {
            guard plan.kind == .workout else { return nil }
            if plan.routineID == CardioIDs.run { return "Run" }
            if plan.routineID == CardioIDs.basketball { return "Basketball" }
            return routines.first { $0.id == plan.routineID }?.name ?? plan.routineName
        }
        if extras.isRestDay(date) { return nil }
        guard fixedSplitOn else { return nil }
        let court = cal.isDateInToday(date) ? courtToday : nil
        switch FixedSplit.day(date, done: splitDone, court: court, calendar: cal).kind {
        case .train(let slot): return splitRoutine(slot)?.name
        case .askCourt: return (splitRoutine(.chest)?.name ?? "Chest") + " or full court"
        case .microChest: return "Micro chest"
        case .basketball: return "Basketball"
        case .rest: return nil
        }
    }

    /// When you usually start a gym session on this weekday (median of the last 10 weeks), as minutes after midnight.
    /// Falls back to all weekdays when that day has fewer than 3 sessions; nil with too little history.
    func usualStartMinutes(weekday: Int) -> Int? {
        let cal = Calendar.current
        let since = Date.now.addingTimeInterval(-70 * 86_400)
        let logs = workoutLogs.filter {
            $0.countsAsTraining && $0.startedAt > since && $0.routineID != CardioIDs.run && $0.routineID != CardioIDs.basketball
        }
        func minutes(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        let sameDay = logs.filter { cal.component(.weekday, from: $0.startedAt) == weekday }.map { minutes($0.startedAt) }
        let pool = sameDay.count >= 3 ? sameDay : logs.map { minutes($0.startedAt) }
        guard sameDay.count >= 3 || pool.count >= 4 else { return nil }
        return UsualTime.median(pool)
    }

    /// Routine steps due on a day (any frequency).
    func routineStepsDue(on date: Date) -> Int {
        guard let dayfold else { return 0 }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        return RoutineKind.allCases.flatMap { dayfold.rows($0, now: noon) }.filter { $0.retryToday && !$0.done }.count
    }

    // MARK: Day notes (the + menu on Today)

    var todaysNotes: [DayNote] { extras.dayNotes.filter { Calendar.current.isDateInToday($0.date) } }

    func addDayNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        extras.dayNotes.append(DayNote(date: .now, text: trimmed))
        saveExtras()
    }

    func deleteDayNote(_ id: UUID) {
        extras.dayNotes.removeAll { $0.id == id }
        saveExtras()
    }
}

// MARK: - Calendar (read-only)

/// MK24: today's events from the iPhone's calendars, for the Today timeline, the leave-for-the-gym nudge and busy weeks.
/// Off until you turn it on (Settings → Sounds & reminders → Your day); nothing is ever written to your calendar.
@MainActor
enum DayAgenda {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
    }

    nonisolated static let enabledKey = "agenda.calendar"
    private static let eventStore = EKEventStore()

    static var enabled: Bool {
        get { Demo.isOn || UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var hasAccess: Bool {
        Demo.isOn || EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Asks once; turns the timeline on if allowed.
    static func requestAccess() async -> Bool {
        guard !Demo.isOn else { return true }
        let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        enabled = granted
        return granted
    }

    static func events(from start: Date, to end: Date) -> [Item] {
        if Demo.isOn { return demoEvents(from: start, to: end) }
        guard enabled, hasAccess else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .map { Item(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event",
                        start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
            .sorted { $0.start < $1.start }
    }

    static func events(on day: Date) -> [Item] {
        let start = Calendar.current.startOfDay(for: day)
        return events(from: start, to: start.addingTimeInterval(86_400))
    }

    /// Something timed (not all-day) overlapping the window.
    static func clash(from start: Date, to end: Date) -> Item? {
        events(on: start).first { !$0.allDay && $0.start < end && $0.end > start }
    }

    /// Events that make a week heavy: exams, assignments, deadlines, presentations, shifts all day.
    static func heavyEvents(in week: DateInterval) -> [Item] {
        events(from: week.start, to: week.end).filter { BusyWords.isHeavy($0.title) }
    }

    private static func demoEvents(from start: Date, to end: Date) -> [Item] {
        let cal = Calendar.current
        var items: [Item] = []
        var day = cal.startOfDay(for: start)
        while day < end {
            let weekday = cal.component(.weekday, from: day)
            func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
            if (2...6).contains(weekday) {
                items.append(Item(id: "demo-uni-\(day)", title: "Lecture", start: at(9), end: at(11), allDay: false))
                items.append(Item(id: "demo-work-\(day)", title: "Work", start: at(13), end: at(16, 30), allDay: false))
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return items.filter { $0.start >= start && $0.start < end }
    }
}

// MARK: - Morning brief and leave-for-the-gym nudge

/// MK24: two daily notifications, planned 3 days ahead (kept small: iOS only holds 64 pending).
@MainActor
enum DailyNudges {
    nonisolated static let briefOnKey = "brief.on"
    nonisolated static let briefMinutesKey = "brief.minutes"          // after midnight; 7:00 by default
    nonisolated static let gymOnKey = "gymNudge.on"
    nonisolated static let travelKey = "gymNudge.travel"             // minutes to get there; 20 by default

    static var briefOn: Bool { UserDefaults.standard.object(forKey: briefOnKey) as? Bool ?? true }
    static var briefMinutes: Int { UserDefaults.standard.object(forKey: briefMinutesKey) as? Int ?? 7 * 60 }
    static var gymOn: Bool { UserDefaults.standard.object(forKey: gymOnKey) as? Bool ?? true }
    static var travelMinutes: Int { UserDefaults.standard.object(forKey: travelKey) as? Int ?? 20 }

    static let prefixes = ["brief.", "gymnudge."]

    static func reschedule(store: PhoneAppStore, now: Date = .now) {
        guard !Demo.isOn else { return }
        let requests = plan(store: store, now: now)
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { id in prefixes.contains { id.hasPrefix($0) } })
            for request in requests { try? await center.add(request) }
        }
    }

    /// Text of today's brief (also shown in Settings as a preview).
    static func briefLines(store: PhoneAppStore, on day: Date) -> (title: String, body: String) {
        let cal = Calendar.current
        var parts: [String] = []
        let title: String
        switch store.extras.dayPlan(on: day)?.kind {
        case .ill?: title = "Sick day: rest up"
        case .travel?: title = "Travel day"
        default:
            if let session = store.plannedSessionName(on: day) { title = "Today: \(session)" } else { title = "Rest day today" }
        }
        if let target = store.proteinTargetG { parts.append("\(Int(target.rounded())) g protein") }
        let steps = store.routineStepsDue(on: day)
        if steps > 0 { parts.append("\(steps) routine step\(steps == 1 ? "" : "s")") }
        if let schedule = store.profile.sleepSchedule {
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            parts.append("bed \(schedule.nextBedtime(after: noon).formatted(date: .omitted, time: .shortened))")
        }
        return (title, parts.isEmpty ? "Open Splitday for today's plan." : parts.joined(separator: " · "))
    }

    private static func plan(store: PhoneAppStore, now: Date) -> [UNNotificationRequest] {
        let cal = Calendar.current
        var out: [UNNotificationRequest] = []
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let key = day.formatted(.iso8601.year().month().day())
            if briefOn, let fire = cal.date(byAdding: .minute, value: briefMinutes, to: day), fire > now {
                let lines = briefLines(store: store, on: day)
                let content = UNMutableNotificationContent()
                content.title = lines.title
                content.body = lines.body
                content.threadIdentifier = "brief"
                out.append(request("brief.\(key)", content, fire))
            }
            if gymOn, let gym = gymNudge(store: store, day: day, now: now) {
                let content = UNMutableNotificationContent()
                content.title = "Time to head to the gym"
                content.body = gym.body
                content.sound = .default
                content.threadIdentifier = "gymnudge"
                out.append(request("gymnudge.\(key)", content, gym.fire))
            }
        }
        return out
    }

    /// At your usual start time minus travel, on days with a gym session planned and not done yet;
    /// skipped when your calendar has something on at that time.
    static func gymNudge(store: PhoneAppStore, day: Date, now: Date = .now) -> (fire: Date, start: Date, body: String)? {
        let cal = Calendar.current
        guard let session = store.plannedSessionName(on: day), session != "Run", session != "Basketball",
              let minutes = store.usualStartMinutes(weekday: cal.component(.weekday, from: day)),
              let start = cal.date(byAdding: .minute, value: minutes, to: day) else { return nil }
        let fire = start.addingTimeInterval(-Double(travelMinutes) * 60)
        guard fire > now else { return nil }
        if store.workoutLogs.contains(where: { $0.countsAsTraining && cal.isDate($0.startedAt, inSameDayAs: day) }) { return nil }
        if DayAgenda.clash(from: start, to: start.addingTimeInterval(3600)) != nil { return nil }
        return (fire, start, "\(session) today. You usually start around \(start.formatted(date: .omitted, time: .shortened)). Bag packed?")
    }

    private static func request(_ id: String, _ content: UNMutableNotificationContent, _ fire: Date) -> UNNotificationRequest {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNNotificationRequest(identifier: id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }
}
