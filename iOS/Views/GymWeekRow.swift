import SwiftUI

/// Monday–Sunday row on the Today screen. Trained days are a green circle with
/// the session's short code (CH, B, U, L, CA); untrained days are an empty circle.
struct GymWeekRow: View {
    let logs: [WorkoutLog]
    var restDays: [Date] = []
    /// Planned workouts, sick and travel days.
    var plans: [DayPlan] = []
    @State private var selectedDay: Date?

    private func plan(on day: Date) -> DayPlan? { plans.last { calendar.isDate($0.day, inSameDayAs: day) } }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }

    private var days: [Date] {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        let weekday = cal.component(.weekday, from: today)
        let offset = (weekday + 5) % 7 // Monday = 0
        guard let monday = cal.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private func logs(on day: Date) -> [WorkoutLog] {
        logs.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let dayLogs = logs(on: day)
                    let trained = !dayLogs.isEmpty
                    let isToday = calendar.isDateInToday(day)
                    let isRest = !trained && restDays.contains { calendar.isDate($0, inSameDayAs: day) }
                    let dayPlan = plan(on: day)
                    let isExcused = !trained && (dayPlan?.kind.isExcused ?? false)
                    let isMissed = !trained && !isRest && !isExcused && day < calendar.startOfDay(for: .now)
                    let plannedCode = (!trained && dayPlan?.kind == .workout) ? dayPlan?.routineName.map(Self.code(forName:)) : nil
                    let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                    Button {
                        selectedDay = isSelected ? nil : day
                    } label: {
                        VStack(spacing: 4) {
                            Text(letters[index])
                                .font(.caption2.bold())
                                .foregroundStyle(isToday ? Color.accentColor : .secondary)
                            ZStack {
                                Circle().fill(trained ? Color.green : (isMissed ? Color.red : (isRest ? Color.gray : (isExcused ? Color.teal : Color.white))))
                                Circle().stroke(isToday ? Color.accentColor : (isMissed || isRest || isExcused ? Color.clear : Color.gray.opacity(0.35)),
                                                lineWidth: isToday || isSelected ? 2 : 1)
                                if isExcused {
                                    Image(systemName: dayPlan?.kind == .travel ? "airplane" : "cross.case.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if let plannedCode, !isMissed {
                                    // Planned, not done yet: the code in grey.
                                    Text(plannedCode)
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.secondary)
                                } else if isMissed {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 14, weight: .heavy))
                                        .foregroundStyle(.white)
                                } else if isRest {
                                    Image(systemName: "moon.zzz.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                if trained {
                                    Text(Self.label(for: dayLogs))
                                        .font(.system(size: Self.label(for: dayLogs).count > 2 ? 10 : 13,
                                                      weight: .heavy, design: .rounded))
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(width: 36, height: 36)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let day = selectedDay {
                Text(detailText(for: day))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func detailText(for day: Date) -> String {
        let name = day.formatted(.dateTime.weekday(.wide))
        let dayLogs = logs(on: day)
        if !dayLogs.isEmpty { return name + ": " + dayLogs.map(\.routineName).joined(separator: ", ") }
        if restDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            return name + ": rest day (Sergeant Cluck disapproves)"
        }
        if let plan = plan(on: day) {
            switch plan.kind {
            case .ill: return name + ": sick day (doesn't count against your week)"
            case .travel: return name + ": travel day (doesn't count against your week)"
            case .workout:
                return name + (day < calendar.startOfDay(for: .now) ? ": missed — planned " : ": planned — ") + (plan.routineName ?? "workout")
            }
        }
        return name + (day < calendar.startOfDay(for: .now) ? ": missed" : ": nothing yet")
    }

    /// One code per day; a second session on the same day is joined with "+" (e.g. "CH+CA").
    static func label(for logs: [WorkoutLog]) -> String {
        var codes: [String] = []
        for log in logs {
            let code = code(for: log)
            if !codes.contains(code) { codes.append(code) }
        }
        if codes.count > 2 { return codes[0] + "+" }
        return codes.joined(separator: "+")
    }

    /// Code from a routine name alone (for planned days).
    static func code(forName routineName: String) -> String {
        let name = routineName.lowercased()
        if name.contains("basketball") { return "BB" }
        if name.contains("cardio") || name == "run" || name.hasSuffix(" run") { return "CA" }
        if name.contains("chest") { return "CH" }
        if name.contains("back") { return "B" }
        if name.contains("upper") { return "U" }
        if name.contains("leg") || name.contains("lower") { return "L" }
        let first = routineName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return first.isEmpty ? "•" : first
    }

    static func code(for log: WorkoutLog) -> String {
        if log.source == ActivityKind.basketball.rawValue { return "BB" }
        if log.source == ActivityKind.run.rawValue { return "CA" }
        let name = log.routineName.lowercased()
        if name.contains("cardio") { return "CA" }
        if name.contains("chest") { return "CH" }
        if name.contains("back") { return "B" }
        if name.contains("upper") { return "U" }
        if name.contains("leg") || name.contains("lower") { return "L" }
        // Fall back to what was actually trained.
        let categories = log.exercises.map { $0.category ?? ExerciseCategory.guess(from: $0.exerciseName) }
        if !categories.isEmpty && categories.allSatisfy({ $0 == .cardio }) { return "CA" }
        let counts = Dictionary(grouping: categories.filter { $0 != .cardio && $0 != .other }, by: { $0 })
            .mapValues(\.count)
        switch counts.max(by: { $0.value < $1.value })?.key {
        case .chest?: return "CH"
        case .back?: return "B"
        case .legs?, .calves?: return "L"
        case .shoulders?, .biceps?, .triceps?: return "U"
        default:
            let first = log.routineName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
            return first.isEmpty ? "✓" : first
        }
    }
}
