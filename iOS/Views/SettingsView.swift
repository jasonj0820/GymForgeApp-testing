import SwiftUI
import UniformTypeIdentifiers

/// MK23: Settings was one list of 18 sections. It's now four pages plus Diagnostics, with the state of
/// your backups at the top because that's the one thing here that can cost you data.
struct SettingsView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            Section {
                NavigationLink { SettingsDataPage() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: BackupStatus.exportOK ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(BackupStatus.exportOK ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BackupStatus.summary).font(.headline)
                            Text(BackupStatus.exportOK
                                 ? "Automatic backup: \(BackupStatus.filesLine)"
                                 : "Nothing recent holds everything. Set up the automatic backup, or export by hand.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                page("You and your goals", "person.crop.circle", "Height, age, phase, weekly goal, Health import") { SettingsYouPage() }
                page("Training and coach", "figure.strengthtraining.traditional", "Coach style, blocks, weekly split, routine, Sergeant Cluck") { SettingsTrainingPage() }
                page("Sounds and reminders", "bell", "Rest timer, set tick, speeches, notifications") { SettingsSoundsPage() }
                page("Data and devices", "externaldrive", "Backups, import, Apple Health, Apple Watch") { SettingsDataPage() }
            }

            Section {
                page("Diagnostics", "stethoscope", "What this install can do, recent problems") { DiagnosticsView() }
            } footer: {
                Text("Splitday \(BuildInfo.summary)")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            refresh += 1
            Usage.opened("Settings")
        }
        .onReceive(NotificationCenter.default.publisher(for: AppLog.changed)) { _ in refresh += 1 }
    }

