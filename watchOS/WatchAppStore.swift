import Foundation
import HealthKit
import WatchKit
import Combine

private struct WatchPersistedState: Codable {
    var routines: [WorkoutRoutine]
    var workoutLogs: [WorkoutLog]
    var activeWorkout: ActiveWorkoutState?
    var profile: UserProfile?
}

@MainActor
final class WatchAppStore: ObservableObject {
    static let shared = WatchAppStore()

    @Published var routines: [WorkoutRoutine] = []
    @Published var workoutLogs: [WorkoutLog] = []
    @Published var profile = UserProfile()
    @Published var activeWorkout: ActiveWorkoutState?
    @Published var isFinishing = false
    /// Numbers being typed on the iPhone for the current set.
    @Published var phoneDraft: WorkoutDraft?
    @Published var phoneReachable = false
    @Published var lastSync: Date?
    /// Shows the full-screen "Rest finished" alert until tapped or the next set is logged.
    @Published var restFinished = false
    /// Full-screen PR celebration.
    @Published var celebration: PRHit?
    /// Summary shown after finishing a workout.
    @Published var summary: WorkoutLog?
    /// Heart rate when the current rest started (for the live recovery readout).
    @Published var restHeartRateStart: Double?
    /// Cardio stopwatch start for the current set.
    @Published var cardioStartedAt: Date?
    /// Green tick shown for a moment after a set is logged.
    @Published var setTick: WatchSetTick?

    let workoutManager = WatchWorkoutManager.shared
    private let bridge = WatchBridge()
    private var restTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var celebrationTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var restFinishedTask: Task<Void, Never>?
    /// Workouts discarded, cancelled or finished here: late copies from the iPhone are ignored.
    private var endedWorkoutIDs = Set<UUID>()
    private var seenPRs = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadFromDisk()
        if let pr = activeWorkout?.lastPR { seenPRs.insert(pr.id) }

