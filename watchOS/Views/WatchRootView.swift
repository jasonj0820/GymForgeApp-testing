import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchAppStore
    @ObservedObject private var activity = WatchActivityManager.shared

    var body: some View {
        Group {
            if activity.isActive {
                ActivityLiveView()
            } else if let finished = activity.summary {
                ActivitySummaryView(session: finished)
            } else if let pr = store.celebration {
                PRCelebrationView(pr: pr)
            } else if let active = store.activeWorkout {
                if active.isResting {
                    RestTimerView(state: active)
                } else if store.restFinished {
                    RestFinishedView(state: active)
                } else {
                    WatchActiveWorkoutView(state: active)
                }
            } else if let summary = store.summary {
                WatchSummaryView(log: summary)
            } else {
                WatchHomeView()
            }
        }
        .overlay {
            if let tick = store.setTick {
                WatchSetTickOverlay(tick: tick)
                    .id(tick.id)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { activity.errorMessage != nil },
            set: { if !$0 { activity.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(activity.errorMessage ?? "")
        }
    }
}
