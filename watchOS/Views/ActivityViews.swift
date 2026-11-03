import SwiftUI

/// Home → Run & basketball.
struct CardioStartView: View {
    var body: some View {
        List {
            NavigationLink {
                RunSetupView(indoor: false)
            } label: {
                Label("Outdoor run", systemImage: "figure.run")
            }
            NavigationLink {
                RunSetupView(indoor: true)
            } label: {
                Label("Treadmill run", systemImage: "figure.run.treadmill")
            }
            NavigationLink {
                BasketballSetupView()
            } label: {
                Label("Basketball", systemImage: "basketball")
            }
        }
        .navigationTitle("Cardio")
    }
}

struct RunSetupView: View {
    @EnvironmentObject private var store: WatchAppStore
    let indoor: Bool
    @State private var kind: RunGoal.Kind = .open
    @State private var km: Double = 5
    @State private var minutes: Double = 30
    @State private var pace: Double = 330   // 5:30 /km

    var body: some View {
        List {
            Picker("Goal", selection: $kind) {
                ForEach(RunGoal.Kind.allCases) { Text($0.title).tag($0) }
            }
            switch kind {
            case .distance:
                Stepper("\(GFFormat.km(km)) km", value: $km, in: 1...42, step: 0.5)
            case .time:
                Stepper("\(Int(minutes)) min", value: $minutes, in: 10...180, step: 5)
            case .pace:
                Stepper("\(CardioFormat.pace(pace)) /km", value: $pace, in: 180...600, step: 5)
            case .open:
                EmptyView()
            }
            Button {
                let goal: RunGoal? = kind == .open ? nil : RunGoal(kind: kind, distanceKm: kind == .distance ? km : nil,
                                                                   minutes: kind == .time ? minutes : nil,
                                                                   paceSeconds: kind == .pace ? pace : nil)
                Task { await store.startActivity(kind: .run, indoor: indoor, goal: goal, basketballType: nil) }
            } label: {
                Label("Start", systemImage: "play.fill").bold().frame(maxWidth: .infinity)
            }
            .tint(.green)
        }
        .navigationTitle(indoor ? "Treadmill" : "Outdoor")
    }
}

struct BasketballSetupView: View {
    @EnvironmentObject private var store: WatchAppStore
    @State private var type: BasketballType = .game

    var body: some View {
        List {
            Picker("Type", selection: $type) {
                ForEach(BasketballType.allCases) { Text($0.title).tag($0) }
            }
            Button {
                Task { await store.startActivity(kind: .basketball, indoor: true, goal: nil, basketballType: type) }
            } label: {
                Label("Start", systemImage: "play.fill").bold().frame(maxWidth: .infinity)
            }
            .tint(.orange)
        }
        .navigationTitle("Basketball")
    }
}

/// Live screen: swipe up for pause / end.
struct ActivityLiveView: View {
    @ObservedObject private var activity = WatchActivityManager.shared
    @State private var confirmDiscard = false

    var body: some View {
        TabView {
            metrics
            controls
        }
        .tabViewStyle(.verticalPage)
    }

    private var zoneColor: Color {
        switch activity.zone {
        case 0?: return .gray
        case 1?: return .blue
        case 2?: return .green
        case 3?: return .orange
        case 4?: return .red
        default: return .secondary
        }
    }

    private var metrics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 2) {
                if let banner = activity.banner {
                    Text(banner)
                        .font(.caption.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.yellow))
                }
                Text(GFFormat.duration(activity.elapsed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(activity.isPaused ? .orange : .yellow)
                if activity.request?.kind == .run {
                    Text("\(String(format: "%.2f", activity.distanceKm)) km")
                        .font(.title3.bold().monospacedDigit())
                    HStack {
                        Text("\(CardioFormat.pace(activity.currentPace ?? 0)) /km")
                        Spacer()
                        Text("avg \(CardioFormat.pace(activity.distanceKm > 0.05 ? activity.elapsed / activity.distanceKm : 0))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.monospacedDigit())
                } else {
                    Text("\(Int(activity.activeCalories)) kcal")
                        .font(.title3.bold().monospacedDigit())
                }
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(activity.heartRate > 0 ? "\(Int(activity.heartRate))" : "--")
                        .font(.title3.bold().monospacedDigit())
                    if let zone = activity.zone {
                        Text("Z\(zone + 1)")
                            .font(.caption.bold())
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(zoneColor))
                    }
                }
                if let goal = activity.request?.goal {
                    Text(goal.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                if activity.isPaused { activity.resume() } else { activity.pause() }
            } label: {
                Label(activity.isPaused ? "Resume" : "Pause", systemImage: activity.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.yellow)
            Button {
                Task { await activity.end() }
            } label: {
                Label(activity.isEnding ? "Saving…" : "End", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.red)
            .disabled(activity.isEnding)
            Button("Discard", role: .destructive) { confirmDiscard = true }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(activity.isEnding)
            if let cadence = activity.cadence {
                Text("\(Int(cadence)) spm" + (activity.powerWatts.map { " · \(Int($0)) W" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Discard this session? Nothing is saved.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { activity.discard() }
            Button("Keep going", role: .cancel) {}
        }
    }
}

struct ActivitySummaryView: View {
    @ObservedObject private var activity = WatchActivityManager.shared
    let session: CardioSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.headline)
                Text(session.title).font(.title3.bold())
                row("Time", GFFormat.duration(session.activeSeconds))
                if let km = session.distanceKm, km > 0 { row("Distance", "\(String(format: "%.2f", km)) km") }
                if let pace = session.averagePace { row("Avg pace", "\(CardioFormat.pace(pace)) /km") }
                if let hr = session.averageHeartRate { row("Avg HR", "\(Int(hr))") }
                if let kcal = session.activeCalories { row("Active kcal", "\(Int(kcal))") }
                if session.kind == .basketball { row("Effort", "\(session.effortScore)/10") }
                ForEach(Array(session.splits.enumerated()), id: \.offset) { index, split in
                    row("Km \(index + 1)", CardioFormat.pace(split))
                }
                Button("Done") { activity.summary = nil }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}
