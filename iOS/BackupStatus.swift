import Foundation

/// MK23: a copy of the data file kept on the iPhone the first time each new build opens, before the new
/// build has read or changed anything. If an update ever damages your history, the copy from before it
/// is in Settings → Data and devices → Safety copies. The newest 5 are kept.
///
/// These live inside the app, so they don't survive deleting it. They're a seat belt for updates, not a
/// replacement for the Files backup.
enum SafetyCopy {
    struct Item: Identifiable {
        let url: URL
        let date: Date
        let build: String
        var id: URL { url }
    }

    private static let buildKey = "safetycopy.lastBuild"
    private static let keep = 5
    /// True when this launch is the first of a new build (used to run the full backup too).
    private(set) static var newBuildThisLaunch = false

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafetyCopies", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var all: [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> Item? in
            // "before-build-<n>-<unix time>.json"
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: "-")
            guard parts.count >= 4, let stamp = TimeInterval(parts[parts.count - 1]) else { return nil }
            return Item(url: url, date: Date(timeIntervalSince1970: stamp), build: parts[parts.count - 2])
        }
        .sorted { $0.date > $1.date }
    }

    /// Call before the data file is read.
    static func makeIfNewBuild(from dataFile: URL) {
        guard !Demo.isOn else { return }
        let build = BuildInfo.build
        let last = UserDefaults.standard.string(forKey: buildKey)
        guard last != build else { return }
        UserDefaults.standard.set(build, forKey: buildKey)
        newBuildThisLaunch = last != nil
        guard FileManager.default.fileExists(atPath: dataFile.path) else { return }
        let name = "before-build-\(build)-\(Int(Date().timeIntervalSince1970)).json"
        do {
            try FileManager.default.copyItem(at: dataFile, to: folder.appendingPathComponent(name))
        } catch {
            AppLog.error("Backup", "Couldn't keep a safety copy before this build: \(error.localizedDescription)")
        }
        for old in all.dropFirst(keep) { try? FileManager.default.removeItem(at: old.url) }
    }

    static func read(_ item: Item) -> AppSnapshot? {
        guard let data = try? Data(contentsOf: item.url) else { return nil }
        return try? JSONDecoder.gymForge.decode(AppSnapshot.self, from: data)
    }
}

/// MK23: where your backups stand, in words. Shown in Settings, Diagnostics and (when stale) on Today.
enum BackupStatus {
    private static let exportKey = "fullbackup.lastExport"

    /// When "Export everything" last finished by hand.
    static var lastManualExport: Date? {
        get { UserDefaults.standard.object(forKey: exportKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: exportKey) }
    }

    /// The newest backup that holds everything, More Training included: automatic or by hand.
    static var lastFull: Date? {
        [AutoBackup.isEnabled ? AutoBackup.lastBackup : nil, lastManualExport].compactMap { $0 }.max()
    }

    static var daysSinceFull: Int? {
        lastFull.map { max(0, Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0) }
    }

    /// Worth a nudge: nothing in two weeks (or ever), once there's something to lose.
    static func isStale(workouts: Int) -> Bool {
        guard workouts >= 3 else { return false }
        guard let days = daysSinceFull else { return true }
        return days >= 14
    }

    static var summary: String {
        guard let date = lastFull else { return "Never backed up" }
        return "Backed up " + date.formatted(.relative(presentation: .named))
    }

    static var filesLine: String {
        guard AutoBackup.isEnabled else { return "Off" }
        if let status = AutoBackup.status, status.hasPrefix("Last automatic backup failed") { return "Failed last time" }
        guard AutoBackup.folderURL != nil, AutoBackup.hasPasscode else { return "On, but not set up" }
        let every = AutoBackup.daily ? "Daily" : "Weekly"
        return AutoBackup.lastBackup.map { "\(every) · last " + $0.formatted(.relative(presentation: .named)) } ?? "\(every) · none yet"
    }

    static var filesOK: Bool {
        guard AutoBackup.isEnabled, AutoBackup.folderURL != nil, AutoBackup.hasPasscode, let last = AutoBackup.lastBackup else { return false }
        if let status = AutoBackup.status, status.hasPrefix("Last automatic backup failed") { return false }
        return Date().timeIntervalSince(last) < AutoBackup.interval * 2 + 86_400
    }

    static var exportLine: String {
        guard let date = lastFull else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    static var exportOK: Bool { (daysSinceFull ?? 99) < 14 }
}
