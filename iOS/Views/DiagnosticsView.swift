import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// MK23: one page that says what this install can and can't do, and what went wrong lately.
/// "Copy report" puts it all on the clipboard to paste into a chat.
struct DiagnosticsView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var pending = 0
    @State private var permission = "Checking…"
    @State private var entries = AppLog.entries
    @State private var copied = false
    @State private var showUsage = false

    var body: some View {
        Form {
            Section("This build") {
                LabeledContent("Version", value: BuildInfo.summary)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                NavigationLink("What's new") { WhatsNewView() }
            }

            Section {
                row("Data file", store.saveProblem == nil ? "Saving normally" : "Not saving", ok: store.saveProblem == nil)
                if let problem = store.saveProblem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
                LabeledContent("Workouts / routines", value: "\(store.workoutLogs.count) / \(store.routines.count)")
                LabeledContent("Data file size", value: store.dataFileSize)
                row("Files backup", BackupStatus.filesLine, ok: BackupStatus.filesOK)
                row("Safety copies on this iPhone", "\(SafetyCopy.all.count)", ok: true)
                row("Full export (with More Training)", BackupStatus.exportLine, ok: BackupStatus.exportOK)
            } header: {
                Text("Your data")
            }

            Section {
                row("Widget storage", SharedGroup.status, ok: SharedGroup.id != nil)
                row("Notifications", permission, ok: permission == "Allowed")
                row("Planned notifications", "\(pending) of 64", ok: pending < 60)
                row("Apple Health", Capabilities.healthLine(store), ok: Capabilities.healthWorks(store))
                row("iCloud backup", Capabilities.cloudLine(store), ok: store.cloud.isSignedIn && store.cloud.statusMessage == nil)
                row("Apple Watch", store.watchBridge.statusText, ok: store.watchBridge.lastError == nil)
                row("Heart rate from the Watch", Capabilities.watchHeartRateLine(store), ok: Capabilities.watchHeartRateWorks(store))
                row("Health through Shortcuts", HealthBridge.last.map { "Last " + $0.date.formatted(.relative(presentation: .named)) } ?? "Not set up",
                    ok: HealthBridge.last.map { Date().timeIntervalSince($0.date) < 3 * 86_400 } ?? false)
            } header: {
                Text("What this install can do")
            } footer: {
                Text("Sideloaded installs usually lose Apple Health and iCloud, and get renamed widget storage. Orange rows are things this install can't do, not things you've set up wrong.")
            }

            Section {
                if entries.isEmpty {
                    Text("Nothing has gone wrong.").foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.area) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.message).font(.footnote)
                    }
                }
                if !entries.isEmpty {
                    Button("Clear", role: .destructive) { AppLog.clear() }
                }
            } header: {
                Text("Recent problems")
            }

            Section {
                DisclosureGroup("Screens you open", isExpanded: $showUsage) {
                    let counts = Usage.counts.sorted { $0.value > $1.value }
                    if counts.isEmpty {
                        Text("Nothing counted yet.").foregroundStyle(.secondary)
                    }
                    ForEach(counts, id: \.key) { item in
                        LabeledContent(item.key, value: "\(item.value)")
                    }
                    if !counts.isEmpty {
                        Button("Reset counts", role: .destructive) { Usage.reset(); showUsage = false }
                    }
                }
            } footer: {
                Text("Counted on this iPhone only\(Usage.since.map { ", since " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""). Nothing is sent anywhere. It's in the report below so we can see what's worth keeping.")
            }

            Section {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } footer: {
                Text("The report has the lines above and nothing from More Training.")
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AppLog.changed)) { _ in entries = AppLog.entries }
    }

    private func row(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .font(.footnote)
            Text(title)
            Spacer(minLength: 12)
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        pending = await center.pendingNotificationRequests().count
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = "Allowed"
        case .denied: permission = "Turned off in iPhone Settings"
        case .notDetermined: permission = "Not asked yet"
        @unknown default: permission = "Unknown"
        }
    }

    private var report: String {
        var lines = [
            "Splitday \(BuildInfo.summary) · iOS \(UIDevice.current.systemVersion)",
            "Data: \(store.saveProblem.map { "NOT SAVING (\($0))" } ?? "saving normally") · \(store.workoutLogs.count) workouts · \(store.routines.count) routines · \(store.dataFileSize)",
            "Files backup: \(BackupStatus.filesLine)",
            "Full export: \(BackupStatus.exportLine)",
            "Safety copies: \(SafetyCopy.all.count)",
            "Widget storage: \(SharedGroup.status)",
            "Notifications: \(permission) · \(pending) of 64 planned",
            "Apple Health: \(Capabilities.healthLine(store))",
            "iCloud backup: \(Capabilities.cloudLine(store))",
            "Apple Watch: \(store.watchBridge.statusText)"
        ]
        let problems = entries.suffix(12)
        lines.append(problems.isEmpty ? "Recent problems: none" : "Recent problems:")
        for entry in problems {
            lines.append("- \(entry.date.formatted(date: .numeric, time: .shortened)) \(entry.area): \(entry.message)")
        }
        let counts = Usage.counts.sorted { $0.value > $1.value }
        if !counts.isEmpty {
            lines.append("Screens opened: " + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// What this install can really do. Sideloading tools strip Apple Health and iCloud, so the app says so
/// plainly instead of offering buttons that do nothing.
@MainActor
enum Capabilities {
    /// Health answered with data, or at least without an error.
    static func healthWorks(_ store: PhoneAppStore) -> Bool {
        store.healthKit.authorizationError == nil && store.healthKit.hasRequestedAuthorization
    }

    static func healthLine(_ store: PhoneAppStore) -> String {
        if let error = store.healthKit.authorizationError { return "Not available (\(error))" }
        return store.healthKit.hasRequestedAuthorization ? "Connected" : "Not asked yet"
    }

    /// MK24: the Watch app has its own Health access. If workouts it ran came back with a heart rate,
    /// that access works on this install even when the iPhone's doesn't.
    static func watchHeartRateWorks(_ store: PhoneAppStore) -> Bool {
        store.workoutLogs.contains { ($0.averageHeartRateBPM ?? 0) > 0 && Date().timeIntervalSince($0.startedAt) < 30 * 86_400 }
    }

    static func watchHeartRateLine(_ store: PhoneAppStore) -> String {
        guard let last = store.workoutLogs.filter({ ($0.averageHeartRateBPM ?? 0) > 0 }).max(by: { $0.startedAt < $1.startedAt }) else {
            return "Never seen: start a workout from the Watch to test"
        }
        return "Working · last " + last.startedAt.formatted(.relative(presentation: .named))
    }

    static func cloudLine(_ store: PhoneAppStore) -> String {
        if !store.cloud.isSignedIn { return "Not available in this install" }
        if let status = store.cloud.statusMessage { return status }
        if let date = store.cloud.lastBackupDate { return "Last " + date.formatted(.relative(presentation: .named)) }
        return store.cloud.isEnabled ? "On, nothing backed up yet" : "Off"
    }
}

// MARK: - What's new

/// MK23: shown once the first time a new build opens, and from Settings → Diagnostics.
struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shown as a sheet (with a Done button) the first time; pushed from Diagnostics otherwise.
    var asSheet = false

    static let seenKey = "whatsnew.seenBuild"
    /// True when this build hasn't shown its notes yet (and it isn't a brand-new install).
    static var isDue: Bool {
        guard !Demo.isOn else { return false }
        let seen = UserDefaults.standard.string(forKey: seenKey)
        return seen != BuildInfo.name
    }
    static func markSeen() { UserDefaults.standard.set(BuildInfo.name, forKey: seenKey) }

    struct Note: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let text: String
    }

    static let notes: [Note] = [
        Note(icon: "checklist", title: "Routine has its own tab",
             text: "Today · Workouts · Routine · Progress · Body. Coach is at the top of Workouts, with Ask the coach and this week's changes."),
        Note(icon: "plus.circle", title: "The + on Today",
             text: "Protein, calories, weight or a note in two taps. A morning brief, your calendar next to the gym and bedtime, and a leave-for-the-gym nudge (Settings → Sounds and reminders → Your day)."),
        Note(icon: "lock.iphone", title: "Log a set from the Lock Screen",
             text: "The workout card has a ✓ button with the planned set. Also: In use (machine taken), Reorder, a finish time, and the mic: say \"80 for 10\"."),
        Note(icon: "flag.checkered", title: "Goals and coaching",
             text: "A goal on any lift with the date you'd reach it, busy weeks that ease the goal, accessory rotation each block."),
        Note(icon: "heart.text.square", title: "Health through Shortcuts",
             text: "Settings → Data and devices → Apple Health: two automations bring weight, sleep and heart data in and send workouts out. Plus a 3-tap readiness check-in."),
        Note(icon: "fork.knife", title: "Food, water and caffeine",
             text: "Body → Nutrition: a food log by meal, recipes with a shopping list, barcode and label scans, water, a caffeine cut-off and weekly averages."),
        Note(icon: "checklist", title: "A routine that does more",
             text: "Tick it from a widget, Siri or the notification. Steps get timers, links, their own times and streaks; sick days pause it."),
        Note(icon: "bell.badge", title: "Notifications on one page",
             text: "Every type with its times, quiet hours, and an at-work window. Plus badges and streak freezes."),
        Note(icon: "basketball.fill", title: "Basketball",
             text: "Shot chart, drills, a drill timer, vertical jump and game stats (Cardio history → Basketball)."),
        Note(icon: "stethoscope", title: "Data check-up",
             text: "Settings → Data and devices finds typos, double saves and split histories, with a fix for each.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.notes) { note in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: note.icon).font(.title3).foregroundStyle(.tint).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.headline)
                            Text(note.text).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(BuildInfo.summary)
            }
        }
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { Self.markSeen() }
    }
}