    private func page<Destination: View>(_ title: String, _ icon: String, _ detail: String,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - You and your goals

struct SettingsYouPage: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        Form {
            YourDetailsSection()

            Section {
                Picker("Phase", selection: Binding(
                    get: { store.nutritionPhase },
                    set: { store.setPhase($0) }
                )) {
                    ForEach(NutritionPhase.allCases) { Text($0.title).tag($0) }
                }
                if let record = store.currentPhaseRecord {
                    DatePicker("Phase started", selection: Binding(
                        get: { record.start },
                        set: { store.setPhaseStart($0) }
                    ), in: ...Date(), displayedComponents: .date)
                }
                Stepper("Mini-cut prompt above \(Int(store.miniCutThreshold))% body fat",
                        value: Binding(get: { store.miniCutThreshold }, set: { store.setMiniCutThreshold($0) }),
                        in: 12...30, step: 1)
                Stepper("\(store.weeklyGoal) workouts per week", value: Binding(
                    get: { store.weeklyGoal },
                    set: { store.setWeeklyGoal($0) }
                ), in: 1...7)
            } header: {
                Text("Goal")
            } footer: {
                Text("Phase sets your protein target, the coach's goal, plateau advice and report cards. Bulk 1.6 g/kg · Recomp and Cut 2.2 g/kg.")
            }

            HealthImportSection()
        }
        .navigationTitle("You and your goals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Training and coach

struct SettingsTrainingPage: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage("cluck.liveActivity") private var cluckIsland = true

    var body: some View {
        Form {
            Section {
                Picker("Coach style", selection: store.profileBinding(\.coachStyle)) {
                    ForEach(CoachStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Coach")
            } footer: {
                Text(sample(for: store.profile.coachStyle))
            }

            Section {
                NavigationLink {
                    ProgramSettingsView()
                } label: {
                    LabeledContent("Program blocks", value: store.profile.program?.name ?? "Off")
                }
                if let until = store.profile.deloadUntil, until > .now {
                    LabeledContent("Deload until", value: until.formatted(date: .abbreviated, time: .omitted))
                    Button("End deload now") { store.endDeload() }
                } else {
                    Button("Start a deload week") { store.startDeloadWeek() }
                }
            } header: {
                Text("Training")
            } footer: {
                Text("Deload: one less set per exercise and ~10% lighter for 7 days. Deload and light sessions don't count against your progression.")
            }

            Section {
                Toggle("Fixed-day split", isOn: Binding(get: { store.fixedSplitOn }, set: { store.fixedSplitOn = $0 }))
            } header: {
                Text("Weekly split")
            } footer: {
                Text("Mon chest · Tue back · Wed legs · Thu buffer (legs if Wednesday was missed) · Fri chest or basketball · Sat back · Sun rest. Missed days are skipped, never shifted. Off = rotate your routines on any days.")
            }

            Section {
                NavigationLink { DayfoldManageView() } label: { Label("Steps", systemImage: "checklist") }
                NavigationLink { DayfoldSettingsView() } label: { Label("Reminders and Watch sync", systemImage: "bell") }
                NavigationLink { MotivationSettingsView() } label: { Label("Quotes and widget", systemImage: "quote.opening") }
            } header: {
                Text("Routine")
            } footer: {
                Text("Your daily, weekly, monthly and yearly steps, with the wake-up and before-bed checklists. They show on Today under the session card.")
            }

            Section {
                Toggle("Sergeant Cluck", isOn: store.profileBinding(\.cluckEnabled))
                if store.profile.cluckEnabled {
                    Toggle("Show on Dynamic Island", isOn: $cluckIsland)
                        .onChange(of: cluckIsland) { _, _ in store.refreshCluck() }
                    let state = CluckEngine.evaluate(store.cluckSnapshot)
                    HStack(spacing: 12) {
                        CluckView(mood: state.mood, animated: true).frame(width: 44, height: 44)
                        Text(state.snoozeAvailable ? "Snooze available this week" : "This week's snooze is used")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Quota enforcer")
            } footer: {
                Text("A furious chicken who guards your weekly goal. He only nags when you're down to 1 or 0 spare rest days: 5:10pm, 7:00pm and a last call at 8:30pm (in your coach style). Logging or starting a workout calms him down. \"Not today\" snoozes once per week. Rest days you plan ahead (Plan week) keep him calm on the day; sick and travel days stand him down. Add the Sergeant Cluck widget to your Home or Lock Screen — it turns angry at 5:10pm by itself. While he's on, he replaces the regular \"behind your goal\" reminders.")
            }

            Section {
                Stepper("Max heart rate: \(min(220, max(140, store.profile.maxHeartRateSetting ?? Int(store.estimatedMaxHeartRate))))",
                        value: Binding(
                            get: { min(220, max(140, store.profile.maxHeartRateSetting ?? Int(store.estimatedMaxHeartRate))) },
                            set: { value in
                                var updated = store.profile
                                updated.maxHeartRateSetting = value
                                store.setProfile(updated)
                            }),
                        in: 140...220)
                if store.profile.maxHeartRateSetting != nil {
                    Button("Use the estimate instead") {
                        var updated = store.profile
                        updated.maxHeartRateSetting = nil
                        store.setProfile(updated)
                    }
                }
            } header: {
                Text("Heart-rate zones")
            } footer: {
                Text("Used for run and basketball zones. If you don't set it, it's the highest heart rate Splitday has seen in the last year (at least 180), or 190.")
            }
        }
        .navigationTitle("Training and coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sample(for style: CoachStyle) -> String {
        switch style {
        case .pushMe: return "e.g. “You've missed two sessions. Get back in today.”"
        case .motivating: return "e.g. “One workout today gets you moving again.”"
        case .analytical: return "e.g. “Adherence fell from 92% to 68% over the last month.”"
        case .supportive: return "e.g. “Any session counts — no pressure.”"
        case .heartbreak: return "Breakup fuel — turns the hurt into reps. Also shown on your Lock Screen during workouts. e.g. “She left. The bar stayed. Pick it up.”"
        case .hardTruth: return "Blunt, no-excuses discipline talk — also shown on your Lock Screen during workouts. e.g. “Discipline is doing it when you don't feel like it.”"
        }
    }
}

// MARK: - Sounds and reminders

struct SettingsSoundsPage: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage(RestSound.modeKey) private var restSound = RestSound.mode.rawValue
    @AppStorage(SetTick.animationKey) private var tickAnimation = true
    @AppStorage(SetTick.hapticKey) private var tickHaptic = true

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    NotificationCheckView()
                } label: {
                    Label("Check notifications", systemImage: "bell.badge")
                }
                Toggle("Workout reminders", isOn: Binding(
                    get: { store.profile.reminders },
                    set: { value in Task { await store.setReminders(enabled: value) } }
                ))
                if store.profile.reminders {
                    DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Nudges when you're falling behind your weekly goal or have had 2+ days off, in your coach style. Plus a note on the 1st when your monthly report is ready. Routine reminders are under Training and coach → Routine.")
            }

            YourDaySettingsSection()

            Section {
                Picker("When rest ends", selection: $restSound) {
                    ForEach(RestAlertSound.allCases) { sound in
                        Text(sound.title).tag(sound.rawValue)
                    }
                }
                .onChange(of: restSound) { _, raw in
                    RestSound.play(announcement: "The next exercise is Lat Pulldown. 8 reps.",
                                   mode: RestAlertSound(rawValue: raw) ?? .ding)
                }
                if restSound == RestAlertSound.train.rawValue {
                    Button {
                        RestSound.play(announcement: "The next exercise is Lat Pulldown. 8 reps.", mode: .train)
                    } label: {
                        Label("Play sample announcement", systemImage: "speaker.wave.2.fill")
                    }
                }
                Toggle("End rest when heart rate drops", isOn: store.profileBinding(\.autoRest))
                if store.profile.autoRest {
                    Stepper("Below \(store.profile.autoRestBPM) BPM", value: store.profileBinding(\.autoRestBPM), in: 80...150, step: 5)
                }
            } header: {
                Text("Rest timer")
            } footer: {
                Text("Train announcement: a three-note chime, then a voice reads out what's next (\"The next exercise is Lat Pulldown. 8 reps.\") over your music, while Splitday is open. With the iPhone locked you get the chime only. On the Watch, rest ends early (with the Rest finished buzz) once your heart rate falls below this — but never before half the planned rest.")
            }

            Section {
                Toggle("Green tick when a set is logged", isOn: $tickAnimation)
                Toggle("Double-tap vibration", isOn: $tickHaptic)
                    .onChange(of: tickHaptic) { _, on in if on { SetTick.playHaptic(pr: false) } }
            } header: {
                Text("Set complete")
            } footer: {
                Text("A green tick pops up on the workout screen for every set (gold with confetti for a PR, and it says when an exercise is done) — including sets logged on your Watch. With Reduce Motion on, it just fades in.")
            }

            Section {
                NavigationLink {
                    SpeechLibraryView()
                } label: {
                    Label("Motivational speeches", systemImage: "music.note.list")
                }
            } footer: {
                Text("Import your own audio files. Once there's at least one, a player appears on the workout screen. They pause your music while they play.")
            }
        }
        .navigationTitle("Sounds and reminders")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.profile.reminderHour ?? 17,
                                      minute: store.profile.reminderMinute ?? 30,
                                      second: 0, of: .now) ?? .now
            },
            set: { date in
                var profile = store.profile
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                profile.reminderHour = parts.hour
                profile.reminderMinute = parts.minute
                store.setProfile(profile)
            }
        )
    }
}

