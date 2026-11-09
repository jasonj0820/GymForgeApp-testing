import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GymForgeWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        CluckWidget()
        CluckLiveActivity()
        SleepLiveActivity()
        QuoteWidget()
        MTTimerLiveActivity()
        MTTrainingWidget()
    }
}

/// Lock Screen + Dynamic Island: current exercise, set, rest countdown, workout time.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(attributes: context.attributes, state: context.state)
                .padding(.horizontal, 16)
                .padding(.vertical, LockScreenWorkoutView.isLong(context.state.motivation) ? 8 : 12)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isResting ? "REST" : "SET \(context.state.setNumber)/\(context.state.totalSets)")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isResting, let end = context.state.restEnd, end > .now {
                        Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: 80)
                    } else {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(context.state.isResting ? "Next: \(context.state.exerciseName)" : context.state.exerciseName)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let last = context.state.lastSetText {
                                Text(last).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if let line = context.state.motivation {
                            // Full quote: wraps onto as many lines as it needs.
                            Text(line)
                                .font(.caption.italic())
                                .foregroundStyle(.orange)
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.state.isResting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                if context.state.isResting, let end = context.state.restEnd, end > .now {
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .foregroundStyle(.cyan)
                } else {
                    Text("\(context.state.setNumber)/\(context.state.totalSets)")
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: context.state.isResting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct LockScreenWorkoutView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    /// Long reflective quotes need the room: the Lock Screen caps a Live Activity at about 160 pt.
    static func isLong(_ quote: String?) -> Bool { (quote?.count ?? 0) > 100 }

    var body: some View {
        // The quote only shows while resting: then the routine/time row and "Last:" line make room for it.
        let compact = state.motivation != nil
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            // The routine / elapsed-time row is dropped for long quotes so the whole quote fits.
            if !compact {
            HStack {
                Label(attributes.routineName, systemImage: "dumbbell.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text(attributes.startedAt, style: .timer)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
            }
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    if state.isResting {
                        Text("REST · NEXT").font(.caption2.bold()).foregroundStyle(.cyan)
                    } else if let label = state.supersetLabel {
                        Text("SUPERSET \(label)").font(.caption2.bold()).foregroundStyle(.purple)
                    }
                    Text(state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !state.isFinished {
                        // "Set 2 of 3" = the set you're on (during rest: the one coming up).
                        // Runs / basketball send pace and heart rate here instead.
                        Text(state.isCardio ? (state.lastSetText ?? "Cardio") : "Set \(state.setNumber) of \(state.totalSets)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let last = state.lastSetText, !state.isCardio, !compact {
                            Text("Last: \(last)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                if state.isResting, let end = state.restEnd, end > .now {
                    Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 100)
                }
            }

            if let line = state.motivation {
                // Room for the whole quote (up to 4 lines, shrinks slightly if it's very long).
                // Long reflective quotes (100+ characters) drop one text size so they still fit in full.
                Text("“\(line)”")
                    .font(line.count > 100 ? .caption.italic().weight(.semibold) : .footnote.italic().weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.75)
            }

            if state.isResting, let start = state.restStart, let end = state.restEnd, end > start {
                SwiftUI.ProgressView(timerInterval: start...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.cyan)
            } else {
                SwiftUI.ProgressView(value: Double(state.completedSets), total: Double(max(state.plannedSets, 1)))
                    .tint(.orange)
            }
        }
    }
}
