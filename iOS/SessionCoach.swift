import Foundation

/// Builds the session preview for a routine: today's targets (exactly what the workout
/// will prefill, including program phase and deload), last time, trend and coaching
/// written in your coach style.
struct SessionPlan {
    var headline: [String]
    var estimatedMinutes: Int
    var totalSets: Int
    var exercises: [ExercisePreview]
    var isDeload: Bool
    var phaseName: String?
}

struct ExercisePreview: Identifiable {
    enum Trend {
        case new, improving, flat, declining, steady

        var label: String {
            switch self {
            case .new: return "New"
            case .improving: return "Improving"
            case .flat: return "Plateau"
            case .declining: return "Down"
            case .steady: return "Steady"
            }
        }
        var symbol: String {
            switch self {
            case .new: return "sparkles"
            case .improving: return "arrow.up.right"
            case .flat: return "arrow.right"
            case .declining: return "arrow.down.right"
            case .steady: return "equal"
            }
        }
    }

    let id: UUID
    let exercise: ExerciseDefinition
    let supersetLabel: String?
    let targetTitle: String
    let targetDetail: String?
    let lastTime: String?
    let lastDate: Date?
    let trend: Trend
    let hadPR: Bool
    let coaching: [String]
    let formCues: [String]
    let swaps: [String]
    /// Today's target for each set ("80 kg × 10 · 10 · 9") and why.
    var setPlanText: String? = nil
    var planReason: String? = nil
}

enum SessionCoach {
    static func plan(
        for routine: WorkoutRoutine,
        logs: [WorkoutLog],
        profile: UserProfile,
        readiness: Readiness?,
        now: Date = .now
    ) -> SessionPlan {
        // The same adjusted routine the workout will use (phase rep ranges, deload sets/weights).
        let state = ActiveWorkoutState.start(routine: routine, profile: profile, light: false, now: now)
        let style = profile.coachStyle
        let deload = state.isDeload == true

        var previews: [ExercisePreview] = []
        var readyToProgress = 0
        var totalSets = 0
        var seconds: Double = 0

        for (index, item) in state.routine.exercises.enumerated() {
            let exercise = item.exercise
            let history = logs.history(for: exercise).filter { $0.date < now }
            let previous = history.last?.log
            let recommendation = ProgressionEngine.recommendation(for: exercise, previous: previous)
            let prefill = state.prefill(for: item, logs: logs)
            let setPlan = state.setPlan(for: item, logs: logs)

            // Target
            let title: String
            var detail: String?
            var lines: [String] = []
            if exercise.isCardio {
                title = "\(exercise.cardioMinutes) min"
                detail = recommendation.message
                lines.append(line(.cardio, style))
                seconds += Double(exercise.cardioMinutes * 60)
            } else {
                let sets = exercise.defaultSets
                totalSets += sets
                seconds += Double(sets) * 45 + Double(max(sets - 1, 0) * exercise.restSeconds) + 60
                let range = "\(exercise.repMin)–\(exercise.repMax) reps"
                if previous == nil || prefill.weightKg <= 0 {
                    title = "\(sets) × \(range)"
                    detail = "Pick a weight you can control for \(exercise.repMax) reps."
                    lines.append(line(.first(repMin: exercise.repMin, repMax: exercise.repMax), style))
                } else {
                    let kg = GFFormat.kg(prefill.weightKg)
                    title = "\(sets) × \(kg) kg\(exercise.isAssisted ? " assist" : "") · \(range)"
                    switch recommendation.action {
                    case .increaseWeight:
                        readyToProgress += 1
                        detail = "Up from \(GFFormat.kg(previous?.bestWeightKg ?? 0)) kg"
                        lines.append(line(.progress(kg: kg, repMin: exercise.repMin), style))
                    case .reduceWeight:
                        detail = "Down from \(GFFormat.kg(previous?.bestWeightKg ?? 0)) kg"
                        lines.append(line(.reduce(kg: kg, repMin: exercise.repMin), style))
                    case .keepWeight(let target):
                        let last = previous?.totalReps ?? 0
                        detail = "Beat \(last) total reps"
                        lines.append(line(.keep(kg: kg, target: target, last: last), style))
                    case .noHistory, .cardio:
                        detail = nil
                    }
                    if exercise.isAssisted {
                        // Assisted: the weight is help — less is harder. Use the plain progression message.
                        let was = previous?.leastAssistanceKg.map { GFFormat.kg($0) } ?? "?"
                        switch recommendation.action {
                        case .increaseWeight: detail = "Less assistance (was \(was) kg) — harder"
                        case .reduceWeight: detail = "More assistance (was \(was) kg)"
                        default: break
                        }
                        lines = [recommendation.message]
                    }
                    if deload { detail = exercise.isAssisted ? "Deload: more assistance, one less set" : "Deload: lighter, one less set" }
                }
            }

            // Extra coaching from recent history (at most two more lines).
            var extras: [String] = []
            if let previousDate = history.last?.date {
                let days = Calendar.current.dateComponents([.day], from: previousDate, to: now).day ?? 0
                if days >= 14 { extras.append(line(.comeback(days: days), style)) }
            }
            let direction = trend(of: history.map(\.log), exercise: exercise)
            if !exercise.isCardio {
                if direction == .flat {
                    let swap = exercise.alternativeList.first?.name
                    extras.append(line(.plateau(sessions: min(history.count, 3), swap: swap), style))
                }
                if let previous, previous.sets.count >= 3,
                   let first = previous.sets.first?.reps, let last = previous.sets.last?.reps,
                   first > 0, Double(last) <= Double(first) * 0.7 {
                    extras.append(line(.dropOff(first: first, last: last, rest: exercise.restSeconds), style))
                }
                if previous?.hasPR == true {
                    extras.append(line(.prLast, style))
                } else if direction == .improving, let pct = improvement(history.map(\.log)) {
                    extras.append(line(.improving(percent: pct), style))
                }
            }
            lines.append(contentsOf: extras.prefix(2))

            previews.append(ExercisePreview(
                id: item.id,
                exercise: exercise,
                supersetLabel: state.supersetLabel(for: index),
                targetTitle: title,
                targetDetail: detail,
                lastTime: previous.map(lastTimeText),
                lastDate: history.last?.date,
                trend: direction,
                hadPR: previous?.hasPR == true,
                coaching: lines,
                formCues: FormCues.cues(for: exercise),
                swaps: exercise.alternativeList.map(\.name),
                setPlanText: exercise.isCardio || setPlan.targets.isEmpty ? nil : setPlan.compactText(for: exercise),
                planReason: exercise.isCardio ? nil : setPlan.reason
            ))
        }

        // Headline for the whole session.
        var headline: [String] = []
        if let readiness, readiness.level == .low {
            headline.append(line(.lowReadiness(score: readiness.score), style))
        }
        if deload {
            headline.append("Deload: one less set per exercise and about 10% lighter. Easy on purpose.")
        }
        if let phase = state.phaseName {
            headline.append("\(phase) phase — rep ranges are set for it.")
        }
        let lifts = previews.filter { !$0.exercise.isCardio }.count
        if lifts > 0 && !deload {
            headline.append(line(.sessionProgress(ready: readyToProgress, of: lifts), style))
        }

        return SessionPlan(
            headline: headline,
            estimatedMinutes: max(Int((seconds / 60).rounded()), 1),
            totalSets: totalSets,
            exercises: previews,
            isDeload: deload,
            phaseName: state.phaseName
        )
    }

