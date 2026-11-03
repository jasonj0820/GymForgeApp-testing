import CoreLocation
import Foundation
import UIKit

/// MK10: runs and basketball recorded on the iPhone when there's no Watch. Outdoor runs use the
/// phone's GPS (distance, pace, km splits, auto-pause, route); treadmill runs and basketball are a timer.
/// No heart rate — you rate the effort (1–10) at the end instead.
@MainActor
final class PhoneActivityRecorder: NSObject, ObservableObject {
    @Published private(set) var request: ActivityRequest?
    @Published private(set) var startDate: Date?
    @Published private(set) var isPaused = false
    @Published private(set) var autoPaused = false
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var currentPace: Double?
    @Published private(set) var splits: [Double] = []
    @Published private(set) var banner: String?
    @Published private(set) var gpsWeak = false
    @Published var locationDenied = false
    /// Finished and waiting for your effort rating (and treadmill distance / basketball numbers).
    @Published var pendingFinish: CardioSession?
    /// The GPS points of the finished run, for the Apple Health route.
    private(set) var finishedLocations: [CLLocation] = []

    /// Live numbers for the Lock Screen card (every 5 s).
    var onProgress: (@MainActor (ActivityProgress) -> Void)?

    private var locationManager: CLLocationManager?
    private var lastLocation: CLLocation?
    private var lastGoodFix: Date?
    private var route: [RoutePoint] = []
    private var locations: [CLLocation] = []
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: Date?
    private var slowSince: Date?
    private var paceSamples: [(time: Double, km: Double)] = []
    private var lastSplitElapsed: Double = 0
    private var goalReached = false
    private var lastGoalAlert = Date.distantPast
    private var ticker: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    private static let checkpointKey = "phoneCardioCheckpoint"

    var isActive: Bool { request != nil }
    var usesGPS: Bool { request?.kind == .run && request?.indoor == false }

