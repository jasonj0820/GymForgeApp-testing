import Foundation
import Combine
import WatchConnectivity

final class PhoneWatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    /// Lets other parts of the app (e.g. timers) reach the Watch.
    static weak var current: PhoneWatchBridge?

    var onCompletedWorkout: ((WorkoutLog) -> Void)?
    var onActiveWorkoutUpdate: ((ActiveWorkoutState) -> Void)?
    var onCancelWorkout: ((UUID) -> Void)?
    /// Called when the Watch needs routines/history: activation, Watch app installed, Watch asked for it.
    var onNeedsSnapshot: (() -> Void)?
    /// Watch asked for the workout in progress, or just became reachable.
    var onNeedsActiveWorkout: (() -> Void)?
    var onActivityProgress: ((ActivityProgress) -> Void)?
    var onCompletedActivity: ((CardioSession) -> Void)?

    // Diagnostics shown in Settings → Apple Watch.
    @Published private(set) var statusText = "Connecting to Apple Watch…"
    @Published private(set) var lastSnapshotSent: Date?
    @Published private(set) var lastSnapshotBytes: Int?
    @Published private(set) var lastReceived: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var pingResult: String?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    var isWatchReady: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    var isReachable: Bool { isWatchReady && (session?.isReachable ?? false) }

    private func refreshStatus() {
        let text: String
        if let session {
            if session.activationState != .activated {
                text = "Connecting to Apple Watch…"
            } else if !session.isPaired {
                text = "No Apple Watch paired."
            } else if !session.isWatchAppInstalled {
                text = "iPhone can't see GymForge on your Watch. Install it from the Watch app on iPhone (My Watch → GymForge), then reopen both apps."
            } else {
                text = session.isReachable ? "Connected — GymForge is open on your Watch." : "Paired — open GymForge on the Watch for live sync."
            }
        } else {
            text = "Apple Watch isn't supported on this device."
        }
        DispatchQueue.main.async { self.statusText = text }
    }

    private func report(error: Error?, context: String) {
        guard let error else { return }
        print("\(context): \(error)")
        DispatchQueue.main.async { self.lastError = "\(context): \(error.localizedDescription)" }
    }

    func activate() {
        guard let session else {
            refreshStatus()
            return
        }
        session.delegate = self
        session.activate()
    }

    /// Routines + recent history. Small payloads go in the application context (latest wins);
    /// big ones go as a file transfer, which has no size limit.
    func sync(snapshot: AppSnapshot) {
        refreshStatus()
        guard let session, isWatchReady else { return }
        do {
            let data = try SyncCodec.pack(.snapshot, snapshot)
            if data.count < SyncCodec.inlineLimit {
                try session.updateApplicationContext(["z": data, "sentAt": Date().timeIntervalSince1970])
            } else {
                for transfer in session.outstandingFileTransfers where transfer.file.metadata?["kind"] as? String == "snapshot" {
                    transfer.cancel()
                }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).bin")
                try data.write(to: url)
                session.transferFile(url, metadata: ["kind": "snapshot"])
            }
            DispatchQueue.main.async {
                self.lastSnapshotSent = .now
                self.lastSnapshotBytes = data.count
                self.lastError = nil
            }
        } catch {
            report(error: error, context: "Sending routines failed")
        }
    }

    /// Round trip to the Watch app to prove the connection works.
    func ping() {
        refreshStatus()
        guard let session, isWatchReady else {
            pingResult = statusText
            return
        }
        guard session.isReachable else {
            pingResult = "Watch not reachable — open GymForge on the Watch and keep it awake, then test again."
            return
        }
        pingResult = "Testing…"
        let started = Date()
        do {
            let data = try SyncCodec.pack(.ping, SyncPing())
            session.sendMessageData(data, replyHandler: { _ in
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                DispatchQueue.main.async { self.pingResult = "Working — Watch replied in \(ms) ms." }
            }, errorHandler: { error in
                DispatchQueue.main.async { self.pingResult = "Failed: \(error.localizedDescription)" }
            })
        } catch {
            pingResult = "Failed: \(error.localizedDescription)"
        }
    }

    /// Makes the Watch vibrate (only works while GymForge is open on the Watch; when the iPhone is
    /// locked, iOS forwards the timer notification to the Watch instead). Sends no details.
    func sendBuzz() {
        guard let session, isReachable, let data = try? SyncCodec.pack(.buzz, SyncPing()) else { return }
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    private var lastCluckSent: CluckSnapshot?

    /// Sergeant Cluck for the Watch face complication. Uses the complication budget when his
    /// complication is on the watch face, otherwise a normal queued transfer.
    func sendCluck(_ snapshot: CluckSnapshot) {
        var comparable = snapshot
        comparable.updatedAt = .distantPast
        guard comparable != lastCluckSent,
              let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        lastCluckSent = comparable
        let info: [String: Any] = ["cluck": data]
        if session.isComplicationEnabled && session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(info)
        } else {
            session.transferUserInfo(info)
        }
    }

    func sendStartWorkout(_ state: ActiveWorkoutState) {
        send(.startWorkout, value: state, reliable: true)
    }

    func sendActiveState(_ state: ActiveWorkoutState, reliable: Bool) {
        send(.activeWorkoutUpdate, value: state, reliable: reliable)
    }

    /// Start a run / basketball session on the Watch.
    func sendStartActivity(_ request: ActivityRequest) {
        send(.startActivity, value: request, reliable: true)
    }

    func sendDraft(_ draft: WorkoutDraft) {
        send(.draftUpdate, value: draft, reliable: false)
    }

    func sendCancel(_ workoutID: UUID) {
        send(.cancelWorkout, value: WorkoutCancel(workoutID: workoutID), reliable: true)
    }

    func sendDayfold(_ snapshot: DayfoldSnapshot, reliable: Bool) {
        send(.dayfold, value: snapshot, reliable: reliable)
    }

    /// reliable = queue with transferUserInfo when the Watch can't be reached right now.
    private func send<T: Codable>(_ type: SyncMessageType, value: T, reliable: Bool) {
        guard let session, isWatchReady else { return }
        do {
            let data = try SyncCodec.pack(type, value)
            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil) { [weak self] error in
                    self?.report(error: error, context: "Live message failed")
                    if reliable { session.transferUserInfo(["z": data]) }
                }
            } else if reliable {
                session.transferUserInfo(["z": data])
            }
        } catch {
            report(error: error, context: "Encoding message failed")
        }
    }

    private func handle(_ data: Data) {
        do {
            let envelope = try SyncCodec.unpack(data)
            DispatchQueue.main.async { self.lastReceived = .now }
            switch envelope.type {
            case .completedWorkout:
                let workout = try envelope.decode(WorkoutLog.self)
                DispatchQueue.main.async { [weak self] in self?.onCompletedWorkout?(workout) }
            case .activeWorkoutUpdate:
                let state = try envelope.decode(ActiveWorkoutState.self)
                DispatchQueue.main.async { [weak self] in self?.onActiveWorkoutUpdate?(state) }
            case .cancelWorkout:
                let cancel = try envelope.decode(WorkoutCancel.self)
                DispatchQueue.main.async { [weak self] in self?.onCancelWorkout?(cancel.workoutID) }
            case .requestSnapshot:
                DispatchQueue.main.async { [weak self] in self?.onNeedsSnapshot?() }
            case .requestActiveWorkout:
                DispatchQueue.main.async { [weak self] in self?.onNeedsActiveWorkout?() }
            case .activityProgress:
                let progress = try envelope.decode(ActivityProgress.self)
                DispatchQueue.main.async { [weak self] in self?.onActivityProgress?(progress) }
            case .completedActivity:
                let session = try envelope.decode(CardioSession.self)
                DispatchQueue.main.async { [weak self] in self?.onCompletedActivity?(session) }
            case .dayfold:
                let snapshot = try envelope.decode(DayfoldSnapshot.self)
                DispatchQueue.main.async { NotificationCenter.default.post(name: .dayfoldReceived, object: snapshot) }
            case .snapshot, .startWorkout, .draftUpdate, .ping, .buzz, .startActivity:
                break
            }
        } catch {
            report(error: error, context: "Couldn't read Watch data")
        }
    }

    private func payload(_ dictionary: [String: Any]) -> Data? {
        (dictionary["z"] as? Data) ?? (dictionary["envelope"] as? Data)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        handle(messageData)
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        replyHandler(Data())
        handle(messageData)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = payload(userInfo) { handle(data) }
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        if let data = try? Data(contentsOf: file.fileURL) { handle(data) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        report(error: error, context: "Sending routines (file) failed")
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        report(error: error, context: "Queued message failed")
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        report(error: error, context: "Watch connection failed")
        refreshStatus()
        if activationState == .activated {
            DispatchQueue.main.async { [weak self] in self?.onNeedsSnapshot?() }
        }
    }

    /// Fires when the Watch app gets installed or the paired Watch changes.
    func sessionWatchStateDidChange(_ session: WCSession) {
        refreshStatus()
        DispatchQueue.main.async { [weak self] in self?.onNeedsSnapshot?() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        refreshStatus()
        guard session.isReachable else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onNeedsActiveWorkout?()
            self?.onNeedsSnapshot?()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
