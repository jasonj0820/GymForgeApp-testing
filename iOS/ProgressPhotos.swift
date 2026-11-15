import CryptoKit
import Foundation
import Security
import UIKit

/// MK24 (88): physique photos, AES-GCM encrypted on disk with a key kept in this iPhone's Keychain.
/// They never go to the Photos app or iCloud. Export them from the photos page before re-signing the app
/// with a different Apple ID (a new signature can't read the old Keychain key).
@MainActor
final class ProgressPhotoStore: ObservableObject {
    static let shared = ProgressPhotoStore()

    enum Pose: String, Codable, CaseIterable, Identifiable {
        case front, side, back
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    struct Entry: Codable, Identifiable, Equatable {
        var id: UUID
        var date: Date
        var pose: Pose
        var weightKg: Double?
    }

    @Published private(set) var entries: [Entry] = []
    @Published var problem: String?

    private let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("index.sealed") }
    private var cache: [UUID: UIImage] = [:]

    private init() {
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProgressPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        load()
    }

    func entries(_ pose: Pose) -> [Entry] { entries.filter { $0.pose == pose }.sorted { $0.date < $1.date } }

    func add(_ image: UIImage, pose: Pose, weightKg: Double?, date: Date = .now) {
        let entry = Entry(id: UUID(), date: date, pose: pose, weightKg: weightKg)
        guard let jpeg = image.resized(maxSide: 2000).jpegData(compressionQuality: 0.85) else { return }
        do {
            try write(jpeg, to: url(entry.id))
            entries.append(entry)
            cache[entry.id] = image
            try saveIndex()
        } catch {
            problem = "Couldn't save the photo (\(error.localizedDescription))."
        }
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: url(entry.id))
        entries.removeAll { $0.id == entry.id }
        cache[entry.id] = nil
        try? saveIndex()
    }

    func image(_ entry: Entry) -> UIImage? {
        if let cached = cache[entry.id] { return cached }
        guard let data = try? read(url(entry.id)), let image = UIImage(data: data) else { return nil }
        cache[entry.id] = image
        return image
    }

    /// Plain JPEGs in a temporary folder, for the share sheet (deleted next launch).
    func exportFiles() -> [URL] {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("SplitdayPhotos", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        return entries.sorted { $0.date < $1.date }.compactMap { entry in
            guard let data = try? read(url(entry.id)) else { return nil }
            let name = "\(entry.date.formatted(.iso8601.year().month().day()))-\(entry.pose.rawValue)-\(entry.id.uuidString.prefix(4)).jpg"
            let file = out.appendingPathComponent(name)
            return (try? data.write(to: file)) != nil ? file : nil
        }
    }

    // MARK: Files

    private func url(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).sealed") }

    private func load() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("SplitdayPhotos"))
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            entries = try JSONDecoder().decode([Entry].self, from: read(indexURL))
        } catch {
            problem = "Couldn't open your progress photos. If the app was re-signed with another Apple ID, the old key is gone."
        }
    }

    private func saveIndex() throws {
        try write(JSONEncoder().encode(entries), to: indexURL)
    }

    private func write(_ plain: Data, to url: URL) throws {
        guard let sealed = try AES.GCM.seal(plain, using: Self.key()).combined else { throw CocoaError(.fileWriteUnknown) }
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func read(_ url: URL) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: Data(contentsOf: url)), using: Self.key())
    }

    private static var storedKey: SymmetricKey?

    private static func key() throws -> SymmetricKey {
        if let storedKey { return storedKey }
        let account = "progress-photos-key"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            let key = SymmetricKey(data: data)
            storedKey = key
            return key
        }
        guard status == errSecItemNotFound else { throw CocoaError(.fileReadNoPermission) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
                                  kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteNoPermission) }
        storedKey = key
        return key
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
