import SwiftUI

/// MK24: how to get Apple Health into Splitday every day through the Shortcuts app, which keeps its own
/// Health access when a sideloaded app loses it.
/// MK24.2: one Shortcut ("Splitday Health") does the reading; an automation runs it after the wake-up alarm,
/// and the weigh-in and sleep buttons run it on demand and come straight back.
struct HealthShortcutsView: View {
    @State private var refresh = 0
    @State private var name = HealthShortcut.name

    var body: some View {
        let _ = refresh
        List {
            Section {
                if let last = HealthBridge.last {
                    LabeledContent("Last received", value: last.date.formatted(.relative(presentation: .named)))
                    Text(last.summary).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("Nothing received yet", systemImage: "hourglass").foregroundStyle(.secondary)
                }
                HealthPullButton(purpose: .test)
            } header: {
                Text("Status")
            } footer: {
                Text("Readings land with your Apple Health export data: Body charts, the coach, the recovery score and backups all use them.")
            }

            Section {
                TextField(HealthShortcut.defaultName, text: $name)
                    .autocorrectionDisabled()
                    .onChange(of: name) { _, value in HealthShortcut.name = value }
            } header: {
                Text("Shortcut name")
            } footer: {
                Text("The buttons run the Shortcut with this name, so it has to match exactly.")
            }

            Section {
                step(1, "In Shortcuts, tap + and name the new shortcut \(HealthShortcut.name).")
                step(2, "Add Find Health Samples: Type is Sleep Analysis. Add filters Start Date is in the last 1 day, Value is not In Bed and Value is not Awake. Sort by Start Date, Oldest First, no limit.")
                step(3, "Add Get Details of Health Samples → Start Date. Add it again → End Date, and set its input (the first blue word) to the Health Samples from step 2.")
                step(4, "Add Find Health Samples: Weight, sorted by Start Date, Latest First, Limit 1. Then Get Details of Health Samples → Start Date: that's when you weighed in.")
                step(5, "The same way (Latest First, Limit 1): Body Fat Percentage, Resting Heart Rate and Heart Rate Variability.")
                step(6, "Add Send Health readings to Splitday and tap Show More. Weight → the weight sample · Weighed at → its Start Date · Body fat · Sleep starts → the Start Dates from step 3 · Sleep ends → the End Dates · Resting heart rate · HRV.")
                step(7, "Tap ▶︎ once and allow Shortcuts to read Apple Health. The status above should change.")
            } header: {
                Text("1 · The Shortcut (once)")
            } footer: {
                Text("Overlapping samples (iPhone and Watch) count once, and an afternoon nap doesn't replace last night. Body fat can come as 0.15 or 15. Leave out anything you don't track.")
            }

            Section {
                step(1, "Automation → + → Alarm. Pick Is Stopped and your wake-up alarm (or Any Alarm). Choose Run Immediately and turn off Notify When Run.")
                step(2, "Add Wait: 120 seconds. Then Run Shortcut: \(HealthShortcut.name).")
            } header: {
                Text("2 · After the wake-up alarm")
            } footer: {
                Text("Why 2 minutes and not 5: iOS ends a shortcut running in the background after about 3 minutes, so a 5-minute Wait never reaches the next step. 2 minutes gives the Watch time to hand last night over. Off the charger with the screen off, iOS can also stretch the wait; the Is Opened automation below catches whatever this one misses.")
            }

            Section {
                Text("Body → weigh-in → Get from Apple Health (it's in the weigh-in sheet too). Step on the scale, let its app sync to Apple Health, then tap: the Shortcut runs, comes straight back and today's weigh-in is saved at the time you weighed. Nothing else to set up.")
                    .font(.subheadline)
                Text("On your weigh-in day, a weight from that day arriving any other way (the alarm automation, or the one below) is saved as the weigh-in too, unless you've already logged one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("3 · Weigh-in button")
            }

            Section {
                step(1, "Automation → + → App → Splitday → Is Opened. Run Immediately, Notify When Run off.")
                step(2, "Add Run Shortcut: \(HealthShortcut.name).")
            } header: {
                Text("Recommended · Each time you open Splitday")
            } footer: {
                Text("The safety net, and no taps: weigh in, open Splitday, and it's logged; a night the alarm run missed arrives the first time you open the app. Readings Splitday already has are skipped, and a fuller copy of last night replaces an earlier one.")
            }

            Section {
                step(1, "Automation → + → App → Splitday → Is Closed, Run Immediately.")
                step(2, "Add Get Splitday workouts (last 24 hours).")
                step(3, "Add Repeat with Each. Inside it, Log Health Sample: Active Energy, the workout's Active calories, dated the workout's Start.")
                step(4, "To avoid logging the same workout twice, set the hours to how often you close the app after training (e.g. 3).")
            } header: {
                Text("Splitday → Health (after a workout)")
            } footer: {
                Text("Without a Watch reading, calories are estimated at 5 kcal a minute.")
            }
        }
        .navigationTitle("Health through Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: .healthBridgeChanged)) { _ in refresh += 1 }
        .onAppear { Usage.opened("Health through Shortcuts") }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.tint).frame(width: 18)
            Text(text).font(.subheadline)
        }
    }
}

