import Foundation

// MK18: the daily routine and when to progress. MK20.1: two options — NIR + PAC, or no NIR + static pump.
// The rule throughout: only step up when the current settings stop doing their job, one or two
// things at a time, in small steps, and judge long-term results 2–3 months after a change.
// Foundation-only, so Scripts/run_mt_checks.sh can test it.

enum MTPlan {
    static let nirMinutes = 15.0
    static let afterNIRMinutes = 35.0
    static let plainMinutes = 40.0
    static let pumpRounds = 4
    static let pumpRoundMinutes = 5.0

    struct Day: Equatable {
        /// NIR days: 15 min of the extending is with NIR, then 35 min without.
        var nir: Bool
        var pumpType: MTType   // .pump (static) or .pac
        var extenderMinutes: Double { nir ? MTPlan.nirMinutes + MTPlan.afterNIRMinutes : MTPlan.plainMinutes }
        var pumpMinutes: Double {
            pumpType == .pac ? MTPlan.pacSteps.reduce(0) { $0 + $1.workMinutes } : Double(MTPlan.pumpRounds) * MTPlan.pumpRoundMinutes
        }
        var title: String { nir ? "NIR + PAC" : "No NIR · static pump" }
    }

    /// MK20.1: the two routines you pick from. NIR always goes with PAC; static pump days have no NIR.
    static let nirPAC = Day(nir: true, pumpType: .pac)
    static let pumpOnly = Day(nir: false, pumpType: .pump)
    static let options = [nirPAC, pumpOnly]

    /// The option marked "Today", worked out from what you've logged so a missed day doesn't break the rhythm:
    /// whatever you've already started today; otherwise the one you didn't do on your last training day.
    /// Starting fresh → NIR + PAC.
    static func day(_ sessions: [MTSession], now: Date = .now, calendar: Calendar = .current) -> Day {
        func isNIRPAC(_ s: MTSession) -> Bool { s.nir == true || s.type == .pac }
        let relevant = sessions.filter { isNIRPAC($0) || $0.type == .pump }
        let todays = relevant.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if todays.contains(where: isNIRPAC) { return nirPAC }
        if !todays.isEmpty { return pumpOnly }
        let today = calendar.startOfDay(for: now)
        guard let last = relevant.filter({ $0.start < today }).max(by: { $0.start < $1.start }) else { return nirPAC }
        let lastDay = relevant.filter { calendar.isDate($0.start, inSameDayAs: last.start) }
        return lastDay.contains(where: isNIRPAC) ? pumpOnly : nirPAC
    }

    /// Timer steps for the day: extender (with NIR first on NIR days), 2 min to switch, then 4 × 5 min.
    static func steps(_ day: Day, pressure: Double?, tension: Double?) -> [MTPresetStep] {
        var steps: [MTPresetStep] = []
        if day.nir {
            steps.append(MTPresetStep(type: .highTensionExtender, rounds: 1, workMinutes: nirMinutes, restMinutes: 0, tensionKg: tension, nir: true))
            steps.append(MTPresetStep(type: .highTensionExtender, rounds: 1, workMinutes: afterNIRMinutes, restMinutes: 2, tensionKg: tension))
        } else {
            steps.append(MTPresetStep(type: .highTensionExtender, rounds: 1, workMinutes: plainMinutes, restMinutes: 2, tensionKg: tension))
        }
        if day.pumpType == .pac {
            steps += pacSteps
        } else {
            steps.append(MTPresetStep(type: .pump, rounds: pumpRounds, workMinutes: pumpRoundMinutes, restMinutes: 1, pressureInHg: pressure))
        }
        return steps
    }

    /// "−8 inHg (−27 kPa)": every PAC setting in both units.
    static func both(_ inHg: Double, _ sign: String) -> String {
        "\(sign)\(String(format: "%g", inHg)) inHg (\(sign)\(Int((inHg * kPaPerInHg).rounded())) kPa)"
    }
    static let kPaPerInHg = 3.38639

