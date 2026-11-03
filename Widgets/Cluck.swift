import Foundation

// Sergeant Cluck — the weekly-quota enforcer: a chicken in a drill-sergeant hat (🪖 in notifications).
// Compiled into the iPhone app AND the widget extension, so it only uses Foundation types.

/// What the app shares with the widget (via the App Group).
struct CluckSnapshot: Codable, Equatable {
    var goal: Int
    /// Start times of recent workouts (last ~3 weeks is plenty).
    var workoutDates: [Date]
    /// Day you used this week's "Not today" snooze.
    var snoozedDay: Date?
    /// CoachStyle raw value, for the 8:30pm closer.
    var coachStyle: String
    var enabled: Bool
    var updatedAt: Date
    /// Days you tapped "Rest day" on the gym side. They don't count — and he nags harder.
    var restDays: [Date]? = nil
    /// Sick / travel days: they lower that week's goal and he stands down on the day.
    var excusedDays: [Date]? = nil
    /// MK10: rest days planned the day before or earlier. He's chill on those (they don't lower the goal).
    var plannedRestDays: [Date]? = nil
    /// MK11: weeks in a row at the goal (before this one).
    var streakWeeks: Int? = nil
    /// MK11: pain flag, low readiness or several late nights — he eases off.
    var worried: Bool? = nil
    /// MK11: weekday (1 = Sunday … 7) you keep skipping, and his line about your training pattern.
    var skipWeekday: Int? = nil
    var patternLine: String? = nil
    /// MK11: tonight's bedtime per weekday (minutes after midnight) and late nights in the last 7.
    var bedtimes: [Int: Int]? = nil
    var lateNights: Int? = nil
    /// MK11.1: a workout is in progress (Locked In), an open pain flag (Protective),
    /// today's session was tagged "unusually tired" (Empathetic).
    var inWorkout: Bool? = nil
    var pain: Bool? = nil
    var toughDay: Bool? = nil
    /// MK11.3: "Give me a break" runs until this time — he stands down and backs you.
    var breakUntil: Date? = nil
}

enum CluckMood: String, Codable {
    case celebrating, proud, chill, watching, annoyed, furious, doomed, sulking
    /// MK11
    case suspicious, impressed, smug, worried, relieved, sleepy
    /// MK11.1
    case analytical, lockedIn, protective, empathetic

    /// Moods that send notifications.
    var nags: Bool { self == .annoyed || self == .furious || self == .doomed }

    var title: String {
        switch self {
        case .celebrating: return "Quota met"
        case .proud: return "Trained today"
        case .chill: return "At ease"
        case .watching: return "Watching you"
        case .annoyed: return "Annoyed"
        case .furious: return "FURIOUS"
        case .doomed: return "Disappointed"
        case .sulking: return "Sulking"
        case .suspicious: return "Suspicious"
        case .impressed: return "Impressed"
        case .smug: return "Smug"
        case .worried: return "Worried"
        case .relieved: return "Relieved"
        case .sleepy: return "Lights out"
        case .analytical: return "Analytical"
        case .lockedIn: return "Locked in"
        case .protective: return "Protective"
        case .empathetic: return "With you"
        }
    }
}

struct CluckState: Equatable {
    var mood: CluckMood
    var goal: Int
    var done: Int
    var remaining: Int
    /// Days left this week including today.
    var daysLeft: Int
    /// Rest days you can still take and hit the goal (negative = can't hit it).
    var spare: Int
    var trainedToday: Bool
    var snoozedToday: Bool
    var snoozeAvailable: Bool
    /// You declared today a gym rest day.
    var restDay: Bool = false
    /// MK10: …and you planned it ahead, so he's fine with it.
    var plannedRest: Bool = false
    /// MK11: extras for the lines.
    var streakWeeks: Int = 0
    var gapDays: Int = 0
    var lateNights: Int = 0
    var patternLine: String? = nil
    var onBreak: Bool = false
}

