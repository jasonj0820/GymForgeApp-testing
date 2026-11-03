import AVFoundation
import Foundation

/// What plays on the iPhone when rest ends.
enum RestAlertSound: String, CaseIterable, Identifiable {
    case ding
    /// Three-note chime, then an Australian voice: "The next exercise is Lat Pulldown. 8 reps."
    case train
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ding: return "Ding"
        case .train: return "Train announcement"
        case .off: return "Vibrate only"
        }
    }

    /// Sound file in the app bundle (also used for the Lock Screen notification).
    var fileName: String? {
        switch self {
        case .ding: return "ding.wav"
        case .train: return "train_chime.wav"
        case .off: return nil
        }
    }
}

/// The "rest finished" sound. Plays over your music (ducks it briefly) and works with the
/// silent switch on, because at the gym you want to hear it.
@MainActor
enum RestSound {
    nonisolated static let modeKey = "rest.sound"
    private static var player: AVAudioPlayer?
    private static let speech = AVSpeechSynthesizer()
    private static let speechDelegate = SpeechDelegate()
    private static var releaseWork: DispatchWorkItem?

    /// The chime or the voice is still playing.
    static var isSounding: Bool { (player?.isPlaying ?? false) || speech.isSpeaking }

    /// Train announcement (default), ding or off. Older versions only had the "rest.ding" on/off switch:
    /// if that was turned off, it stays off.
    nonisolated static var mode: RestAlertSound {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: modeKey), let mode = RestAlertSound(rawValue: raw) { return mode }
        return (defaults.object(forKey: "rest.ding") as? Bool ?? true) ? .train : .off
    }

    nonisolated static var isEnabledNonisolated: Bool { mode != .off }

    /// Plays the chosen sound. `announcement` is what the train voice says (ignored for the ding).
    static func play(announcement: String? = nil, mode: RestAlertSound = RestSound.mode) {
        guard let file = mode.fileName else { return }
        let name = (file as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        speech.stopSpeaking(at: .immediate)
        // A motivational speech is playing: keep its audio session, just turn it down for the chime / voice.
        let speechPlaying = SpeechPlayer.shared.isPlaying
        if speechPlaying {
            SpeechPlayer.shared.duck(for: mode == .train ? 7 : 2)
        } else {
            activateSession(spoken: mode == .train)
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 1
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            print("Rest sound failed: \(error)")
        }

        if mode == .train, let announcement, !announcement.isEmpty {
            let utterance = AVSpeechUtterance(string: announcement)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-AU") ?? AVSpeechSynthesisVoice(language: "en-GB")
            utterance.rate = 0.46
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1
            // Speak once the chime has rung: "du-du-du … The next exercise is …"
            utterance.preUtteranceDelay = 1.15
            speech.delegate = speechDelegate
            speech.speak(utterance)
            releaseSession(after: 12)   // safety net; normally released when the voice finishes
        } else {
            releaseSession(after: 2.1)
        }
    }

    /// "The next exercise is Lat Pulldown. 8 reps." (or the next set of the same exercise).
    static func announcement(for state: ActiveWorkoutState, previousExerciseID: UUID?, reps: Int?) -> String? {
        guard let item = state.currentItem, !state.isComplete else { return nil }
        let exercise = item.exercise
        let target: String
        if exercise.isCardio {
            target = "\(exercise.cardioMinutes) minutes."
        } else if let reps, reps > 0 {
            target = "\(reps) rep\(reps == 1 ? "" : "s")."
        } else {
            target = "\(exercise.repMin) to \(exercise.repMax) reps."
        }
        let setNumber = state.sets(for: item).count + 1
        if previousExerciseID == exercise.id, !exercise.isCardio {
            return "The next set is \(exercise.name), set \(setNumber) of \(exercise.defaultSets). \(target)"
        }
        return "The next exercise is \(exercise.name). \(target)"
    }

    private static func activateSession(spoken: Bool) {
        releaseWork?.cancel()
        let session = AVAudioSession.sharedInstance()
        if spoken {
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } else {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        }
        try? session.setActive(true)
    }

    /// Gives the music its volume back.
    fileprivate static func releaseSession(after seconds: Double) {
        releaseWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                // Never cut off a motivational speech that's playing.
                guard !SpeechPlayer.shared.isPlaying else { return }
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in
                SpeechPlayer.shared.unduck()
                RestSound.releaseSession(after: 0.3)
            }
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
            Task { @MainActor in
                SpeechPlayer.shared.unduck()
                RestSound.releaseSession(after: 0.3)
            }
        }
    }
}
