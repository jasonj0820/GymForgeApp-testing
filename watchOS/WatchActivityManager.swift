import CoreLocation
import Foundation
import HealthKit
import WatchKit

/// Runs (outdoor with GPS, or treadmill) and basketball as their own Apple Health workouts:
/// heart rate, zones, distance, pace, km splits with a wrist tap, pace / distance / time goals,
/// auto-pause outdoors, running form, and a GPS route saved with the workout.
@MainActor
final class WatchActivityManager: NSObject, ObservableObject {
    static let shared = WatchActivityManager()

    @Published private(set) var request: ActivityRequest?
    @Published private(set) var startDate: Date?
    @Published private(set) var isPaused = false
    @Published private(set) var autoPaused = false
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var activeCalories: Double = 0
    @Published private(set) var currentPace: Double?
    @Published private(set) var splits: [Double] = []
    @Published private(set) var cadence: Double?
    @Published private(set) var powerWatts: Double?
    @Published private(set) var strideMeters: Double?
    /// "Km 3 · 5:12" / "Speed up" etc. for a few seconds.
    @Published private(set) var banner: String?
    @Published var summary: CardioSession?
    @Published var errorMessage: String?

    /// A run / basketball session exists or is being started.
    var isActive: Bool { session != nil || isStarting }
    private var isStarting = false
    @Published private(set) var isEnding = false
    /// Distance already covered before a recovered session was re-attached (keeps km splits right).
    private var splitBaseKm = 0

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationManager: CLLocationManager?
    private var route: [RoutePoint] = []
    private var heartRates: [Double] = []
    private var maxHeart: Double = 0
    private var zoneSeconds: [Double] = [0, 0, 0, 0, 0]
    private var lastHeartSample: Date?
    private var paceSamples: [(time: Double, km: Double)] = []
    private var lastSplitElapsed: Double = 0
    private var lastGoalAlert: Date = .distantPast
    private var goalReachedAnnounced = false
    private var slowSince: Date?
    private var progressTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var cadenceSteps: Double = 0

    /// Moving time (pauses excluded).
    var elapsed: TimeInterval { builder?.elapsedTime ?? 0 }

    // MARK: Start

    func start(_ newRequest: ActivityRequest) async {
        guard session == nil, !isStarting else {
            // Already running (or starting): a duplicate from the iPhone just fills in its settings.
            if request?.kind == newRequest.kind {
                request?.goal = newRequest.goal ?? request?.goal
                request?.basketballType = newRequest.basketballType ?? request?.basketballType
                request?.maxHeartRate = newRequest.maxHeartRate
            }
            return
        }
        guard !WatchWorkoutManager.shared.isBusy else {
            errorMessage = "Finish your gym workout first."
            return
        }
        isStarting = true
        defer { isStarting = false }
        resetMetrics()
        request = newRequest   // set before waiting, so a duplicate arriving now can merge into it
        await requestAuthorization(outdoorRun: newRequest.kind == .run && !newRequest.indoor)
        guard request?.id == newRequest.id, let startRequest = request else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = newRequest.kind == .run ? .running : .basketball
        config.locationType = newRequest.indoor || newRequest.kind == .basketball ? .indoor : .outdoor
        do {
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            newSession.delegate = self
            newBuilder.delegate = self
            request = startRequest
            session = newSession
            builder = newBuilder
            let start = Date()
            newSession.startActivity(with: start)
            try await newBuilder.beginCollection(at: start)
            startDate = start
            if startRequest.kind == .run && !startRequest.indoor { startLocation() }
            WKInterfaceDevice.current().play(.start)
            startProgressUpdates()
        } catch {
            errorMessage = error.localizedDescription
            session?.end()
            session = nil
            builder = nil
            request = nil
        }
    }