enum CluckEngine {
    /// Anger switches on at 5:10pm.
    static let cutoffHour = 17
    static let cutoffMinute = 10
    /// Notification times: 5:10pm, 7:00pm, 8:30pm.
    static let stages: [(hour: Int, minute: Int)] = [(17, 10), (19, 0), (20, 30)]

    static var calendar: Calendar { Calendar.current }

    static func evaluate(_ snapshot: CluckSnapshot, at date: Date = .now) -> CluckState {
        let cal = calendar
        let week = cal.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86_400)
        let excused = (snapshot.excusedDays ?? []).filter { $0 >= week.start && $0 < week.end }
        let excusedToday = excused.contains { cal.isDate($0, inSameDayAs: date) }
        // Each sick / travel day takes one session off this week's goal.
        let goal = max(snapshot.goal - excused.count, excused.isEmpty ? 1 : 0)
        let inWeek = snapshot.workoutDates.filter { $0 >= week.start && $0 < week.end && $0 <= date }
        let done = inWeek.count
        let trainedToday = inWeek.contains { cal.isDate($0, inSameDayAs: date) }
        let remaining = max(goal - done, 0)
        let today = cal.startOfDay(for: date)
        let daysLeft = max(cal.dateComponents([.day], from: today, to: week.end).day ?? 1, 1)
        // One session per day: if today is used, it can't hold another. Sick / travel days can't be used either.
        let excusedAhead = excused.filter { $0 >= today && !(trainedToday && cal.isDate($0, inSameDayAs: date)) }.count
        // Planned rest days ahead can't hold a session either (but don't lower the goal).
        let plannedRest = (snapshot.plannedRestDays ?? []).filter { $0 >= week.start && $0 < week.end }
        let plannedRestToday = plannedRest.contains { cal.isDate($0, inSameDayAs: date) }
        let restAhead = plannedRest.filter { day in
            day >= today && !excused.contains { cal.isDate($0, inSameDayAs: day) }
                && !(trainedToday && cal.isDate(day, inSameDayAs: date))
        }.count
        let usableDays = daysLeft - (trainedToday ? 1 : 0) - excusedAhead - restAhead
        let spare = usableDays - remaining

        let snoozedToday = snapshot.snoozedDay.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let snoozedThisWeek = snapshot.snoozedDay.map { $0 >= week.start && $0 < week.end } ?? false

        let cutoff = cal.date(bySettingHour: cutoffHour, minute: cutoffMinute, second: 0, of: date) ?? date
        let afterCutoff = date >= cutoff

        let restDay = snapshot.restDays?.contains { cal.isDate($0, inSameDayAs: date) } ?? false

        // MK11: the gap before today's session, and whether it's past tonight's bedtime.
        let previous = snapshot.workoutDates.filter { $0 < today }.max()
        let gapDays = previous.map { cal.dateComponents([.day], from: cal.startOfDay(for: $0), to: today).day ?? 0 } ?? 0
        let streak = snapshot.streakWeeks ?? 0
        let weekday = cal.component(.weekday, from: date)
        let minutesNow = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        var pastBedtime = false
        if minutesNow < 4 * 60 {
            // Small hours: compare with last night's bedtime (yesterday's weekday).
            let yesterday = weekday == 1 ? 7 : weekday - 1
            if let bed = snapshot.bedtimes?[yesterday] { pastBedtime = bed < 12 * 60 ? minutesNow >= bed : true }
        } else if let bed = snapshot.bedtimes?[weekday], bed >= 12 * 60 {
            pastBedtime = minutesNow >= bed
        }

