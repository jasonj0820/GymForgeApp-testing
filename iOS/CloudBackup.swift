import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum BackupError: LocalizedError {
    case unavailable
    case notFound
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive for Splitday in Settings."
        case .notFound: return "No iCloud backup found yet."
        case .unreadable: return "The backup couldn't be read."
        }
    }
}

/// Backs up all routines, history and settings to the app's iCloud Drive folder
/// (latest copy + one per day, last 14 kept). Restores automatically on a fresh install.
@MainActor
final class CloudBackup: ObservableObject {
    nonisolated static let containerID = "iCloud.com.jason.gymforge"
    nonisolated static let latestName = "GymForge-backup.json"

    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isWorking = false
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "gymforge.icloudBackup") }
    }

    private var pending: Task<Void, Never>?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "gymforge.icloudBackup") as? Bool ?? true
        lastBackupDate = UserDefaults.standard.object(forKey: "gymforge.lastBackup") as? Date
    }

    var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Debounced so a burst of edits makes one backup.
    func scheduleBackup(_ snapshot: AppSnapshot) {
        guard isEnabled, isSignedIn else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.backupNow(snapshot)
        }
    }

    func backupNow(_ snapshot: AppSnapshot) async {
        guard let data = try? JSONEncoder.gymForge.encode(snapshot) else { return }
        isWorking = true
        defer { isWorking = false }
        let result: Result<Date, Error> = await Task.detached(priority: .utility) {
            do { return .success(try CloudBackup.write(data)) } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let date):
            lastBackupDate = date
            UserDefaults.standard.set(date, forKey: "gymforge.lastBackup")
            statusMessage = nil
        case .failure(let error):
            statusMessage = error.localizedDescription
        }
    }

    /// Latest backup in iCloud, downloading it first if needed.
    func fetchLatest() async throws -> (snapshot: AppSnapshot, date: Date) {
        isWorking = true
        defer { isWorking = false }
        let result: Result<(Data, Date), Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try CloudBackup.readLatest()) } catch { return .failure(error) }
        }.value
        let (data, date) = try result.get()
        guard let snapshot = try? JSONDecoder.gymForge.decode(AppSnapshot.self, from: data) else { throw BackupError.unreadable }
        return (snapshot, date)
    }

    // MARK: File work (off the main thread)

    nonisolated static func folder() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            throw BackupError.unavailable
        }
        let folder = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    nonisolated static func write(_ data: Data) throws -> Date {
        let folder = try folder()
        try coordinatedWrite(data, to: folder.appendingPathComponent(latestName))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        try coordinatedWrite(data, to: folder.appendingPathComponent("GymForge-\(formatter.string(from: .now)).json"))

        let dailies = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let old = dailies.filter { $0.hasPrefix("GymForge-20") && $0.hasSuffix(".json") }.sorted().dropLast(14)
        for name in old {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        return .now
    }

    nonisolated static func readLatest() throws -> (Data, Date) {
        let url = try folder().appendingPathComponent(latestName)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        // Wait up to ~15 s for iCloud to bring the file down.
        for _ in 0..<30 {
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values?.ubiquitousItemDownloadingStatus == .current { break }
            if FileManager.default.fileExists(atPath: url.path), values?.ubiquitousItemDownloadingStatus == nil { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw BackupError.notFound }

        var coordinationError: NSError?
        var readError: Error?
        var data: Data?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do { data = try Data(contentsOf: target) } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let data else { throw BackupError.unreadable }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return (data, date)
    }

    nonisolated static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}

/// A backup file you can save anywhere (Files, AirDrop) — works without iCloud too.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var snapshot: AppSnapshot

    init(snapshot: AppSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let snapshot = try? JSONDecoder.gymForge.decode(AppSnapshot.self, from: data) else {
            throw BackupError.unreadable
        }
        self.snapshot = snapshot
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder.gymForge.encode(snapshot))
    }
}
