import Foundation
import UIKit

/// MK23: what this build is. The build number was shown nowhere before.
enum BuildInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    /// The name on the branch and in the README ("MK23"). Bump with each version.
    static let name = "MK24"
    static var summary: String { "\(name) · build \(build)" }
}

/// MK23: problems that used to go to a console nobody reads (a failed save, a backup that couldn't be
/// written). The last 40 are kept and shown in Settings → Diagnostics.
enum AppLog {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var area: String
        var message: String
    }

    static let changed = Notification.Name("applog.changed")
    private static let key = "applog.entries"
    private static let limit = 40

    static var entries: [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func error(_ area: String, _ message: String) {
        print("[\(area)] \(message)")
        var all = entries
        // The same problem repeating (a save failing on every change) is one line, not forty.
        if let last = all.last, last.area == area, last.message == message {
            all[all.count - 1].date = Date()
        } else {
            all.append(Entry(date: Date(), area: area, message: message))
        }
        if let data = try? JSONEncoder().encode(Array(all.suffix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: changed, object: nil) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// MK23: counts which screens you open, on this iPhone only (nothing is sent anywhere). It's there so we
/// can see what's used and what could be cut. Settings → Diagnostics shows it.
enum Usage {
    private static let key = "usage.counts"
    private static let sinceKey = "usage.since"

    static var counts: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    static var since: Date? { UserDefaults.standard.object(forKey: sinceKey) as? Date }

    static func opened(_ screen: String) {
        guard !Demo.isOn else { return }
        var all = counts
        all[screen, default: 0] += 1
        UserDefaults.standard.set(all, forKey: key)
        if since == nil { UserDefaults.standard.set(Date(), forKey: sinceKey) }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(Date(), forKey: sinceKey)
    }
}

/// MK23: writes the main data file off the main thread, and at most once per burst of changes.
/// Before this, every tick of a box encoded and rewrote the whole history on the main thread.
///
/// Nothing is left unwritten when it matters: the pending write is flushed straight away when the app
/// leaves the foreground, and anything saved while the app isn't on screen (a notification button, a
/// Watch message, a widget) is written immediately, as before.
final class SnapshotWriter {
    private let url: URL
    private let queue = DispatchQueue(label: "splitday.snapshot.writer", qos: .userInitiated)
    private var pending: AppSnapshot?
    private var scheduled = false
    /// The app is on screen. False at launch and in the background, when every write is immediate.
    private(set) var isActive = false
    /// Called on the main thread: nil after a good write, the reason after a failed one.
    var onResult: ((String?) -> Void)?

    init(url: URL) {
        self.url = url
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isActive = true
        }
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                     UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.isActive = false
                self?.flush()
            }
        }
    }

    /// Main thread only.
    func write(_ snapshot: AppSnapshot) {
        pending = snapshot
        guard isActive else {
            flush()
            return
        }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.drain() }
    }

    /// Writes whatever is waiting, and returns only once it's on disk.
    func flush() {
        guard let snapshot = pending else { return }
        pending = nil
        let result = queue.sync { Self.save(snapshot, to: url) }
        onResult?(result)
    }

    private func drain() {
        scheduled = false
        guard let snapshot = pending else { return }
        pending = nil
        let url = url
        queue.async { [weak self] in
            let result = Self.save(snapshot, to: url)
            DispatchQueue.main.async { self?.onResult?(result) }
        }
    }

    private static func save(_ snapshot: AppSnapshot, to url: URL) -> String? {
        do {
            try FileStore.shared.save(snapshot, to: url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