// MARK: - Demo screens

/// MK23: `-demo YES -screen <name>` opens one screen directly, so a picture of it can be taken.
/// A name ending in "-end" shows the bottom of the page.
struct DemoRoot: View {
    @EnvironmentObject private var store: PhoneAppStore
    let screen: String

    static let tabs = ["today", "workouts", "routine", "progress", "body"]

    var body: some View {
        let atEnd = screen.hasSuffix("-end")
        let name = atEnd ? String(screen.dropLast(4)) : screen
        Group {
            if Self.tabs.contains(name) || name == "workout" {
                RootTabView(startTab: name == "workout" ? "today" : name)
                    .task {
                        if name == "workout", let routine = store.routines.first { await store.startWorkout(routine) }
                    }
            } else {
                NavigationStack { pushed(name) }
            }
        }
        .defaultScrollAnchor(atEnd ? .bottom : nil)
    }

    @ViewBuilder
    private func pushed(_ name: String) -> some View {
        switch name {
        case "settings": SettingsView()
        case "settings-you": SettingsYouPage()
        case "settings-training": SettingsTrainingPage()
        case "settings-sounds": SettingsSoundsPage()
        case "settings-data": SettingsDataPage()
        case "diagnostics": DiagnosticsView()
        case "whatsnew": WhatsNewView()
        case "coach": CoachView()
        case "sunday": SundayResetView()
        case "history": HistoryView()
        case "nutrition": NutritionView()
        case "recovery": RecoveryView()
        case "plan": WeekPlanView()
        case "review": WeeklyReviewView()
        case "month": MonthlyReportView()
        case "preview":
            if let routine = store.routines.first { SessionPreviewView(routine: routine) }
        case "lift":
            if let exercise = store.progressExercises.first(where: { $0.name == "Leg Press" }) ?? store.progressExercises.first {
                LiftDetailView(exercise: exercise, range: .threeMonths)
            }
        default:
            ContentUnavailableView("No demo screen called \"\(name)\"", systemImage: "questionmark.square.dashed")
        }
    }
}