    // MARK: - History analysis

    static func lastTimeText(_ log: ExerciseLog) -> String {
        if log.isCardio {
            var text = GFFormat.minutes(log.totalDurationSeconds)
            if log.totalDistanceKm > 0 { text += " · \(GFFormat.km(log.totalDistanceKm)) km" }
            return text
        }
        let sets = log.sets.map { "\(GFFormat.kg($0.weightKg))×\($0.reps)" }
        // Collapse "60×10, 60×10, 60×10" into "60×10 ×3".
        if let first = sets.first, sets.allSatisfy({ $0 == first }), sets.count > 1 {
            return "\(first) kg  ×\(sets.count) sets"
        }
        return sets.joined(separator: "  ·  ") + " kg"
    }

    static func trend(of logs: [ExerciseLog], exercise: ExerciseDefinition) -> ExercisePreview.Trend {
        let strength = logs.filter { !$0.isCardio && $0.estimatedOneRepMaxKg > 0 }
        if exercise.isCardio {
            let cardio = logs.filter { $0.totalDurationSeconds > 0 }
            guard cardio.count >= 2 else { return .new }
            let a = cardio[cardio.count - 2].totalDurationSeconds, b = cardio.last!.totalDurationSeconds
            return b > a * 1.02 ? .improving : (b < a * 0.9 ? .declining : .steady)
        }
        guard strength.count >= 2 else { return .new }
        let recent = Array(strength.suffix(4))
        let latest = recent.last!.estimatedOneRepMaxKg
        let earlierBest = recent.dropLast().map(\.estimatedOneRepMaxKg).max() ?? latest
        if latest > earlierBest * 1.01 { return .improving }
        if latest < earlierBest * 0.93 { return .declining }
        // Three or more sessions without beating the earlier best = plateau.
        if recent.count >= 3 && latest <= earlierBest * 1.005 { return .flat }
        return .steady
    }

