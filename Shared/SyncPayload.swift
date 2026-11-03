import Foundation

public enum SyncMessageType: String, Codable {
    case snapshot
    case startWorkout
    case activeWorkoutUpdate
    case completedWorkout
    case cancelWorkout
    case requestSnapshot
    case draftUpdate
    /// Watch → iPhone: "send me the workout in progress" (e.g. right after the iPhone launched the Watch app).
    case requestActiveWorkout
    /// Connection test (answered immediately with a reply).
    case ping
    /// iPhone → Watch: "a timer just ended, vibrate". Carries no details.
    case buzz
    /// iPhone → Watch: start a run / basketball session.
    case startActivity
    /// Watch → iPhone: live numbers for the Lock Screen while running.
    case activityProgress
    /// Watch → iPhone: a finished run / basketball session.
    case completedActivity
    /// Either direction: Dayfold's routines and check-offs (merged per occurrence on arrival).
    case dayfold
}

/// Compact encoding for WatchConnectivity: JSON envelope compressed with LZFSE.
/// Application context and messages are limited to ~64 KB, which a full history easily exceeds.
public enum SyncCodec {
    public static func pack<T: Codable>(_ type: SyncMessageType, _ value: T) throws -> Data {
        let json = try JSONEncoder.gymForge.encode(SyncEnvelope(type: type, value: value))
        return try (json as NSData).compressed(using: .lzfse) as Data
    }

    public static func unpack(_ data: Data) throws -> SyncEnvelope {
        if let envelope = try? JSONDecoder.gymForge.decode(SyncEnvelope.self, from: data) {
            return envelope // older, uncompressed format
        }
        let json = try (data as NSData).decompressed(using: .lzfse) as Data
        return try JSONDecoder.gymForge.decode(SyncEnvelope.self, from: json)
    }

    /// Safe size for applicationContext / sendMessage payloads.
    public static let inlineLimit = 60_000
}

public struct SyncEnvelope: Codable {
    public var type: SyncMessageType
    public var payload: Data

    public init<T: Codable>(type: SyncMessageType, value: T) throws {
        self.type = type
        self.payload = try JSONEncoder.gymForge.encode(value)
    }

    public func decode<T: Codable>(_ type: T.Type) throws -> T {
        try JSONDecoder.gymForge.decode(T.self, from: payload)
    }
}

public struct WorkoutCancel: Codable {
    public var workoutID: UUID
    public init(workoutID: UUID) { self.workoutID = workoutID }
}

public struct SyncPing: Codable {
    public var sentAt: Date
    public init(sentAt: Date = .now) { self.sentAt = sentAt }
}

/// Numbers typed on the iPhone for the upcoming set, mirrored live to the Watch.
public struct WorkoutDraft: Codable, Equatable {
    public var workoutID: UUID
    public var exerciseID: UUID
    public var setNumber: Int
    public var weightKg: Double?
    public var reps: Int?
    public var durationSeconds: Double?
    public var distanceKm: Double?

    public init(
        workoutID: UUID,
        exerciseID: UUID,
        setNumber: Int,
        weightKg: Double?,
        reps: Int?,
        durationSeconds: Double? = nil,
        distanceKm: Double? = nil
    ) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceKm = distanceKm
    }

    /// True if this draft belongs to the set the workout is currently on.
    public func matches(_ state: ActiveWorkoutState) -> Bool {
        guard let item = state.currentItem else { return false }
        return workoutID == state.workoutID && exerciseID == item.exercise.id && setNumber == state.sets(for: item).count + 1
    }

    public var isCompleteStrength: Bool { weightKg != nil && reps != nil }
    public var isCompleteCardio: Bool { (durationSeconds ?? 0) > 0 }
}