    /// MK19.1: your top settings. The progression cards never suggest going past them, and the
    /// "Pressure is high" card only shows above them.
    static let pumpMaxInHg = 8.5
    static var pacMaxInHg: Double { pacSteps.compactMap(\.pressureInHg).max() ?? 10 }
    static func maxPressure(for type: MTType) -> Double {
        switch type {
        case .pump: return pumpMaxInHg
        case .pac: return pacMaxInHg
        default: return 6
        }
    }

    /// MK18.2 / MK19: guided PAC (Karl's routine, 25 min under pressure). pressureInHg is the vacuum; the clamp is in the cue.
    static let pacSteps: [MTPresetStep] = [
        MTPresetStep(type: .pac, rounds: 1, workMinutes: 2, restMinutes: 0, pressureInHg: 7.5,
                     cue: "Fill up\nVacuum −7 to −8 inHg (−24 to −27 kPa) · clamp off\nStart semi-erect, not fully hard."),
        MTPresetStep(type: .pac, rounds: 1, workMinutes: 5, restMinutes: 0, pressureInHg: 8,
                     cue: "Clamp set 1\nVacuum \(both(8, "−")) · clamp \(both(8, "+"))\nRelease early once the pump stops kicking in."),
        MTPresetStep(type: .pac, rounds: 1, workMinutes: 3, restMinutes: 0,
                     cue: "Fresh blood\nClamp released · RIP up to \(both(12, "−")), then let it drop near zero."),
        MTPresetStep(type: .pac, rounds: 1, workMinutes: 5, restMinutes: 0, pressureInHg: 9,
                     cue: "Clamp set 2\nVacuum \(both(9, "−")) · clamp \(both(10, "+"))"),
        MTPresetStep(type: .pac, rounds: 1, workMinutes: 10, restMinutes: 0, pressureInHg: 10,
                     cue: "Final set\nVacuum \(both(10, "−")) · clamp \(both(12, "+")) by feel\nDeep stretch, never pain or tingling."),
    ]

    /// MK19: "Time to train" at 8:45pm on each of the next 7 days with no More Training logged (skips rest days).
    static let reminderHour = 20, reminderMinute = 45
    static func reminderDates(_ data: MTData, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let trained = Set(data.sessions.map { calendar.startOfDay(for: $0.start) })
        let rest = Set(data.restDayList.map { calendar.startOfDay(for: $0) })
        // MK19.1: a timer running (or the stretcher on) counts as training today — steps are only saved when they finish.
        let trainingNow = data.isBusy || data.stretcherStartedAt != nil
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  !trained.contains(day), !rest.contains(day), !(offset == 0 && trainingNow),
                  let fire = calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: day),
                  fire > now,
                  // Never "Time to train" on a day the safety check says rest.
                  !MTSafety.advice(data, now: fire, calendar: calendar).contains(where: { $0.level == .rest }) else { return nil }
            return fire
        }
    }

    /// Minutes done today: extender in total, of it with NIR, and today's pump / PAC.
    static func done(_ sessions: [MTSession], day: Day, now: Date = .now, calendar: Calendar = .current)
        -> (extender: Double, nir: Double, pump: Double) {
        let todays = sessions.filter { calendar.isDate($0.start, inSameDayAs: now) }
        func minutes(_ list: [MTSession]) -> Double { list.reduce(0) { $0 + $1.duration } / 60 }
        let extender = todays.filter { $0.type == .highTensionExtender }
        return (minutes(extender), minutes(extender.filter { $0.nir == true }), minutes(todays.filter { $0.type == day.pumpType }))
    }

    static func isComplete(_ done: (extender: Double, nir: Double, pump: Double), day: Day) -> Bool {
        done.extender >= day.extenderMinutes - 1 && done.pump >= day.pumpMinutes - 0.5
            && (!day.nir || done.nir >= nirMinutes - 1)
    }
}

