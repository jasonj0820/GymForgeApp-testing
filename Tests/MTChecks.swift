import Foundation

// More Training routine + progression checks (Foundation-only). Run: ./Scripts/run_mt_checks.sh
@main
struct MTChecks {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("ok  \(message)")
    }

    static func main() {
        let cal = Calendar.current
        let day: TimeInterval = 86_400
        let now = cal.startOfDay(for: .now).addingTimeInterval(19 * 3600)
        func at(_ daysAgo: Double, hour: Double = 18) -> Date { cal.startOfDay(for: now).addingTimeInterval(-daysAgo * day + hour * 3600) }
        func session(_ type: MTType, _ daysAgo: Double, minutes: Double, pressure: Double? = nil, tension: Double? = nil,
                     nir: Bool? = nil, expansion: Double? = nil, warnings: [MTWarning]? = nil) -> MTSession {
            var s = MTSession(type: type, start: at(daysAgo), end: at(daysAgo).addingTimeInterval(minutes * 60),
                              pressureInHg: pressure, tensionKg: tension, nir: nir, expansionPercent: expansion)
            s.warnings = warnings
            return s
        }

        // Routine (MK20.1): two options — NIR + PAC, or no NIR + static pump — taking turns
        check(MTPlan.options == [MTPlan.Day(nir: true, pumpType: .pac), MTPlan.Day(nir: false, pumpType: .pump)], "two options: NIR + PAC, no NIR + static pump")
        check(MTPlan.day([], now: now) == MTPlan.nirPAC, "first day: NIR + PAC")
        let yesterday = [session(.highTensionExtender, 1, minutes: 15, nir: true), session(.pac, 1, minutes: 25, pressure: 10)]
        let today = MTPlan.day(yesterday, now: now)
        check(today == MTPlan.pumpOnly, "NIR + PAC yesterday → no NIR + static pump today")
        check(today.extenderMinutes == 40 && today.pumpMinutes == 20, "static pump day is 40 min extending + 4 × 5 min pump")
        let dayAfter = MTPlan.day([session(.highTensionExtender, 3, minutes: 15, nir: true), session(.pump, 2, minutes: 20)], now: now)
        check(dayAfter == MTPlan.nirPAC && dayAfter.extenderMinutes == 50 && dayAfter.pumpMinutes == 25, "pump last time (missed a day) → NIR + PAC (50 + 25 min)")
        let started = MTPlan.day(yesterday + [session(.pump, 0, minutes: 5)], now: now)
        check(started == MTPlan.pumpOnly, "already pumped today → today stays static pump")
        let pickedAgain = MTPlan.day(yesterday + [session(.highTensionExtender, 0, minutes: 15, nir: true)], now: now)
        check(pickedAgain == MTPlan.nirPAC, "picked NIR + PAC again today → today shows NIR + PAC")
        let steps = MTPlan.steps(MTPlan.Day(nir: true, pumpType: .pac), pressure: 8.5, tension: 3)
        check(steps.count == 7 && steps[0].nir == true && steps[0].workMinutes == 15 && steps[1].nir == nil && steps[1].workMinutes == 35
              && steps[2...].allSatisfy { $0.type == .pac && $0.cue != nil }, "NIR PAC day timer: HTE 15 NIR → HTE 35 → 5 guided PAC steps")
        check(MTPlan.pacSteps.map(\.pressureInHg) == [7.5, 8, nil, 9, 10], "PAC vacuum −7.5 → −8 → released → −9 → −10")
        let run = MTActiveInterval.build(name: "Daily routine", steps: steps, now: now)
        let plainHTE = [MTPresetStep(type: .highTensionExtender, rounds: 1, workMinutes: 40, restMinutes: 0)]

        // How the timer saves each step: guided PAC folds into one session at its top vacuum.
        func runSteps(_ steps: [MTPresetStep]) -> MTData {
            var data = MTData()
            var run = MTActiveInterval.build(name: "test", steps: steps, now: now)
            var t = now
            for (phaseIndex, phase) in run.phases.enumerated() {
                run.index = phaseIndex
                if run.stepStarts[phase.stepIndex] == nil { run.stepStarts[phase.stepIndex] = t }
                if phase.kind == .work { run.workDone[phase.stepIndex, default: 0] += phase.seconds }
                t = t.addingTimeInterval(phase.seconds)
                let lastWork = !run.phases[(phaseIndex + 1)...].contains { $0.stepIndex == phase.stepIndex && $0.kind == .work }
                if phase.kind == .work, lastWork { _ = data.logStep(run, stepIndex: phase.stepIndex, end: t) }
            }
            return data
        }
        let guided = runSteps(MTPlan.pacSteps).sessions
        check(guided.count == 1 && guided[0].type == .pac && guided[0].pressureInHg == 10 && guided[0].duration == 25 * 60,
              "guided PAC saves as one 25-min PAC at −10 inHg, not five sessions")
        let routineDay = runSteps(steps).sessions
        check(routineDay.map(\.type) == [.highTensionExtender, .highTensionExtender, .pac] && routineDay[0].nir == true && routineDay[2].duration == 25 * 60,
              "NIR PAC day saves HTE+NIR, HTE, and one PAC")
        check(runSteps(MTPlan.steps(MTPlan.Day(nir: false, pumpType: .pump), pressure: 8.5, tension: 3)).sessions.map(\.rounds) == [1, 4],
              "static pump 4 × 5 stays one session of 4 rounds")
        check(run.phases.filter { $0.kind == .work }.reduce(0) { $0 + $1.seconds } == 75 * 60, "75 min of work on a NIR PAC day")
        check(MTPlan.pacSteps.map(\.workMinutes) == [2, 5, 3, 5, 10], "PAC: fill 2 → set 5 → fresh blood 3 → set 5 → final 10")
        check(MTPlan.pacSteps[4].cue?.contains("−10 inHg (−34 kPa)") == true && MTPlan.pacSteps[4].cue?.contains("+12 inHg (+41 kPa)") == true,
              "PAC cues show inHg and kPa for vacuum and clamp")
        var trainedToday = MTData(); trainedToday.sessions = [session(.pump, 0.4, minutes: 20)]
        let reminders = MTPlan.reminderDates(trainedToday, now: now)
        check(reminders.count == 6 && !reminders.contains { Calendar.current.isDate($0, inSameDayAs: now) },
              "8:45pm reminder skips today once trained, then the next 6 days")
        check(MTPlan.reminderDates(MTData(), now: at(0, hour: 21)).count == 6, "after 8:45pm, today's reminder is gone")
        var timing = MTData(); timing.activeInterval = MTActiveInterval.build(name: "HTE", steps: plainHTE, now: at(0, hour: 20.3))
        let duringTimer = MTPlan.reminderDates(timing, now: at(0, hour: 20.5))
        check(duringTimer.count == 6 && !duringTimer.contains { Calendar.current.isDate($0, inSameDayAs: now) },
              "no 'Time to train' at 8:45pm while a timer is running (steps save when they finish)")
        var hurt = MTData()
        hurt.sessions = [{ var s = MTSession(type: .pump, start: at(1, hour: 22), end: at(1, hour: 22.3)); s.warnings = [.pain]; return s }()]
        let restDates = MTPlan.reminderDates(hurt, now: now)
        let tomorrow = now.addingTimeInterval(day)
        check(restDates.count == 5 && !restDates.contains { cal.isDate($0, inSameDayAs: now) || cal.isDate($0, inSameDayAs: tomorrow) },
              "pain logged last night → no 'Time to train' for the 2 rest days the safety check asks for")
        check(run.phases.filter { $0.stepIndex >= 2 }.allSatisfy { $0.kind == .work }, "guided PAC runs straight through, no rests")
        let plain = MTPlan.steps(MTPlan.Day(nir: false, pumpType: .pump), pressure: nil, tension: nil)
        check(plain.count == 2 && plain[0].workMinutes == 40, "no-NIR timer: HTE 40 → static pump 4 × 5")
        let doneToday = [session(.highTensionExtender, 0, minutes: 15, nir: true), session(.highTensionExtender, 0, minutes: 35), session(.pac, 0, minutes: 25)]
        let nirDay = MTPlan.nirPAC
        check(MTPlan.isComplete(MTPlan.done(doneToday, day: nirDay, now: now), day: nirDay), "50 min (15 NIR) + 25 min PAC completes NIR + PAC")
        check(!MTPlan.isComplete(MTPlan.done(Array(doneToday.dropFirst()), day: nirDay, now: now), day: nirDay), "skipping the NIR part isn't complete")

        func pacWeek(_ days: [Double]) -> Bool {
            var d = MTData(); d.sessions = days.map { session(.pac, $0, minutes: 29) }
            return MTSafety.advice(d, now: now).contains { $0.title == "Too much PAC this week" }
        }
        check(!pacWeek([0, 2, 4, 6]) && pacWeek([0, 1, 2, 3, 4]), "PAC 4×/week is fine, 5× in 7 days gets the 3–4×/week warning")

        // Progression
        func pumps(_ days: ClosedRange<Int>, pressure: Double, expansion: Double?) -> [MTSession] {
            days.map { session(.pump, Double($0), minutes: 20, pressure: pressure, expansion: expansion) }
        }
        func girth(_ sessions: [MTSession], _ measurements: [MTMeasurement] = []) -> MTProgression.Advice? {
            var data = MTData()
            data.sessions = sessions
            data.measurements = measurements
            return MTProgression.advice(for: .girth, data, now: now)
        }
        check(girth(pumps(1...30, pressure: 8.5, expansion: nil))?.kind == .needData, "no expansion logged → asks for before/after girth")
        check(girth(pumps(1...30, pressure: 7.5, expansion: 5))?.kind == .raise, "5% at the same pressure for weeks → raise one step")
        check(girth(pumps(1...30, pressure: 7.5, expansion: 5))?.message.contains("8.0–8.5") == true, "step is 0.5–1 inHg (7.5 → 8.0–8.5)")
        check(girth(pumps(1...30, pressure: 8.0, expansion: 5))?.message.contains("Go up to 8.5 inHg") == true, "never suggests past your 8.5 inHg max")
        let atMax = girth(pumps(1...30, pressure: 8.5, expansion: 5))
        check(atMax?.kind == .addTime && atMax?.message.contains("your max") == true && atMax?.message.contains("10 to 12 min") == true,
              "at 8.5 inHg (your max) → add time (PAC final set 10 → 12 min), not pressure")
        func pressureWarning(_ type: MTType, _ inHg: Double) -> Bool {
            var d = MTData(); d.sessions = [session(type, 1, minutes: 20, pressure: inHg)]
            return MTSafety.advice(d, now: now).contains { $0.title == "Pressure is high" }
        }
        check(!pressureWarning(.pump, 8.5) && !pressureWarning(.pac, 10) && pressureWarning(.pump, 9.5) && pressureWarning(.pac, 11),
              "'Pressure is high' only above your plan (pump 8.5, PAC −10 inHg)")
        check(girth(pumps(6...30, pressure: 8.0, expansion: 9) + pumps(1...5, pressure: 8.5, expansion: 5))?.kind == .hold,
              "changed pressure 5 days ago → hold it 2 weeks first")
        check(girth(pumps(1...30, pressure: 8.5, expansion: 14))?.kind == .tooMuch, "14% → don't chase pressure")
        check(girth(pumps(1...30, pressure: 8.5, expansion: 8) + [session(.pac, 2, minutes: 20, warnings: [.weakErections])])?.kind == .backOff,
              "weaker erections → back off, whatever the numbers")
        check(girth(pumps(1...20, pressure: 8.5, expansion: 8))?.kind == .keep, "good expansion, new routine → change nothing, judge in 2–3 months")
        let pac = (1...30).filter { $0 % 2 == 0 }.map { session(.pac, Double($0), minutes: 20, pressure: 6, expansion: 8) }
        let alt = (1...30).filter { $0 % 2 == 1 }.map { session(.pump, Double($0), minutes: 20, pressure: 8.5, expansion: 8) }
        check(girth(pac + alt)?.kind == .keep, "pump and PAC at their own pressures isn't read as 'changed every day'")
        // Guided PAC logged step by step (as MK18.2/MK19 did): −7.5 → −10 within each session isn't a daily "change".
        let splitPAC = (1...100).filter { $0 % 2 == 1 }.flatMap { daysAgo -> [MTSession] in
            var t = at(Double(daysAgo))
            return MTPlan.pacSteps.map { step in
                defer { t = t.addingTimeInterval(step.workMinutes * 60) }
                return MTSession(type: .pac, start: t, end: t.addingTimeInterval(step.workMinutes * 60), pressureInHg: step.pressureInHg, expansionPercent: 8)
            }
        }
        let pumpDays = (1...100).filter { $0 % 2 == 0 }.map { session(.pump, Double($0), minutes: 20, pressure: 8.5, expansion: 8) }
        check(MTProgression.lastSettingChange(splitPAC, track: .girth) == nil, "PAC's climbing vacuum isn't read as a settings change")
        let mixed = girth(splitPAC + pumpDays)
        check(mixed?.kind == .keep && mixed?.message.contains("changed settings") == false, "pump + guided PAC for 100 days → no false 'hold the new setting'")

        // Long term: rested measurements decide
        let long = pumps(1...110, pressure: 8.5, expansion: 8)
        func measure(_ daysAgo: Double, mg: Double) -> MTMeasurement { MTMeasurement(date: at(daysAgo, hour: 8), mg: mg) }
        var restedLong = long.filter { ![101, 102, 103, 3, 4, 5].contains(Int((now.timeIntervalSince($0.start) / day).rounded(.down))) }
        restedLong.sort { $0.start < $1.start }
        check(girth(restedLong, [measure(100, mg: 12.0), measure(2, mg: 12.5)])?.message.contains("It's working") == true, "+0.5 cm on rested measurements → it's working, change nothing")
        check(girth(restedLong, [measure(100, mg: 12.0), measure(2, mg: 12.1)])?.kind == .addTime, "flat (within error) after 3+ months → add time, not pressure")
        check(MTProgression.rested({ var d = MTData(); d.sessions = long; d.measurements = [measure(2, mg: 13)]; return d }()).isEmpty,
              "a measurement the morning after a session isn't rested")
        // Already added time and pressure in the last 6 months and still flat → proper break
        let earlier = (125...175).filter { $0 % 2 == 0 }.map { session(.pump, Double($0), minutes: 10, pressure: 7.5, expansion: 8) }
        let stuck = earlier + restedLong
        check(girth(stuck, [measure(100, mg: 12.0), measure(2, mg: 12.05)])?.kind == .takeBreak, "flat after adding time and intensity → take a proper break")
        print("PASS: More Training checks")
    }
}
