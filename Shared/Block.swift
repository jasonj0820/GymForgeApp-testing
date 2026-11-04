import Foundation

/// One study block on the calendar. Shared by the app and the widget.
struct Block: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var start: Date
    var minutes: Int
    var fullTask = ""
    var minTask = ""
    var outcome: Outcome? = nil

    enum Outcome: String, Codable { case full, minimum }

    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
}

/// The block whose timer is running right now.
struct ActiveTimer: Codable, Equatable, Hashable {
    var blockID: UUID
    var ends: Date
    /// Seconds left when paused; nil while running.
    var pausedLeft: TimeInterval? = nil

    var isPaused: Bool { pausedLeft != nil }

    func left(at now: Date = .now) -> TimeInterval { pausedLeft ?? max(0, ends.timeIntervalSince(now)) }

    /// Pausing freezes the time left; resuming pushes the end out by however long it was paused.
    func toggled(at now: Date = .now) -> ActiveTimer {
        var t = self
        if let left = pausedLeft {
            t.ends = now.addingTimeInterval(left)
            t.pausedLeft = nil
        } else {
            t.pausedLeft = left(at: now)
        }
        return t
    }
}

/// Saved in the App Group so the widget sees the same blocks as the app.
enum Store {
    static let group = "group.com.jason.ductile"
    static let defaults = UserDefaults(suiteName: group) ?? .standard

    // shortcut: if a future version renames a Block field, old data won't decode and reads as empty; add a migration then.
    static var blocks: [Block] {
        get { decode("blocks") ?? [] }
        set { encode(newValue, "blocks") }
    }

    static var active: ActiveTimer? {
        get { decode("active") }
        set { encode(newValue, "active") }
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// The blocks on one calendar day, earliest first.
func dayBlocks(_ all: [Block], on day: Date, calendar: Calendar = .current) -> [Block] {
    all.filter { calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start }
}

enum Links {
    /// Names of the two Shortcuts you make once in the Shortcuts app (see README).
    static let focusOn = "Ductile Focus On"
    static let focusOff = "Ductile Focus Off"

    static func start(_ id: UUID) -> URL { URL(string: "ductile://start?id=\(id.uuidString)")! }

    /// Runs a Shortcut with `text` as its input, then jumps back to Ductile.
    static func runShortcut(_ name: String, text: String = "") -> URL {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "x-success", value: "ductile://"),
        ]
        return c.url!
    }
}
