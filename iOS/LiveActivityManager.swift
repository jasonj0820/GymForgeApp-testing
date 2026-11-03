import ActivityKit
import Foundation

/// Shows the current exercise and rest countdown on the Lock Screen and Dynamic Island.
@MainActor
final class LiveActivityManager {
    private var activity: Activity<WorkoutActivityAttributes>?
    /// The run / basketball Live Activity (kept when the gym-workout one ends). Saved so a relaunch
    /// doesn't mistake it for the gym workout's card.
    private var cardioID: UUID? {
        didSet { UserDefaults.standard.set(cardioID?.uuidString, forKey: "liveCardioID") }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "liveCardioID").flatMap(UUID.init(uuidString:))
        cardioID = saved
        activity = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes.workoutID != saved }
    }

    func sync(_ state: ActiveWorkoutState?, style: CoachStyle = .motivating) {
        guard let state else {
            endAll()
            return
        }
        let content = ActivityContent(state: Self.contentState(for: state, style: style), staleDate: nil)

        if let current = activity, current.attributes.workoutID == state.workoutID,
           current.activityState == .active || current.activityState == .stale {
            Task { await current.update(content) }
            return
        }

        endAll()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutID: state.workoutID, routineName: state.routine.name, startedAt: state.startedAt)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("Live Activity failed to start: \(error)")
        }
    }

    private func endAll() {
        let running = Activity<WorkoutActivityAttributes>.activities.filter { $0.attributes.workoutID != cardioID }
        activity = nil
        for item in running {
            Task { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Last set with the machine's unit ("20 kg/side × 8", "level 7 × 10").
    private static func lastSetText(_ state: ActiveWorkoutState) -> String? {
        guard let last = state.lastLoggedSet else { return nil }
        let exerciseID = state.completedSets.first { $0.value.contains { $0.id == last.id } }?.key
        let load = exerciseID.flatMap { state.exerciseDefinition(id: $0) }?.load
        return last.summary(load: load)
    }

    /// Ends the Lock Screen card of one run / basketball session (even after a relaunch).
    func endCardio(id: UUID) {
        for item in Activity<WorkoutActivityAttributes>.activities where item.attributes.workoutID == id {
            Task { await item.end(nil, dismissalPolicy: .immediate) }
        }
        if cardioID == id { cardioID = nil }
    }

    /// Run / basketball on the Lock Screen: distance (or the sport), pace and heart rate. nil ends it.
    func syncCardio(_ progress: ActivityProgress?) {
        guard let progress else {
            if let id = cardioID { endCardio(id: id) }
            cardioID = nil
            return
        }
        if let old = cardioID, old != progress.id { endCardio(id: old) }
        let isRun = progress.kind == .run
        let detail = (isRun ? "\(CardioFormat.pace(progress.paceSeconds ?? 0)) /km · " : "")
            + (progress.heartRate > 0 ? "\(Int(progress.heartRate)) bpm" : "")
            + (progress.isPaused ? " · paused" : "")
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: isRun ? "\(String(format: "%.2f", progress.distanceKm)) km" : progress.title,
            setNumber: 1, totalSets: 1, isCardio: true, isResting: false, restStart: nil, restEnd: nil,
            completedSets: 0, plannedSets: 1, lastSetText: detail, supersetLabel: nil, isFinished: false, motivation: nil)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
        if let current = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.workoutID == progress.id }) {
            Task { await current.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = WorkoutActivityAttributes(workoutID: progress.id, routineName: progress.title, startedAt: progress.startedAt)
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        cardioID = progress.id
    }

    static func contentState(for state: ActiveWorkoutState, style: CoachStyle) -> WorkoutActivityAttributes.ContentState {
        let item = state.currentItem
        let index = state.exerciseIndex
        let done = item.map { state.sets(for: $0).count } ?? 0
        return WorkoutActivityAttributes.ContentState(
            exerciseName: state.isComplete ? "All sets done" : (item?.exercise.name ?? state.routine.name),
            setNumber: min(done + 1, item?.exercise.defaultSets ?? 1),
            totalSets: item?.exercise.defaultSets ?? 0,
            isCardio: item?.exercise.isCardio ?? false,
            isResting: state.isResting,
            restStart: state.restStartedAt,
            restEnd: state.restEndDate,
            completedSets: state.totalCompletedSets,
            plannedSets: state.totalPlannedSets,
            lastSetText: (item?.exercise.isCardio ?? false) ? nil : lastSetText(state),
            supersetLabel: state.supersetLabel(for: index),
            isFinished: state.isComplete,
            // The quote only shows during rest; the rest of the time it's the exercise and your set.
            motivation: state.isResting ? style.workoutLine(workout: state.workoutID, step: state.totalCompletedSets) : nil
        )
    }
}