        bridge.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.applySnapshot(snapshot) }
        }
        bridge.onStartWorkout = { [weak self] state in
            Task { @MainActor in self?.acceptPhoneStartedWorkout(state) }
        }
        bridge.onActiveState = { [weak self] state in
            Task { @MainActor in self?.receivePhoneState(state) }
        }
        bridge.onCancelWorkout = { [weak self] id in
            Task { @MainActor in self?.receiveCancel(id) }
        }
        bridge.onActivated = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.bridge.requestSnapshot()
                if self.activeWorkout == nil { self.bridge.requestActiveWorkout() }
            }
        }
        bridge.onDraft = { [weak self] draft in
            Task { @MainActor in self?.phoneDraft = draft }
        }
        bridge.onReachabilityChange = { [weak self] reachable in
            Task { @MainActor in
                guard let self else { return }
                self.phoneReachable = reachable
                if reachable && self.routines.isEmpty { self.bridge.requestSnapshot() }
            }
        }
        bridge.onBuzz = {
            Task { await WatchAppStore.buzzThreeTimes() }
        }
        bridge.onReceived = { [weak self] in
            Task { @MainActor in self?.lastSync = .now }
        }
        bridge.onStartActivity = { request in
            Task { @MainActor in
                // Ignore start messages that were queued while the Watch was off.
                guard abs(request.requestedAt.timeIntervalSinceNow) <= 120 else { return }
                WatchAppStore.shared.clearOrphanedGymSession()
                await WatchActivityManager.shared.start(request)
            }
        }
        bridge.activate()

        // Auto-end rest once heart rate has come down (optional, set on iPhone).
        workoutManager.$heartRateBPM
            .sink { [weak self] bpm in
                Task { @MainActor in self?.checkAutoRest(heartRate: bpm) }
            }
            .store(in: &cancellables)

        if let active = activeWorkout, active.isResting, let end = active.restEndDate {
            scheduleRestCompletion(at: end)
        }
    }

    // MARK: Sync from iPhone

    func requestSync() {
        bridge.requestSnapshot()
    }

    private func applySnapshot(_ snapshot: AppSnapshot) {
        routines = snapshot.routines
        if let incoming = snapshot.profile { profile = incoming }
        // Keep any Watch-only workouts the iPhone hasn't received yet.
        let phoneIDs = Set(snapshot.workoutLogs.map(\.id))
        let newestPhone = snapshot.workoutLogs.map(\.startedAt).max() ?? .distantPast
        let pending = workoutLogs.filter { !phoneIDs.contains($0.id) && $0.startedAt > newestPhone }
        workoutLogs = (snapshot.workoutLogs + pending).sorted { $0.startedAt < $1.startedAt }
        saveToDisk()
    }

    private func acceptPhoneStartedWorkout(_ state: ActiveWorkoutState) {
        // Ignore stale start messages that were queued while the Watch was off.
        guard abs(state.startedAt.timeIntervalSinceNow) < 300 else { return }
        if workoutLogs.contains(where: { $0.id == state.workoutID }) || endedWorkoutIDs.contains(state.workoutID) { return }
        if let current = activeWorkout, current.workoutID != state.workoutID, current.totalCompletedSets > 0 {
            bridge.sendActiveState(current)
            return
        }
        summary = nil
        WatchActivityManager.shared.summary = nil
        restFinished = false
        activeWorkout = state
        saveToDisk()
        bridge.sendActiveState(state)
        Task { await workoutManager.startWorkout() }
    }

    private func receivePhoneState(_ incoming: ActiveWorkoutState) {
        if workoutLogs.contains(where: { $0.id == incoming.workoutID }) { return }
        if endedWorkoutIDs.contains(incoming.workoutID) {
            bridge.sendCancel(incoming.workoutID)
            return
        }
        let previous = activeWorkout
        var state = incoming
        if let current = previous {
            guard current.workoutID == incoming.workoutID else { return }
            if incoming.revision < current.revision {
                if incoming.finishRequested && !current.finishRequested {
                    // A Finish from the iPhone always counts, even on an older copy.
                    state = current.merged(with: incoming)
                } else {
                    let knownIDs = Set(current.completedSets.values.flatMap { $0 }.map(\.id))
                    let hasNewSets = incoming.completedSets.values.flatMap { $0 }.contains { !knownIDs.contains($0.id) }
                    if hasNewSets {
                        // The iPhone was behind but logged a set meanwhile: keep it.
                        state = current.merged(with: incoming)
                    } else {
                        // The iPhone is behind (e.g. it was closed by iOS): send it the newer copy.
                        bridge.sendActiveState(current, reliable: false)
                        return
                    }
                }
            } else if incoming.revision == current.revision {
                // Both changed at the same moment: keep every set from both, and tell the iPhone.
                guard incoming != current else { return }
                state = current.merged(with: incoming)
            }
            if state.totalCompletedSets != current.totalCompletedSets || state.isResting { restFinished = false }
        } else {
            guard abs(incoming.startedAt.timeIntervalSinceNow) < 4 * 3600 else { return }
            summary = nil
        }
        activeWorkout = state
        saveToDisk()
        if state != incoming { bridge.sendActiveState(state, reliable: true) }
        if state.finishRequested {
            Task { await finishWorkout() }
            return
        }
        if !workoutManager.hasSession {
            Task { await workoutManager.startWorkout() }
        }
        syncRestTimer(state)
        let hadPR = state.lastPR.map { !seenPRs.contains($0.id) } ?? false
        // Celebrate PRs from new sets only (not when a set is edited on the iPhone).
        if state.totalCompletedSets > (previous?.totalCompletedSets ?? 0) {
            announcePRIfNew(state)
        } else if let pr = state.lastPR {
            seenPRs.insert(pr.id)
        }
        if let previous, !hadPR { showTickForNewSet(old: previous, new: state, haptic: false) }

        // The set was logged on the iPhone: still measure heart-rate recovery here.
        if state.isResting, state.totalCompletedSets > (previous?.totalCompletedSets ?? 0), let last = state.lastLoggedSet {
            startRecoveryMeasurement(setID: last.id, startHeartRate: workoutManager.heartRateBPM)
        }
    }

    private func receiveCancel(_ id: UUID) {
        endedWorkoutIDs.insert(id)
        guard activeWorkout?.workoutID == id else {
            // A Health session started for a workout that never arrived here: stop it.
            if activeWorkout == nil, workoutManager.hasSession { workoutManager.discardWorkout() }
            return
        }
        restTask?.cancel()
        recoveryTask?.cancel()
        restFinished = false
        workoutManager.discardWorkout()
        activeWorkout = nil
        saveToDisk()
    }

    /// Called when the iPhone launches this app via `startWatchApp`.
    func startHealthSessionFromPhone() async {
        if activeWorkout == nil { bridge.requestActiveWorkout() }
        await workoutManager.startWorkout()
        // If no workout ever arrives from the iPhone, don't leave a Health session running.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            await MainActor.run {
                guard let self, self.activeWorkout == nil, self.workoutManager.hasSession else { return }
                self.workoutManager.discardWorkout()
            }
        }
    }

    // MARK: Runs & basketball

    /// Started from the Watch's own menu.
    func startActivity(kind: ActivityKind, indoor: Bool, goal: RunGoal?, basketballType: BasketballType?) async {
        let request = ActivityRequest(kind: kind, indoor: indoor, goal: goal, basketballType: basketballType,
                                      maxHeartRate: HeartZones.estimatedMax(profile: profile, logs: workoutLogs))
        await WatchActivityManager.shared.start(request)
    }

    /// The iPhone launched the app for a run / basketball (its message with the goal may arrive just after).
    func startActivityFromPhone(_ configuration: HKWorkoutConfiguration) async {
        let kind: ActivityKind = configuration.activityType == .basketball ? .basketball : .run
        try? await Task.sleep(nanoseconds: 1_500_000_000)   // give the iPhone's message (with the goal) a moment
        guard !WatchActivityManager.shared.isActive else { return }
        clearOrphanedGymSession()
        await startActivity(kind: kind, indoor: configuration.locationType != .outdoor, goal: nil, basketballType: nil)
    }

    /// A gym session left running with no workout on screen would block the run from starting.
    func clearOrphanedGymSession() {
        if activeWorkout == nil, workoutManager.hasSession { workoutManager.discardWorkout() }
    }

    func sendActivityProgress(_ progress: ActivityProgress) {
        bridge.sendActivityProgress(progress)
    }

    func sendCompletedActivity(_ session: CardioSession) {
        bridge.sendCompletedActivity(session)
    }

    /// Counts it here too (history for the week until the iPhone sends its snapshot).
    func recordActivity(_ session: CardioSession) {
        guard !workoutLogs.contains(where: { $0.id == session.id }) else { return }
        workoutLogs.append(session.workoutLog)
        saveToDisk()
    }

    // MARK: Workout actions

    func beginFromWatch(_ routine: WorkoutRoutine) async {
        guard activeWorkout == nil, !routine.exercises.isEmpty else { return }
        let state = ActiveWorkoutState.start(routine: routine, profile: profile)
        summary = nil
        WatchActivityManager.shared.summary = nil
        restFinished = false
        activeWorkout = state
        saveToDisk()
        bridge.sendActiveState(state, reliable: true)
        await workoutManager.startWorkout()
    }

    /// The phone's draft, only if it's for the set you're on now.
    var currentDraft: WorkoutDraft? {
        guard let draft = phoneDraft, let state = activeWorkout, draft.matches(state) else { return nil }
        return draft
    }

    func previousLog(for exercise: ExerciseDefinition) -> ExerciseLog? {
        workoutLogs.previousLog(for: exercise, before: activeWorkout?.startedAt)
    }

    func prefill(for item: RoutineExercise) -> (weightKg: Double, reps: Int) {
        guard let state = activeWorkout else { return (0, item.exercise.repMin) }
        return state.prefill(for: item, logs: workoutLogs)
    }

    func dismissRestFinished() {
        restFinishedTask?.cancel()
        guard restFinished else { return }
        restFinished = false
        WKInterfaceDevice.current().play(.click)
    }

    func dismissCelebration() {
        celebrationTask?.cancel()
        celebration = nil
    }

    func startCardioTimer() {
        cardioStartedAt = .now
    }

    func completeCurrentSet(weightKg: Double, reps: Int, durationSeconds: Double? = nil, distanceKm: Double? = nil) {
        guard var state = activeWorkout, let item = state.currentItem else { return }
        restFinished = false
        phoneDraft = nil
        cardioStartedAt = nil

        let isCardio = item.exercise.isCardio
        let target = state.prefill(for: item, logs: workoutLogs)
        let heartRate = workoutManager.heartRateBPM
        let result = state.completeSet(
            weightKg: weightKg,
            reps: reps,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            targetWeightKg: isCardio ? nil : target.weightKg,
            targetReps: isCardio ? nil : target.reps,
            history: workoutLogs,
            heartRate: heartRate
        )
        let loggedID = state.lastLoggedSet?.id
        let previous = activeWorkout
        update(state, reliable: true)
        let isPR = state.lastPR.map { !seenPRs.contains($0.id) } ?? false
        announcePRIfNew(state)
        // PRs get the full-screen celebration (and its buzz); every other set gets the tick + light double tap.
        if !isPR, let previous { showTickForNewSet(old: previous, new: state, haptic: true) }

        if case .rest = result, let loggedID {
            startRecoveryMeasurement(setID: loggedID, startHeartRate: heartRate)
        }
    }

    func skipRest() {
        guard var state = activeWorkout else { return }
        state.endRest()
        update(state)
    }

    func addRest(seconds: Int) {
        guard var state = activeWorkout else { return }
        state.extendRest(by: seconds)
        update(state)
    }

    func jumpToExercise(_ index: Int) {
        guard var state = activeWorkout else { return }
        state.jump(toExercise: index)
        cardioStartedAt = nil
        update(state)
    }

    func skipExercise(at index: Int) {
        guard var state = activeWorkout else { return }
        state.skipExercise(at: index)
        cardioStartedAt = nil
        restFinished = false
        update(state, reliable: true)
        if state.isComplete { WKInterfaceDevice.current().play(.success) }
    }

    func addExtraSet(toExercise index: Int) {
        guard var state = activeWorkout else { return }
        state.addExtraSet(to: index)
        update(state)
    }

    func swapExercise(at index: Int, to replacement: ExerciseDefinition) {
        guard var state = activeWorkout else { return }
        state.swapExercise(at: index, to: replacement)
        cardioStartedAt = nil
        update(state, reliable: true)
    }

    func finishWorkout() async {
        guard let state = activeWorkout, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        restTask?.cancel()
        recoveryTask?.cancel()
        restFinished = false
        cardioStartedAt = nil

        if state.totalCompletedSets == 0 {
            endedWorkoutIDs.insert(state.workoutID)
            workoutManager.discardWorkout()
            activeWorkout = nil
            saveToDisk()
            bridge.sendCancel(state.workoutID)
            return
        }

        let metrics = await workoutManager.endWorkout()
        var log = state.makeLog(
            endedAt: .now,
            activeCalories: metrics.activeCalories,
            averageHeartRate: metrics.averageHeartRate,
            maxHeartRate: metrics.maxHeartRate
        )
        log.heartRateSeries = metrics.heartRateSeries
        workoutLogs.append(log)
        activeWorkout = nil
        summary = log
        saveToDisk()
        bridge.sendCompletedWorkout(log)
    }

    func discardWorkout() {
        guard let state = activeWorkout else { return }
        endedWorkoutIDs.insert(state.workoutID)
        restTask?.cancel()
        recoveryTask?.cancel()
        restFinished = false
        cardioStartedAt = nil
        workoutManager.discardWorkout()
        activeWorkout = nil
        saveToDisk()
        bridge.sendCancel(state.workoutID)
    }

    func closeSummary() {
        summary = nil
    }

    // MARK: Helpers

    private func update(_ state: ActiveWorkoutState, reliable: Bool = false) {
        if !state.isResting { restFinished = false }
        activeWorkout = state
        saveToDisk()
        bridge.sendActiveState(state, reliable: reliable)
        syncRestTimer(state)
    }

    private func announcePRIfNew(_ state: ActiveWorkoutState) {
        guard let pr = state.lastPR, !seenPRs.contains(pr.id) else { return }
        seenPRs.insert(pr.id)
        celebration = pr
        WKInterfaceDevice.current().play(.success)
        celebrationTask?.cancel()
        celebrationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.celebration = nil }
        }
    }

    private func syncRestTimer(_ state: ActiveWorkoutState) {
        if state.isResting, let end = state.restEndDate {
            if end.timeIntervalSinceNow < -5 {
                // A rest that already ended (the iPhone hadn't heard yet): end it quietly, no second alert.
                restTask?.cancel()
                var ended = state
                ended.endRest()
                activeWorkout = ended
                saveToDisk()
                bridge.sendActiveState(ended, reliable: true)
            } else {
                scheduleRestCompletion(at: end)
            }
        } else {
            restTask?.cancel()
        }
    }

    private func scheduleRestCompletion(at date: Date) {
        restTask?.cancel()
        restTask = Task { [weak self] in
            let interval = max(0, date.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.finishRest()
        }
    }

    /// Ends rest with the "Rest finished" screen and three buzzes (timer ran out, or HR came down).
    private func finishRest() async {
        guard var state = activeWorkout, state.isResting else { return }
        state.endRest()
        activeWorkout = state
        restFinished = true
        saveToDisk()
        bridge.sendActiveState(state, reliable: true)
        // Don't leave the alert up forever if it's missed: back to the set screen after 20 s.
        restFinishedTask?.cancel()
        restFinishedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.restFinished = false }
        }
        await WatchAppStore.buzzThreeTimes()
    }

    private func checkAutoRest(heartRate: Double) {
        guard profile.autoRest, heartRate > 0, heartRate <= Double(profile.autoRestBPM),
              let state = activeWorkout, state.isResting,
              let start = state.restStartedAt, let end = state.restEndDate else { return }
        let planned = end.timeIntervalSince(start)
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed >= max(30, planned * 0.5) else { return }
        restTask?.cancel()
        Task { await finishRest() }
    }

    /// Records how far heart rate falls in the first 60 s of rest.
    private func startRecoveryMeasurement(setID: UUID, startHeartRate: Double) {
        recoveryTask?.cancel()
        guard startHeartRate > 0 else {
            restHeartRateStart = nil
            return
        }
        restHeartRateStart = startHeartRate
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, var state = self.activeWorkout,
                      state.lastLoggedSet?.id == setID,
                      state.isResting || self.restFinished else { return }
                let now = self.workoutManager.heartRateBPM
                guard now > 0 else { return }
                state.updateSet(id: setID) { $0.heartRateRecovery = max(0, startHeartRate - now) }
                self.activeWorkout = state
                self.saveToDisk()
                self.bridge.sendActiveState(state, reliable: true)
            }
        }
    }

    /// Tick for the newest set that wasn't in `old` (says when the exercise / workout is done).
    private func showTickForNewSet(old: ActiveWorkoutState, new state: ActiveWorkoutState, haptic: Bool) {
        guard old.workoutID == state.workoutID else { return }
        let oldIDs = Set(old.completedSets.values.flatMap { $0 }.map(\.id))
        let fresh = state.completedSets.flatMap { key, list in
            list.filter { !oldIDs.contains($0.id) }.map { (exerciseID: key, set: $0) }
        }
        guard let newest = fresh.max(by: { $0.set.completedAt < $1.set.completedAt }),
              newest.set.completedAt.timeIntervalSinceNow > -15 else { return }
        let finishedItem = state.routine.exercises.first {
            $0.exercise.id == newest.exerciseID && state.isFinished($0) && !state.isSkipped($0)
        }
        let caption: String? = state.isComplete ? "All sets done" : finishedItem.map { "\($0.exercise.name) done" }
        let tick = WatchSetTick(id: newest.set.id, caption: caption)
        setTick = tick
        if haptic { WatchAppStore.lightDoubleTap() }
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: caption == nil ? 1_000_000_000 : 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.setTick?.id == tick.id { self?.setTick = nil }
            }
        }
    }

    /// Two light taps in quick succession.
    static func lightDoubleTap() {
        WKInterfaceDevice.current().play(.click)
        Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            await MainActor.run { WKInterfaceDevice.current().play(.click) }
        }
    }

    /// Three distinct taps, spaced so they're felt as separate buzzes.
    static func buzzThreeTimes() async {
        for index in 0..<3 {
            await MainActor.run { WKInterfaceDevice.current().play(.notification) }
            if index < 2 { try? await Task.sleep(nanoseconds: 900_000_000) }
        }
    }

    // MARK: Persistence (so a terminated app doesn't lose the workout)

    private var stateURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("gymforge-watch.json")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder.gymForge.decode(WatchPersistedState.self, from: data) else { return }
        routines = saved.routines
        workoutLogs = saved.workoutLogs
        if let savedProfile = saved.profile { profile = savedProfile }
        if let active = saved.activeWorkout, abs(active.startedAt.timeIntervalSinceNow) < 6 * 3600 {
            activeWorkout = active
        }
    }

    private func saveToDisk() {
        let state = WatchPersistedState(routines: routines, workoutLogs: workoutLogs, activeWorkout: activeWorkout, profile: profile)
        do {
            let data = try JSONEncoder.gymForge.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            print("Could not save Watch state: \(error)")
        }
    }
}