/// MK24.2: runs the Splitday Health Shortcut, waits for it to hand back, and says what came in. For the weigh-in
/// it saves today's weigh-in from the reading; for sleep it's last night (the check-in card on Today goes once
/// it's there).
struct HealthPullButton: View {
    enum Purpose { case weighIn, sleep, test }
    let purpose: Purpose
    /// After a weigh-in was saved (the sheet closes itself).
    var onSaved: (() -> Void)? = nil
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var waiting = false
    @State private var note: String?
    @State private var good = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                note = nil
                waiting = true
                HealthShortcut.run()
            } label: {
                Label(waiting ? "Waiting for Apple Health…" : title, systemImage: "heart.text.square")
            }
            .disabled(waiting || Demo.isOn)
            if let note {
                Label(note, systemImage: good ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(good ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthShortcutReturned)) { returned in
            guard waiting else { return }
            finish(returned.object as? String)
        }
        .onChange(of: scenePhase) { _, phase in
            // Back without the return link (switched back by hand): look at what arrived after a moment.
            guard phase == .active, waiting else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if waiting { finish(nil) }
            }
        }
    }

    private var title: String {
        switch purpose {
        case .weighIn: return "Get from Apple Health"
        case .sleep: return "Get last night from Apple Health"
        case .test: return "Run it now"
        }
    }

    private func finish(_ host: String?) {
        waiting = false
        good = false
        switch host {
        case "health-error"?:
            note = "Shortcuts couldn't run \"\(HealthShortcut.name)\". Check the name in Settings → Data and devices → Daily, through Shortcuts (under Apple Health)."
            return
        case "health-cancel"?:
            note = "The Shortcut stopped before it finished."
            return
        default:
            break
        }
        guard let reading = HealthShortcut.freshReading else {
            note = "Nothing came back. The Shortcut's last action should be Send Health readings to Splitday."
            return
        }
        switch purpose {
        case .weighIn:
            let result = store.adoptHealthWeighIn(force: true)
            if let entry = result.entry {
                good = true
                note = "Saved \(WeighInSheet.summary(entry)), weighed at \(entry.date.formatted(date: .omitted, time: .shortened))."
                Haptics.success()
                onSaved?()
            } else {
                note = result.problem ?? "No weight came back."
            }
        case .sleep:
            if let night = reading.night, Calendar.current.isDateInToday(night.date) {
                good = true
                note = String(format: "Last night: %.1f h asleep.", night.hoursAsleep)
                Haptics.success()
            } else {
                note = "No night in Apple Health yet. If you've just woken up, give the Watch a few minutes to hand it over."
            }
        case .test:
            good = true
            note = "Received: " + (HealthBridge.last?.summary ?? "readings")
            Haptics.success()
        }
    }
}

/// MK24: three taps instead of sleep and heart-rate data. Shown on Today until you've checked in (or
/// when there's no recovery data at all), and from Body → Sleep & recovery.
struct ReadinessCheckInCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var sleep: Double = 7
    @State private var soreness = 1
    @State private var energy = 2
    var onSave: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How do you feel?", systemImage: "heart.text.square").font(.headline)
            // MK24.2: the Shortcut is set up, so last night can come straight from Apple Health instead.
            if HealthBridge.last != nil {
                HealthPullButton(purpose: .sleep)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Slept")
                    Spacer()
                    Text(String(format: "%.1f h", sleep)).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $sleep, in: 3...11, step: 0.5)
                    .accessibilityValue(String(format: "%.1f hours", sleep))
            }
            picker("Sore", $soreness, ["Fresh", "A bit", "Very"])
            picker("Energy", $energy, ["Low", "Normal", "High"])
            Button {
                store.saveCheckIn(ReadinessCheckIn(date: .now, sleepHours: sleep, soreness: soreness, energy: energy))
                Haptics.tap()
                onSave?()
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Text("Sets today's recovery score. A low one suggests a light session.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
        .onAppear {
            if let last = store.todaysCheckIn {
                sleep = last.sleepHours; soreness = last.soreness; energy = last.energy
            } else if let night = store.healthKit.sleep.last, Calendar.current.isDateInToday(night.date) {
                sleep = (night.hoursAsleep * 2).rounded() / 2
            }
        }
    }

    private func picker(_ title: String, _ value: Binding<Int>, _ labels: [String]) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            Picker(title, selection: value) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in Text(label).tag(index + 1) }
            }
            .pickerStyle(.segmented)
        }
    }
}
