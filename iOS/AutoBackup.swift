import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

/// Weekly automatic backup of everything (gym + private section + photos) to a folder you pick
/// in Files. Encrypted with a backup passcode kept in this iPhone's Keychain, so it can run
/// without asking — and the file is useless without the passcode. Keeps the newest 4.
@MainActor
enum AutoBackup {
    private static let enabledKey = "autobackup.enabled"
    private static let bookmarkKey = "autobackup.folderBookmark"
    private static let lastKey = "autobackup.last"
    private static let statusKey = "autobackup.status"
    private static let keychainService = "com.gymforge.autobackup"
    static let filePrefix = "GymForge-auto-"
    static let interval: TimeInterval = 7 * 86_400
    static let keep = 4

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    nonisolated static var lastBackup: Date? {
        get { UserDefaults.standard.object(forKey: lastKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastKey) }
    }

    nonisolated static var status: String? {
        get { UserDefaults.standard.string(forKey: statusKey) }
        set { UserDefaults.standard.set(newValue, forKey: statusKey) }
    }

    // MARK: Folder

    static func setFolder(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    static var folderURL: URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Passcode (Keychain, this device only)

    static var hasPasscode: Bool { !(passcode ?? "").isEmpty }

    static func clearPasscode() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: keychainService,
                       kSecAttrAccount as String: "passcode"] as CFDictionary)
    }

    static var passcode: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "passcode",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setPasscode(_ value: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "passcode"
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    // MARK: Running

    static var isDue: Bool {
        guard let last = lastBackup else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

    /// Called when the app becomes active (waits a moment so launch stays smooth).
    static func runIfDue(store: PhoneAppStore) {
        guard isEnabled, isDue, folderURL != nil, hasPasscode else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            _ = await runNow(store: store)
        }
    }

    private static var running = false

    /// Returns a short result message. Encryption, verification and writing run off the main thread.
    @discardableResult
    static func runNow(store: PhoneAppStore) async -> String {
        guard !running else { return "A backup is already running." }
        guard let folder = folderURL else { return fail("Choose a folder first.") }
        guard let passcode, !passcode.isEmpty else { return fail("Set a backup passcode first.") }
        running = true
        defer { running = false }

        let gym = store.snapshot
        let privateJSON: Data
        do {
            privateJSON = try MTVault.shared.exportPayloadJSONForAutoBackup()
        } catch {
            return fail(error.localizedDescription)
        }
        let name = filePrefix + Date().formatted(.iso8601.year().month().day()) + ".gfbackup"
        let keepCount = keep
        let prefix = filePrefix

        let outcome: Result<(workouts: Int, summary: String), Error> = await Task.detached(priority: .utility) { () -> Result<(workouts: Int, summary: String), Error> in
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                let bytes = try FullBackup.make(gym: gym, privateData: privateJSON, passcode: passcode)
                // Verify the file opens with the passcode before writing it.
                let check = try FullBackup.open(bytes, passcode: passcode)
                guard check.privateData != nil else { throw MTVaultError.badFile }
                let target = folder.appendingPathComponent(name)
                var coordinatorError: NSError?
                var writeError: Error?
                NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinatorError) { url in
                    do { try bytes.write(to: url, options: .atomic) } catch { writeError = error }
                }
                if let error = coordinatorError ?? writeError { throw error }
                // Keep only the newest few.
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                let autos = files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "gfbackup" }
                    .sorted { $0.lastPathComponent > $1.lastPathComponent }
                for old in autos.dropFirst(keepCount) { try? FileManager.default.removeItem(at: old) }
                let summary = MTVault.summary(ofPayload: privateJSON)?.text ?? ""
                return .success((workouts: check.gym.workoutLogs.count, summary: summary))
            } catch {
                return .failure(error)
            }
        }.value

        switch outcome {
        case .success(let result):
            lastBackup = .now
            let message = "Backed up \(result.workouts) workouts" + (result.summary.isEmpty ? "" : ", " + result.summary) + " to \(folder.lastPathComponent)."
            status = message
            return message
        case .failure(let error):
            return fail(error.localizedDescription)
        }
    }

    private static func fail(_ message: String) -> String {
        status = "Last automatic backup failed: " + message
        return message
    }

}

/// Settings screen for the automatic backup (opened from Export & import everything).
struct AutoBackupView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var enabled = AutoBackup.isEnabled
    @State private var choosingFolder = false
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var result: String?
    @State private var working = false
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            Section {
                Toggle("Automatic weekly backup", isOn: $enabled)
                    .onChange(of: enabled) { _, value in AutoBackup.isEnabled = value }
            } footer: {
                Text("Every 7 days, when you open GymForge, everything (gym, More Training and photos) is saved to the folder you pick — encrypted with your backup passcode. The newest 4 are kept. Restore with \"Import everything…\".")
            }
            if enabled {
                Section("Where") {
                    Button {
                        choosingFolder = true
                    } label: {
                        LabeledContent("Folder", value: AutoBackup.folderURL?.lastPathComponent ?? "Choose…")
                    }
                }
                Section {
                    if AutoBackup.hasPasscode {
                        LabeledContent("Passcode", value: "Saved on this iPhone")
                        Button("Change passcode", role: .destructive) {
                            AutoBackup.clearPasscode()
                            refresh += 1
                        }
                    } else {
                        SecureField("Backup passcode (6+ characters)", text: $newPasscode)
                        SecureField("Confirm passcode", text: $confirmPasscode)
                        Button("Save passcode") {
                            if AutoBackup.setPasscode(newPasscode) {
                                result = "Passcode saved. Write it down somewhere safe — you'll need it to restore."
                            }
                            newPasscode = ""
                            confirmPasscode = ""
                            refresh += 1
                        }
                        .disabled(newPasscode.count < 6 || newPasscode != confirmPasscode)
                    }
                } header: {
                    Text("Passcode")
                } footer: {
                    Text("Kept in this iPhone's Keychain so backups can run by themselves. Without it the backup files can't be opened.")
                }
                Section {
                    if let last = AutoBackup.lastBackup {
                        LabeledContent("Last backup", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let status = AutoBackup.status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(status.hasPrefix("Last automatic backup failed") ? Color.red : Color.secondary)
                    }
                    Button {
                        working = true
                        Task {
                            result = await AutoBackup.runNow(store: store)
                            working = false
                            refresh += 1
                        }
                    } label: {
                        HStack {
                            Text("Back up now")
                            if working { Spacer(); SwiftUI.ProgressView() }
                        }
                    }
                    .disabled(working || AutoBackup.folderURL == nil || !AutoBackup.hasPasscode)
                }
            }
        }
        .navigationTitle("Automatic backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { picked in
            if case .success(let url) = picked {
                do {
                    try AutoBackup.setFolder(url)
                    refresh += 1
                } catch {
                    result = error.localizedDescription
                }
            }
        }
        .alert("Automatic backup", isPresented: Binding(
            get: { result != nil },
            set: { if !$0 { result = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result ?? "")
        }
    }
}
