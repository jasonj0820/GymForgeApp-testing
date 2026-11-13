import SwiftUI
import Charts
import Combine

/// Stamina training: goal timer with 1-minute cool-down pauses.
///
/// MK22.1: this screen also turns sideways. With a session running, landscape shows just the timer (large,
/// on the left) and its buttons (on the right).
struct MTStaminaView: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var finishing = false
    @State private var finishNote = ""
    @State private var withPorn: Bool?
    @State private var confirmCancel = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if verticalSizeClass == .compact, let run = vault.data.activeStamina {
                sideways(run)
            } else {
                List {
                    if let run = vault.data.activeStamina {
                        runningSection(run)
                    } else {
                        startSection
                    }
                    statsSection
                    historySection
                }
            }
        }
        .navigationTitle("Stamina")
        .onReceive(ticker) { _ in vault.tickStamina() }
        .alert("Finish session", isPresented: $finishing) {
            TextField("Notes (optional)", text: $finishNote)
            Button("Save") {
                vault.finishStamina(notes: finishNote)
                finishNote = ""
            }
            Button("Keep going", role: .cancel) {}
        }
        // MK22.1: one stray tap used to throw the session away.
        .confirmationDialog("Cancel without saving?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Discard session", role: .destructive) { vault.cancelStamina() }
            Button("Keep going", role: .cancel) {}
        }
        .onAppear { OrientationLock.allowLandscape(true, for: "mt.stamina") }
        .onDisappear { OrientationLock.allowLandscape(false, for: "mt.stamina") }
    }

    // MARK: Start

    private var startSection: some View {
        Section {
            Picker("Session", selection: Binding(
                get: { withPorn ?? vault.data.settings.staminaLastWithPorn ?? false },
                set: { withPorn = $0 }
            )) {
                Text("Without porn").tag(false)
                Text("With porn").tag(true)
            }
            .pickerStyle(.segmented)
            Stepper("Goal: \(vault.data.settings.staminaGoal) min", value: goalBinding, in: 1...90)
            if let suggestion = MTStamina.suggestedGoal(vault.data.staminaList, currentMinutes: vault.data.settings.staminaGoal,
                                                        withPorn: selectedMode) {
                Button {
                    goalBinding.wrappedValue = suggestion
                } label: {
                    Label("You've hit your goal 3 times with ≤1 pause — raise to \(suggestion) min?", systemImage: "arrow.up.circle.fill")
                        .font(.subheadline)
                }
            }
            Button {
                vault.startStamina(goalMinutes: vault.data.settings.staminaGoal, withPorn: selectedMode)
            } label: {
                Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        } footer: {
            Text("When you feel close, tap Cool down — the goal timer stops for \(vault.data.settings.cooldownSeconds) s, then resume. In another app, press and hold the Dynamic Island for the same button; it's on the Lock Screen card and the widget too.")
        }
    }

    private var selectedMode: Bool { withPorn ?? vault.data.settings.staminaLastWithPorn ?? false }

    private var goalBinding: Binding<Int> {
        Binding(
            get: { vault.data.settings.staminaGoal },
            set: { value in
                var settings = vault.data.settings
                settings.staminaGoal = value
                vault.updateSettings(settings)
            }
        )
    }

    // MARK: Running

    private func runningSection(_ run: MTActiveStamina) -> some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                runningClock(run, now: context.date, clockSize: 56)
                    .frame(maxWidth: .infinity)
            }
            runningButtons(run)
        } header: {
            Text("Session")
        }
    }

    /// MK22.1: iPhone on its side — the time large on the left, the buttons on the right.
    private func sideways(_ run: MTActiveStamina) -> some View {
        HStack(spacing: 24) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                runningClock(run, now: context.date, clockSize: 104)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ViewThatFits(in: .vertical) {
                VStack(spacing: 12) { runningButtons(run) }
                ScrollView { VStack(spacing: 12) { runningButtons(run) } }
            }
            .frame(width: 260)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func runningClock(_ run: MTActiveStamina, now: Date, clockSize: CGFloat) -> some View {
        let active = run.active(at: now)
        let reached = active >= run.goalSeconds
        return VStack(spacing: 10) {
            if let until = run.cooldownUntil {
                let left = until.timeIntervalSince(now)
                Text(left > 0 ? "COOL DOWN" : "READY")
                    .font(.caption.bold())
                    .foregroundStyle(left > 0 ? Color.cyan : Color.green)
                Text(MTStats.clock(max(0, left)))
                    .font(.system(size: clockSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(left > 0 ? Color.cyan : Color.green)
                Text("Goal timer paused at \(MTStats.clock(active))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(reached ? "GOAL REACHED" : "TIME")
                    .font(.caption.bold())
                    .foregroundStyle(reached ? Color.green : Color.blue)
                Text(MTStats.clock(active))
                    .font(.system(size: clockSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(reached ? Color.green : Color.primary)
                Text("Goal \(MTStats.clock(run.goalSeconds)) · \(run.withPorn == true ? "with porn" : "without porn")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            SwiftUI.ProgressView(value: min(active, run.goalSeconds), total: max(run.goalSeconds, 1))
                .tint(reached ? .green : .blue)
            Text("Pauses: \(run.pauses)").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func runningButtons(_ run: MTActiveStamina) -> some View {
        if run.isCoolingDown {
            HStack {
                Button {
                    vault.staminaExtendCooldown(seconds: 30)
                } label: {
                    Text("+30 s").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    vault.staminaResume()
                } label: {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        } else {
            Button {
                vault.staminaCoolDown()
            } label: {
                Label("Close — cool down", systemImage: "snowflake")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }

        Button {
            finishing = true
        } label: {
            Label("Finish & save", systemImage: "checkmark").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        Button("Cancel without saving", role: .destructive) { confirmCancel = true }
    }

    // MARK: Stats

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let minutes: Double
        let pauses: Int
        let reached: Bool
        let series: String
    }

    private static func seriesName(_ withPorn: Bool?) -> String { withPorn == true ? "With porn" : "Without porn" }

    /// Each session's time, plus a running average of the last 5 sessions of the same kind.
    private func points(_ sessions: [MTStaminaSession]) -> (raw: [Point], average: [Point]) {
        var raw: [Point] = []
        var average: [Point] = []
        for mode in [false, true] {
            let group = sessions.filter { ($0.withPorn ?? false) == mode }
            for (index, session) in group.enumerated() {
                let window = group[max(0, index - 4)...index]
                let mean = window.map(\.activeSeconds).reduce(0, +) / Double(window.count) / 60
                let name = Self.seriesName(mode)
                raw.append(Point(id: session.id, date: session.start, minutes: session.activeSeconds / 60,
                                 pauses: session.pauses, reached: session.reachedGoal, series: name))
                average.append(Point(id: session.id, date: session.start, minutes: mean,
                                     pauses: session.pauses, reached: session.reachedGoal, series: name))
            }
        }
        return (raw, average)
    }

    @ViewBuilder
    private var statsSection: some View {
        let sessions = vault.data.staminaList.sorted { $0.start < $1.start }
        if !sessions.isEmpty {
            let chart = points(Array(sessions.suffix(60)))
            let without = sessions.filter { $0.withPorn != true }
            let with = sessions.filter { $0.withPorn == true }
            let recent = Array(sessions.suffix(10))
            let hitRate = Double(recent.filter(\.reachedGoal).count) / Double(max(recent.count, 1))
            let avgPauses = Double(recent.map(\.pauses).reduce(0, +)) / Double(max(recent.count, 1))

            Section("Progress") {
                HStack {
                    stat("Avg without", averageText(without))
                    stat("Avg with", averageText(with))
                    stat("Goal hit", "\(Int((hitRate * 100).rounded()))%")
                }
                Text("Average time lasted").font(.subheadline.bold())
                Chart {
                    ForEach(chart.average) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Minutes", point.minutes))
                            .foregroundStyle(by: .value("Session", point.series))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(chart.raw) { point in
                        PointMark(x: .value("Date", point.date), y: .value("Minutes", point.minutes))
                            .foregroundStyle(by: .value("Session", point.series))
                            .opacity(0.35)
                            .symbolSize(25)
                    }
                }
                .chartForegroundStyleScale(["Without porn": Color.blue, "With porn": Color.orange])
                .chartYAxisLabel("min")
                .frame(height: 200)
                Text("Lines are the running average of your last 5 sessions of each kind; faint dots are single sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Pauses per session").font(.subheadline.bold())
                Chart(chart.raw) { point in
                    PointMark(x: .value("Date", point.date), y: .value("Pauses", point.pauses))
                        .foregroundStyle(by: .value("Session", point.series))
                }
                .chartForegroundStyleScale(["Without porn": Color.blue, "With porn": Color.orange])
                .frame(height: 120)
                Text(String(format: "Avg %.1f pauses over your last 10 sessions.", avgPauses))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func averageText(_ sessions: [MTStaminaSession]) -> String {
        guard !sessions.isEmpty else { return "–" }
        return MTStats.clock(sessions.map(\.activeSeconds).reduce(0, +) / Double(sessions.count))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: History

    private var historySection: some View {
        Section("History") {
            let sessions = vault.data.staminaList.sorted { $0.start > $1.start }
            if sessions.isEmpty {
                Text("No sessions yet").foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                HStack {
                    Image(systemName: session.reachedGoal ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(session.reachedGoal ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(MTStats.clock(session.activeSeconds)) of \(MTStats.clock(session.goalSeconds))")
                        Text("\(session.start.formatted(date: .abbreviated, time: .shortened)) · \(session.pauses) pause\(session.pauses == 1 ? "" : "s") · \(session.withPorn == true ? "with porn" : "without porn")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let notes = session.notes {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { vault.deleteStamina(session.id) }
                    Button(session.withPorn == true ? "Mark without" : "Mark with") {
                        vault.setStaminaTag(session.id, withPorn: session.withPorn != true)
                    }
                    .tint(.orange)
                }
            }
        }
    }
}
