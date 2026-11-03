import Foundation

/// MK11.3: "Give me a break" — when life gets busy. Deliberately hard to switch on: a real reason with
/// numbers, a short end date, once every 6 weeks, and a typed confirmation.
public struct GymBreak: Codable, Equatable, Identifiable {
    public enum Reason: String, Codable, CaseIterable, Identifiable {
        case deadlines, work, life
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .deadlines: return "Assignments or exams due"
            case .work: return "Work crunch"
            case .life: return "Moving, family or an emergency"
            }
        }

        /// The number you have to give.
        public var question: String {
            switch self {
            case .deadlines: return "Assignments / exams due"
            case .work: return "Days of 10+ hours"
            case .life: return "Days it takes up"
            }
        }

        public var minimum: Int {
            switch self {
            case .deadlines: return 2
            case .work: return 3
            case .life: return 2
            }
        }
    }

    public enum Mode: String, Codable {
        /// 2 short sessions a week (keeps strength).
        case maintenance
        /// No gym at all.
        case full
    }

    public var id: UUID
    public var reason: Reason
    public var count: Int
    public var detail: String
    public var mode: Mode
    public var start: Date
    /// Start of the day after the last thing is due.
    public var end: Date
    public var endedEarly: Date?

    public init(id: UUID = UUID(), reason: Reason, count: Int, detail: String, mode: Mode, start: Date, end: Date) {
        self.id = id
        self.reason = reason
        self.count = count
        self.detail = detail
        self.mode = mode
        self.start = start
        self.end = end
    }

    public var finish: Date { endedEarly.map { min($0, end) } ?? end }
    public func isActive(at date: Date = .now) -> Bool { date >= start && date < finish }
    public var interval: DateInterval { DateInterval(start: start, end: max(finish, start)) }

    /// The week's goal while a break touches it.
    public func weekGoal(normal: Int) -> Int { mode == .full ? 0 : min(normal, GymBreakRules.maintenanceGoal) }
}

public enum GymBreakRules {
    public static let maintenanceGoal = 2
    public static let maxDays = 14
    public static let cooldownDays = 42
    public static let confirmWord = "BREAK"

    /// Why a break can't start (nil = it can). `lastDue` is the day the last thing is due.
    public static func refusal(reason: GymBreak.Reason, count: Int, detail: String, lastDue: Date,
                               history: [GymBreak], now: Date = .now, calendar: Calendar = .current) -> String? {
        let today = calendar.startOfDay(for: now)
        if history.contains(where: { $0.isActive(at: now) }) { return "You're already on a break." }
        if let last = history.map(\.start).max(), now.timeIntervalSince(last) < Double(cooldownDays) * 86_400 {
            let next = calendar.date(byAdding: .day, value: cooldownDays, to: calendar.startOfDay(for: last)) ?? now
            return "One break every 6 weeks. Next one from \(next.formatted(date: .abbreviated, time: .omitted))."
        }
        if count < reason.minimum {
            return "\(reason.question): \(count). That's a normal week, recruit — you need \(reason.minimum)+ for a break."
        }
        if detail.trimmingCharacters(in: .whitespacesAndNewlines).count < 5 { return "Say what's due (e.g. \"CIVL3390 report, exam\")." }
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: lastDue)).day ?? 0
        if days < 1 { return "Pick the day the last one is due (tomorrow or later)." }
        if days > maxDays { return "A break is \(maxDays) days at most. Plan around the rest." }
        return nil
    }

    /// The break, ending the day after the last thing is due.
    public static func make(reason: GymBreak.Reason, count: Int, detail: String, mode: GymBreak.Mode, lastDue: Date,
                            now: Date = .now, calendar: Calendar = .current) -> GymBreak {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDue)) ?? lastDue
        return GymBreak(reason: reason, count: count, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                        mode: mode, start: now, end: end)
    }

    /// The break touching the week of `date` (most recent first).
    public static func breakInWeek(of date: Date, breaks: [GymBreak], calendar: Calendar = .current) -> GymBreak? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return breaks.last { $0.start < week.end && $0.finish > week.start && $0.finish > $0.start }
    }

    /// First week back after a break of 5+ days that ended in the last 7 days, before you've trained since.
    public static func comeback(breaks: [GymBreak], logs: [WorkoutLog], now: Date = .now) -> Bool {
        guard let last = breaks.filter({ !$0.isActive(at: now) && $0.finish <= now }).max(by: { $0.finish < $1.finish }),
              last.finish.timeIntervalSince(last.start) >= 5 * 86_400,
              now.timeIntervalSince(last.finish) < 7 * 86_400 else { return false }
        return !logs.contains { $0.countsAsTraining && $0.startedAt >= last.finish }
    }
}
