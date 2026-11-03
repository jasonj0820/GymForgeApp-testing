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
    }

    var workoutID: UUID
    var routineName: String
    var startedAt: Date
}
#endif