    /// Estimated 1RM change from ~3 sessions ago to the latest, in whole percent.
    static func improvement(_ logs: [ExerciseLog]) -> Int? {
        let strength = logs.filter { $0.estimatedOneRepMaxKg > 0 }
        guard strength.count >= 2 else { return nil }
        let base = strength[max(strength.count - 4, 0)].estimatedOneRepMaxKg
        let latest = strength.last!.estimatedOneRepMaxKg
        guard base > 0 else { return nil }
        let pct = Int(((latest / base - 1) * 100).rounded())
        return pct > 0 ? pct : nil
    }

    // MARK: - Voice

    enum Kind {
        case progress(kg: String, repMin: Int)
        case keep(kg: String, target: Int, last: Int)
        case reduce(kg: String, repMin: Int)
        case first(repMin: Int, repMax: Int)
        case cardio
        case plateau(sessions: Int, swap: String?)
        case improving(percent: Int)
        case dropOff(first: Int, last: Int, rest: Int)
        case comeback(days: Int)
        case prLast
        case lowReadiness(score: Int)
        case sessionProgress(ready: Int, of: Int)
    }

    static func line(_ kind: Kind, _ style: CoachStyle) -> String {
        switch kind {
        case let .progress(kg, repMin):
            switch style {
            case .pushMe: return "You earned it — \(kg) kg today. Own the first set."
            case .motivating: return "Time to move up to \(kg) kg. Start around \(repMin) reps and build from there."
            case .analytical: return "Every working set hit the top of the range. Load \(kg) kg, target \(repMin)+ reps."
            case .supportive: return "Great work last time — try \(kg) kg. If it feels wrong, stay where you were."
            case .hardTruth: return "You hit every rep last time. \(kg) kg now. Comfort never built anything."
            case .heartbreak: return "Heavier today — \(kg) kg. Show her exactly what you turned into."
            }
        case let .keep(kg, target, last):
            switch style {
            case .pushMe: return "Same \(kg) kg. \(target)+ total reps or it didn't count."
            case .motivating: return "Stay at \(kg) kg and beat \(last) total reps — one extra rep is progress."
            case .analytical: return "Hold \(kg) kg. Last session: \(last) total reps. Target: \(target)+."
            case .supportive: return "Keep \(kg) kg and aim for \(target) reps in total. Matching last time is fine too."
            case .hardTruth: return "\(last) reps last time. \(target) today. No excuses at \(kg) kg."
            case .heartbreak: return "\(last) reps last time. Nobody thinks you'll get \(target). Get \(target) at \(kg) kg."
            }
        case let .reduce(kg, repMin):
            switch style {
            case .pushMe: return "Too heavy last time. Drop to \(kg) kg and own every rep."
            case .motivating: return "Step back to \(kg) kg — one step back to come back stronger."
            case .analytical: return "All sets finished under \(repMin) reps. Reduce to \(kg) kg and rebuild the range."
            case .supportive: return "Go a little lighter at \(kg) kg. Good reps beat heavy, ugly ones."
            case .hardTruth: return "Ego lifting is why you stalled. \(kg) kg, clean reps."
            case .heartbreak: return "Ego got you nowhere. \(kg) kg, every rep clean — rebuild like you're rebuilding yourself."
            }
        case let .first(repMin, repMax):
            switch style {
            case .pushMe: return "First time. Find a weight that makes \(repMax) reps hard — then that's your number."
            case .motivating: return "New exercise! Find a weight you can lift for \(repMin)–\(repMax) good reps."
            case .analytical: return "No history. Use set 1 to calibrate: aim to finish near \(repMax) reps with 1–2 in reserve."
            case .supportive: return "First go — start light and learn the movement. The app will take it from here."
            case .hardTruth: return "No data yet. Pick an honest weight and log it. Everything starts somewhere."
            case .heartbreak: return "Day one on this one. Everything new starts here — find your weight."
            }
        case .cardio:
            switch style {
            case .pushMe: return "Go a little longer or faster than last time. No coasting."
            case .motivating: return "Beat last time by a minute or a little more distance."
            case .analytical: return "Aim for a small increase in time or distance versus last session."
            case .supportive: return "Steady effort — any time you put in counts."
            case .hardTruth: return "Cardio is where the excuses come out. Finish the time."
            case .heartbreak: return "Run it out. Every minute is one less minute thinking about her."
            }
        case let .plateau(sessions, swap):
            let alt = swap.map { " Or swap to \($0)." } ?? ""
            switch style {
            case .pushMe: return "Stuck for \(sessions) sessions. Lower in 3 seconds and fight for one more rep.\(alt)"
            case .motivating: return "Flat for \(sessions) sessions — change the stimulus with slow 3-second negatives.\(alt)"
            case .analytical: return "No estimated-1RM gain in \(sessions) sessions. Options: 3 s eccentrics, an extra set\(swap.map { ", or \($0)" } ?? "")."
            case .supportive: return "Plateaus are normal. Try slower lowering today.\(alt)"
            case .hardTruth: return "\(sessions) sessions, same numbers. Something has to change — 3-second negatives.\(alt)"
            case .heartbreak: return "\(sessions) sessions stuck in the same place. Don't stay stuck — slow negatives.\(alt)"
            }
        case let .improving(percent):
            switch style {
            case .pushMe: return "Up \(percent)% recently. Keep the pressure on."
            case .motivating: return "\(percent)% stronger over your last few sessions — keep it rolling."
            case .analytical: return "Estimated 1RM +\(percent)% over the last few sessions."
            case .supportive: return "You're \(percent)% stronger than a few sessions ago. That's real."
            case .hardTruth: return "+\(percent)%. Good. Don't get comfortable."
            case .heartbreak: return "+\(percent)% stronger. The guy she left is already gone."
            }
        case let .dropOff(first, last, rest):
            let restText = GFFormat.duration(TimeInterval(rest))
            switch style {
            case .pushMe: return "Reps fell from \(first) to \(last) last time. Take the full \(restText) and hit every set hard."
            case .motivating: return "You went \(first) → \(last) reps. A little more rest keeps you strong to the last set."
            case .analytical: return "Rep drop-off \(first) → \(last) across sets. Consider resting longer than \(restText)."
            case .supportive: return "The last sets got tough (\(first) → \(last)). Take your time between sets."
            case .hardTruth: return "\(first) to \(last). You faded. Rest properly and finish like you started."
            case .heartbreak: return "You faded, \(first) → \(last). Finishing strong is the point — rest \(restText), then go."
            }
        case let .comeback(days):
            switch style {
            case .pushMe: return "\(days) days since this one. First set conservative, then back to work."
            case .motivating: return "Welcome back after \(days) days — ease into the first set."
            case .analytical: return "\(days)-day gap: expect 5–10% lower. Treat today's targets as a ceiling."
            case .supportive: return "It's been \(days) days — go easy on the first set, no pressure."
            case .hardTruth: return "\(days) days off. You know why. Start lighter and earn it back."
            case .heartbreak: return "\(days) days away. Starting again isn't losing — ease in and rebuild."
            }
        case .prLast:
            switch style {
            case .pushMe: return "PR last time. Defend it."
            case .motivating: return "You set a PR last time — ride that momentum."
            case .analytical: return "Last session included a PR."
            case .supportive: return "You hit a PR last time. Well done."
            case .hardTruth: return "PR last time. Now do it again."
            case .heartbreak: return "PR last time. Keep proving it."
            }
        case let .lowReadiness(score):
            switch style {
            case .pushMe: return "Recovery is low (\(score)). Still show up — keep 1–2 reps in reserve."
            case .motivating: return "Recovery's a bit low today (\(score)). A light session still counts."
            case .analytical: return "Readiness \(score)/100. Consider the light session or 1–2 reps in reserve."
            case .supportive: return "Your body's tired today (\(score)). Going light is a smart choice."
            case .hardTruth: return "Readiness \(score). Tired isn't an excuse to skip — but go light."
            case .heartbreak: return "Running on empty (\(score)). Show up anyway — light, but show up."
            }
        case let .sessionProgress(ready, total):
            if ready == 0 {
                switch style {
                case .pushMe: return "No weight jumps today. Win on reps — every set."
                case .motivating: return "Today's about beating reps — stack them up."
                case .analytical: return "0/\(total) exercises meet the progression rule. Focus: total reps."
                case .supportive: return "No weight changes today — just aim for a rep or two more."
                case .hardTruth: return "Nothing's going up yet. Earn it with reps."
                case .heartbreak: return "No weight jumps yet. Grind the reps — that's how you get back up."
                }
            }
            switch style {
            case .pushMe: return "\(ready) lift\(ready == 1 ? "" : "s") going up today. No backing off."
            case .motivating: return "\(ready) of \(total) exercises are ready to go heavier — great day to push."
            case .analytical: return "\(ready)/\(total) exercises meet the progression rule."
            case .supportive: return "\(ready) exercise\(ready == 1 ? " is" : "s are") ready to go up — only if it feels right."
            case .hardTruth: return "\(ready) weight increase\(ready == 1 ? "" : "s") on the board. Earn \(ready == 1 ? "it" : "them")."
            case .heartbreak: return "\(ready) lift\(ready == 1 ? "" : "s") going up today. Every one is for you, not her."
            }
        }
    }
}
