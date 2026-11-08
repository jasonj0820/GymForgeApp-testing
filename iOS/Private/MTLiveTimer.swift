import ActivityKit
import Foundation

/// MK17: starts, updates and ends the More Training timer Live Activity from the vault's state.
/// Called after every save while unlocked, so it follows start / pause / resume / skip / stop.
@MainActor
enum MTLiveTimer {
    typealias State = MTTimerAttributes.ContentState

    static func sync(_ data: MTData, now: Date = .now) {
        let running = Activity<MTTimerAttributes>.activities
        guard let plan = content(for: data, now: now), ActivityAuthorizationInfo().areActivitiesEnabled else {
            let showing = running.filter { [.active, .stale].contains($0.activityState) }
            guard !showing.isEmpty else { return }
            Task {
                for activity in showing { await activity.end(nil, dismissalPolicy: .immediate) }
                PhoneAppStore.shared.refreshCluck()   // MK19.1: Sergeant Cluck's card comes straight back
            }
            return
        }
        let content = ActivityContent(state: plan.state, staleDate: plan.stale)
        CluckActivityManager.endAll()   // only one card on the Lock Screen: the timer replaces Sergeant Cluck
        if let current = running.first {
            for other in running.dropFirst() { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            guard current.content.state != plan.state || current.content.staleDate != plan.stale else { return }
            Task { await current.update(content) }
        } else {
            _ = try? Activity.request(attributes: MTTimerAttributes(startedAt: plan.start), content: content, pushType: nil)
        }
    }

    /// What the card shows now, when it goes stale (phase end / time limit), and when the session began.
    nonisolated static func content(for data: MTData, now: Date) -> (state: State, stale: Date?, start: Date)? {
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

    /// Generic on purpose ("Then work, round 3", never the session type).
    nonisolated static func nextText(_ run: MTActiveInterval) -> String {
        let index = run.index + 1
        guard index < run.phases.count else { return "Last one" }
        let next = run.phases[index]
        return next.kind == .rest ? "Then rest \(MTTimerAttributes.clock(next.seconds))" : "Then work, round \(next.round)"
    }
}
