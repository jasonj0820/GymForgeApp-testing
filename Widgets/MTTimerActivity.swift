import ActivityKit
import SwiftUI
import WidgetKit

// MK17: the More Training timer on the Lock Screen, Dynamic Island and Watch Smart Stack.
// Discreet on purpose: it only ever says "Timer", "Work" or "Rest", never what the session is.
// Compiled into the iPhone app AND the widget extension.

struct MTTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Timer", "Work · 2 of 3", "Rest".
        var label: String
        /// Counting down to the end of this phase, or to an open timer's time limit.
        var countdownTo: Date?
        /// Open timer: when it started (counts up once the limit is passed, or if there is none).
        var countUpFrom: Date?
        /// Set while paused: seconds left in the phase.
        var pausedRemaining: Double?
        /// "Then rest 2:00" / "Then work, round 3".
        var next: String?
        /// Intervals: when the whole program ends.
        var endsAt: Date?
        var isInterval: Bool
        /// MK20.5: a stamina run (goal countdown → count-up, cool-downs). Still shown only as "Timer".
        var stamina: Bool? = nil
    }
    var startedAt: Date

    /// "4:12".
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MTTimerLiveActivity: Widget {
    /// Opens the app (More Training stays unlocked while a timer runs).
    static let openURL = URL(string: "gymforge://mt")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MTTimerAttributes.self) { context in
            MTTimerLockScreen(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .widgetURL(Self.openURL)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(MTTimerLockScreen.title(state, stale: stale), systemImage: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(.indigo)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MTTimerClock(state: state, stale: stale)
                        .font(.title2.bold().monospacedDigit())
                        .frame(width: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let detail = MTTimerLockScreen.detail(state, stale: stale) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: state.pausedRemaining == nil ? "timer" : "pause.fill").foregroundStyle(.indigo)
            } compactTrailing: {
                MTTimerClock(state: state, stale: stale)
                    .font(.caption.monospacedDigit())
                    .frame(width: 46)
            } minimal: {
                MTTimerClock(state: state, stale: stale)
                    .font(.caption2.monospacedDigit())
            }
            .widgetURL(Self.openURL)
            .keylineTint(.indigo)
        }
    }
}

/// Countdown, count-up, or a frozen time while paused.
struct MTTimerClock: View {
    let state: MTTimerAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let paused = state.pausedRemaining {
            Text(MTTimerAttributes.clock(paused))
        } else if !stale, let end = state.countdownTo {
            Text(timerInterval: min(Date.now, end)...end, countsDown: true)
        } else if state.isInterval, let ends = state.endsAt, ends > .now {
            // The phase ended while the app was asleep: show time left in the whole program.
            Text(timerInterval: Date.now...ends, countsDown: true)
        } else if let from = state.countUpFrom {
            Text(timerInterval: from...from.addingTimeInterval(24 * 3600), countsDown: false)
        } else if state.stamina == true {
            Text("Go")   // cool-down finished while the app was asleep
        } else {
            Text("Done")
        }
    }

}

struct MTTimerLockScreen: View {
    let state: MTTimerAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.pausedRemaining == nil ? "timer" : "pause.circle.fill")
                .font(.title)
                .foregroundStyle(.indigo)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(state, stale: stale)).font(.headline)
                if let detail = Self.detail(state, stale: stale) {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            MTTimerClock(state: state, stale: stale)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: 130, alignment: .trailing)
        }
        .padding(14)
    }

    static func title(_ state: MTTimerAttributes.ContentState, stale: Bool) -> String {
        guard stale, state.pausedRemaining == nil else { return state.label }
        if state.stamina == true { return state.label == "Cool-down" ? "Cool-down over" : "Goal reached" }
        return state.isInterval ? "Next step" : "Limit reached"
    }

    static func detail(_ state: MTTimerAttributes.ContentState, stale: Bool) -> String? {
        if state.pausedRemaining != nil { return "Paused" }
        if stale, state.stamina == true {
            return state.label == "Cool-down" ? "Resume when you're ready" : "Keep going or finish"
        }
        if stale { return state.isInterval ? "Open the app to see where you're at" : "Stop when you're ready" }
        if let next = state.next { return next }
        return state.endsAt.map { "Ends \($0.formatted(date: .omitted, time: .shortened))" }
    }
}