    private func requestAuthorization(outdoorRun: Bool) async {
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        var read: Set<HKObjectType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .stepCount,
                                               .runningPower, .runningStrideLength, .runningSpeed]
        for id in ids {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                read.insert(type)
                if id == .activeEnergyBurned || id == .distanceWalkingRunning || id == .heartRate { share.insert(type) }
            }
        }
        share.insert(HKSeriesType.workoutRoute())
        read.insert(HKSeriesType.workoutRoute())
        try? await healthStore.requestAuthorization(toShare: share, read: read)
        _ = outdoorRun   // location permission is asked by the manager that's kept for the run (startLocation)
    }

    private func resetMetrics() {
        distanceKm = 0
        heartRate = 0
        activeCalories = 0
        currentPace = nil
        splits = []
        cadence = nil
        powerWatts = nil
        strideMeters = nil
        banner = nil
        summary = nil
        isPaused = false
        autoPaused = false
        route = []
        heartRates = []
        maxHeart = 0
        zoneSeconds = [0, 0, 0, 0, 0]
        lastHeartSample = nil
        paceSamples = []
        lastSplitElapsed = 0
        splitBaseKm = 0
        lastGoalAlert = .distantPast
        goalReachedAnnounced = false
        slowSince = nil
        cadenceSteps = 0
    }

    // MARK: Location (outdoor runs)

    private func startLocation() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone   // standing still must still report (auto-pause needs it)
        manager.activityType = .fitness
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        locationManager = manager
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
    }

    fileprivate func received(_ locations: [CLLocation]) {
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 50 }
        guard !good.isEmpty, session != nil else { return }
        if !isPaused {
            routeBuilder?.insertRouteData(good) { _, _ in }
            for location in good where route.last.map({ location.timestamp.timeIntervalSince($0.t) >= 4 }) ?? true {
                route.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude, t: location.timestamp))
            }
        }
        // Auto-pause: stopped (< 0.6 m/s) for 10 s; resume when moving again (> 1.4 m/s).
        guard let speed = good.last?.speed, speed >= 0 else { return }
        if !isPaused, speed < 0.6 {
            if let since = slowSince {
                if Date().timeIntervalSince(since) >= 10 { pause(auto: true) }
            } else {
                slowSince = Date()
            }
        } else {
            slowSince = nil
            if isPaused, autoPaused, speed > 1.4 { resume() }
        }
    }

    // MARK: Controls

    func pause(auto: Bool = false) {
        guard let session, !isPaused else { return }
        session.pause()
        isPaused = true
        autoPaused = auto
        showBanner(auto ? "Auto-paused" : "Paused")
        WKInterfaceDevice.current().play(.stop)
    }

    func resume() {
        guard let session, isPaused else { return }
        session.resume()
        isPaused = false
        autoPaused = false
        slowSince = nil
        showBanner("Resumed")
        WKInterfaceDevice.current().play(.start)
    }

    func end() async {
        guard !isEnding, let session, let builder, let request, let startDate else { return }
        isEnding = true
        defer { isEnding = false }
        progressTask?.cancel()
        locationManager?.stopUpdatingLocation()
        let end = Date()
        let moving = builder.elapsedTime
        if session.state != .ended { session.end() }
        var workout: HKWorkout?
        do {
            try await builder.endCollection(at: end)
            workout = try await builder.finishWorkout()
        } catch {
            errorMessage = error.localizedDescription
        }
        if let workout, let routeBuilder, !route.isEmpty {
            _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
        }
        let averageHR = heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count)
        var result = CardioSession(id: request.id, kind: request.kind, indoor: request.indoor, startedAt: startDate, endedAt: end,
                                   activeSeconds: moving, distanceKm: request.kind == .run ? distanceKm : nil,
                                   activeCalories: activeCalories > 0 ? activeCalories : nil,
                                   averageHeartRate: averageHR, maxHeartRate: maxHeart > 0 ? maxHeart : nil,
                                   splits: splits, route: route.isEmpty ? nil : route, goal: request.goal,
                                   zoneSeconds: zoneSeconds, basketballType: request.basketballType)
        result.cadence = cadence
        result.powerWatts = powerWatts
        result.strideMeters = strideMeters
        WatchAppStore.shared.sendCompletedActivity(result)
        WatchAppStore.shared.recordActivity(result)
        summary = result
        self.session = nil
        self.builder = nil
        self.routeBuilder = nil
        self.locationManager = nil
        self.request = nil
        self.startDate = nil
        WKInterfaceDevice.current().play(.success)
    }

    /// Ends without saving (e.g. started by mistake).
    func discard() {
        guard !isEnding else { return }
        progressTask?.cancel()
        locationManager?.stopUpdatingLocation()
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        routeBuilder = nil
        locationManager = nil
        request = nil
        startDate = nil
    }

    /// Re-attaches a run / basketball session after the app was closed mid-workout (no route afterwards).
    func adopt(_ recovered: HKWorkoutSession) {
        guard session == nil else { return }
        let config = recovered.workoutConfiguration
        let kind: ActivityKind = config.activityType == .basketball ? .basketball : .run
        resetMetrics()
        request = ActivityRequest(kind: kind, indoor: config.locationType != .outdoor, maxHeartRate: 190)
        session = recovered
        builder = recovered.associatedWorkoutBuilder()
        recovered.delegate = self
        builder?.delegate = self
        startDate = builder?.startDate ?? Date()
        isPaused = recovered.state == .paused
        // Splits restart from the next whole km of what was already run.
        if kind == .run, let builder,
           let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           let km = builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) {
            distanceKm = km
            splitBaseKm = Int(km)
            lastSplitElapsed = builder.elapsedTime
        }
        startProgressUpdates()
    }

    // MARK: Live numbers

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.sendProgress() }
            }
        }
    }

    private func sendProgress() {
        guard let request, let startDate else { return }
        WatchAppStore.shared.sendActivityProgress(ActivityProgress(
            id: request.id, kind: request.kind, title: request.title, startedAt: startDate, elapsed: elapsed,
            distanceKm: distanceKm, paceSeconds: currentPace, heartRate: heartRate, isPaused: isPaused))
    }

    fileprivate func update(heartRate newHR: Double?, energy: Double?, distance: Double?, steps: Double?,
                            power: Double?, stride: Double?) {
        let now = Date()
        if let newHR, newHR > 0 {
            heartRate = newHR
            heartRates.append(newHR)
            maxHeart = max(maxHeart, newHR)
            if let last = lastHeartSample, !isPaused, let zone = HeartZones.zone(heartRate: newHR, max: request?.maxHeartRate ?? 190) {
                zoneSeconds[zone] += min(now.timeIntervalSince(last), 15)
            }
            lastHeartSample = now
        }
        if let energy { activeCalories = energy }
        if let power, power > 0 { powerWatts = power }
        if let stride, stride > 0 { strideMeters = stride }
        if let steps, steps > 0 {
            cadenceSteps = steps
            if elapsed > 60 { cadence = steps / (elapsed / 60) }
        }
        guard let distance, request?.kind == .run else { return }
        distanceKm = distance
        let time = elapsed
        paceSamples.append((time, distance))
        paceSamples.removeAll { time - $0.time > 60 }
        if let first = paceSamples.first, time - first.time >= 20, distance - first.km > 0.02 {
            currentPace = (time - first.time) / (distance - first.km)
        }
        // Km splits.
        let completed = Int(distance)
        if completed > splits.count + splitBaseKm {
            let split = time - lastSplitElapsed
            lastSplitElapsed = time
            splits.append(split)
            showBanner("Km \(completed) · \(CardioFormat.pace(split))")
            WKInterfaceDevice.current().play(.notification)
        }
        checkGoal(time: time, distance: distance)
    }

    private func checkGoal(time: Double, distance: Double) {
        guard let goal = request?.goal else { return }
        switch goal.kind {
        case .open:
            break
        case .distance:
            if let target = goal.distanceKm, distance >= target, !goalReachedAnnounced {
                goalReachedAnnounced = true
                showBanner("Goal reached: \(GFFormat.km(target)) km")
                WKInterfaceDevice.current().play(.success)
            }
        case .time:
            if let minutes = goal.minutes, time >= minutes * 60, !goalReachedAnnounced {
                goalReachedAnnounced = true
                showBanner("Goal reached: \(Int(minutes)) min")
                WKInterfaceDevice.current().play(.success)
            }
        case .pace:
            guard let target = goal.paceSeconds, let pace = currentPace, Date().timeIntervalSince(lastGoalAlert) > 60,
                  time > 90 else { return }
            if pace > target + 15 {
                lastGoalAlert = Date()
                showBanner("Speed up — \(CardioFormat.pace(pace)) vs \(CardioFormat.pace(target))")
                WKInterfaceDevice.current().play(.directionUp)
            } else if pace < target - 15 {
                lastGoalAlert = Date()
                showBanner("Ease off — \(CardioFormat.pace(pace)) vs \(CardioFormat.pace(target))")
                WKInterfaceDevice.current().play(.directionDown)
            }
        }
    }

    private func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.banner = nil }
        }
    }

    /// 0…4 (zones 1–5) for the current heart rate.
    var zone: Int? { HeartZones.zone(heartRate: heartRate, max: request?.maxHeartRate ?? 190) }
}

