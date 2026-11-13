import Foundation

/// One study block on the calendar. Shared by the app and the widget.
struct Block: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var start: Date
    /// Length of the window, e.g. 1:00–3:30 = 150.
    var minutes: Int
    var fullTask = ""
    var minTask = ""
    var outcome: Outcome? = nil
    /// Uninterrupted focus to do somewhere inside the window. Optional so blocks saved before MK1.3 still load.
    var focusMinutes: Int? = nil
    /// MK2: minutes the timer actually ran before the block was ticked off. nil = ticked off by hand.
    var focusedMinutes: Int? = nil

    enum Outcome: String, Codable { case full, minimum }

    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
    /// What the timer and Focus run for.
    var focus: Int { min(focusMinutes ?? minutes, minutes) }
    /// Latest start that still fits the focus target in the window.
    var startBy: Date { end.addingTimeInterval(-Double(focus) * 60) }

    /// The window has closed and it was never ticked off.
    func isMissed(at now: Date) -> Bool { outcome == nil && end <= now }
    /// The window is open right now and it isn't ticked off yet.
    func isOpen(at now: Date) -> Bool { outcome == nil && start <= now && now < end }

    /// Minutes of focus this block counts for: what the timer measured, or the whole target for a full
    /// block ticked off by hand. A minimum ticked off by hand has no time to count.
    var creditedMinutes: Int {
        guard let outcome else { return 0 }
        return focusedMinutes ?? (outcome == .full ? focus : 0)
    }

    /// The same block on another day, not ticked off.
    func copied(byDays days: Int, calendar: Calendar = .current) -> Block {
        var copy = self
        copy.id = UUID()
        copy.start = calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86400)
        copy.outcome = nil
        copy.focusedMinutes = nil
        return copy
    }
}