    /// Moving time (pauses excluded).
    var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        let end = pausedAt ?? Date()
        return Swift.max(0, end.timeIntervalSince(startDate) - pausedTotal)
    }

    var averagePace: Double? {
        distanceKm > 0.05 ? elapsed / distanceKm : nil
    }

    // MARK: Start / stop

    func start(_ newRequest: ActivityRequest) {
        guard request == nil else { return }
        reset()
        request = newRequest
        startDate = Date()
        if usesGPS { startLocation() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ticker = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                tick += 1
                self.everySecond()
                if tick % 5 == 0 { self.sendProgress() }
                if tick % 30 == 0 { self.saveCheckpoint() }
            }
        }
        sendProgress()
        saveCheckpoint()
    }

    func pause(auto: Bool = false) {
        guard isActive, !isPaused else { return }
        pausedAt = Date()
        isPaused = true
        autoPaused = auto
        showBanner(auto ? "Auto-paused" : "Paused")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sendProgress()
    }

    func resume() {
        guard isActive, isPaused, let pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        isPaused = false
        autoPaused = false
        slowSince = nil
        showBanner("Resumed")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        sendProgress()
    }

    /// Stops recording; the session waits in `pendingFinish` for your rating.
    func finish() {
        guard let request, let startDate else { return }
        let moving = elapsed
        let end = pausedAt ?? Date()
        stopSensors()
        var session = CardioSession(id: request.id, kind: request.kind, indoor: request.indoor, startedAt: startDate, endedAt: end,
                                    activeSeconds: moving, distanceKm: request.kind == .run && !request.indoor ? distanceKm : nil,
                                    splits: splits, route: route.count >= 2 ? route : nil, goal: request.goal,
                                    basketballType: request.basketballType)
        session.recordedOn = "phone"
        finishedLocations = locations
        pendingFinish = session
        clearState()
    }

    func discard() {
        stopSensors()
        clearState()
        pendingFinish = nil
        finishedLocations = []
    }

    private func reset() {
        distanceKm = 0
        currentPace = nil
        splits = []
        banner = nil
        isPaused = false
        autoPaused = false
        gpsWeak = false
        lastLocation = nil
        lastGoodFix = nil
        route = []
        locations = []
        pausedTotal = 0
        pausedAt = nil
        slowSince = nil
        paceSamples = []
        lastSplitElapsed = 0
        goalReached = false
        lastGoalAlert = .distantPast
    }

    private func stopSensors() {
        ticker?.cancel()
        ticker = nil
        locationManager?.stopUpdatingLocation()
        locationManager = nil
    }

    private func clearState() {
        request = nil
        startDate = nil
        isPaused = false
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
    }

    // MARK: GPS

    private func startLocation() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: locationDenied = true
        default: break
        }
        manager.startUpdatingLocation()
        locationManager = manager
    }

    fileprivate func received(_ newLocations: [CLLocation]) {
        guard isActive, usesGPS else { return }
        for location in newLocations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 25 {
            lastGoodFix = location.timestamp
            if !isPaused, let last = lastLocation {
                let meters = location.distance(from: last)
                let seconds = location.timestamp.timeIntervalSince(last.timestamp)
                // Ignore GPS jumps (faster than 12 m/s is not running).
                if seconds > 0, meters / seconds < 12 {
                    distanceKm += meters / 1000
                }
            }
            lastLocation = location
            if !isPaused {
                locations.append(location)
                if route.last.map({ location.timestamp.timeIntervalSince($0.t) >= 4 }) ?? true {
                    route.append(RoutePoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude, t: location.timestamp))
                }
            }
            // Auto-pause: stopped (< 0.6 m/s) for 10 s; resume when moving again (> 1.4 m/s).
            if location.speed >= 0 {
                if !isPaused, location.speed < 0.6 {
                    if let since = slowSince {
                        if Date().timeIntervalSince(since) >= 10 { pause(auto: true) }
                    } else {
                        slowSince = Date()
                    }
                } else if location.speed >= 0.6 {
                    slowSince = nil
                    if isPaused, autoPaused, location.speed > 1.4 { resume() }
                }
            }
        }
        updatePaceAndSplits()
    }

    private func updatePaceAndSplits() {
        let time = elapsed
        paceSamples.append((time, distanceKm))
        paceSamples.removeAll { time - $0.time > 60 }
        if let first = paceSamples.first, time - first.time >= 20, distanceKm - first.km > 0.02 {
            currentPace = (time - first.time) / (distanceKm - first.km)
        }
        let completed = Int(distanceKm)
        if completed > splits.count {
            let split = time - lastSplitElapsed
            lastSplitElapsed = time
            splits.append(split)
            showBanner("Km \(completed) · \(CardioFormat.pace(split))")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: Every second

    private func everySecond() {
        objectWillChange.send()
        if usesGPS {
            gpsWeak = !isPaused && (lastGoodFix.map { Date().timeIntervalSince($0) > 20 } ?? (elapsed > 20))
        }
        guard let goal = request?.goal, !isPaused else { return }
        switch goal.kind {
        case .open:
            break
        case .distance:
            if let target = goal.distanceKm, distanceKm >= target, !goalReached {
                goalReached = true
                showBanner("Goal reached: \(GFFormat.km(target)) km")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .time:
            if let minutes = goal.minutes, elapsed >= minutes * 60, !goalReached {
                goalReached = true
                showBanner("Goal reached: \(Int(minutes)) min")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .pace:
            guard let target = goal.paceSeconds, let pace = currentPace, elapsed > 90,
                  Date().timeIntervalSince(lastGoalAlert) > 60 else { return }
            if pace > target + 15 {
                lastGoalAlert = Date()
                showBanner("Speed up — \(CardioFormat.pace(pace)) vs \(CardioFormat.pace(target))")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            } else if pace < target - 15 {
                lastGoalAlert = Date()
                showBanner("Ease off — \(CardioFormat.pace(pace)) vs \(CardioFormat.pace(target))")
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    private func sendProgress() {
        guard let request, let startDate else { return }
        onProgress?(ActivityProgress(id: request.id, kind: request.kind, title: request.title, startedAt: startDate,
                                     elapsed: elapsed, distanceKm: distanceKm, paceSeconds: currentPace ?? averagePace,
                                     heartRate: 0, isPaused: isPaused))
    }

    private func showBanner(_ text: String) {
        banner = text
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    // MARK: If the app is closed mid-session

    private struct Checkpoint: Codable {
        var request: ActivityRequest
        var startDate: Date
        var elapsed: Double
        var distanceKm: Double
        var splits: [Double]
        var savedAt: Date
    }

    private func saveCheckpoint() {
        guard let request, let startDate else { return }
        let checkpoint = Checkpoint(request: request, startDate: startDate, elapsed: elapsed, distanceKm: distanceKm,
                                    splits: splits, savedAt: Date())
        if let data = try? JSONEncoder().encode(checkpoint) {
            UserDefaults.standard.set(data, forKey: Self.checkpointKey)
        }
    }

    /// A session cut short by the app closing (up to its last checkpoint): offered for saving.
    func recoverCheckpoint() {
        guard request == nil, pendingFinish == nil,
              let data = UserDefaults.standard.data(forKey: Self.checkpointKey),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else { return }
        UserDefaults.standard.removeObject(forKey: Self.checkpointKey)
        guard Date().timeIntervalSince(checkpoint.savedAt) < 12 * 3600, checkpoint.elapsed >= 60 else { return }
        let request = checkpoint.request
        var session = CardioSession(id: request.id, kind: request.kind, indoor: request.indoor, startedAt: checkpoint.startDate,
                                    endedAt: checkpoint.savedAt, activeSeconds: checkpoint.elapsed,
                                    distanceKm: request.kind == .run && !request.indoor ? checkpoint.distanceKm : nil,
                                    splits: checkpoint.splits, goal: request.goal, basketballType: request.basketballType)
        session.recordedOn = "phone"
        finishedLocations = []
        pendingFinish = session
    }
}

extension PhoneActivityRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in self?.received(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.locationDenied = status == .denied || status == .restricted
        }
    }
}
