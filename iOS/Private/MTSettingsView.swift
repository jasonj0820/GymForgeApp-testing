import SwiftUI
import UniformTypeIdentifiers

struct MTSettingsView: View {
    @EnvironmentObject private var vault: MTVault
    @State private var exportPasscode = ""
    @State private var exportConfirm = ""
    @State private var exportDocument: MTExportDocument?
    @State private var showingExporter = false
    @State private var importing = false
    @State private var importBytes: Data?
    @State private var importPasscode = ""
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Units") {
                Picker("Measurements", selection: settingsBinding(\.unit)) {
                    ForEach(MTUnit.allCases) { Text($0.label).tag($0) }
                }
                Picker("Extender tension", selection: settingsBinding(\.weightUnit)) {
                    ForEach(MTWeightUnit.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section {
                HStack {
                    Text("Hours before the app")
                    Spacer()
                    TextField("173", value: settingsBinding(\.baseHours), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("h").foregroundStyle(.secondary)
                }
                Stepper(String(format: "Daily goal: %.1f green-equivalent h", vault.data.settings.dailyGoal),
                        value: settingsBinding(\.dailyGoal), in: 1...16, step: 0.5)
            } header: {
                Text("Phallosan")
            } footer: {
                Text("Hours from your Phallosan log count toward your total and milestones. In the daily goal, Red counts ×3 and High Green/Yellow ×1.5.")
            }

            Section {
                Stepper("Cool-down: \(vault.data.settings.cooldownSeconds) s", value: settingsBinding(\.cooldownSeconds), in: 15...300, step: 15)
            } header: {
                Text("Stamina")
            }

            Section {
                Picker("Measuring reminder", selection: settingsBinding(\.reminderWeeks)) {
                    Text("Off").tag(0)
                    Text("Every 2 weeks").tag(2)
                    Text("Every 4 weeks").tag(4)
                }
                Toggle("Ghost of last photo in camera", isOn: settingsBinding(\.showGhost))
                Toggle("Nudge after 3 days off", isOn: settingsBinding(\.trainingNudgeOn))
            } header: {
                Text("Measuring progress")
            } footer: {
                Text("Reminders say only \"Time to log your progress.\" The ghost helps you match angle and distance between photos. The nudge is a silent \"⏱\" at 7:30pm on day 3 without training (1 h+ stretcher, 30+ min extender, or any PAC / pump), once more on day 6 — never on rest days or when the safety check says rest.")
            }

            Section {
                Toggle("Daily routine", isOn: Binding(get: { vault.data.settings.dailyRoutineOn },
                                                     set: { vault.setDailyRoutine($0) }))
            } header: {
                Text("Plan")
            } footer: {
                Text(vault.data.settings.dailyRoutineOn
                     ? "Every day: high tension extender 50 min on NIR days (15 min with NIR, then 35 without) or 40 min on the others, NIR every other day; then static pump or PAC 4 × 5 min, taking turns day to day. The PAC every-other-day plan and its reminders are off. Turn this off to go back to it and your old weekly goal."
                     : "Off: PAC every other day. On: extender every day (NIR every other day) plus static pump and PAC 4 × 5 min on alternating days.")
            }

            Section {
                Stepper("\(vault.data.settings.targetDaysPerWeek) training days per week",
                        value: settingsBinding(\.targetDaysPerWeek), in: 1...7)
            } header: {
                Text("Consistency goal")
            }

            Section {
                ForEach(MTType.allCases.filter { $0 != .allDayStretcher }) { type in
                    Stepper(value: limitBinding(type), in: 0...120, step: 1) {
                        HStack {
                            Label(type.title, systemImage: type.symbol)
                            Spacer()
                            let minutes = vault.data.settings.limit(for: type)
                            Text(minutes.map { "\($0) min" } ?? "Off").foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Time-limit alerts")
            } footer: {
                Text("When a session reaches its limit you get a notification (just ⏱, no words) and the timer turns red. Set to 0 for off.")
            }

            Section {
                SecureField("Export passcode", text: $exportPasscode)
                SecureField("Confirm passcode", text: $exportConfirm)
                Button("Export encrypted file") {
                    do {
                        exportDocument = MTExportDocument(bytes: try vault.exportData(passcode: exportPasscode))
                        showingExporter = true
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .disabled(exportPasscode.count < 6 || exportPasscode != exportConfirm)
                Button("Import encrypted file…") { importing = true }
            } header: {
                Text("Backup")
            } footer: {
                Text("This section is never included in GymForge's normal backups, iCloud or the Watch. An export includes everything (photos too), encrypted with the passcode you choose — at least 6 characters. If you forget it, the file can't be opened.")
            }

            Section {
                Button("Delete all More Training data", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Settings")
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .data,
                      defaultFilename: "MoreTraining-\(Date().formatted(.iso8601.year().month().day())).gfvault") { result in
            switch result {
            case .success: message = "Exported."
            case .failure(let error): message = error.localizedDescription
            }
            exportPasscode = ""
            exportConfirm = ""
            exportDocument = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                importBytes = try? Data(contentsOf: url)
                importPasscode = ""
                if importBytes == nil { message = MTVaultError.badFile.localizedDescription }
            }
        }
        .alert("Enter the export's passcode", isPresented: Binding(
            get: { importBytes != nil },
            set: { if !$0 { importBytes = nil } }
        )) {
            SecureField("Passcode", text: $importPasscode)
            Button("Import") {
                guard let bytes = importBytes else { return }
                do {
                    let added = try vault.importData(bytes, passcode: importPasscode)
                    message = "Imported \(added) items."
                } catch {
                    message = error.localizedDescription
                }
                importBytes = nil
            }
            Button("Cancel", role: .cancel) { importBytes = nil }
        }
        .confirmationDialog("Delete all More Training data and photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { vault.deleteEverything() }
        } message: {
            Text("This can't be undone unless you have an exported file.")
        }
        .alert("More Training", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<MTSettings, Value>) -> Binding<Value> {
        Binding(
            get: { vault.data.settings[keyPath: keyPath] },
            set: { value in
                var settings = vault.data.settings
                settings[keyPath: keyPath] = value
                vault.updateSettings(settings)
            }
        )
    }

    private func limitBinding(_ type: MTType) -> Binding<Int> {
        Binding(
            get: { vault.data.settings.limitMinutes[type.rawValue] ?? 0 },
            set: { value in
                var settings = vault.data.settings
                settings.limitMinutes[type.rawValue] = value > 0 ? value : nil
                vault.updateSettings(settings)
            }
        )
    }
}
