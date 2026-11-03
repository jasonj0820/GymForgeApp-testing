import Foundation
import HealthKit
import Combine

struct WorkoutMetrics {
    var activeCalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    /// MK10.1: a reading every ~10 s for the heart-rate graph.
    var heartRateSeries: [HeartRatePoint]?
}

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published var heartRateBPM: Double = 0
    @Published var maxHeartRateBPM: Double = 0
    @Published var activeEnergyKcal: Double = 0
    @Published var isRunning = false
    @Published var startDate: Date?
    @Published var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStarting = false
    /// Discard was asked for while the session was still starting (e.g. during the Health permission prompt).
    private var cancelPending = false
    private var didRequestAuthorization = false
    private var heartSeries: [HeartRatePoint] = []

    private override init() { super.init() }

    var hasSession: Bool { session != nil }
    /// A gym session exists or is being started.
    var isBusy: Bool { session != nil || isStarting }

    func requestAuthorization() async {
        guard !didRequestAuthorization else { return }
        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        else { return }

        let share: Set<HKSampleType> = [HKObjectType.workoutType(), activeEnergy, heartRate]
        let read: Set<HKObjectType> = [heartRate, activeEnergy, HKObjectType.workoutType()]

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            didRequestAuthorization = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Safe to call from both the iPhone launch path and the Watch UI — only one session is ever created.
    /// The configuration from `startWatchApp` is ignored on purpose: it often arrives as a default
    /// "Other" workout, which would save to Apple Health with the wrong type.
    func startWorkout() async {
        // A run / basketball session already owns HealthKit's workout session.
        guard session == nil, !isStarting, !WatchActivityManager.shared.isActive else { return }
        isStarting = true
        cancelPending = false
        defer { isStarting = false }

        await requestAuthorization()
        if cancelPending {
            cancelPending = false
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            newSession.delegate = self
            newBuilder.delegate = self
            session = newSession
            builder = newBuilder
            heartRateBPM = 0
            maxHeartRateBPM = 0
            activeEnergyKcal = 0
            heartSeries = []

            let start = Date()
            newSession.startActivity(with: start)
            try await newBuilder.beginCollection(at: start)
            // Discarded while collection was starting.
            guard session === newSession else { return }
            startDate = start
            isRunning = true
            if cancelPending {
                cancelPending = false
                discardWorkout()
                return
            }

            do {
                try await newSession.startMirroringToCompanionDevice()
            } catch {
                print("Workout mirroring unavailable: \(error)")
            }
        } catch {
            errorMessage = error.localizedDescription
            // Don't leave a half-started session running in the background.
            session?.end()
            builder?.discardWorkout()
            session = nil
            builder = nil
            isRunning = false
        }
    }

    /// Re-attaches to a workout that was running when the app crashed or was terminated.
    func recoverSession() {
        guard session == nil else { return }
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            Task { @MainActor in
                guard let self else { return }
                if let error { self.errorMessage = error.localizedDescription }
                guard let recovered, self.session == nil else { return }
                // A run or basketball session: hand it to the activity manager.
                let type = recovered.workoutConfiguration.activityType
                if type == .running || type == .basketball {
                    WatchActivityManager.shared.adopt(recovered)
                    return
                }
                let recoveredBuilder = recovered.associatedWorkoutBuilder()
                recovered.delegate = self
                recoveredBuilder.delegate = self
                self.session = recovered
                self.builder = recoveredBuilder
                self.startDate = recoveredBuilder.startDate
                self.isRunning = true
            }
        }
    }

    /// Keeps one reading every 10 s (≈360 an hour) for the graph after the workout.
    private func recordHeartRate(_ bpm: Double) {
        guard let startDate, bpm > 0 else { return }
        let t = Int(Date().timeIntervalSince(startDate))
        if let last = heartSeries.last, t - last.t < 10 { return }
        heartSeries.append(HeartRatePoint(t: Swift.max(t, 0), bpm: Int(bpm.rounded())))
    }

    func endWorkout() async -> WorkoutMetrics {
        guard let session, let builder else { return WorkoutMetrics() }
        let end = Date()
        session.end()

        do {
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            errorMessage = error.localizedDescription
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        var metrics = WorkoutMetrics(activeCalories: activeEnergyKcal > 0 ? activeEnergyKcal : nil)
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           let stats = builder.statistics(for: hrType) {
            metrics.averageHeartRate = stats.averageQuantity()?.doubleValue(for: bpm)
            metrics.maxHeartRate = stats.maximumQuantity()?.doubleValue(for: bpm)
        }
        if metrics.maxHeartRate == nil, maxHeartRateBPM > 0 { metrics.maxHeartRate = maxHeartRateBPM }
        metrics.heartRateSeries = heartSeries.count >= 3 ? heartSeries : nil
        heartSeries = []

        reset()
        return metrics
    }

    /// Ends the session without saving anything to Apple Health.
    func discardWorkout() {
        guard let session, let builder else {
            if isStarting { cancelPending = true }
            return
        }
        session.end()
        builder.discardWorkout()
        reset()
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        startDate = nil
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.isRunning = toState == .running
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var heartRate: Double?
        var energy: Double?
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(hrType) {
            heartRate = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?.doubleValue(for: bpm)
        }
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned), collectedTypes.contains(energyType) {
            energy = workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        let latestHeartRate = heartRate
        let totalEnergy = energy
        Task { @MainActor in
            if let heartRate = latestHeartRate {
                self.heartRateBPM = heartRate
                self.maxHeartRateBPM = max(self.maxHeartRateBPM, heartRate)
                self.recordHeartRate(heartRate)
            }
            if let energy = totalEnergy { self.activeEnergyKcal = energy }
        }
    }
}
