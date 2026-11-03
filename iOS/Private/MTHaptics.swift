import CoreHaptics
import UIKit

/// A continuous, full-strength vibration (default 2 s) for when a PE timer reaches zero.
/// Works with the app open; when the phone is locked the silent notification's vibration is used instead.
enum MTHaptics {
    private static var engine: CHHapticEngine?

    /// A timer reached zero: strong vibration on the iPhone and a buzz on the Watch.
    static func timerUp(seconds: Double = 2) {
        longStrong(seconds: seconds)
        PhoneWatchBridge.current?.sendBuzz()
    }

    static func longStrong(seconds: Double = 2) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback(seconds: seconds)
            return
        }
        do {
            if engine == nil {
                let newEngine = try CHHapticEngine()
                newEngine.playsHapticsOnly = true
                newEngine.isAutoShutdownEnabled = true
                newEngine.resetHandler = { try? engine?.start() }
                engine = newEngine
            }
            try engine?.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0,
                duration: seconds
            )
            let player = try engine?.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback(seconds: seconds)
        }
    }

    /// Rapid heavy taps for devices without Core Haptics support.
    private static func fallback(seconds: Double) {
        Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            let taps = Int(seconds / 0.1)
            for _ in 0..<taps {
                generator.impactOccurred(intensity: 1.0)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }
}
