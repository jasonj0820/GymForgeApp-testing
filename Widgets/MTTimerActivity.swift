import ActivityKit
import AppIntents
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
        /// MK20.6.1: the step's name, for the More Training widget only (never drawn on the Lock Screen
        /// card). Lets the widget work from the Live Activity when the App Group isn't available.
        var widgetTitle: String? = nil
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

// MARK: - More Training widget (MK20.6): shared between the app and the widget extension

/// What the More Training widget shows, written by the app to the App Group on every More Training save.
/// Unlike the Live Activity it names the step (e.g. "HTE + NIR") — the widget is opt-in, you add it yourself.
struct MTWidgetSnapshot: Codable, Equatable {
    enum Kind: String, Codable { case interval, timed, stamina }

    /// One stretch of the timeline: from `date`, show this.
    struct Step: Codable, Equatable {
        var date: Date
        var title: String
        var state: MTTimerAttributes.ContentState
    }

    struct Control: Codable, Equatable, Hashable {
        var action: String      // MTWidgetAction raw value
        var label: String
        var icon: String
    }

    var kind: Kind
    /// Program name ("NIR + PAC"), if any.
    var program: String?
    /// Now, then each upcoming phase (intervals) or the goal / cool-down end (stamina).
    var steps: [Step]
    /// After this the timer is over (show the quote again). nil = open-ended.
    var endsAt: Date?
    var controls: [Control]
    /// A button was tapped but the app had been closed by iOS — open it to carry on.
    var needsApp: Bool = false
}

enum MTWidgetAction: String {
    case pause, skip, next, coolDown, resume, finish, stop
}

enum MTWidgetStore {
    static let kind = "MoreTrainingTimer"
    private static let key = "mt.widget.snapshot"

    /// What the widget should show: the App Group snapshot, or — if the App Group isn't shared (some
    /// sideloading tools drop it) — one built from the running More Training Live Activity.
    static func current(now: Date = .now) -> MTWidgetSnapshot? {
        if let saved = load(), saved.endsAt.map({ $0 > now }) ?? true { return saved }
        guard let activity = Activity<MTTimerAttributes>.activities.first(where: { [.active, .stale].contains($0.activityState) }) else {
            return nil
        }
        return fromLiveActivity(activity.content.state, staleDate: activity.content.staleDate, now: now)
    }

    static func fromLiveActivity(_ state: MTTimerAttributes.ContentState, staleDate: Date?, now: Date) -> MTWidgetSnapshot {
        typealias Control = MTWidgetSnapshot.Control
        let title = state.widgetTitle ?? "Timer"
        let paused = state.pausedRemaining != nil
        var steps = [MTWidgetSnapshot.Step(date: now, title: title, state: state)]
        if !paused, let stale = staleDate ?? state.countdownTo, stale > now {
            // What to show once this phase is over, until the app updates it.
            var later = state
            later.countdownTo = nil
            if state.isInterval {
                later.label = "Next step"
                later.next = "Open the app to see where you're at"
            } else if state.stamina == true {
                later.label = state.label == "Cool-down" ? "Cool-down over" : "Goal reached"
            } else {
                later.label = "Limit reached"
            }
            steps.append(.init(date: stale, title: title, state: later))
        }
        let controls: [Control]
        if state.isInterval {
            controls = [paused ? Control(action: MTWidgetAction.resume.rawValue, label: "Resume", icon: "play.fill")
                               : Control(action: MTWidgetAction.pause.rawValue, label: "Pause", icon: "pause.fill"),
                        Control(action: MTWidgetAction.skip.rawValue, label: state.label == "Rest" ? "Skip rest" : "Skip", icon: "forward.fill"),
                        Control(action: MTWidgetAction.next.rawValue, label: "Next", icon: "forward.end.fill")]
        } else if state.stamina == true {
            controls = [state.label == "Cool-down" ? Control(action: MTWidgetAction.resume.rawValue, label: "Resume", icon: "play.fill")
                                                   : Control(action: MTWidgetAction.coolDown.rawValue, label: "Cool down", icon: "pause.fill"),
                        Control(action: MTWidgetAction.finish.rawValue, label: "Finish", icon: "checkmark")]
        } else {
            controls = [Control(action: MTWidgetAction.stop.rawValue, label: "Stop", icon: "stop.fill")]
        }
        let kind: MTWidgetSnapshot.Kind = state.isInterval ? .interval : (state.stamina == true ? .stamina : .timed)
        return MTWidgetSnapshot(kind: kind, program: nil, steps: steps, endsAt: state.isInterval ? state.endsAt : nil, controls: controls)
    }

    static func load() -> MTWidgetSnapshot? {
        guard let data = CluckStore.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MTWidgetSnapshot.self, from: data)
    }

    /// Saves (nil clears) and reloads the widget — only when something actually changed.
    static func save(_ snapshot: MTWidgetSnapshot?) {
        guard snapshot != load() else { return }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            CluckStore.defaults.set(data, forKey: key)
        } else {
            CluckStore.defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// The widget's Pause / Skip / Next buttons. A LiveActivityIntent, so iOS runs it inside the app (where
/// More Training's timer lives), not in the widget extension.
struct MTWidgetControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Timer control"
    static var isDiscoverable = false

    @Parameter(title: "Action") var action: String

    init() {}
    init(_ action: MTWidgetAction) { self.action = action.rawValue }

    func perform() async throws -> some IntentResult {
        await MTWidgetControl.run(action)
        return .result()
    }
}

/// Set by the app at launch; does nothing in the widget extension.
@MainActor
enum MTWidgetControl {
    static var handler: ((MTWidgetAction) -> Void)?

    static func run(_ raw: String) {
        guard let action = MTWidgetAction(rawValue: raw) else { return }
        handler?(action)
    }
}
