import ActivityKit
import Foundation
import WidgetKit

/// MK17: starts, updates and ends the More Training timer Live Activity from the vault's state.
/// Called after every save while unlocked, so it follows start / pause / resume / skip / stop.
@MainActor
enum MTLiveTimer {
    typealias State = MTTimerAttributes.ContentState

    static func sync(_ data: MTData, now: Date = .now) {
        MTWidgetStore.save(widgetSnapshot(for: data, now: now))   // MK20.6: the More Training widget
        let running = Activity<MTTimerAttributes>.activities
        guard let plan = content(for: data, now: now), ActivityAuthorizationInfo().areActivitiesEnabled else {
            let showing = running.filter { [.active, .stale].contains($0.activityState) }
            guard !showing.isEmpty else { return }
            Task {
                for activity in showing { await activity.end(nil, dismissalPolicy: .immediate) }
                PhoneAppStore.shared.refreshCluck()   // MK19.1: Sergeant Cluck's card comes straight back
                reloadWidget()
            }
            return
        }
        let content = ActivityContent(state: plan.state, staleDate: plan.stale)
        CluckActivityManager.endAll()   // only one card on the Lock Screen: the timer replaces Sergeant Cluck
        if let current = running.first {
            for other in running.dropFirst() { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            guard current.content.state != plan.state || current.content.staleDate != plan.stale else { return }
            Task {
                await current.update(content)
                reloadWidget()
            }
        } else {
            _ = try? Activity.request(attributes: MTTimerAttributes(startedAt: plan.start), content: content, pushType: nil)
            reloadWidget()
        }
    }

    /// MK20.6.1: the widget may read the Live Activity (when the App Group isn't shared), so refresh it
    /// once the card has changed.
    private static func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: MTWidgetStore.kind)
    }

    /// What the card shows now, when it goes stale (phase end / time limit), and when the session began.
    nonisolated static func content(for data: MTData, now: Date) -> (state: State, stale: Date?, start: Date)? {
        guard var result = baseContent(for: data, now: now) else { return nil }
        result.state.widgetTitle = widgetTitle(for: data)   // MK20.6.1: only the widget reads it
        return result
    }

    /// The step's name for the More Training widget ("HTE + NIR", "PAC", "Stamina").
    nonisolated static func widgetTitle(for data: MTData) -> String? {
        if let run = data.activeInterval, let phase = run.currentPhase, phase.stepIndex < run.steps.count {
            let step = run.steps[phase.stepIndex]
            return step.type.shortTitle + (step.nir == true ? " + NIR" : "")
        }
        if data.activeStamina != nil { return "Stamina" }
        if let active = data.activeSession { return active.type.shortTitle + (active.nir == true ? " + NIR" : "") }
        return nil
    }

    nonisolated private static func baseContent(for data: MTData, now: Date) -> (state: State, stale: Date?, start: Date)? {
        if let run = data.activeInterval, let phase = run.currentPhase {
            let rounds = phase.stepIndex < run.steps.count ? max(run.steps[phase.stepIndex].rounds, 1) : 1
            let label = phase.kind == .rest ? "Rest" : (rounds > 1 ? "Work · \(phase.round) of \(rounds)" : "Work")
            let start = run.stepStarts[0] ?? run.phaseStartedAt
            let next = nextText(run)
            if let paused = run.pausedRemaining {
                return (State(label: label, pausedRemaining: paused, next: next, isInterval: true), nil, start)
            }
            guard let end = run.phaseEnd() else { return nil }
            let rest = run.phases.dropFirst(run.index + 1).reduce(0) { $0 + $1.seconds }
            return (State(label: label, countdownTo: end, next: next, endsAt: end.addingTimeInterval(rest), isInterval: true), end, start)
        }
        // MK20.5: stamina — counts down to the goal, then counts up your active time; cool-downs count down.
        if let run = data.activeStamina {
            let pauses = run.pauses == 0 ? nil : (run.pauses == 1 ? "1 pause" : "\(run.pauses) pauses")
            if let until = run.cooldownUntil {
                let active = "Active " + MTTimerAttributes.clock(run.active(at: now))
                return (State(label: "Cool-down", countdownTo: until, next: [active, pauses].compactMap { $0 }.joined(separator: " · "),
                              isInterval: false, stamina: true), until, run.start)
            }
            guard let since = run.runningSince else { return nil }
            let activeStart = since.addingTimeInterval(-run.accumulated)   // counting up from here = total active time
            let goalAt = activeStart.addingTimeInterval(run.goalSeconds)
            if goalAt > now {
                return (State(label: "Timer · goal in", countdownTo: goalAt, countUpFrom: activeStart, next: pauses,
                              isInterval: false, stamina: true), goalAt, run.start)
            }
            return (State(label: "Goal reached", countUpFrom: activeStart, next: pauses ?? "Keep going or finish",
                          isInterval: false, stamina: true), nil, run.start)
        }
        if let active = data.activeSession {
            let limit = data.settings.limit(for: active.type).map { active.start.addingTimeInterval(Double($0 * 60)) }
            if let limit, limit > now {
                return (State(label: "Timer · limit in", countdownTo: limit, countUpFrom: active.start, isInterval: false), limit, active.start)
            }
            return (State(label: limit == nil ? "Timer" : "Limit reached", countUpFrom: active.start, isInterval: false), nil, active.start)
        }
        return nil
    }

    // MARK: More Training widget (MK20.6)

    /// The widget's view of the timer: the step you're on, upcoming phases (so it keeps up while the app
    /// sleeps), and which buttons make sense right now. nil when no timer is running.
    nonisolated static func widgetSnapshot(for data: MTData, now: Date) -> MTWidgetSnapshot? {
        typealias Step = MTWidgetSnapshot.Step
        typealias Control = MTWidgetSnapshot.Control
        if let run = data.activeInterval, let phase = run.currentPhase {
            func title(_ stepIndex: Int) -> String {
                guard stepIndex < run.steps.count else { return run.name }
                let step = run.steps[stepIndex]
                return step.type.shortTitle + (step.nir == true ? " + NIR" : "")
            }
            guard let current = content(for: data, now: now) else { return nil }
            var steps = [Step(date: now, title: title(phase.stepIndex), state: current.state)]
            var endsAt: Date?
            if !run.isPaused, var start = run.phaseEnd() {
                // Each later phase, as if the app had moved on to it (up to 40 ahead).
                for index in (run.index + 1)..<min(run.phases.count, run.index + 41) {
                    var future = data
                    var next = run
                    next.index = index
                    next.phaseStartedAt = start
                    future.activeInterval = next
                    if let state = content(for: future, now: start)?.state {
                        steps.append(Step(date: start, title: title(run.phases[index].stepIndex), state: state))
                    }
                    start = start.addingTimeInterval(run.phases[index].seconds)
                }
                endsAt = run.index + 41 >= run.phases.count ? start : nil
            }
            let paused = run.isPaused
            return MTWidgetSnapshot(kind: .interval, program: run.name, steps: steps, endsAt: endsAt, controls: [
                paused ? Control(action: MTWidgetAction.resume.rawValue, label: "Resume", icon: "play.fill")
                       : Control(action: MTWidgetAction.pause.rawValue, label: "Pause", icon: "pause.fill"),
                Control(action: MTWidgetAction.skip.rawValue, label: phase.kind == .rest ? "Skip rest" : "Skip", icon: "forward.fill"),
                Control(action: MTWidgetAction.next.rawValue, label: "Next", icon: "forward.end.fill")
            ])
        }
        if let run = data.activeStamina {
            guard let current = content(for: data, now: now) else { return nil }
            var steps = [Step(date: now, title: "Stamina", state: current.state)]
            if let stale = current.stale, stale > now {
                // Goal reached / cool-down over, shown on time even if the app is asleep.
                var later = current.state
                if run.isCoolingDown {
                    later.label = "Cool-down over"
                    later.countdownTo = nil
                    later.next = "Resume when you're ready"
                } else {
                    later.label = "Goal reached"
                    later.countdownTo = nil
                }
                steps.append(Step(date: stale, title: "Stamina", state: later))
            }
            return MTWidgetSnapshot(kind: .stamina, program: nil, steps: steps, endsAt: nil, controls: [
                run.isCoolingDown ? Control(action: MTWidgetAction.resume.rawValue, label: "Resume", icon: "play.fill")
                                  : Control(action: MTWidgetAction.coolDown.rawValue, label: "Cool down", icon: "pause.fill"),
                Control(action: MTWidgetAction.finish.rawValue, label: "Finish", icon: "checkmark")
            ])
        }
        if let active = data.activeSession, let current = content(for: data, now: now) {
            var steps = [Step(date: now, title: active.type.shortTitle + (active.nir == true ? " + NIR" : ""), state: current.state)]
            if let stale = current.stale, stale > now {
                var later = current.state
                later.label = "Limit reached"
                later.countdownTo = nil
                steps.append(Step(date: stale, title: steps[0].title, state: later))
            }
            return MTWidgetSnapshot(kind: .timed, program: nil, steps: steps, endsAt: nil, controls: [
                Control(action: MTWidgetAction.stop.rawValue, label: "Stop", icon: "stop.fill")
            ])
        }
        return nil
    }

    /// A widget button, run inside the app. If iOS had closed the app (More Training locked), the widget
    /// says to open it instead.
    static func handleWidget(_ action: MTWidgetAction) {
        let vault = MTVault.shared
        guard vault.isUnlocked else {
            if var snapshot = MTWidgetStore.load() {
                snapshot.needsApp = true
                MTWidgetStore.save(snapshot)
            }
            return
        }
        vault.advanceInterval()
        switch action {
        case .pause: vault.pauseInterval()
        case .resume:
            if vault.data.activeInterval != nil { vault.resumeInterval() } else { vault.staminaResume() }
        case .skip: vault.skipPhase()
        case .next: vault.nextStep()
        case .coolDown: vault.staminaCoolDown()
        case .finish: vault.finishStamina()
        case .stop: vault.stopTimed()
        }
        MTWidgetStore.save(widgetSnapshot(for: vault.data, now: .now))
    }

    /// Generic on purpose ("Then work, round 3", never the session type).
    nonisolated static func nextText(_ run: MTActiveInterval) -> String {
        let index = run.index + 1
        guard index < run.phases.count else { return "Last one" }
        let next = run.phases[index]
        return next.kind == .rest ? "Then rest \(MTTimerAttributes.clock(next.seconds))" : "Then work, round \(next.round)"
    }
}
