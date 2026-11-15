#if os(iOS)
import ActivityKit
import Foundation

/// Shared by the iPhone app (which starts/updates the Live Activity) and the widget extension (which draws it).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setNumber: Int
        var totalSets: Int
        var isCardio: Bool
        var isResting: Bool
        var restStart: Date?
        var restEnd: Date?
        var completedSets: Int
        var plannedSets: Int
        var lastSetText: String?
        var supersetLabel: String?
        var isFinished: Bool
        /// "Hard Truth" coach line (nil for other coach styles).
        var motivation: String?
        /// MK24: the set the Done button logs ("80 kg × 10"); nil hides the button.
        var nextSetText: String? = nil
        /// MK24: when the session should be over at today's pace.
        var finishAt: Date? = nil
    }

    var workoutID: UUID
    var routineName: String
    var startedAt: Date
}

import AppIntents

/// MK24: the Lock Screen / Dynamic Island "Done" button. A LiveActivityIntent, so iOS runs it inside the app,
/// which logs the planned set exactly as the big Complete button does with empty boxes.
struct CompleteSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Log the set"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutWidgetControl.completeSet()
        return .result()
    }
}

/// Set by the app at launch; does nothing in the widget extension.
@MainActor
enum WorkoutWidgetControl {
    static var handler: (() -> Void)?
    static func completeSet() { handler?() }
}
#endif
