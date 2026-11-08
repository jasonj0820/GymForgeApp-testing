import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var exporting = false
    @State private var importingFile = false
    @State private var pendingRestore: AppSnapshot?
    @State private var pendingRestoreDate: Date?
    @State private var message: String?
    @AppStorage("cluck.liveActivity") private var cluckIsland = true
    @AppStorage(RestSound.modeKey) private var restSound = RestSound.mode.rawValue
    @AppStorage(SetTick.animationKey) private var tickAnimation = true
    @AppStorage(SetTick.hapticKey) private var tickHaptic = true

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

            Section {
                Picker("Coach style", selection: profileBinding(\.coachStyle)) {
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
                Toggle("Sergeant Cluck", isOn: profileBinding(\.cluckEnabled))
                if store.profile.cluckEnabled {
                    Toggle("Show on Dynamic Island", isOn: $cluckIsland)
                        .onChange(of: cluckIsland) { _, _ in store.refreshCluck() }
                }
                if store.profile.cluckEnabled {
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

            Group {
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
                Text("Used for run and basketball zones. If you don't set it, it's the highest heart rate GymForge has seen in the last year (at least 180), or 190.")
            }

            Section {
                NavigationLink {
                    SpeechLibraryView()
                } label: {
                    Label("Motivational speeches", systemImage: "music.note.list")
                }
            } footer: {
                Text("Import your own audio files. Play them from the workout screen — they pause your music while they play.")
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
                Toggle("End rest when heart rate drops", isOn: profileBinding(\.autoRest))
                if store.profile.autoRest {
                    Stepper("Below \(store.profile.autoRestBPM) BPM", value: profileBinding(\.autoRestBPM), in: 80...150, step: 5)
                }
            } header: {
                Text("Rest timer")
            } footer: {
                Text("Train announcement: a three-note chime, then a voice reads out what's next (\"The next exercise is Lat Pulldown. 8 reps.\") over your music, while GymForge is open. With the iPhone locked you get the chime only. On the Watch, rest ends early (with the Rest finished buzz) once your heart rate falls below this — but never before half the planned rest.")
            }
            }

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
                Text("Nudges when you're falling behind your weekly goal or have had 2+ days off, in your coach style. Plus a note on the 1st when your monthly report is ready.")
            }

            Section {
                Toggle("Back up to iCloud", isOn: Binding(
                    get: { store.cloud.isEnabled },
                    set: { store.cloud.isEnabled = $0 }
                ))
                if !store.cloud.isSignedIn {
                    Text("Sign in to iCloud (and turn on iCloud Drive) to use backups.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
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
                .disabled(!store.cloud.isSignedIn || store.cloud.isWorking)
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
                .disabled(!store.cloud.isSignedIn || store.cloud.isWorking)
                NavigationLink {
                    FullBackupView()
                } label: {
                    Label("Export & import everything", systemImage: "externaldrive.fill")
                        .bold()
                }
                Button("Export backup file (gym only)") { exporting = true }
                Button("Restore from backup file (gym only)…") { importingFile = true }
            } header: {
                Text("Backup")
            } footer: {
                Text("Routines, workout history and settings back up automatically after changes (keeps the last 14 days). A backup file can be saved to Files or AirDropped.")
            }

            Group {
                Section("Import") {
                    NavigationLink {
                        StrongImportView()
                    } label: {
                        Label("Import from Strong", systemImage: "square.and.arrow.down")
                    }
                }

                Section {
                    Toggle("Fixed-day split", isOn: Binding(get: { store.fixedSplitOn }, set: { store.fixedSplitOn = $0 }))
                } header: {
                    Text("Weekly split")
                } footer: {
                    Text("Mon chest · Tue back · Wed legs · Thu buffer (legs if Wednesday was missed) · Fri chest or basketball · Sat back · Sun rest. Missed days are skipped, never shifted. Off = rotate your routines on any days.")
                }

                Section("Apple Health") {
                    Button("Request Health access") {
                        Task { await store.requestHealthAccess() }
                    }
                    Button("Refresh Health data") {
                        Task { await store.appBecameActive() }
                    }
                    // MK19.3.1: say what happened — iOS only shows the Health pop-up once, so a second tap looks dead.
                    if let error = store.healthKit.authorizationError {
                        Text("Health said: \(error)").font(.footnote).foregroundStyle(.red)
                    } else if store.healthKit.hasRequestedAuthorization {
                        Text("Asked ✓ iOS only shows the Health pop-up the first time. To change what Splitday can see: Settings → Health → Data Access & Devices → GymForge (or Splitday).")
                            .font(.footnote).foregroundStyle(.green)
                    }
                    Text("If weight, body fat or sleep doesn't appear: Settings → Health → Data Access & Devices → GymForge, and turn on Weight, Body Fat Percentage, Sleep, Resting Heart Rate and Heart Rate Variability.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

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
                Text("For the test, open GymForge on the Watch first. If it says the iPhone can't see GymForge on your Watch, delete the Watch app, reinstall from Xcode, and open both apps once.")
            }

            Section("Data") {
                LabeledContent("Routines", value: "\(store.routines.count)")
                LabeledContent("Workouts logged", value: "\(store.workoutLogs.count)")
            }
        }
        .navigationTitle("Settings")
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

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<UserProfile, Value>) -> Binding<Value> {
        Binding(
            get: { store.profile[keyPath: keyPath] },
            set: { value in
                var profile = store.profile
                profile[keyPath: keyPath] = value
                store.setProfile(profile)
            }
        )
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