// MARK: - Data and devices

struct SettingsDataPage: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var exporting = false
    @State private var importingFile = false
    @State private var pendingRestore: AppSnapshot?
    @State private var pendingRestoreDate: Date?
    @State private var message: String?
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            Section {
                statusRow("Last backup that holds everything", BackupStatus.exportLine, ok: BackupStatus.exportOK)
                NavigationLink {
                    AutoBackupView()
                } label: {
                    LabeledContent("Automatic backup to Files", value: BackupStatus.filesLine)
                }
                NavigationLink {
                    FullBackupView()
                } label: {
                    Label("Export & import everything", systemImage: "externaldrive.fill")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("\"Everything\" is one encrypted file: routines, history, settings, imported Health data, and More Training with its photos. It's the only backup that survives re-signing the app with a different Apple ID or tool, because More Training's key lives in this iPhone's Keychain and doesn't move with the app. Keep one that's less than two weeks old.")
            }

            Section {
                let copies = SafetyCopy.all
                if copies.isEmpty {
                    Text("None yet. One is kept the first time each new build opens.").foregroundStyle(.secondary)
                }
                ForEach(copies) { copy in
                    Button {
                        if let snapshot = SafetyCopy.read(copy) {
                            pendingRestore = snapshot
                            pendingRestoreDate = copy.date
                        } else {
                            message = BackupError.unreadable.localizedDescription
                        }
                    } label: {
                        LabeledContent("Before build \(copy.build)", value: copy.date.formatted(date: .abbreviated, time: .shortened))
                    }
                    .tint(.primary)
                }
            } header: {
                Text("Safety copies")
            } footer: {
                Text("Your gym data as it was just before each update, kept on this iPhone (newest 5). Tap one to go back to it. They're gone if the app is deleted, so they don't replace a backup.")
            }

            Section {
                Button("Export backup file (gym only)") { exporting = true }
                Button("Restore from backup file (gym only)…") { importingFile = true }
                NavigationLink {
                    StrongImportView()
                } label: {
                    Label("Import from Strong", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Files")
            } footer: {
                Text("A plain file with routines, workout history and settings, without More Training. Save it to Files or AirDrop it.")
            }

            cloudSection
            healthSection

            Section {
                Text(store.watchBridge.statusText)
                if let sent = store.watchBridge.lastSnapshotSent {
                    LabeledContent("Routines sent", value: sent.formatted(.relative(presentation: .named)))
                }
                if let received = store.watchBridge.lastReceived {
                    LabeledContent("Last heard from Watch", value: received.formatted(.relative(presentation: .named)))
                }
                if let error = store.watchBridge.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button("Send routines to Watch") { store.pushSnapshotToWatch() }
                Button("Test connection") { store.watchBridge.ping() }
                if let result = store.watchBridge.pingResult {
                    Text(result).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("For the test, open Splitday on the Watch first. If it says the iPhone can't see Splitday on your Watch, delete the Watch app, reinstall it, and open both apps once.")
            }

            Section("Data") {
                NavigationLink { DataCheckView() } label: { Label("Data check-up", systemImage: "checklist.checked") }
                LabeledContent("Routines", value: "\(store.routines.count)")
                LabeledContent("Workouts logged", value: "\(store.workoutLogs.count)")
                LabeledContent("Data file", value: store.dataFileSize)
            }
        }
        .navigationTitle("Data and devices")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh += 1 }
        .onReceive(NotificationCenter.default.publisher(for: AppLog.changed)) { _ in refresh += 1 }
        .fileExporter(isPresented: $exporting, document: BackupDocument(snapshot: store.snapshot), contentType: .json,
                      defaultFilename: "GymForge-backup-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url),
                   let snapshot = try? JSONDecoder.gymForge.decode(AppSnapshot.self, from: data) {
                    pendingRestore = snapshot
                    pendingRestoreDate = nil
                } else {
                    message = BackupError.unreadable.localizedDescription
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Replace your data with this backup?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let snapshot = pendingRestore {
                    store.restore(snapshot)
                    message = "Restored \(snapshot.workoutLogs.count) workouts and \(snapshot.routines.count) routines."
                }
                pendingRestore = nil
            }
        } message: {
            if let snapshot = pendingRestore {
                Text("Backup\(pendingRestoreDate.map { " from " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""): \(snapshot.workoutLogs.count) workouts, \(snapshot.routines.count) routines. Your current data on this iPhone will be replaced.")
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

    private func statusRow(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// iCloud only works when the install kept its iCloud entitlement; sideloaded ones don't.
    @ViewBuilder
    private var cloudSection: some View {
        if store.cloud.isSignedIn {
            Section {
                Toggle("Back up to iCloud", isOn: Binding(
                    get: { store.cloud.isEnabled },
                    set: { store.cloud.isEnabled = $0 }
                ))
                if let date = store.cloud.lastBackupDate {
                    LabeledContent("Last backup", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let status = store.cloud.statusMessage {
                    Text(status).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await store.backupNow() }
                } label: {
                    HStack {
                        Text("Back up now")
                        if store.cloud.isWorking { Spacer(); SwiftUI.ProgressView() }
                    }
                }
                .disabled(store.cloud.isWorking)
                Button("Restore from iCloud…") {
                    Task {
                        do {
                            let backup = try await store.cloud.fetchLatest()
                            pendingRestore = backup.snapshot
                            pendingRestoreDate = backup.date
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .disabled(store.cloud.isWorking)
            } header: {
                Text("iCloud")
            } footer: {
                Text("Routines, workout history and settings (not More Training) back up after changes; the last 14 days are kept.")
            }
        } else {
            Section {
                Label("Not available in this install", systemImage: "icloud.slash").foregroundStyle(.secondary)
            } header: {
                Text("iCloud")
            } footer: {
                Text("Splitday's own iCloud backup needs an entitlement that sideloading tools remove (or this iPhone isn't signed in to iCloud Drive). Use the automatic backup above and pick a folder in iCloud Drive: that does work, and it holds more.")
            }
        }
    }

    /// Same idea for Apple Health: once it has answered with an error, stop offering buttons that can't work.
    @ViewBuilder
    private var healthSection: some View {
        Section {
            if let error = store.healthKit.authorizationError {
                Label("Not available in this install", systemImage: "heart.slash").foregroundStyle(.secondary)
                Text("Health said: \(error)").font(.footnote).foregroundStyle(.secondary)
                Button("Try again") { Task { await store.requestHealthAccess() } }
            } else {
                Button("Request Health access") {
                    Task { await store.requestHealthAccess() }
                }
                Button("Refresh Health data") {
                    Task { await store.appBecameActive() }
                }
                if store.healthKit.hasRequestedAuthorization {
                    Text("Asked ✓ iOS only shows the Health pop-up the first time. To change what Splitday can see: Settings → Health → Data Access & Devices → Splitday.")
                        .font(.footnote).foregroundStyle(.green)
                }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text(store.healthKit.authorizationError != nil
                 ? "Sideloading tools remove Apple Health. Your weight and body fat come from the Sunday weigh-in, your details from You and your goals, and older history from an Apple Health export (You and your goals → Apple Health export)."
                 : "If weight, body fat or sleep doesn't appear: Settings → Health → Data Access & Devices → Splitday, and turn on Weight, Body Fat Percentage, Sleep, Resting Heart Rate and Heart Rate Variability.")
        }
    }
}

// MARK: - Your details (MK20.3)

/// Height, birthday and sex, typed in because Apple Health isn't available. Used for BMI, the calorie
/// estimate (Mifflin–St Jeor when there's no body fat reading) and max heart rate.
struct YourDetailsSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var heightText = ""
    @FocusState private var heightFocused: Bool

    var body: some View {
        let profile = store.profile
        let latestWeight = store.healthKit.bodyWeight.last?.value
        Section {
            HStack {
                Text("Height")
                Spacer()
                TextField("cm", text: $heightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .focused($heightFocused)
                    .onSubmit(saveHeight)
                Text("cm").foregroundStyle(.secondary)
            }
            if let birth = profile.birthDate {
                DatePicker("Birthday", selection: Binding(get: { birth }, set: { date in edit { $0.birthDate = date } }),
                           in: ...Date(), displayedComponents: .date)
            } else {
                Button("Set birthday") {
                    edit { $0.birthDate = Calendar.current.date(byAdding: .year, value: -25, to: .now) }
                }
            }
            Picker("Sex", selection: Binding(get: { profile.sex ?? "" }, set: { value in edit { $0.sex = value.isEmpty ? nil : value } })) {
                Text("Not set").tag("")
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            NavigationLink {
                WeighInHistoryView()
            } label: {
                LabeledContent("Weight & body fat", value: latestWeight.map { "\(GFFormat.kg($0)) kg" } ?? "Add")
            }
            if let age = profile.age() {
                LabeledContent("Age", value: "\(age)")
            }
            if let weight = latestWeight, let bmi = profile.bmi(weightKg: weight) {
                LabeledContent("BMI", value: String(format: "%.1f", bmi))
            }
            if let maintenance = store.calorieCoach.adaptiveMaintenance ?? store.calorieCoach.formulaMaintenance {
                LabeledContent("Maintenance", value: "≈ \(Int(maintenance.kcal.rounded())) kcal")
            }
        } header: {
            Text("Your details")
        } footer: {
            Text("Typed in here since Apple Health isn't connected. Height, age and sex set your calorie estimate (when there's no body fat reading) and max heart rate if you haven't set one. Weight and body fat — including past readings — go in Weight & body fat.")
        }
        .onAppear { heightText = profile.heightCm.map { GFFormat.kg($0) } ?? "" }
        .onChange(of: heightFocused) { _, focused in if !focused { saveHeight() } }
        .onDisappear(perform: saveHeight)
    }

    private func saveHeight() {
        let value = Double(heightText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        let height = value.flatMap { (100...250).contains($0) ? $0 : nil }
        if heightText.isEmpty || height != nil, height != store.profile.heightCm {
            edit { $0.heightCm = height }
        }
    }

    private func edit(_ change: (inout UserProfile) -> Void) {
        var profile = store.profile
        change(&profile)
        store.setProfile(profile)
    }
}

// MARK: - Import Apple Health export (MK20.4)

/// Health app → your picture → Export All Health Data → save to Files → pick it here (the .zip as is,
/// or export.xml if you unzipped it). Weight, body fat, height, birthday, sex, sleep, resting HR and HRV.
struct HealthImportSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var picking = false
    @State private var progress: Double?
    @State private var message: String?
    @State private var failed = false
    @State private var confirmRemove = false
    @State private var reminderTick = 0

    var body: some View {
        let imported = store.healthKit.imported
        Section {
            if let progress {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reading your export… \(Int(progress * 100))%")
                    ProgressView(value: progress)
                    Text("Big exports take a minute or two — keep the app open.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    picking = true
                } label: {
                    Label(imported == nil ? "Import Apple Health export" : "Import a newer export", systemImage: "square.and.arrow.down")
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(failed ? .red : .secondary)
            }
            if let imported, progress == nil {
                LabeledContent("Last import", value: imported.importedAt.formatted(date: .abbreviated, time: .omitted))
                Text(imported.summary).font(.footnote).foregroundStyle(.secondary)
                Toggle("Remind me monthly", isOn: Binding(get: { HealthImportReminder.enabled },
                                                          set: { HealthImportReminder.enabled = $0; reminderTick += 1 }))
                    .id(reminderTick)
                NavigationLink { HealthShortcutsView() } label: {
                    Label("Daily, through Shortcuts", systemImage: "arrow.triangle.branch")
                }
                Button("Remove imported data", role: .destructive) { confirmRemove = true }
            }
            if imported == nil {
                NavigationLink { HealthShortcutsView() } label: {
                    Label("Daily, through Shortcuts", systemImage: "arrow.triangle.branch")
                }
            }
        } header: {
            Text("Apple Health export")
        } footer: {
            Text("In the Health app: tap your picture → Export All Health Data → Save to Files. Then pick export.zip here (no need to unzip). Brings in weight, body fat, height, birthday, sex, and the last \(HealthExportImporter.recoveryYears) years of sleep, resting heart rate and HRV. A newer export only adds what's new; your typed-in weigh-ins stay. For every day without exporting, set up the Shortcuts automation.")
        }
        // Its own document picker: a second .fileImporter on this screen would clash with the backup restore one.
        .sheet(isPresented: $picking) {
            HealthExportPicker(onPick: { url in
                picking = false
                startImport(url)
            }, onCancel: { picking = false })
            .ignoresSafeArea()
        }
        .confirmationDialog("Remove the imported Apple Health data?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                store.removeHealthImport()
                message = "Imported data removed. Your typed-in weigh-ins and details are kept."
                failed = false
            }
        }
    }

    private func startImport(_ url: URL) {
        failed = false
        message = nil
        progress = 0
        Task {
            do {
                let data = try await store.importHealthExport(from: url) { value in
                    Task { @MainActor in if progress != nil { progress = value } }
                }
                message = store.lastImportAdded == 0
                    ? "Nothing new in this export: everything in it was already here."
                    : "Added \(store.lastImportAdded) new reading\(store.lastImportAdded == 1 ? "" : "s"). In total: " + data.summary
            } catch {
                failed = true
                message = error.localizedDescription
            }
            progress = nil
        }
    }
}

/// Files picker for export.zip / export.xml, opened in place (no copy of a multi-GB file).
struct HealthExportPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .xml], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) { self.onPick = onPick; self.onCancel = onCancel }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
