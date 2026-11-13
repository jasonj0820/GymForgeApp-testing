import Charts
import MapKit
import SwiftUI

/// Today card: start a run or basketball (the Watch opens and records), plus a live readout.
struct CardioStartCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var setup: ActivityKind?
    @State private var logging: ActivityKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cardio").font(.headline)
                Spacer()
                NavigationLink {
                    CardioHistoryView()
                } label: {
                    Text("History").font(.subheadline)
                }
            }
            if let live = store.liveCardio {
                Label(live.kind == .run
                      ? "\(live.title): \(String(format: "%.2f", live.distanceKm)) km · \(CardioFormat.pace(live.paceSeconds ?? 0)) /km"
                      : "\(live.title): \(GFFormat.duration(live.elapsed))",
                      systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
            }
            HStack {
                Button { setup = .run } label: {
                    Label("Run", systemImage: "figure.run").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button { setup = .basketball } label: {
                    Label("Basketball", systemImage: "basketball").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .disabled(store.activeWorkout != nil || store.phoneRecorder.isActive)
            Menu {
                Button("Log a run") { logging = .run }
                Button("Log basketball") { logging = .basketball }
            } label: {
                Label("Log one you didn't record", systemImage: "square.and.pencil").font(.caption)
            }
        }
        .card()
        .sheet(item: $setup) { kind in
            NavigationStack { ActivityStartSheet(kind: kind) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $logging) { kind in
            NavigationStack { ManualCardioLogView(kind: kind) }
        }
    }
}

struct ActivityStartSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let kind: ActivityKind
    @State private var indoor = false
    @State private var goalKind: RunGoal.Kind = .open
    @State private var km: Double = 5
    @State private var minutes: Double = 30
    @State private var pace: Double = 330
    @State private var type: BasketballType = .game
    @State private var onWatch = true

    var body: some View {
        Form {
            Picker("Record with", selection: $onWatch) {
                Label("Apple Watch", systemImage: "applewatch").tag(true)
                Label("iPhone", systemImage: "iphone").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(!store.watchAvailableForCardio)
            if kind == .run {
                Picker("Where", selection: $indoor) {
                    Text("Outdoor").tag(false)
                    Text("Treadmill").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Goal", selection: $goalKind) {
                    ForEach(RunGoal.Kind.allCases) { Text($0.title).tag($0) }
                }
                switch goalKind {
                case .distance: Stepper("\(GFFormat.km(km)) km", value: $km, in: 1...42, step: 0.5)
                case .time: Stepper("\(Int(minutes)) min", value: $minutes, in: 10...180, step: 5)
                case .pace: Stepper("Hold \(CardioFormat.pace(pace)) /km", value: $pace, in: 180...600, step: 5)
                case .open: EmptyView()
                }
            } else {
                Picker("Session", selection: $type) {
                    ForEach(BasketballType.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Button {
                    let goal: RunGoal? = kind == .run && goalKind != .open
                        ? RunGoal(kind: goalKind, distanceKm: goalKind == .distance ? km : nil,
                                  minutes: goalKind == .time ? minutes : nil, paceSeconds: goalKind == .pace ? pace : nil)
                        : nil
                    if onWatch {
                        store.startActivity(kind: kind, indoor: kind == .basketball || indoor, goal: goal,
                                            basketballType: kind == .basketball ? type : nil)
                    } else {
                        store.startPhoneActivity(kind: kind, indoor: indoor, goal: goal,
                                                 basketballType: kind == .basketball ? type : nil)
                    }
                    dismiss()
                } label: {
                    Label(onWatch ? "Start on Apple Watch" : "Start on iPhone", systemImage: onWatch ? "applewatch" : "iphone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(kind == .run ? "Run" : "Basketball")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { onWatch = store.watchAvailableForCardio }
    }

    private var footer: String {
        if !onWatch {
            if kind == .basketball { return "Timer on your iPhone (no heart rate). Rate how hard it was at the end; add minutes and shots." }
            return indoor
                ? "Timer on your iPhone. Type the treadmill's distance and rate the effort at the end."
                : "Your iPhone's GPS: distance, pace, km splits, auto-pause and the route. Keep the phone on you (pocket or armband); no heart rate — rate the effort at the end."
        }
        if !store.watchAvailableForCardio { return "No Apple Watch set up — recording on your iPhone." }
        return kind == .run
            ? (indoor ? "Treadmill: no GPS — the Watch estimates distance; you can correct it with the treadmill's number afterwards."
                      : "Outdoor: GPS route, km splits with a wrist tap, auto-pause at stops. Saved to Apple Health with the route.")
            : "Heart rate, zones and calories, saved to Apple Health as Basketball. Add shots and minutes afterwards."
    }
}

private struct EfficiencyPoint: Identifiable {
    let id: UUID
    let date: Date
    let value: Double
}

/// Run and basketball history, best times and the fitness trend.
struct CardioHistoryView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var deleting: CardioSession?

    var body: some View {
        let runs = store.runs
        let games = store.cardioSessions.filter { $0.kind == .basketball }.sorted { $0.startedAt > $1.startedAt }
        let efficiency = runs.reversed().compactMap { run in run.efficiency.map { EfficiencyPoint(id: run.id, date: run.startedAt, value: $0) } }
        List {
            if !runs.isEmpty {
                Section("Best times") {
                    if let best = RunStats.best1k(runs) {
                        LabeledContent("1 km", value: "\(CardioFormat.pace(best.seconds)) · \(best.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if let best = RunStats.best5k(runs) {
                        LabeledContent("5 km", value: "\(GFFormat.duration(best.seconds)) · \(best.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if RunStats.best1k(runs) == nil {
                        Text("Bests appear after your first full km.").foregroundStyle(.secondary)
                    }
                }
            }
            if efficiency.count >= 2 {
                Section {
                    Chart(efficiency) { point in
                        LineMark(x: .value("Date", point.date), y: .value("m/beat", point.value))
                        PointMark(x: .value("Date", point.date), y: .value("m/beat", point.value))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                } header: {
                    Text("Running fitness")
                } footer: {
                    Text("Metres per heartbeat: going up means you run the same pace with a lower heart rate — your aerobic fitness improving. Compare easy runs with easy runs.")
                }
            }
            Section("Runs") {
                if runs.isEmpty { Text("No runs yet.").foregroundStyle(.secondary) }
                ForEach(runs) { run in
                    NavigationLink { RunDetailView(session: run) } label: { row(run) }
                }
                .onDelete { offsets in if let index = offsets.first { deleting = runs[index] } }   // MK22.1: asks first
            }
            Section("Basketball") {
                if games.isEmpty { Text("No basketball yet.").foregroundStyle(.secondary) }
                ForEach(games) { game in
                    NavigationLink { BasketballDetailView(session: game) } label: { row(game) }
                }
                .onDelete { offsets in if let index = offsets.first { deleting = games[index] } }
            }
        }
        .navigationTitle("Cardio")
        .confirmationDialog("Delete this session?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { session in
            Button("Delete \(session.title)", role: .destructive) { store.deleteCardio(session) }
            Button("Keep it", role: .cancel) {}
        } message: { session in
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .omitted)). This can't be undone.")
        }
    }

    private func row(_ session: CardioSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(session.title).font(.headline)
                Spacer()
                Text(session.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(session.kind == .run
                 ? "\(String(format: "%.2f", session.distanceKm ?? 0)) km · \(CardioFormat.pace(session.averagePace ?? 0)) /km · \(GFFormat.duration(session.activeSeconds))"
                 : "\(GFFormat.duration(session.activeSeconds))" + (session.effortRating.map { " · effort \($0)/10" } ?? "") + (session.averageHeartRate.map { " · \(Int($0)) bpm" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct RunDetailView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let session: CardioSession
    @State private var correcting = false
    @State private var distanceText = ""

    private var current: CardioSession { store.cardioSessions.first { $0.id == session.id } ?? session }

    var body: some View {
        let run = current
        List {
            if let route = run.route, route.count >= 2 {
                Section {
                    Map {
                        MapPolyline(coordinates: route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                            .stroke(.orange, lineWidth: 4)
                    }
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                LabeledContent("Distance", value: "\(String(format: "%.2f", run.distanceKm ?? 0)) km" + (run.distanceCorrected == true ? " (corrected)" : ""))
                LabeledContent("Time", value: GFFormat.duration(run.activeSeconds))
                LabeledContent("Average pace", value: "\(CardioFormat.pace(run.averagePace ?? 0)) /km")
                if let hr = run.averageHeartRate { LabeledContent("Average heart rate", value: "\(Int(hr)) bpm") }
                if let max = run.maxHeartRate { LabeledContent("Max heart rate", value: "\(Int(max)) bpm") }
                if let kcal = run.activeCalories { LabeledContent("Active calories", value: "\(Int(kcal)) kcal") }
                if let goal = run.goal { LabeledContent("Goal", value: goalResult(goal, run)) }
                if run.indoor {
                    Button("Correct distance (treadmill)") {
                        distanceText = String(format: "%.2f", run.distanceKm ?? 0)
                        correcting = true
                    }
                }
            } header: {
                Text("\(run.title) · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
            }
            Section {
                EffortScale(effort: Binding(
                    get: { current.effort ?? current.effortRating ?? 6 },
                    set: { value in
                        var updated = current
                        updated.effort = value
                        store.updateCardio(updated)
                    }))
            } footer: {
                Text("Training load \(Int(run.sessionLoad)) (effort × minutes)" + (run.effort == nil ? " — rate it so the coach knows how hard it was." : "."))
            }
            if !run.splits.isEmpty {
                Section("Splits") {
                    Chart(Array(run.splits.enumerated()), id: \.offset) { index, split in
                        BarMark(x: .value("Km", "\(index + 1)"), y: .value("Min/km", split / 60))
                            .foregroundStyle(.green)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                    ForEach(Array(run.splits.enumerated()), id: \.offset) { index, split in
                        LabeledContent("Km \(index + 1)", value: CardioFormat.pace(split))
                    }
                }
            }
            ZoneSection(session: run)
            if run.cadence != nil || run.powerWatts != nil || run.strideMeters != nil {
                Section("Running form") {
                    if let cadence = run.cadence { LabeledContent("Cadence", value: "\(Int(cadence)) steps/min") }
                    if let stride = run.strideMeters { LabeledContent("Stride length", value: String(format: "%.2f m", stride)) }
                    if let power = run.powerWatts { LabeledContent("Power", value: "\(Int(power)) W") }
                }
            }
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Treadmill distance (km)", isPresented: $correcting) {
            TextField("km", text: $distanceText).keyboardType(.decimalPad)
            Button("Save") {
                if let km = Double(distanceText.replacingOccurrences(of: ",", with: ".")), km > 0 {
                    var updated = current
                    updated.distanceKm = km
                    updated.distanceCorrected = true
                    store.updateCardio(updated)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func goalResult(_ goal: RunGoal, _ run: CardioSession) -> String {
        switch goal.kind {
        case .open: return "Open"
        case .distance:
            let target = goal.distanceKm ?? 0
            return (run.distanceKm ?? 0) >= target ? "\(GFFormat.km(target)) km ✓" : "\(GFFormat.km(target)) km — not reached"
        case .time:
            let target = goal.minutes ?? 0
            return run.activeSeconds >= target * 60 ? "\(Int(target)) min ✓" : "\(Int(target)) min — not reached"
        case .pace:
            let target = goal.paceSeconds ?? 0
            let pace = run.averagePace ?? .infinity
            return pace <= target + 5 ? "Held \(CardioFormat.pace(target)) /km ✓" : "Aimed \(CardioFormat.pace(target)), ran \(CardioFormat.pace(pace))"
        }
    }
}

struct BasketballDetailView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let session: CardioSession

    private var current: CardioSession { store.cardioSessions.first { $0.id == session.id } ?? session }

    var body: some View {
        let game = current
        List {
            Section {
                LabeledContent("Time", value: GFFormat.duration(game.activeSeconds))
                LabeledContent("Training load", value: "\(Int(game.sessionLoad))")
                if let hr = game.averageHeartRate { LabeledContent("Average heart rate", value: "\(Int(hr)) bpm") }
                if let max = game.maxHeartRate { LabeledContent("Max heart rate", value: "\(Int(max)) bpm") }
                if let kcal = game.activeCalories { LabeledContent("Active calories", value: "\(Int(kcal)) kcal") }
                Picker("Session", selection: binding(\.basketballType, default: .game)) {
                    ForEach(BasketballType.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text(game.startedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                EffortScale(effort: binding(\.effort, default: game.effortRating ?? 6))
            } footer: {
                Text(game.effort == nil ? "Rate it so the coach knows how hard it was on your legs." : "")
            }
            Section {
                Stepper("Minutes played: \(Int(game.minutesPlayed ?? 0))",
                        value: binding(\.minutesPlayed, default: 0), in: 0...240, step: 1)
                Stepper("Shots made: \(game.shotsMade ?? 0)", value: binding(\.shotsMade, default: 0), in: 0...500)
                Stepper("Shots attempted: \(game.shotsAttempted ?? 0)", value: binding(\.shotsAttempted, default: 0), in: 0...500)
                if let percent = game.shootingPercent {
                    LabeledContent("Shooting", value: String(format: "%.0f%%", percent))
                }
            } header: {
                Text("Your numbers")
            }
            ZoneSection(session: game)
        }
        .navigationTitle("Basketball")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CardioSession, Value?>, default fallback: Value) -> Binding<Value> {
        Binding(
            get: { current[keyPath: keyPath] ?? fallback },
            set: { value in
                var updated = current
                updated[keyPath: keyPath] = value
                // You can't make more shots than you took.
                let made = updated.shotsMade ?? 0
                let attempted = updated.shotsAttempted ?? 0
                if made > attempted {
                    if (keyPath as AnyKeyPath) == (\CardioSession.shotsMade as AnyKeyPath) {
                        updated.shotsAttempted = made
                    } else {
                        updated.shotsMade = attempted
                    }
                }
                store.updateCardio(updated)
            }
        )
    }
}

/// Time in heart-rate zones 1–5.
struct ZoneSection: View {
    let session: CardioSession

    var body: some View {
        let total = session.zoneSeconds.reduce(0, +)
        if total > 0 {
            Section {
                ForEach(0..<min(5, session.zoneSeconds.count), id: \.self) { index in
                    let seconds = session.zoneSeconds[index]
                    HStack {
                        Text("Zone \(index + 1)").frame(width: 64, alignment: .leading)
                        SwiftUI.ProgressView(value: seconds, total: total)
                            .tint([Color.gray, .blue, .green, .orange, .red][index])
                        Text(GFFormat.duration(seconds)).font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Heart-rate zones")
            } footer: {
                Text("Zones are % of your max heart rate (set it in Settings, or it's estimated from your workouts). Zone 2 builds the base; zones 4–5 are hard efforts.")
            }
        }
    }
}
