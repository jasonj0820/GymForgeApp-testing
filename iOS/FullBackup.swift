import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// One passcode-encrypted file with everything: routines, workout history, settings,
/// and the private section (data + photos). Made for reinstalling / re-signing the app.
struct FullBackupPayload: Codable {
    var version = 1
    var createdAt: Date
    var gym: AppSnapshot
    /// Private section export (JSON), nil if it was skipped.
    var privateData: Data?
}

enum FullBackup {
    static let magic = "GFALL1"

    static func make(gym: AppSnapshot, privateData: Data?, passcode: String) throws -> Data {
        let payload = FullBackupPayload(createdAt: .now, gym: gym, privateData: privateData)
        let json = try JSONEncoder.gymForge.encode(payload)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        return try MTVault.seal(compressed, passcode: passcode, magic: magic)
    }

    static func open(_ file: Data, passcode: String) throws -> FullBackupPayload {
        let compressed = try MTVault.open(file, passcode: passcode, magic: magic)
        let json = try (compressed as NSData).decompressed(using: .lzfse) as Data
        guard let payload = try? JSONDecoder.gymForge.decode(FullBackupPayload.self, from: json) else { throw MTVaultError.badFile }
        return payload
    }

    static var fileName: String {
        "GymForge-everything-\(Date().formatted(.iso8601.year().month().day())).gfbackup"
    }

    // MARK: Weekly reminder

    static let reminderID = "gymforge.fullbackup.weekly"

    static var weeklyReminder: Bool {
        get { UserDefaults.standard.bool(forKey: reminderID) }
        set {
            UserDefaults.standard.set(newValue, forKey: reminderID)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [reminderID])
            guard newValue else { return }
            let content = UNMutableNotificationContent()
            content.title = "Back up Splitday"
            content.body = "Export everything before you re-sign the app."
            var when = DateComponents()
            when.weekday = 1 // Sunday
            when.hour = 19
            center.add(UNNotificationRequest(identifier: reminderID, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
        }
    }
}

struct FullBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws { bytes = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct FullBackupView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var passcode = ""
    @State private var confirm = ""
    @State private var document: FullBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var importFile: Data?
    @State private var importPasscode = ""
    @State private var pending: FullBackupPayload?
    @State private var working = false
    @State private var message: String?
    @State private var reminder = FullBackup.weeklyReminder
    @State private var exportSummary = ""

    var body: some View {
        Form {
            Section {
                SecureField("Passcode (6+ characters)", text: $passcode)
                SecureField("Confirm passcode", text: $confirm)
                Button {
                    Task { await export() }
                } label: {
                    HStack {
                        Label("Export everything", systemImage: "square.and.arrow.up")
                        if working { Spacer(); SwiftUI.ProgressView() }
                    }
                }
                .disabled(passcode.count < 6 || passcode != confirm || working)
            } header: {
                Text("Export")
            } footer: {
                Text("One encrypted file with all routines, workout history, settings and every private section (with photos). Face ID is needed to include the private parts. Keep the passcode safe — the file can't be opened without it.")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Import everything…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Replaces this iPhone's routines, history and settings with the backup, and merges the private data back in.")
            }

            Section {
                NavigationLink {
                    AutoBackupView()
                } label: {
                    LabeledContent("Automatic weekly backup",
                                   value: AutoBackup.isEnabled ? (AutoBackup.lastBackup.map { "Last " + $0.formatted(.relative(presentation: .named)) } ?? "On") : "Off")
                }
            }

            Section {
                Toggle("Weekly backup reminder", isOn: $reminder)
                    .onChange(of: reminder) { _, value in
                        Task {
                            if value { _ = await ReminderScheduler.requestPermission() }
                            FullBackup.weeklyReminder = value
                        }
                    }
            } footer: {
                Text("Sunday evening. Tip: when re-signing, install the new build over the existing app (don't delete it first) — your data stays. Export first anyway, in case the signing identity changes.")
            }
        }
        .navigationTitle("Export & import everything")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: FullBackup.fileName) { result in
            switch result {
            case .success: message = "Exported and verified: \(exportSummary). Save a copy off this phone too (Files → iCloud Drive, or AirDrop to your Mac)."
            case .failure(let error): message = error.localizedDescription
            }
            document = nil
            passcode = ""
            confirm = ""
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            importFile = try? Data(contentsOf: url)
            importPasscode = ""
            if importFile == nil { message = MTVaultError.badFile.localizedDescription }
        }
        .alert("Backup passcode", isPresented: Binding(
            get: { importFile != nil },
            set: { if !$0 { importFile = nil } }
        )) {
            SecureField("Passcode", text: $importPasscode)
            Button("Open") {
                guard let file = importFile else { return }
                importFile = nil
                do {
                    pending = try FullBackup.open(file, passcode: importPasscode)
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { importFile = nil }
        }
        .confirmationDialog("Restore this backup?", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let payload = pending { Task { await restore(payload) } }
                pending = nil
            }
        } message: {
            if let payload = pending {
                Text("Made \(payload.createdAt.formatted(date: .abbreviated, time: .shortened)): \(payload.gym.workoutLogs.count) workouts, \(payload.gym.routines.count) routines. This iPhone's routines and history will be replaced.")
            }
        }
        .alert("Backup", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func export() async {
        working = true
        defer { working = false }
        let vault = MTVault.shared
        var privateData: Data?
        let wasUnlocked = vault.isUnlocked
        var unlocked = wasUnlocked
        if !unlocked { unlocked = await vault.unlock() }
        if unlocked {
            do {
                privateData = try vault.exportPayloadJSON()
            } catch {
                if !wasUnlocked { vault.lock() }
                message = "Export stopped: \(error.localizedDescription)"
                return
            }
            if !wasUnlocked { vault.lock() }
        } else {
            message = "Face ID was cancelled, so nothing was exported."
            return
        }
        do {
            let bytes = try FullBackup.make(gym: store.snapshot, privateData: privateData, passcode: passcode)
            // Re-open the finished file to prove it decrypts and contains everything.
            let check = try FullBackup.open(bytes, passcode: passcode)
            guard let privateJSON = check.privateData, let summary = MTVault.summary(ofPayload: privateJSON) else {
                message = "Export check failed — the private section wasn't in the file. Nothing was saved."
                return
            }
            exportSummary = "\(check.gym.workoutLogs.count) workouts, \(check.gym.routines.count) routines, " + summary.text
            document = FullBackupDocument(bytes: bytes)
            exporting = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore(_ payload: FullBackupPayload) async {
        store.restore(payload.gym)
        var privateCount = 0
        if let privateData = payload.privateData {
            let vault = MTVault.shared
            let wasUnlocked = vault.isUnlocked
            var unlocked = wasUnlocked
            if !unlocked { unlocked = await vault.unlock() }
            if unlocked {
                do {
                    privateCount = try vault.importPayloadJSON(privateData)
                } catch {
                    if !wasUnlocked { vault.lock() }
                    message = "Restored \(payload.gym.workoutLogs.count) workouts, but the private data failed: \(error.localizedDescription)"
                    return
                }
                if !wasUnlocked { vault.lock() }
            } else {
                message = "Restored \(payload.gym.workoutLogs.count) workouts. Face ID was cancelled, so the private data wasn't restored — import again to add it."
                return
            }
        }
        message = "Restored \(payload.gym.workoutLogs.count) workouts and \(payload.gym.routines.count) routines" + (privateCount > 0 ? ", plus \(privateCount) private items." : ".")
    }
}
