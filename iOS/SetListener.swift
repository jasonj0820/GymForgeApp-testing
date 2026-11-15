import AVFoundation
import Foundation
import Speech

/// MK24 (64): tap the mic, say "80 for 10", tap again (or wait). Recognition runs on the iPhone where it can.
@MainActor
final class SetListener: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-AU"))
    private var autoStop: Task<Void, Never>?

    func start(onTimeout: @escaping @MainActor () -> Void) async {
        guard !listening else { return }
        problem = nil
        heard = ""
        let speechOK = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else {
            problem = "Allow the microphone and speech recognition for Splitday in the iPhone's Settings → Apps → Splitday."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            problem = "Speech recognition isn't available right now."
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            problem = "Couldn't use the microphone."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["for", "kilos", "reps", "bodyweight"]
        self.request = request
        guard Self.installTap(engine.inputNode, request: request) else {
            problem = "No microphone found."
            cleanUp()
            return
        }
        engine.prepare()
        do { try engine.start() } catch {
            problem = "Couldn't start listening."
            cleanUp()
            return
        }
        listening = true
        task = Self.recognise(recognizer, request: request) { [weak self] text in
            Task { @MainActor in self?.heard = text }
        }
        autoStop = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled, self.listening { onTimeout() }
        }
    }

    /// Stops and returns what was heard (after a moment for the last word).
    func stop() async -> String {
        guard listening else { return heard }
        autoStop?.cancel()
        request?.endAudio()
        try? await Task.sleep(nanoseconds: 500_000_000)
        cleanUp()
        return heard
    }

    private func cleanUp() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        listening = false
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Off the main actor: the audio and recognition callbacks come in on their own threads.
    nonisolated private static func installTap(_ input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) -> Bool {
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        return true
    }

    nonisolated private static func recognise(_ recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, _ in
            if let text = result?.bestTranscription.formattedString { update(text) }
        }
    }
}
