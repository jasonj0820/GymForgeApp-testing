import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct BlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlockActivity.self) { context in
            // MK2: when time is up the card turns into Full / Minimum, so it can be ticked off right here.
            Group {
                if isUp(context) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(context.attributes.title): time's up").font(.headline).lineLimit(1)
                        TickOffButtons()
                    }
                } else {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title).font(.headline).lineLimit(1)
                            Countdown(timer: context.state).font(.system(size: 40, weight: .bold, design: .rounded))
                        }
                        Spacer()
                        PauseButton(timer: context.state).font(.title2)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: "timer").font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(timer: context.state).font(.title2.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if isUp(context) { TickOffButtons() } else { PauseButton(timer: context.state) }
                }
            } compactLeading: {
                Image(systemName: isUp(context) ? "checkmark.circle" : context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange)
            } compactTrailing: {
                if isUp(context) { Text("Done") } else { Countdown(timer: context.state).frame(maxWidth: 52) }
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "ductile://"))
        }
    }
}

/// The card goes stale at the timer's end, which is what redraws it.
private func isUp(_ context: ActivityViewContext<BlockActivity>) -> Bool {
    !context.state.isPaused && (context.isStale || context.state.ends <= Date())
}

private struct TickOffButtons: View {
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: TickOffIntent(full: true)) {
                Label("Full", systemImage: "bolt.fill").frame(maxWidth: .infinity)
            }
            .tint(.green)
            Button(intent: TickOffIntent(full: false)) {
                Label("Minimum", systemImage: "leaf.fill").frame(maxWidth: .infinity)
            }
            .tint(.orange)
        }
    }
}

private struct Countdown: View {
    let timer: ActiveTimer

    var body: some View {
        Group {
            if timer.isPaused {
                Text(Duration.seconds(timer.left()).formatted(.time(pattern: .minuteSecond))).opacity(0.6)
            } else {
                // Ticks by itself on the lock screen; stops at 0:00 instead of counting up.
                Text(timerInterval: min(Date(), timer.ends)...timer.ends, countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct PauseButton: View {
    let timer: ActiveTimer

    var body: some View {
        Button(intent: PauseResumeIntent()) {
            Label(timer.isPaused ? "Resume" : "Pause", systemImage: timer.isPaused ? "play.fill" : "pause.fill")
        }
        .tint(.orange)
    }
}