        let mood: CluckMood
        if snapshot.inWorkout == true {
            // MK11.1: mid-workout he's all business.
            mood = .lockedIn
        } else if let until = snapshot.breakUntil, date < until {
            // MK11.3: on a break — no nagging, just support.
            mood = trainedToday ? .proud : .empathetic
        } else if pastBedtime {
            // MK11: after bedtime he only wants you asleep.
            mood = .sleepy
        } else if excusedToday && !trainedToday {
            // Sick or travelling: he stands down — and he's on your side (MK11.1).
            mood = (remaining == 0 && done > 0) ? .celebrating : .empathetic
        } else if plannedRestToday && !trainedToday {
            // A rest day you planned: recovery is part of the plan.
            mood = (remaining == 0 && done > 0) ? .celebrating : .chill
        } else if restDay && !trainedToday && remaining > 0 && !snoozedToday {
            // "Rest day"? Not on his watch.
            mood = spare < 0 ? .doomed : ((afterCutoff || spare <= 1) ? .furious : .annoyed)
        } else if remaining == 0 && (goal > 0 || done > 0) {
            mood = streak >= 3 ? .impressed : .celebrating
        } else if remaining == 0 {
            // The whole week excused (sick / travel) and nothing done: at ease, no celebration.
            mood = .chill
        } else if trainedToday {
            if snapshot.toughDay == true { mood = .empathetic }
            else if restDay || plannedRestToday { mood = .smug }
            else if gapDays >= 5 { mood = .relieved }
            else { mood = .proud }
        } else if snoozedToday {
            mood = .sulking
        } else if spare < 0 {
            mood = .doomed
        } else if snapshot.pain == true && spare >= 1 {
            // MK11.1: an injury flag — he guards you rather than yelling.
            mood = .protective
        } else if snapshot.worried == true && spare >= 1 {
            // Pain, low readiness or bad sleep: he eases off (unless the week is on the line).
            mood = .worried
        } else if !afterCutoff, snapshot.skipWeekday == weekday {
            mood = .suspicious
        } else if spare >= 2 {
            mood = snapshot.coachStyle == "analytical" ? .analytical : .chill
        } else if !afterCutoff {
            mood = .watching
        } else {
            mood = spare == 0 ? .furious : .annoyed
        }

