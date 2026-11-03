#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Sergeant Cluck on the Lock Screen and Dynamic Island on days you still owe a session.
/// Started / refreshed whenever GymForge is opened; at 5:10pm it turns angry by itself
/// (the content goes stale at the cutoff and the view switches to the "after 5:10" mood).
struct CluckActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: String
        var moodAfterCutoff: String
        var line: String
        var lineAfterCutoff: String
        var remaining: Int
        var daysLeft: Int
        var spare: Int
        var cutoff: Date
    }

    var day: Date
}

struct CluckLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CluckActivityAttributes.self) { context in
            CluckActivityLockScreen(state: context.state, angry: Self.isAngry(context))
                .activityBackgroundTint(Self.mood(context).tint.opacity(0.25))
        } dynamicIsland: { context in
            let mood = Self.mood(context)
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CluckView(mood: mood).frame(width: 52, height: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(state.remaining) left").font(.headline)
                        Text("\(state.daysLeft) day\(state.daysLeft == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Sergeant Cluck · \(mood.title)").font(.caption.bold()).foregroundStyle(mood.tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.isAngry(context) ? state.lineAfterCutoff : state.line)
                            .font(.subheadline)
                            .lineLimit(2)
                        if !Self.isAngry(context) && state.cutoff > .now {
                            HStack(spacing: 4) {
                                Text("Angry in")
                                Text(timerInterval: min(Date.now, state.cutoff)...state.cutoff, countsDown: true)
                                    .monospacedDigit()
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        }
                    }
                }
            } compactLeading: {
                CluckView(mood: mood).frame(width: 22, height: 22)
            } compactTrailing: {
                Text("\(state.remaining)/\(state.daysLeft)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(mood.tint)
            } minimal: {
                CluckView(mood: mood).frame(width: 20, height: 20)
            }
            .keylineTint(mood.tint)
        }
    }

    /// After 5:10pm (or once iOS marks the content stale) he switches to his angry mood.
    static func isAngry(_ context: ActivityViewContext<CluckActivityAttributes>) -> Bool {
        context.isStale || Date() >= context.state.cutoff
    }

    static func mood(_ context: ActivityViewContext<CluckActivityAttributes>) -> CluckMood {
        CluckMood(rawValue: isAngry(context) ? context.state.moodAfterCutoff : context.state.mood) ?? .watching
    }
}

struct CluckActivityLockScreen: View {
    let state: CluckActivityAttributes.ContentState
    let angry: Bool

    var body: some View {
        let mood = CluckMood(rawValue: angry ? state.moodAfterCutoff : state.mood) ?? .watching
        HStack(spacing: 12) {
            CluckView(mood: mood).frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Sergeant Cluck").font(.caption.bold())
                    Spacer()
                    Text("\(state.remaining) left · \(state.daysLeft)d").font(.caption.bold().monospacedDigit())
                }
                Text(angry ? state.lineAfterCutoff : state.line)
                    .font(.subheadline)
                    .lineLimit(2)
                if !angry && state.cutoff > .now {
                    HStack(spacing: 4) {
                        Text("Angry in")
                        Text(timerInterval: min(Date.now, state.cutoff)...state.cutoff, countsDown: true).monospacedDigit()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - MK11: wind-down before bed

/// Counts down to bedtime; 10 minutes before, it turns into "Wind down" by itself (the content goes stale).
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var bedtime: Date
        var windDown: Date
        var wake: Date
        var lateNights: Int
        // Dayfold before-bed checklist.
        var started: Bool
        var done: Int
        var total: Int
        var next: String?
        /// Tomorrow's planned session.
        var gym: String?
    }

    var night: Date
}

struct SleepLiveActivity: Widget {
    /// Opens GymForge, which clears the card, stops the nags and runs your Sleep Focus shortcut.
    static let bedtimeURL = URL(string: "gymforge://bedtime")!
    /// Opens the before-bed checklist (Dayfold) and marks tonight's wind-down as started.
    static let startURL = URL(string: "gymforge://winddown")!

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            SleepActivityLockScreen(state: context.state, late: Self.late(context))
                .activityBackgroundTint(Self.late(context) ? Color.red.opacity(0.3) : Color.indigo.opacity(0.3))
        } dynamicIsland: { context in
            let state = context.state
            let late = Self.late(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CluckView(mood: late ? .furious : .sleepy).frame(width: 46, height: 46)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SleepActivityTimer(state: state, late: late)
                        .font(.headline.monospacedDigit())
                        .frame(width: 70)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(late ? "GO TO BED. You're past your bedtime." : SleepActivityLockScreen.checklistLine(state))
                            .font(.caption.bold())
                            .lineLimit(2)
                        SleepActivityButton(state: state, late: late).font(.caption.bold())
                    }
                }
            } compactLeading: {
                Image(systemName: late ? "exclamationmark.triangle.fill" : "moon.zzz.fill").foregroundStyle(late ? .red : .indigo)
            } compactTrailing: {
                SleepActivityTimer(state: state, late: late)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(late ? .red : .primary)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: late ? "exclamationmark.triangle.fill" : "moon.zzz.fill").foregroundStyle(late ? .red : .indigo)
            }
            .keylineTint(late ? .red : .indigo)
        }
    }

    /// Past bedtime (the content went stale at bedtime, or it was started late).
    static func late(_ context: ActivityViewContext<SleepActivityAttributes>) -> Bool {
        context.isStale || Date() >= context.state.bedtime
    }
}

