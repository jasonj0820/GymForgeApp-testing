import Foundation

/// MK24: small pure helpers for "when do you usually…" (logic-checked in Tests/).
public enum UsualTime {
    /// Median of minutes-after-midnight values; nil when empty. Even counts take the later middle value.
    public static func median(_ minutes: [Int]) -> Int? {
        guard !minutes.isEmpty else { return nil }
        let sorted = minutes.sorted()
        return sorted[sorted.count / 2]
    }
}

/// MK24: calendar titles that mark a heavy week (busy weeks lower the goal).
public enum BusyWords {
    public static let words = ["exam", "exams", "test", "assignment", "assessment", "deadline", "due", "presentation",
                               "quiz", "midterm", "final", "finals", "report", "submission", "interview"]

    public static func isHeavy(_ title: String) -> Bool {
        let tokens = title.lowercased().split { !$0.isLetter }.map(String.init)
        return tokens.contains { words.contains($0) }
    }
}
