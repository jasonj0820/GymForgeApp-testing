import WatchKit
import HealthKit

final class AppDelegate: NSObject, WKApplicationDelegate {
    /// Called when the iPhone runs `startWatchApp(with:)`.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            switch workoutConfiguration.activityType {
            case .running, .basketball:
                await WatchAppStore.shared.startActivityFromPhone(workoutConfiguration)
            default:
                await WatchAppStore.shared.startHealthSessionFromPhone()
            }
        }
    }

    /// Called if the app was terminated mid-workout.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in
            WatchWorkoutManager.shared.recoverSession()
        }
    }
}
