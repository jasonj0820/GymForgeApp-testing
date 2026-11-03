import CoreLocation
import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitClient: ObservableObject {
    @Published var bodyWeight: [BodyMetricPoint] = []
    @Published var bodyFat: [BodyMetricPoint] = []
    @Published var sleep: [SleepNight] = []
    @Published var restingHeartRate: [BodyMetricPoint] = []
    @Published var heartRateVariability: [BodyMetricPoint] = []
    @Published var authorizationError: String?
    @Published var hasRequestedAuthorization = false

    private let healthStore = HKHealthStore()
    /// Retained so the mirrored session from the Watch isn't deallocated immediately.
    private var mirroredSession: HKWorkoutSession?

    init() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.mirroredSession = session }
        }
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data isn't available on this device."
            return
        }

        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let bodyFatPercentage = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        else { return }

        let workout = HKObjectType.workoutType()
        var read: Set<HKObjectType> = [heartRate, activeEnergy, bodyMass, bodyFatPercentage, workout]
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { read.insert(sleepType) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { read.insert(hrv) }
        var share: Set<HKSampleType> = [workout, activeEnergy, heartRate, HKSeriesType.workoutRoute()]
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { share.insert(distance) }
        share.formUnion(SleepHealth.shareTypes)   // MK11: manual "Going to sleep / I'm awake"

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            hasRequestedAuthorization = true
            await refreshBodyMetrics()
            await refreshRecovery()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    /// MK10: asks for the run types (distance, route) if they haven't been asked yet — no-op otherwise.
    func requestCardioAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), distance, HKSeriesType.workoutRoute()]
        try? await healthStore.requestAuthorization(toShare: share, read: [HKObjectType.workoutType()])
    }

    /// MK10: saves a run / basketball session recorded on the iPhone (or logged by hand) to Apple Health,
    /// with distance and the GPS route when there is one.
    func saveCardio(_ session: CardioSession, route: [CLLocation]) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = session.kind == .run ? .running : .basketball
        configuration.locationType = session.indoor || session.kind == .basketball ? .indoor : .outdoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            if let km = session.distanceKm, km > 0,
               let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                                              start: session.startedAt, end: Swift.max(session.endedAt, session.startedAt.addingTimeInterval(1)))
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: Swift.max(session.endedAt, session.startedAt.addingTimeInterval(1)))
            if let workout = try await builder.finishWorkout(), route.count >= 2 {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                try await routeBuilder.insertRouteData(route)
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            print("Could not save \(session.kind.rawValue) to Health: \(error.localizedDescription)")
        }
    }

    /// Wakes the Watch app. The Watch receives `handle(_ workoutConfiguration:)` and starts the HealthKit session.
    func launchWatchStrengthWorkout() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // No async version exists; the completion can also hang if the Watch is off, so don't wait on it.
        healthStore.startWatchApp(with: configuration) { success, error in
            if !success {
                print("Could not launch Watch workout app: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }

    /// Opens GymForge on the Watch for a run or basketball session (it starts recording straight away).
    func launchWatchActivity(kind: ActivityKind, indoor: Bool) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = kind == .run ? .running : .basketball
        configuration.locationType = indoor || kind == .basketball ? .indoor : .outdoor
        healthStore.startWatchApp(with: configuration) { success, error in
            if !success { print("Could not launch Watch for \(kind.rawValue): \(error?.localizedDescription ?? "unknown")") }
        }
    }

    /// Reads ~10 years so every chart range (including "All") has data.
    func refreshBodyMetrics(days: Int = 3650) async {
        async let weight = queryQuantity(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            metric: .bodyWeight,
            days: days,
            transform: { $0 }
        )
        async let fat = queryQuantity(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            metric: .bodyFatPercentage,
            days: days,
            transform: { $0 * 100 }
        )

        bodyWeight = await weight
        bodyFat = await fat
    }

    /// Sleep, resting heart rate and HRV for readiness and the monthly report (last ~120 days).
    func refreshRecovery(days: Int = 120) async {
        async let nights = querySleep(days: days)
        async let resting = queryQuantity(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            metric: .restingHeartRate,
            days: days,
            transform: { $0 }
        )
        async let variability = queryQuantity(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            metric: .heartRateVariability,
            days: days,
            transform: { $0 }
        )
        sleep = await nights
        restingHeartRate = await resting
        heartRateVariability = await variability
    }

    private func querySleep(days: Int) async -> [SleepNight] {
        await SleepHealth.nights(days: days, store: healthStore)
    }

    /// MK11: "Going to sleep" / "I'm awake" on the iPhone.
    func startManualSleep() { SleepHealth.manualStart = .now }

    func finishManualSleep() async {
        if await SleepHealth.finishManual(store: healthStore) { await refreshRecovery() }
    }

    private func queryQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        metric: BodyMetricPoint.Metric,
        days: Int,
        transform: @escaping (Double) -> Double
    ) async -> [BodyMetricPoint] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let store = healthStore

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let points = (samples as? [HKQuantitySample] ?? []).map { sample in
                    BodyMetricPoint(
                        metric: metric,
                        date: sample.startDate,
                        value: transform(sample.quantity.doubleValue(for: unit))
                    )
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }
}
