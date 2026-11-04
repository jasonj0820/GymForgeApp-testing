import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct BlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BlockActivity.self) { context in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    Countdown(timer: context.state).font(.system(size: 40, weight: .bold, design: .rounded))
                }
                Spacer()
                PauseButton(timer: context.state).font(.title2)
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
                    PauseButton(timer: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange)
            } compactTrailing: {
                Countdown(timer: context.state).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "ductile://"))
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
