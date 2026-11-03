import Foundation
import WatchConnectivity
import WidgetKit

final class WatchBridge: NSObject, WCSessionDelegate {
    /// Lets Dayfold reach the iPhone through this one connection.
    static weak var current: WatchBridge?
    var onSnapshot: ((AppSnapshot) -> Void)?
    var onStartWorkout: ((ActiveWorkoutState) -> Void)?
    var onActiveState: ((ActiveWorkoutState) -> Void)?
    var onCancelWorkout: ((UUID) -> Void)?
    var onActivated: (() -> Void)?
    var onDraft: ((WorkoutDraft) -> Void)?
    var onReachabilityChange: ((Bool) -> Void)?
    /// Any data arrived from the iPhone (for the "last synced" readout).
    var onReceived: (() -> Void)?
    var onBuzz: (() -> Void)?
    var onStartActivity: ((ActivityRequest) -> Void)?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        Self.current = self
        session?.delegate = self
        session?.activate()
    }

    /// reliable = queue it for later if the iPhone can't be reached right now (use for logged sets).
    func sendActiveState(_ state: ActiveWorkoutState, reliable: Bool = false) {
        send(.activeWorkoutUpdate, value: state, reliable: reliable)
    }

    func requestActiveWorkout() {
        send(.requestActiveWorkout, value: SyncPing(), reliable: false)
    }

    /// Always queued with transferUserInfo: the system delivers it even if the iPhone is in a locker
    /// or the Watch app is terminated before the phone comes back in range.
    func sendCompletedWorkout(_ log: WorkoutLog) {
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try SyncCodec.pack(.completedWorkout, log)
            if data.count < SyncCodec.inlineLimit {
                session.transferUserInfo(["z": data])
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-\(log.id.uuidString).bin")
                try data.write(to: url)
                session.transferFile(url, metadata: ["kind": "workout"])
            }
        } catch {
            print("Could not encode workout: \(error)")
        }
    }

    /// Live numbers for the iPhone's Lock Screen (dropped if the iPhone isn't reachable).
    func sendActivityProgress(_ progress: ActivityProgress) {
        send(.activityProgress, value: progress, reliable: false)
    }

    /// A finished run / basketball session — always delivered (queued or as a file for long GPS routes).
    func sendCompletedActivity(_ cardio: CardioSession) {
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try SyncCodec.pack(.completedActivity, cardio)
            if data.count < SyncCodec.inlineLimit {
                session.transferUserInfo(["z": data])
            } else {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(cardio.id.uuidString).bin")
                try data.write(to: url)
                session.transferFile(url, metadata: ["kind": "activity"])
            }
        } catch {
            print("Could not encode activity: \(error)")
        }
    }

    func sendCancel(_ workoutID: UUID) {
        send(.cancelWorkout, value: WorkoutCancel(workoutID: workoutID), reliable: true)
    }

    func requestSnapshot() {
        send(.requestSnapshot, value: SyncPing(), reliable: false)
    }

    func sendDayfold(_ snapshot: DayfoldSnapshot, reliable: Bool) {
        send(.dayfold, value: snapshot, reliable: reliable)
    }

    private func send<T: Codable>(_ type: SyncMessageType, value: T, reliable: Bool) {
        guard let session, session.activationState == .activated else { return }
        do {
            let data = try SyncCodec.pack(type, value)
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil) { error in
                    print("Watch->Phone send failed: \(error)")
                    if reliable { session.transferUserInfo(["z": data]) }
                }
            } else if reliable {
                session.transferUserInfo(["z": data])
            }
        } catch {
            print("Watch message encode failed: \(error)")
        }
    }

    private func handle(_ data: Data) {
        do {
            let envelope = try SyncCodec.unpack(data)
            DispatchQueue.main.async { [weak self] in self?.onReceived?() }
            switch envelope.type {
            case .snapshot:
                let snapshot = try envelope.decode(AppSnapshot.self)
                DispatchQueue.main.async { [weak self] in self?.onSnapshot?(snapshot) }
            case .startWorkout:
                let state = try envelope.decode(ActiveWorkoutState.self)
                DispatchQueue.main.async { [weak self] in self?.onStartWorkout?(state) }
            case .activeWorkoutUpdate:
                let state = try envelope.decode(ActiveWorkoutState.self)
                DispatchQueue.main.async { [weak self] in self?.onActiveState?(state) }
            case .cancelWorkout:
                let cancel = try envelope.decode(WorkoutCancel.self)
                DispatchQueue.main.async { [weak self] in self?.onCancelWorkout?(cancel.workoutID) }
            case .draftUpdate:
                let draft = try envelope.decode(WorkoutDraft.self)
                DispatchQueue.main.async { [weak self] in self?.onDraft?(draft) }
            case .buzz:
                DispatchQueue.main.async { [weak self] in self?.onBuzz?() }
            case .startActivity:
                let request = try envelope.decode(ActivityRequest.self)
                DispatchQueue.main.async { [weak self] in self?.onStartActivity?(request) }
            case .dayfold:
                let snapshot = try envelope.decode(DayfoldSnapshot.self)
                DispatchQueue.main.async { NotificationCenter.default.post(name: .dayfoldReceived, object: snapshot) }
            case .completedWorkout, .requestSnapshot, .requestActiveWorkout, .ping, .activityProgress, .completedActivity:
                break
            }
        } catch {
            print("Could not decode phone payload: \(error)")
        }
    }

    private func payload(_ dictionary: [String: Any]) -> Data? {
        (dictionary["z"] as? Data) ?? (dictionary["envelope"] as? Data)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = payload(applicationContext) { handle(data) }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        handle(messageData)
    }

    /// Answers the iPhone's connection test.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        replyHandler(Data())
        handle(messageData)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let cluck = userInfo["cluck"] as? Data {
            // Sergeant Cluck for the watch face: save for the complication and refresh it.
            if let snapshot = try? JSONDecoder().decode(CluckSnapshot.self, from: cluck) {
                CluckStore.save(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        if let data = payload(userInfo) { handle(data) }
    }

    /// Large snapshots arrive as a file. It must be read before this method returns.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        if let data = try? Data(contentsOf: file.fileURL) { handle(data) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error { print("Workout file transfer failed: \(error)") }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("WCSession activation error: \(error)") }
        guard activationState == .activated else { return }
        // Apply whatever the iPhone sent while this app wasn't running.
        if let data = payload(session.receivedApplicationContext) { handle(data) }
        let reachable = session.isReachable
        DispatchQueue.main.async { [weak self] in
            self?.onActivated?()
            self?.onReachabilityChange?(reachable)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { [weak self] in self?.onReachabilityChange?(reachable) }
    }
}