extension WatchActivityManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            let manager = WatchActivityManager.shared
            guard manager.session === workoutSession else { return }
            switch toState {
            case .paused:
                manager.isPaused = true
            case .running:
                manager.isPaused = false
                manager.autoPaused = false
            case .ended:
                // Ended from outside the app (e.g. the system): save what was recorded.
                if !manager.isEnding { await manager.end() }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }
}

extension WatchActivityManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            guard let type = HKObjectType.quantityType(forIdentifier: id), collectedTypes.contains(type) else { return nil }
            return workoutBuilder.statistics(for: type)?.mostRecentQuantity()?.doubleValue(for: unit)
        }
        func total(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) -> Double? {
            guard let type = HKObjectType.quantityType(forIdentifier: id), collectedTypes.contains(type) else { return nil }
            return workoutBuilder.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
        }
        let heart = latest(.heartRate, HKUnit.count().unitDivided(by: .minute()))
        let energy = total(.activeEnergyBurned, .kilocalorie())
        let distance = total(.distanceWalkingRunning, .meterUnit(with: .kilo))
        let steps = total(.stepCount, .count())
        let power = latest(.runningPower, .watt())
        let stride = latest(.runningStrideLength, .meter())
        Task { @MainActor in
            WatchActivityManager.shared.update(heartRate: heart, energy: energy, distance: distance, steps: steps,
                                               power: power, stride: stride)
        }
    }
}

extension WatchActivityManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in WatchActivityManager.shared.received(locations) }
    }
}
