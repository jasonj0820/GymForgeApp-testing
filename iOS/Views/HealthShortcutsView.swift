import SwiftUI

/// MK24: how to get Apple Health into Splitday every day through the Shortcuts app, which keeps its own
/// Health access when a sideloaded app loses it. Two automations, set up once.
struct HealthShortcutsView: View {
    @State private var refresh = 0

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
            } header: {
                Text("Status")
            } footer: {
                Text("Readings land with your Apple Health export data: Body charts, the coach, the recovery score and backups all use them.")
            }

            Section {
                step(1, "Open Shortcuts → Automation → + → Time of Day. Pick a morning time after your scale and Watch have synced (e.g. 9:30), Daily, and Run Immediately.")
                step(2, "Add Find Health Samples: Weight, Sort by Start Date, Latest First, Limit 1. Do the same for Body Fat Percentage, Resting Heart Rate and Heart Rate Variability.")
                step(3, "For sleep, add Find Health Samples: Sleep, Start Date is in the last 1 day, Value is Asleep (or Core, Deep and REM). Then Calculate Statistics → Sum of their Duration, and Convert it to hours.")
                step(4, "Add Send Health readings to Splitday, and fill each box with the matching result. Leave out anything you don't track.")
                step(5, "Run it once by hand. Allow Shortcuts to read Health when it asks; the status above should change.")
            } header: {
                Text("Health → Splitday (each morning)")
            } footer: {
                Text("Body fat can be passed as 0.15 or 15: both are read as 15%. Empty or zero values are ignored.")
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
