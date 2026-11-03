import Foundation
import SwiftUI

/// Trend lines and "you've stalled" advice for the private section's measurements.
enum MTInsights {
    struct Trend {
        let start: (date: Date, value: Double)
        let end: (date: Date, value: Double)
        /// Change per 30 days, in the same units as the input.
        let perMonth: Double
    }

    /// Least-squares line through the points. Needs 3+ readings spanning 14+ days.
    static func trend(_ points: [(date: Date, value: Double)]) -> Trend? {
        let sorted = points.sorted { $0.date < $1.date }
        guard sorted.count >= 3, let first = sorted.first, let last = sorted.last,
              last.date.timeIntervalSince(first.date) >= 14 * 86_400 else { return nil }
        let xs = sorted.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = sorted.map { $0.value }
        let n = Double(sorted.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0 else { return nil }
        let slope = num / den
        let intercept = meanY - slope * meanX
        let lastX = xs.last ?? 0
        return Trend(start: (first.date, intercept), end: (last.date, intercept + slope * lastX), perMonth: slope * 30)
    }

    struct StallAdvice {
        let metric: MTMetric
        let days: Int
        let change: Double        // cm
        let averageADSHours: Double
        let goalHours: Double
        /// Safety comes first: a recent warning sign or falling erection quality means rest, not more tension.
        let blockedBySafety: Bool
        let tips: [String]
    }

    static func bpfslStall(_ data: MTData, now: Date = .now) -> StallAdvice? { stall(.bpfsl, data, now: now) }

    /// No gain in `metric` over about 8 weeks (needs a reading 56+ days before the latest).
    /// Escalates safely: consistency → more time at the same tension → one small tension step →
    /// a high-tension extender → a break. Never suggests more force after warning signs or falling EQ.
    static func stall(_ metric: MTMetric, _ data: MTData, now: Date = .now) -> StallAdvice? {
        let readings = data.measurements
            .compactMap { m in m.value(metric).map { (date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
        guard let latest = readings.last,
              let reference = readings.last(where: { latest.date.timeIntervalSince($0.date) >= 56 * 86_400 }),
              now.timeIntervalSince(latest.date) < 45 * 86_400 else { return nil }
        // Average a little so one noisy reading doesn't trigger it.
        let recent = readings.filter { latest.date.timeIntervalSince($0.date) < 10 * 86_400 }.map { $0.value }
        let recentAverage = recent.reduce(0, +) / Double(max(recent.count, 1))
        let change = recentAverage - reference.value
        guard change <= 0.1 else { return nil }   // ≤ 1 mm in 8+ weeks

        let days = Int(latest.date.timeIntervalSince(reference.date) / 86_400)
        let windowStart = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let adsSeconds = data.sessions
            .filter { $0.type == .allDayStretcher && $0.start >= windowStart }
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let averageHours = adsSeconds / 3600 / 30
        let goal = data.settings.dailyGoal
        let extenderSessions = data.sessions.filter { $0.type == .highTensionExtender && $0.start >= windowStart }.count

        // Safety: serious warning in the last 14 days, or EQ down a point or more vs the weeks before.
        let twoWeeks = now.addingTimeInterval(-14 * 86_400)
        let recentWarning = data.sessions.contains { $0.start >= twoWeeks && $0.warningList.contains(where: \.isSerious) }
        let checkIns = data.checkInList.filter { $0.eq != nil }
        let eqRecent = checkIns.filter { $0.day >= twoWeeks }.compactMap(\.eq)
        let eqBefore = checkIns.filter { $0.day < twoWeeks && $0.day >= now.addingTimeInterval(-56 * 86_400) }.compactMap(\.eq)
        var eqFalling = false
        if eqRecent.count >= 4, eqBefore.count >= 4 {
            let a = Double(eqRecent.reduce(0, +)) / Double(eqRecent.count)
            let b = Double(eqBefore.reduce(0, +)) / Double(eqBefore.count)
            eqFalling = a <= b - 1
        }
        let blocked = recentWarning || eqFalling

        var tips: [String] = []
        if blocked {
            tips.append(recentWarning
                        ? "You logged a warning sign (pain, numbness or swelling) in the last 2 weeks. Rest until it's fully gone — don't add tension or time now."
                        : "Erection quality has dropped over the last 2 weeks. Take a few days off and come back at your previous settings — more force now would be the wrong move.")
            tips.append("If it doesn't settle within a week or two, see a doctor (urologist).")
        } else if averageHours < goal * 0.8 {
            tips.append("1. Consistency first: you averaged \(String(format: "%.1f", averageHours)) h/day of ADS wear vs your \(String(format: "%.0f", goal)) h goal. Hit the goal most days for 4–6 weeks before changing anything else.")
        } else {
            tips.append("1. Add time at the same tension: +1–2 h/day of ADS, or +5–10 min per extender session. Change one thing at a time for 4–6 weeks.")
            tips.append("2. Still flat after that? One small tension step: +0.25–0.5 kg on the extender, or one Phallosan level (e.g. Green → High Green) — only within your device's stated limits and only if it's comfortable.")
            if extenderSessions == 0 {
                tips.append("3. Then consider a high-tension extender: short sessions 3–4×/week alongside ADS, starting at the lowest tension.")
            } else {
                tips.append("3. Already using the extender: vary angles (straight out, slightly up / down) rather than adding more force again.")
            }
            tips.append("4. Trained hard for 3+ months straight? A 1–2 week break often gets things moving again.")
        }
        tips.append("Measure the same way every time (time of day, rest day before, same stretch). A flat line can be measurement noise.")
        if !blocked {
            tips.append("Stop and rest straight away if you notice numbness, discolouration, pain or swelling.")
        }
        return StallAdvice(metric: metric, days: days, change: change, averageADSHours: averageHours,
                           goalHours: goal, blockedBySafety: blocked, tips: tips)
    }
}

// MARK: - MK11: Sergeant Cluck inside More Training (never shown outside it)

enum MTCluck {
    /// His mood and comments on your More Training consistency (last 2–4 weeks).
    static func read(_ data: MTData, now: Date = .now, calendar: Calendar = .current) -> (mood: CluckMood, lines: [String]) {
        if MTSafety.advice(data, now: now).contains(where: { $0.level == .rest }) {
            return (.protective, ["Your safety check says rest. Rest IS the order today, recruit."])
        }
        let trained = MTTrainingDays.trainedDays(data, calendar: calendar)
        guard let last = trained.max() else {
            return (.watching, ["Nothing logged yet. I'll be watching."])
        }
        let today = calendar.startOfDay(for: now)
        let rest = Set(data.restDayList.map { calendar.startOfDay(for: $0) })
        // Days off since the last session, not counting rest days you marked.
        var daysOff = 0
        var day = calendar.date(byAdding: .day, value: 1, to: last) ?? today
        while day < today {
            if !rest.contains(day) { daysOff += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today
        }
        var lines: [String] = []
        if daysOff >= 3 { lines.append("\(daysOff) days off. Gains don't hold the line by themselves.") }

        if !data.settings.dailyRoutineOn,
           case .due(let overdue) = MTPACSchedule.status(data.sessions, now: now, calendar: calendar), overdue >= 2 {
            lines.append("PAC is \(overdue) days overdue — the every-other-day rhythm is broken.")
        }

        // Stretcher hours: this week vs the 3 weeks before.
        func adsHours(from: Date, to: Date) -> Double {
            data.sessions.filter { $0.type == .allDayStretcher && $0.start >= from && $0.start < to }.reduce(0) { $0 + $1.duration } / 3600
        }
        let weekAgo = today.addingTimeInterval(-7 * 86_400)
        let thisWeek = adsHours(from: weekAgo, to: now)
        let before = adsHours(from: today.addingTimeInterval(-28 * 86_400), to: weekAgo) / 3
        if before >= 5, thisWeek < before * 0.7 {
            lines.append(String(format: "Stretcher hours down %.0f%% this week (%.0f h vs ~%.0f h).", (1 - thisWeek / before) * 100, thisWeek, before))
        }

        // Starts and stops: separate gaps of 2+ days (not rest days) in the last 14.
        let fortnight = (1...14).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.reversed()
        var gaps = 0
        var run = 0
        for day in fortnight {
            if trained.contains(day) || rest.contains(day) {
                if run >= 2 { gaps += 1 }
                run = 0
            } else {
                run += 1
            }
        }
        if run >= 2 { gaps += 1 }
        if gaps >= 3 { lines.append("Starts and stops — \(gaps) breaks in two weeks. Consistency beats intensity.") }

        let recent = trained.filter { $0 >= today.addingTimeInterval(-14 * 86_400) }.count
        if lines.isEmpty {
            return recent >= 10 ? (.impressed, ["\(recent) of the last 14 days trained. That's discipline, recruit."])
                                : (.proud, ["On track. \(recent) training days in the last two weeks."])
        }
        return (daysOff >= 5 ? .furious : (daysOff >= 3 ? .annoyed : .suspicious), lines)
    }
}

struct MTCluckCard: View {
    @EnvironmentObject private var vault: MTVault

    var body: some View {
        let read = MTCluck.read(vault.data)
        HStack(alignment: .top, spacing: 10) {
            CluckView(mood: read.mood, animated: true).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sergeant Cluck · \(read.mood.title)").font(.caption.bold())
                ForEach(read.lines, id: \.self) { line in
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