        return CluckState(mood: mood, goal: goal, done: done, remaining: remaining, daysLeft: daysLeft,
                          spare: spare, trainedToday: trainedToday, snoozedToday: snoozedToday,
                          snoozeAvailable: !snoozedThisWeek, restDay: restDay, plannedRest: plannedRestToday,
                          streakWeeks: streak, gapDays: gapDays, lateNights: snapshot.lateNights ?? 0,
                          patternLine: snapshot.patternLine,
                          onBreak: snapshot.breakUntil.map { date < $0 } ?? false)
    }

    /// MK11: bedtimes (he turns sleepy) and 4am (back to normal) for the next 3 days, for widget timelines.
    static func sleepTimes(_ snapshot: CluckSnapshot?, now: Date = .now) -> [Date] {
        guard let bedtimes = snapshot?.bedtimes else { return [] }
        let cal = calendar
        var result: [Date] = []
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let bed = bedtimes[cal.component(.weekday, from: day)] ?? 23 * 60
            let fire = day.addingTimeInterval(Double(bed < 12 * 60 ? bed + 24 * 60 : bed) * 60)
            let morning = day.addingTimeInterval(28 * 3600)
            result += [fire, morning].filter { $0 > now }
        }
        return result
    }

    // MARK: Lines

    /// Rotates through options once per day so it doesn't repeat itself.
    private static func pick(_ options: [String], _ date: Date, salt: Int = 0) -> String {
        guard !options.isEmpty else { return "" }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return options[(day + salt) % options.count]
    }

    private static func spareText(_ s: CluckState) -> String {
        switch s.spare {
        case ..<0: return "can't hit \(s.goal) any more"
        case 0: return "zero rest days left"
        case 1: return "one rest day left"
        default: return "\(s.spare) rest days left"
        }
    }

    /// Widget / Today card line.
    static func line(_ s: CluckState, at date: Date = .now) -> String {
        let r = s.remaining, d = s.daysLeft
        if s.restDay && (s.mood == .annoyed || s.mood == .furious) {
            return pick(["Rest day? REST DAY? \(r) sessions left, \(d) days. Rest is for rotisserie chickens.",
                         "You called it a rest day. I call it a missed day with a nicer name.",
                         "Rest day logged. Disappointment also logged. \(r) to go."], date)
        }
        switch s.mood {
        case .celebrating:
            return pick(["Quota smashed. I'm… proud. Don't make it weird.",
                         "\(s.goal)/\(s.goal). The coop salutes you, recruit.",
                         "Week complete. Sergeant Cluck stands down."], date)
        case .proud:
            return pick(["Session logged. I'll allow it.",
                         "Good. You showed up. Feathers unruffled.",
                         "That's what I like to see. \(r) to go."], date)
        case .chill where s.plannedRest:
            return pick(["Planned rest day. Eat, sleep, grow. Back at it tomorrow.",
                         "Rest day on the plan — approved. Recovery is training too.",
                         "At ease, recruit. You earned this one. \(r) to go."], date)
        case .chill:
            return pick(["\(r) to go, \(d) days. I'm watching. Casually.",
                         "You've got time. Not infinite time.",
                         "At ease, recruit. For now."], date)
        case .watching:
            return pick(["\(r) left, \(d) days — \(spareText(s)). 5:10pm. Don't make me come over there.",
                         "I'm not mad. Yet. \(r) sessions, \(d) days.",
                         "Clock's ticking, recruit: \(spareText(s))."], date)
        case .annoyed:
            return pick(["One rest day left and you're spending it on THIS?",
                         "\(r) left, \(d) days. I can see you on the couch.",
                         "You're one skip away from me losing it."], date)
        case .furious:
            return pick(["\(r) sessions. \(d) days. ZERO rest days. GET. UP.",
                         "No more skips. Every. Single. Day.",
                         "I didn't hatch for this. Gym. NOW."], date)
        case .doomed:
            return pick(["\(s.goal) isn't happening this week. Damage control — get as close as you can.",
                         "The goal's gone. Your dignity doesn't have to be.",
                         "I'm not angry. I'm disappointed."], date)
        case .sulking:
            return pick(["Fine. Take your day. I'll remember this.",
                         "Snoozed. I'm writing this down.",
                         "Enjoy your day off. I'll be here. Judging."], date)
        case .suspicious:
            return pick([(s.patternLine.map { $0 + " " } ?? "") + "Today's one of those days. I'm watching.",
                         "This is the day you usually go missing. Prove me wrong, recruit.",
                         "Funny how this weekday keeps slipping. Not today."], date)
        case .impressed:
            return pick(["\(s.streakWeeks + 1) weeks straight at the goal. I'm… impressed. Don't tell anyone.",
                         "That's \(s.streakWeeks + 1) weeks in a row. Now THAT is discipline.",
                         "Week \(s.streakWeeks + 1) on target. Keep the streak alive, recruit."], date)
        case .smug:
            return pick(["Trained on a rest day. I knew you had it in you.",
                         "Rest day? Didn't need it. I like your style.",
                         "Planned rest, trained anyway. Just don't skip tomorrow's session for it."], date)
        case .worried:
            return pick(["Something's off — pain, bad sleep or low recovery. Train smart today, not hard.",
                         "Recovery's low. A lighter session still counts.",
                         "I yell because I care. Today I'm saying: be careful."], date)
        case .relieved:
            return pick(["There you are. \(s.gapDays) days, recruit. Don't do that to me again.",
                         "Back after \(s.gapDays) days. Good. Now stay back.",
                         "\(s.gapDays)-day gap closed. Welcome back to the coop."], date)
        case .analytical:
            return pick(["\(s.done)/\(s.goal) done, \(d) days, \(s.spare) spare. The numbers are on your side — for now.",
                         "Data says: \(r) sessions in \(d) days is comfortable. Data also says don't waste it.",
                         "Pace check: \(s.done) of \(s.goal). On track. Analysis complete."], date)
        case .lockedIn:
            return pick(["Workout in progress. Eyes front. Next set.",
                         "Locked in. Phone down between sets, recruit.",
                         "This is the part that counts. Finish the plan."], date)
        case .protective:
            return pick(["You've flagged pain. Train around it — nothing heroic today.",
                         "I protect my chicks. Skip what hurts, do what doesn't.",
                         "Pain flag's open. Lighter, smoother, pain-free reps only."], date)
        case .empathetic where s.onBreak:
            return pick(["You're on a break. Get those deadlines done — I'll be here when you're back.",
                         "Break approved. Sleep, eat, finish the work. The gym will wait, recruit.",
                         "Busy week. Two short sessions if you can, none if you can't. No judgement."], date)
        case .empathetic:
            return pick([s.trainedToday ? "Tired and you still trained. That's the job — now rest." : "Rough day. Rest, recover, come back stronger. I've got your back.",
                         "Even sergeants have off days. Look after yourself.",
                         s.trainedToday ? "Not your best day, but you showed up. That counts." : "Get better first. The gym will wait."], date)
        case .sleepy:
            return pick(["Lights out, recruit. Muscles grow in your sleep, not on your phone.",
                         s.lateNights >= 2 ? "That's \(s.lateNights) late nights this week. Bed. Now." : "It's past your bedtime. Phone down.",
                         "Tomorrow's session starts with tonight's sleep. Go to bed."], date)
        }
    }

    /// Notification for a stage (0 = 5:10, 1 = 7:00, 2 = 8:30). nil = no nag at that point.
    static func notification(_ s: CluckState, stage: Int, at date: Date, style: String) -> (title: String, body: String)? {
        guard s.mood.nags else { return nil }
        let r = s.remaining, d = s.daysLeft
        let reachable = s.done + min(d, r)
        let title: String
        switch s.mood {
        case .furious: title = "🪖 \(r) left · \(d) day\(d == 1 ? "" : "s") · ZERO rest days"
        case .annoyed: title = "🪖 \(r) left · \(d) days · one rest day left"
        default: title = "🪖 \(s.done)/\(s.goal) this week"
        }
        let body: String
        switch (s.mood, stage) {
        case (.annoyed, 0):
            body = pick(["It's 5:10. \(r) left, \(d) days. You've got ONE rest day left. Is it today? Really?",
                         "5:10pm, recruit. One skip left this week. Spend it wisely. (Don't spend it.)"], date)
        case (.furious, 0):
            body = pick(["It's 5:10. \(r) sessions, \(d) days, zero rest days. Shoes. On. Now.",
                         "5:10pm. Every day from here is a gym day. Today included. Especially today."], date)
        case (.doomed, 0):
            body = pick(["\(s.goal) isn't happening this week. But \(reachable) still is. Go.",
                         "Goal's out of reach. Getting closer isn't. Damage control starts tonight."], date)
        case (.annoyed, 1):
            body = pick(["Still nothing? I've been staring at the door for two hours.",
                         "7pm. Your rest day is ticking away and you didn't even enjoy it."], date)
        case (.furious, 1):
            body = pick(["7pm. The gym is still open. My patience is not.",
                         "You saw my last message. I know you did."], date)
        case (.doomed, 1):
            body = pick(["Every session still counts. Even now. Especially now.",
                         "Disappointed chicken noises."], date)
        default:
            // 8:30pm — the chicken, then your coach style.
            let opener = s.mood == .doomed ? "Last call." : "Last call, recruit."
            body = opener + " " + closer(style: style, remaining: r, daysLeft: d)
        }
        return (title, body)
    }

    static func closer(style: String, remaining: Int, daysLeft: Int) -> String {
        switch style {
        case "pushMe": return "Go now and it still counts."
        case "analytical": return "\(remaining) sessions in \(daysLeft) days requires one today."
        case "supportive": return "Even a short session counts — you've got this."
        case "hardTruth": return "Nobody's coming to make you. That's the point."
        case "heartbreak": return "She's not thinking about you tonight. Make tonight about you."
        default: return "30 minutes tonight keeps the week alive."
        }
    }
}