enum MTProgression {
    enum Track: String, CaseIterable {
        case girth, length
        var title: String { self == .girth ? "Girth" : "Length" }
        var types: Set<MTType> { self == .girth ? [.pump, .pac] : [.highTensionExtender] }
        /// MK19.1: what "add time" means in your routine.
        var addTimeHow: String {
            self == .girth
                ? "Add time instead: about 5 min more of static pump, or stretch PAC's final set from 10 to 12 min (or repeat fresh blood + clamp set 2). The timer's +1 min button adds it to the step you're on."
                : "Add time instead: about 10 min more on the extender, or a second short session."
        }
        /// Expansion straight after the session that means it's doing its job.
        var band: ClosedRange<Double> { self == .girth ? 6...12 : 3...4 }
        /// The real measurement that shows growth.
        var metric: MTMetric { self == .girth ? .mg : .bpel }
    }

    struct Advice: Identifiable, Equatable {
        enum Kind: Equatable { case keep, addTime, raise, hold, backOff, takeBreak, tooMuch, needData }
        var id: String { track.rawValue }
        let track: Track
        let kind: Kind
        let title: String
        let message: String
    }

    /// Normal measuring error is 0.1–0.15" (0.25–0.4 cm): a smaller change isn't growth.
    static let noiseCM = 0.3
    /// One small step: 0.5–1 inHg of pressure, or about 1 lb of tension.
    static let pressureStep = 0.5...1.0
    static let tensionStepKg = 0.45
    /// Hold a new level at least this long before changing again, and judge growth only after this.
    static let holdDays = 14.0
    static let judgeDays = 60.0
    static let stuckDays = 90.0
    /// Signs that mean back off for a few days.
    static let backOffSigns: Set<MTWarning> = [.weakErections, .swelling, .skinIrritation]

    static func advice(_ data: MTData, now: Date = .now, calendar: Calendar = .current) -> [Advice] {
        Track.allCases.compactMap { advice(for: $0, data, now: now, calendar: calendar) }
    }

    /// Measurements taken 3+ days after your last session — swelling and pump gone, so they're comparable.
    static func rested(_ data: MTData) -> [MTMeasurement] {
        let ends = data.sessions.map(\.end)
        return data.measurements.filter { measurement in
            guard let last = ends.filter({ $0 <= measurement.date }).max() else { return true }
            return measurement.date.timeIntervalSince(last) >= 3 * 86_400
        }.sorted { $0.date < $1.date }
    }

    /// When the current pressure (girth) / tension (length) was first used, i.e. the last setting change.
    static func lastSettingChange(_ sessions: [MTSession], track: Track, calendar: Calendar = .current) -> Date? {
        // MK19.1: one value per day (the day's highest), so a session that climbs through settings —
        // like guided PAC's −7.5 → −10 inHg — isn't read as a change every day.
        var days: [Date: (start: Date, value: Double)] = [:]
        for session in sessions {
            guard let value = track == .girth ? session.pressureInHg : session.tensionKg else { continue }
            let day = calendar.startOfDay(for: session.start)
            let earlier = days[day]
            days[day] = (min(earlier?.start ?? session.start, session.start), max(earlier?.value ?? value, value))
        }
        let values = days.values.sorted { $0.start < $1.start }.map { ($0.start, $0.value) }
        guard var since = values.last?.0, let current = values.last?.1 else { return nil }
        for (date, value) in values.reversed() {
            guard abs(value - current) < 0.05 else { break }
            since = date
        }
        return values.first.map { $0.0 } == since ? nil : since   // nil = never changed
    }