/// Counts down to bedtime, then counts up how late you are.
struct SleepActivityTimer: View {
    let state: SleepActivityAttributes.ContentState
    let late: Bool

    var body: some View {
        if late {
            Text(timerInterval: state.bedtime...state.bedtime.addingTimeInterval(8 * 3600), countsDown: false)
        } else {
            Text(timerInterval: min(Date.now, state.bedtime)...state.bedtime, countsDown: true)
        }
    }
}

struct SleepActivityLockScreen: View {
    let state: SleepActivityAttributes.ContentState
    let late: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CluckView(mood: late ? .furious : .sleepy).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(late ? "GO TO BED, RECRUIT" : (state.total > 0 ? "Before bed · \(state.done)/\(state.total)" : "Wind down"))
                        .font(.headline)
                        .foregroundStyle(late ? .red : .primary)
                    HStack(spacing: 4) {
                        Text(late ? "Past your bedtime by" : "Lights out in")
                        SleepActivityTimer(state: state, late: late).monospacedDigit()
                    }
                    .font(.subheadline.bold())
                    Text(late
                         ? (state.lateNights >= 2 ? "\(state.lateNights) late nights this week. Not another one." : "Phone down. Tomorrow's session starts tonight.")
                         : Self.checklistLine(state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            SleepActivityButton(state: state, late: late)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.indigo.opacity(0.35), in: Capsule())
        }
        .padding(14)
    }

    /// "Next: Skincare · Push tomorrow" / "4 things, incl. packing for Push".
    static func checklistLine(_ state: SleepActivityAttributes.ContentState) -> String {
        let gym = state.gym.map { " · \($0) tomorrow" } ?? ""
        if state.total == 0 { return "Screens off, lights low. Up at \(state.wake.formatted(date: .omitted, time: .shortened))." + gym }
        if state.done == state.total { return "Checklist done. Lights out." + gym }
        if state.started, let next = state.next { return "Next: \(next)" }
        return "\(state.total - state.done) to do before bed" + gym
    }
}

/// Start the checklist until you have; after that (or once late) it's "I'm going to bed".
struct SleepActivityButton: View {
    let state: SleepActivityAttributes.ContentState
    let late: Bool

    var body: some View {
        if state.started || late || state.total == 0 {
            Link(destination: SleepLiveActivity.bedtimeURL) { Label("I'm going to bed", systemImage: "bed.double.fill") }
        } else {
            Link(destination: SleepLiveActivity.startURL) { Label("Start", systemImage: "checklist") }
        }
    }
}
#endif