// MARK: - Random motivation, rest-day nags, Sunday recap

extension CluckEngine {
    private static func roll(_ options: [String], _ seed: Int) -> String {
        options.isEmpty ? "" : options[abs(seed) % options.count]
    }

    /// Mood bucket → the chicken's own words, plus a line tuned to your coach style.
    static func motivation(_ s: CluckState, style: String, seed: Int) -> (title: String, body: String) {
        let r = s.remaining, d = s.daysLeft
        let bucket: Int
        switch s.mood {
        case .celebrating, .proud, .impressed, .smug, .relieved, .lockedIn: bucket = 0
        case .chill, .sulking, .worried, .sleepy, .protective, .empathetic: bucket = 1
        case .watching, .annoyed, .furious, .suspicious, .analytical: bucket = 2
        case .doomed: bucket = 3
        }
        let chicken: [[String]] = [
            ["Look at you. Showing up. I might actually cry. I won't. But I might.",
             "Good work this week, recruit. Don't let it go to your comb.",
             "The coop is proud. Keep stacking days."],
            ["\(r) to go, \(d) days. Plenty of time — which is exactly how people waste it.",
             "Quiet morning. Suspiciously quiet. Get your bag packed.",
             "Hydrate. Eat your protein. Then come lift something heavy."],
            ["\(r) sessions, \(d) days. You do the maths. I already did. Move.",
             "Every hour you wait, the gym gets further away. Go now.",
             "I've been pecking at this screen all day. Get. To. The. Gym."],
            ["The week's goal is gone. Today still counts. Go anyway.",
             "Damage control, recruit. One session beats zero every time.",
             "You can't fix the week. You can fix today."]
        ]
        let styled: [String: [[String]]] = [
            "pushMe": [["Good. Now do it again."], ["Stop planning. Start lifting."], ["No more excuses. Go train."], ["Salvage it. Go."]],
            "motivating": [["You're building something real. Keep going."], ["One session today moves the whole week forward."], ["You've done harder things than this. Go."], ["Fresh start begins with one set."]],
            "analytical": [["On pace: \(s.done)/\(s.goal) this week."], ["\(r) sessions in \(d) days — \(s.spare) spare."], ["\(s.spare) spare days left. The margin is gone."], ["Best case this week: \(s.done + Swift.min(d, r))/\(s.goal)."]],
            "supportive": [["Proud of you. Rest well too."], ["Whenever you're ready — even a short session counts."], ["You can do this. Just start with the warm-up."], ["No guilt — just do what you can today."]],
            "hardTruth": [["Don't celebrate. Repeat."], ["Comfort is the enemy. Get moving."], ["Nobody is coming to drag you there. That's the point."], ["You didn't keep your word this week. Start keeping it today."]],
            "heartbreak": [["She'd barely recognise you now. Keep going.", "Every rep is a reason she'll regret it."],
                           ["She moved on. Did you? Prove it — go train.", "Turn the hurt into reps today."],
                           ["You were never 'not enough'. You were just not training. Go.", "She left. The bar didn't. Pick it up.", "Lying on the couch is exactly what she expected. Go."],
                           ["Rock bottom is a great place to build from. Gym. Now.", "Heartbreak doesn't excuse a missed week. Go fix today."]]
        ]
        // Gym-pattern comments (missed weekdays, gaps, shrinking sessions) come first when there is one.
        let base = bucket >= 1 && seed % 2 == 0 ? (s.patternLine ?? roll(chicken[bucket], seed)) : roll(chicken[bucket], seed)
        let tuned = styled[style].map { roll($0[bucket], seed / 3) } ?? ""
        let title: String
        switch bucket {
        case 0: title = "🪖 Sergeant Cluck approves"
        case 2: title = "🪖 Sergeant Cluck · \(r) left"
        case 3: title = "🪖 Sergeant Cluck"
        default: title = "🪖 A word from Sergeant Cluck"
        }
        // Heartbreak style leans on the style line; the others keep the chicken in front.
        let body = style == "heartbreak" && !tuned.isEmpty ? tuned + " 🪖" : (tuned.isEmpty ? base : base + " " + tuned)
        return (title, body)
    }