    /// Minutes per week for the track, `weeksAgo` 0 = this week.
    static func weeklyMinutes(_ sessions: [MTSession], weeksAgo: Int, now: Date, calendar: Calendar) -> Double {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: thisWeek),
              let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return 0 }
        return sessions.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.duration } / 60
    }

    /// When the weekly time last changed by more than ~25% (the routine changed), looking back up to 26 weeks.
    /// "Usual" is the median of the last 4 weeks, and a change needs 2 weeks in a row that differ from it,
    /// so a rest week before measuring doesn't count as a new routine.
    static func lastTimeChange(_ sessions: [MTSession], now: Date, calendar: Calendar) -> Date? {
        let weeks = (0...27).map { weeklyMinutes(sessions, weeksAgo: $0, now: now, calendar: calendar) }
        let usual = weeks[1...4].sorted()[1...2].reduce(0, +) / 2
        guard usual > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        func differs(_ minutes: Double) -> Bool { abs(minutes - usual) > usual * 0.25 }
        for week in 2...25 where differs(weeks[week]) && differs(weeks[week + 1]) {
            return calendar.date(byAdding: .weekOfYear, value: -(week - 1), to: thisWeek)
        }
        return nil
    }

    static func advice(for track: Track, _ data: MTData, now: Date = .now, calendar: Calendar = .current) -> Advice? {
        let sessions = data.sessions.filter { track.types.contains($0.type) }.sorted { $0.start < $1.start }
        guard let first = sessions.first else { return nil }
        let name = track.title
        func card(_ kind: Advice.Kind, _ title: String, _ message: String) -> Advice {
            Advice(track: track, kind: kind, title: "\(name): \(title)", message: message)
        }

        // Weaker erections, lasting swelling, irritated skin or blisters: back off first, whatever the numbers say.
        let signs = Set(data.sessions.filter { $0.end >= now.addingTimeInterval(-4 * 86_400) }.flatMap(\.warningList))
            .intersection(backOffSigns)
        if !signs.isEmpty {
            let list = signs.map(\.title).sorted().joined(separator: ", ").lowercased()
            return card(.backOff, "back off for a few days",
                        "You logged \(list) in the last few days. Take a few days off (or go clearly lighter), then come back at the last settings that felt fine.")
        }

        // Pump and PAC each keep their own pressure; the static pump's is the one to step up.
        let mainType: MTType = track == .girth
            ? (sessions.contains { $0.type == .pump && $0.pressureInHg != nil } ? .pump : .pac)
            : .highTensionExtender
        func value(_ session: MTSession) -> Double? { track == .girth ? session.pressureInHg : session.tensionKg }
        let setting = sessions.last { $0.type == mainType }.flatMap(value)
        let settingChanged = track.types.compactMap { type in
            lastSettingChange(sessions.filter { $0.type == type }, track: track, calendar: calendar)
        }.max()
        let heldDays = now.timeIntervalSince(settingChanged ?? first.start) / 86_400

        // Your guide is how much each session stretches you — at the settings you're on now.
        let recent = sessions.filter { $0.end >= now.addingTimeInterval(-14 * 86_400) }
        let how = track == .girth
            ? "Measure girth just before and straight after pumping — the after-session check asks for both. Aim for 6–12%."
            : "Measure stretched length just before and right after extending — the after-session check asks for both. Aim for about 3–4%."
        guard recent.compactMap(\.expansionPercent).count >= 3 else {
            return card(.needData, "log your expansion", "\(recent.compactMap(\.expansionPercent).count) of 3 readings in the last 2 weeks. " + how)
        }
        let readings = recent.filter { settingChanged == nil || $0.start >= settingChanged! }.compactMap(\.expansionPercent)
        guard readings.count >= 3 else {
            return card(.hold, "hold the new setting",
                        "You changed settings \(Int(heldDays)) day\(Int(heldDays) == 1 ? "" : "s") ago — log expansion for a few sessions and give it at least 2 weeks before changing again.")
        }
        let average = readings.reduce(0, +) / Double(readings.count)
        let pct = String(format: "%.1f%%", average)

        if track == .girth, average > track.band.upperBound {
            let at = setting.map { String(format: " at %.1f inHg", $0) } ?? ""
            return card(.tooMuch, "more expansion than you need",
                        "Averaging \(pct)\(at) (aim 6–12%). Don't chase pressure: stay at the lowest pressure that still gives 6–12% — the harder you push, the sooner you stall and need breaks.")
        }
        if average < track.band.lowerBound {
            if heldDays < holdDays {
                return card(.hold, "hold the new setting",
                            "Expansion is \(pct), but you changed settings \(Int(heldDays)) day\(Int(heldDays) == 1 ? "" : "s") ago. Give it at least 2 weeks before changing again.")
            }
            if track == .girth {
                // MK19.1: never past your max — at it, add time instead.
                let top = MTPlan.maxPressure(for: mainType)
                if let setting, setting >= top - 0.25 {
                    return card(.addTime, "add time, not pressure",
                                String(format: "Expansion has dropped to %@ at %.1f inHg — that's your max, so don't go higher. ", pct, setting)
                                + track.addTimeHow + " Then hold it for at least 2 weeks.")
                }
                let step = setting.map { s in
                    s + pressureStep.upperBound <= top
                        ? String(format: "Add 0.5–1 inHg (from %.1f to about %.1f–%.1f inHg)", s, s + pressureStep.lowerBound, s + pressureStep.upperBound)
                        : String(format: "Go up to %.1f inHg — your max — and no higher", top)
                } ?? "Add 0.5–1 inHg"
                return card(.raise, "raise \(mainType == .pump ? "pump" : "PAC") pressure one small step",
                            "Expansion has dropped to \(pct) at the same settings. \(step), then hold that for at least 2 weeks.")
            }
            let next = setting.map { String(format: " (from %.1f to about %.1f kg)", $0, $0 + tensionStepKg) } ?? ""
            return card(.raise, "add a little tension",
                        "Stretch has dropped to \(pct) at the same settings. Add about 1 lb\(next), then hold that for at least 2 weeks.")
        }

        // Good stretch. Now the long-term question: are rested measurements going up?
        let timeChanged = lastTimeChange(sessions, now: now, calendar: calendar)
        let since = [settingChanged, timeChanged, first.start].compactMap { $0 }.max() ?? first.start
        let sinceDays = now.timeIntervalSince(since) / 86_400
        if sinceDays < judgeDays {
            return card(.keep, "change nothing",
                        "Good stretch (\(pct)). Your last change was \(Int(sinceDays / 7)) week\(Int(sinceDays / 7) == 1 ? "" : "s") ago — wait 2–3 months before judging growth.")
        }
        let points = rested(data).compactMap { m in m.value(track.metric).map { (date: m.date, cm: $0) } }
        guard let latest = points.last,
              let baseline = points.last(where: { $0.date <= since.addingTimeInterval(7 * 86_400) }) ?? points.first,
              latest.date.timeIntervalSince(baseline.date) >= judgeDays * 86_400 else {
            return card(.keep, "change nothing",
                        "Good stretch (\(pct)). To judge growth, log a \(track.metric.title) measurement after 3+ days off — about every 3 months, measured the same way each time.")
        }
        let gain = latest.cm - baseline.cm
        let unit = data.settings.unit
        let gainText = String(format: "%+.2f %@", unit.display(gain), unit.label)
        if gain >= noiseCM {
            return card(.keep, "change nothing",
                        "Good stretch (\(pct)) and \(track.metric.title) \(gainText) since \(baseline.date.formatted(date: .abbreviated, time: .omitted)) on rested measurements. It's working.")
        }
        guard sinceDays >= stuckDays else {
            return card(.keep, "change nothing",
                        "Good stretch (\(pct)). \(track.metric.title) \(gainText) so far — within measuring error. Give it until 3 months after your last change.")
        }
        // Already added time and intensity in the last 6 months and still flat: rest properly.
        let earlier = sessions.filter { $0.start >= now.addingTimeInterval(-182 * 86_400) && $0.start < now.addingTimeInterval(-120 * 86_400) }
        let earlierSetting = earlier.filter { $0.type == mainType }.compactMap(value).max()
        let earlierMinutes = (18...25).map { weeklyMinutes(sessions, weeksAgo: $0, now: now, calendar: calendar) }.reduce(0, +) / 8 // same 4–6 month window as earlierSetting
        let recentMinutes = (1...4).map { weeklyMinutes(sessions, weeksAgo: $0, now: now, calendar: calendar) }.reduce(0, +) / 4
        let addedIntensity = (setting ?? 0) > (earlierSetting ?? .infinity) + 0.05
        let addedTime = earlierMinutes > 0 && recentMinutes >= earlierMinutes * 1.15
        if addedIntensity && addedTime {
            return card(.takeBreak, "take a proper break",
                        "Still flat (\(gainText)) after adding both time and intensity. Take a real break — a week to a month or more — then restart at your earlier settings.")
        }
        return card(.addTime, "add time, not pressure",
                    "Good stretch (\(pct)) but \(track.metric.title) is flat (\(gainText)) after ~3 months. \(track.addTimeHow) More often beats harder.")
    }
}
