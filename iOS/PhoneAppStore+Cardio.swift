import Foundation

/// MK9.1: runs and basketball recorded on the Watch.
extension PhoneAppStore {
    var estimatedMaxHeartRate: Double {
        HeartZones.estimatedMax(profile: profile, logs: workoutLogs, sessions: cardioSessions)
    }

    var runs: [CardioSession] {
        cardioSessions.filter { $0.kind == .run }.sorted { $0.startedAt > $1.startedAt }
    }

    /// Opens GymForge on the Watch already recording.
    func startActivity(kind: ActivityKind, indoor: Bool, goal: RunGoal?, basketballType: BasketballType?) {
        guard activeWorkout == nil, !phoneRecorder.isActive else { return }
        let request = ActivityRequest(kind: kind, indoor: indoor, goal: goal, basketballType: basketballType,
                                      maxHeartRate: estimatedMaxHeartRate)
        watchBridge.sendStartActivity(request)
        healthKit.launchWatchActivity(kind: kind, indoor: indoor)
    }

    func receiveActivityProgress(_ progress: ActivityProgress) {
        guard !cardioSessions.contains(where: { $0.id == progress.id }) else { return }
        liveCardio = progress
        lastCardioProgressAt = .now
        liveActivity.syncCardio(progress)
        cardioStaleTask?.cancel()
        cardioStaleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 125 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.clearStaleCardio()
        }
    }

    /// The Watch sends numbers every 10 s; after 2 minutes of silence (Watch app closed, session lost)
    /// the live card goes away rather than freezing on old numbers.
    func clearStaleCardio() {
        guard liveCardio != nil, let last = lastCardioProgressAt, Date().timeIntervalSince(last) > 120 else { return }
        liveCardio = nil
        lastCardioProgressAt = nil
        liveActivity.syncCardio(nil)
    }

    /// A finished run / basketball session from the Watch: kept with its details, and as a workout
    /// so it shows on the week row (as an extra: only weight training counts toward the goal).
    func receiveCompletedActivity(_ session: CardioSession, showSummary: Bool = true) {
        let isNew = !cardioSessions.contains { $0.id == session.id }
        if let index = cardioSessions.firstIndex(where: { $0.id == session.id }) {
            cardioSessions[index] = session
        } else {
            cardioSessions.append(session)
        }
        let log = session.workoutLog
        if let index = workoutLogs.firstIndex(where: { $0.id == log.id }) {
            workoutLogs[index] = log
        } else {
            workoutLogs.append(log)
            workoutLogs.sort { $0.startedAt < $1.startedAt }
        }
        if liveCardio?.id == session.id {
            liveCardio = nil
            lastCardioProgressAt = nil
            cardioStaleTask?.cancel()
        }
        liveActivity.endCardio(id: session.id)
        persistAndSync()
        rescheduleReminders()
        if showSummary, isNew, Date().timeIntervalSince(session.endedAt) < 30 * 60 { cardioSummary = session }
    }

    // MARK: MK10 — on the iPhone, without a Watch

    /// The Watch is set up (paired, GymForge installed).
    var watchAvailableForCardio: Bool { watchBridge.isWatchReady }

    /// Records on the iPhone: GPS for outdoor runs, a timer otherwise. No heart rate.
    func startPhoneActivity(kind: ActivityKind, indoor: Bool, goal: RunGoal?, basketballType: BasketballType?) {
        guard activeWorkout == nil, !phoneRecorder.isActive else { return }
        let request = ActivityRequest(kind: kind, indoor: kind == .basketball || indoor, goal: goal, basketballType: basketballType,
                                      maxHeartRate: estimatedMaxHeartRate)
        phoneRecorder.start(request)
        Task { await healthKit.requestCardioAuthorization() }
    }

    /// Saves the phone-recorded session once you've rated it (effort, treadmill distance, basketball numbers).
    func savePhoneActivity(_ session: CardioSession) {
        let route = phoneRecorder.finishedLocations
        phoneRecorder.pendingFinish = nil
        liveCardio = nil
        lastCardioProgressAt = nil
        cardioStaleTask?.cancel()
        receiveCompletedActivity(session, showSummary: false)
        Task { await healthKit.saveCardio(session, route: route) }
    }

    func discardPhoneActivity() {
        let id = phoneRecorder.pendingFinish?.id ?? phoneRecorder.request?.id
        phoneRecorder.discard()
        liveCardio = nil
        lastCardioProgressAt = nil
        if let id { liveActivity.endCardio(id: id) }
    }

    /// A run or game you didn't record: logged afterwards (and saved to Apple Health).
    func logManualActivity(_ session: CardioSession) {
        var logged = session
        logged.recordedOn = "manual"
        receiveCompletedActivity(logged, showSummary: false)
        Task { await healthKit.saveCardio(logged, route: []) }
    }

    /// Shots, minutes played, a corrected treadmill distance…
    func updateCardio(_ session: CardioSession) {
        guard let index = cardioSessions.firstIndex(where: { $0.id == session.id }) else { return }
        cardioSessions[index] = session
        if let logIndex = workoutLogs.firstIndex(where: { $0.id == session.id }) {
            workoutLogs[logIndex] = session.workoutLog
        }
        persistAndSync()
    }

    func deleteCardio(_ session: CardioSession) {
        cardioSessions.removeAll { $0.id == session.id }
        workoutLogs.removeAll { $0.id == session.id }
        persistAndSync()
        rescheduleReminders()
    }
}