/// 150 → "2h 30m", 120 → "2h", 45 → "45m".
func durationText(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h \(m)m"
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

/// The App Group the app and its widget share. Sideloading tools (Sideloadly, AltStore, SideStore) re-sign
/// the app with a renamed group (e.g. "group.com.jason.ductile.TEAMID"), so the name in the code doesn't
/// match and the widget can't see the app's blocks. This finds the group this install was really given:
/// the built-in name if it works, otherwise the one listed in the signing profile inside the bundle.
enum SharedGroup {
    static let preferred = "group.com.jason.ductile"

    /// nil = this install has no usable App Group at all.
    static let id: String? = {
        let listed = profileGroups()
        let ordered = listed.filter { $0.contains("com.jason.ductile") } + listed.filter { !$0.contains("com.jason.ductile") }
        return ([preferred] + ordered).first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    /// Whether the widget can see the app's blocks, in words.
    static var status: String {
        guard let id else { return "Not shared: the widget can't see your blocks in this install" }
        return id == preferred ? "Connected" : "Connected (renamed by the installer)"
    }

    /// App Groups in the signing profile (embedded.mobileprovision) of this bundle, and — from inside the
    /// widget extension — of the app that contains it.
    static func profileGroups() -> [String] {
        let bundle = Bundle.main.bundleURL
        var files = [bundle.appendingPathComponent("embedded.mobileprovision")]
        if bundle.pathExtension == "appex" {
            // The app's own profile first, so the widget lands on the same group the app picked.
            files.insert(bundle.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("embedded.mobileprovision"), at: 0)
        }
        var groups: [String] = []
        for file in files {
            // The profile is a signed blob with a plain XML property list inside it.
            guard let data = try? Data(contentsOf: file),
                  let start = data.range(of: Data("<?xml".utf8)),
                  let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
                  let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
                  let entitlements = plist["Entitlements"] as? [String: Any],
                  let listed = entitlements["com.apple.security.application-groups"] as? [String] else { continue }
            for group in listed where !groups.contains(group) { groups.append(group) }
        }
        return groups
    }
}

/// Saved in the App Group so the widget sees the same blocks as the app.
enum Store {
    /// The suite MK1 always wrote to. When the group isn't really shared it's a private file of the app.
    private static let legacy = UserDefaults(suiteName: SharedGroup.preferred) ?? .standard
    static let defaults: UserDefaults = SharedGroup.id.flatMap { UserDefaults(suiteName: $0) } ?? legacy

    /// App only, once: blocks MK1 saved under the built-in name (which the installer had renamed, so they
    /// never reached the widget) move into the group this install really has.
    static func migrateIfNeeded() {
        guard let id = SharedGroup.id, id != SharedGroup.preferred, !defaults.bool(forKey: "migrated") else { return }
        for key in ["blocks", "active"] where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: "migrated")
    }

    static var blocks: [Block] {
        // One block that won't decode (a future field change) no longer empties the whole calendar.
        get { (decode("blocks") as [Lossy<Block>]?)?.compactMap(\.value) ?? [] }
        set { encode(newValue, "blocks") }
    }

    static var active: ActiveTimer? {
        get { decode("active") }
        set { encode(newValue, "active") }
    }

    /// Settings (MK2). Both default to on.
    static var remind: Bool {
        get { defaults.object(forKey: "remind") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "remind") }
    }
    static var useFocus: Bool {
        get { defaults.object(forKey: "useFocus") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useFocus") }
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
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

// MARK: - Week summary and streak (MK2)

struct WeekStats: Equatable {
    var planned = 0
    var full = 0
    var minimum = 0
    var missed = 0
    var focusMinutes = 0
    var done: Int { full + minimum }
}

/// The week (by the calendar's own first weekday) that `day` falls in.
func weekStats(_ all: [Block], containing day: Date, now: Date, calendar: Calendar = .current) -> WeekStats {
    guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return WeekStats() }
    var stats = WeekStats()
    for block in all where week.start <= block.start && block.start < week.end {
        stats.planned += 1
        switch block.outcome {
        case .full?: stats.full += 1
        case .minimum?: stats.minimum += 1
        case nil: if block.isMissed(at: now) { stats.missed += 1 }
        }
        stats.focusMinutes += block.creditedMinutes
    }
    return stats
}

/// Days in a row, up to today, on which at least one block was ticked off. Days with nothing planned
/// don't break it, and neither does today while it's still open.
func streak(_ all: [Block], today: Date, calendar: Calendar = .current) -> Int {
    var count = 0
    var day = calendar.startOfDay(for: today)
    for step in 0..<366 {
        let blocks = dayBlocks(all, on: day, calendar: calendar)
        if blocks.contains(where: { $0.outcome != nil }) {
            count += 1
        } else if !blocks.isEmpty && step > 0 {
            break
        }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
        day = previous
    }
    return count
}

// MARK: - Reminders (MK2)

struct Reminder: Equatable, Sendable {
    var id: String
    var date: Date
    var title: String
    var body: String
}

/// Two nudges per unfinished block still ahead: when its window opens, and at the last moment the focus
/// target still fits. iOS keeps at most 64 pending per app, so only the soonest are planned.
func reminders(for blocks: [Block], now: Date, skipping active: UUID? = nil, limit: Int = 40) -> [Reminder] {
    var result: [Reminder] = []
    for block in blocks where block.outcome == nil && block.id != active {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        if block.start > now {
            result.append(Reminder(id: "remind-open-\(block.id.uuidString)", date: block.start,
                                   title: "\(block.title): window open",
                                   body: block.startBy > block.start
                                       ? "\(durationText(block.focus)) of focus. Start by \(time(block.startBy))."
                                       : "\(durationText(block.focus)) of focus, until \(time(block.end))."))
        }
        if block.startBy > now && block.startBy > block.start {
            result.append(Reminder(id: "remind-last-\(block.id.uuidString)", date: block.startBy,
                                   title: "\(block.title): start now",
                                   body: "Last moment to fit \(durationText(block.focus)) before \(time(block.end)). The minimum still counts."))
        }
    }
    return Array(result.sorted { $0.date < $1.date }.prefix(limit))
}

enum Links {
    /// Names of the two Shortcuts you make once in the Shortcuts app (see Focus setup in the app).
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