    /// Extra nags on a day you marked as a gym rest day.
    static func restDayNag(_ s: CluckState, index: Int, at date: Date) -> (title: String, body: String) {
        let r = s.remaining, d = s.daysLeft
        let lines = ["Rest day? Cute. \(r) sessions, \(d) days. I'll check again in two hours.",
                     "Still resting? The weights aren't. Neither am I.",
                     "Rest day update: still a bad idea. Gym's open.",
                     "You can still turn this 'rest day' into a gym day. Just saying. Loudly.",
                     "Your muscles aren't recovering. They're forgetting.",
                     "I'm not leaving you alone until you train or the day ends. Your call."]
        return ("🪖 Rest day? Really?", lines[(index + (calendar.ordinality(of: .day, in: .era, for: date) ?? 0)) % lines.count])
    }

    /// Sunday night recap.
    static func recap(sessions: Int, goal: Int, prs: Int, liftsUp: Int, restDays: Int, style: String) -> (title: String, body: String) {
        let stats = "\(sessions)/\(goal) sessions · \(prs) PR\(prs == 1 ? "" : "s") · \(liftsUp) lift\(liftsUp == 1 ? "" : "s") went up"
        let verdict: String
        if sessions >= goal {
            verdict = prs > 0 ? "Quota met AND PRs. Sergeant Cluck salutes you." : "Quota met. Solid week, recruit."
        } else if goal - sessions == 1 {
            verdict = "One short. So close it hurts. Next week, no excuses."
        } else {
            verdict = "\(goal - sessions) short. That's not a week, that's a warning."
        }
        let rest = restDays > 0 ? " (\(restDays) 'rest day\(restDays == 1 ? "" : "s")' — noted.)" : ""
        let styleNote: String
        switch style {
        case "heartbreak": styleNote = sessions >= goal ? " She's missing this version of you." : " Don't give her the satisfaction of a second bad week."
        case "hardTruth": styleNote = sessions >= goal ? " Now do it again." : " Results follow standards. Raise yours."
        case "supportive": styleNote = " Rest up tonight — new week tomorrow."
        default: styleNote = ""
        }
        return ("🪖 Week recap: \(sessions)/\(goal)", stats + ". " + verdict + rest + styleNote)
    }
}

