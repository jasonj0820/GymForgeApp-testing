import Foundation
import UIKit

/// MK24 (section D): the live workout's new controls — machine taken, reorder, finish time, the Lock Screen
/// Done button, saying the set, and your playlist on start.
extension PhoneAppStore {
    /// The Live Activity, with the Done button's set and the finish time.
    func syncLiveActivity() {
        guard let state = activeWorkout else {
            liveActivity.sync(nil, style: profile.coachStyle)
            return
        }
        liveActivity.sync(state, style: profile.coachStyle, nextSet: plannedSetText(state), finishAt: estimatedFinish(state))
    }

    /// "80 kg × 10" for the set the app would log with empty boxes; nil for cardio.
    func plannedSetText(_ state: ActiveWorkoutState) -> String? {
        guard let item = state.currentItem, !item.exercise.isCardio, !state.isFinished(item) else { return nil }
        let target = state.prefill(for: item, logs: workoutLogs)
        guard target.reps > 0, item.exercise.isBodyweight || target.weightKg > 0 else { return nil }
        let exercise = item.exercise
        return exercise.isBodyweight ? "\(target.reps) reps" : "\(exercise.formatLoad(target.weightKg)) × \(target.reps)"
    }

    /// At today's pace (or last time's, early on).
    func estimatedFinish(_ state: ActiveWorkoutState, now: Date = .now) -> Date? {
        let left = state.setsLeft
        guard left > 0 else { return nil }
        let previous = workoutLogs.last { $0.routineID == state.routine.id && $0.totalSets > 0 }
            .map { (duration: $0.endedAt.timeIntervalSince($0.startedAt), sets: $0.totalSets) }
        let pace = FinishEstimate.secondsPerSet(elapsed: now.timeIntervalSince(state.startedAt),
                                                setsDone: state.totalCompletedSets, previous: previous)
        return FinishEstimate.finish(now: now, setsLeft: left, secondsPerSet: pace)
    }

    /// The Lock Screen / Dynamic Island Done button.
    func completeSetFromLockScreen() {
        guard let state = activeWorkout, let item = state.currentItem, !item.exercise.isCardio, !state.isComplete else { return }
        let target = state.prefill(for: item, logs: workoutLogs)
        guard target.reps > 0, item.exercise.isBodyweight || target.weightKg > 0 else { return }
        completeSetOnPhone(weightKg: item.exercise.isBodyweight ? 0 : target.weightKg, reps: target.reps)
    }

    /// "Machine taken": do the next exercise first, this one after it. false = nothing else to do first.
    @discardableResult
    func machineTaken() -> Bool {
        guard var state = activeWorkout, state.machineTaken() else { return false }
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
        return true
    }

    func reorderRemaining(_ firstIDs: [UUID]) {
        guard var state = activeWorkout else { return }
        state.reorderRemaining(firstIDs)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// Logs what you said ("80 for 10"). Missing numbers come from the plan. Returns what was logged.
    func logSpoken(_ heard: String) -> String? {
        guard let state = activeWorkout, let item = state.currentItem, !item.exercise.isCardio,
              let parsed = SpokenSet.parse(heard) else { return nil }
        let target = state.prefill(for: item, logs: workoutLogs)
        let reps = parsed.reps ?? target.reps
        let weight = item.exercise.isBodyweight ? (parsed.weightKg ?? 0) : (parsed.weightKg ?? target.weightKg)
        guard reps > 0, item.exercise.isBodyweight || weight > 0 else { return nil }
        completeSetOnPhone(weightKg: weight, reps: reps)
        return item.exercise.isBodyweight && weight <= 0 ? "\(reps) reps" : "\(item.exercise.formatLoad(weight)) × \(reps)"
    }
}

// MARK: - Playlist or Shortcut when a workout starts (63)

enum WorkoutStartAction {
    enum Kind: String, CaseIterable, Identifiable {
        case none, shortcut, link
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "Nothing"
            case .shortcut: return "Run a Shortcut"
            case .link: return "Open a playlist link"
            }
        }
    }

    static let kindKey = "start.kind"
    static let valueKey = "start.value"

    static var kind: Kind { Kind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "") ?? .none }
    static var value: String { (UserDefaults.standard.string(forKey: valueKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    static var url: URL? {
        guard !value.isEmpty else { return nil }
        switch kind {
        case .none:
            return nil
        case .shortcut:
            // x-success brings you straight back to the workout once the Shortcut has started your music.
            var parts = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")
            parts?.queryItems = [URLQueryItem(name: "name", value: value), URLQueryItem(name: "x-success", value: "gymforge://gym")]
            return parts?.url
        case .link:
            return URL(string: value)
        }
    }

    @MainActor
    static func run() {
        guard !Demo.isOn, let url else { return }
        UIApplication.shared.open(url)
    }

    /// After the workout screen is up.
    @MainActor
    static func runSoon() {
        guard url != nil, !Demo.isOn, UIApplication.shared.applicationState == .active else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            run()
        }
    }
}