extension CluckEngine {
    /// Weekly celebration when strength or muscle went up (nil = nothing to celebrate).
    static func celebration(strongerLifts: [String], leanChange: Double?, phase: String) -> String? {
        var parts: [String] = []
        if !strongerLifts.isEmpty {
            let names = strongerLifts.prefix(3).joined(separator: ", ")
            parts.append(strongerLifts.count == 1 ? "\(names) got STRONGER this week!" : "\(strongerLifts.count) lifts got stronger (\(names)\(strongerLifts.count > 3 ? "…" : ""))!")
        }
        if let lean = leanChange {
            if lean >= 0.2 {
                parts.append(String(format: "Muscle up %.1f kg this month!", lean))
            } else if phase == "cutting" && lean > -0.3 {
                parts.append("Muscle held steady on the cut — exactly the job.")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ") + " The coop is PROUD."
    }
}

/// Shared storage between the app and the widget.
enum CluckStore {
    static let appGroup = "group.com.jason.gymforge"
    static let key = "cluck.snapshot"
    static let widgetKind = "SergeantCluck"

    /// Falls back to the app's own defaults if the App Group isn't available (widget then shows a hint).
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load() -> CluckSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CluckSnapshot.self, from: data)
    }

    static func save(_ snapshot: CluckSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    /// Uses this week's snooze for today. Returns false if it was already used.
    @discardableResult
    static func snoozeToday(now: Date = .now) -> Bool {
        guard var snapshot = load() else { return false }
        let state = CluckEngine.evaluate(snapshot, at: now)
        guard state.snoozeAvailable else { return false }
        snapshot.snoozedDay = now
        save(snapshot)
        return true
    }
}
