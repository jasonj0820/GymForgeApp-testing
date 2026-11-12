import SwiftUI

/// Shows the iPhone run / basketball screen while recording, and the "how hard was it?" sheet after.
struct PhoneRecorderPresenter: ViewModifier {
    @EnvironmentObject private var store: PhoneAppStore
    @ObservedObject var recorder: PhoneActivityRecorder

    func body(content: Content) -> some View {
        // One full-screen cover for both steps (recording, then "how hard was it?").
        content
            .fullScreenCover(isPresented: Binding(get: { recorder.isActive || recorder.pendingFinish != nil }, set: { _ in })) {
                Group {
                    if recorder.isActive {
                        PhoneActivityLiveView(recorder: recorder)
                    } else if let session = recorder.pendingFinish {
                        NavigationStack { PhoneActivityFinishView(session: session) }
                    }
                }
                .environmentObject(store)
            }
    }
}

/// Recording on the iPhone: big numbers, pause / finish.
struct PhoneActivityLiveView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @ObservedObject var recorder: PhoneActivityRecorder
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label(recorder.request?.title ?? "", systemImage: recorder.request?.kind == .basketball ? "basketball" : "figure.run")
                    .font(.headline)
                Spacer()
                Label("iPhone", systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
            }
            if let banner = recorder.banner {
                Text(banner)
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.yellow))
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 10) {
                    Text(GFFormat.duration(recorder.elapsed))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(recorder.isPaused ? .orange : .primary)
                    if recorder.usesGPS {
                        Text("\(String(format: "%.2f", recorder.distanceKm)) km")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        HStack(spacing: 24) {
                            metric("Pace", "\(CardioFormat.pace(recorder.currentPace ?? 0)) /km")
                            metric("Average", "\(CardioFormat.pace(recorder.averagePace ?? 0)) /km")
                        }
                    }
                    if let goal = recorder.request?.goal {
                        Text(goal.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if recorder.isPaused {
                        Text(recorder.autoPaused ? "Auto-paused — starts again when you move" : "Paused")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            if recorder.locationDenied && recorder.usesGPS {
                Label("Location is off for Splitday, so there's no distance. Turn it on in Settings → Privacy → Location Services.",
                      systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if recorder.gpsWeak {
                Label("Weak GPS — distance may lag.", systemImage: "location.slash").font(.footnote).foregroundStyle(.orange)
            }
            if !recorder.splits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(recorder.splits.enumerated()), id: \.offset) { index, split in
                            Text("Km \(index + 1) · \(CardioFormat.pace(split))")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if recorder.isPaused { recorder.resume() } else { recorder.pause() }
                } label: {
                    Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                Button {
                    confirmFinish = true
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            Button("Discard", role: .destructive) { confirmDiscard = true }
                .font(.footnote)
        }
        .padding()
        .confirmationDialog("Finish this session?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish") { recorder.finish() }
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Discard? Nothing is saved.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.discardPhoneActivity() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
    }
}

/// 1–10 effort scale in plain words.
struct EffortScale: View {
    @Binding var effort: Int

    static func label(_ value: Int) -> String {
        switch value {
        case ...2: return "Very easy"
        case 3...4: return "Easy — could chat"
        case 5...6: return "Moderate — short sentences"
        case 7...8: return "Hard — a few words"
        case 9: return "Very hard"
        default: return "All out"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("How hard was it?")
                Spacer()
                Text("\(effort)/10").bold().monospacedDigit()
            }
            Slider(value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 1...10, step: 1)
            Text(Self.label(effort)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// After an iPhone session: effort (instead of heart rate), treadmill distance, basketball numbers.
struct PhoneActivityFinishView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let session: CardioSession
    @State private var effort = 6
    @State private var kmText = ""
    @State private var minutesPlayed: Double = 0
    @State private var made = 0
    @State private var attempted = 0
    @State private var confirmDiscard = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Time", value: GFFormat.duration(session.activeSeconds))
                if let km = session.distanceKm {
                    LabeledContent("Distance", value: "\(String(format: "%.2f", km)) km")
                }
                if let pace = session.averagePace {
                    LabeledContent("Average pace", value: "\(CardioFormat.pace(pace)) /km")
                }
            } header: {
                Text(session.title)
            }
            Section {
                EffortScale(effort: $effort)
            } footer: {
                Text("No heart rate without the Watch, so your rating sets this session's training load (effort × minutes) for the coach.")
            }
            if session.kind == .run && session.indoor {
                Section("Treadmill distance") {
                    TextField("km from the treadmill", text: $kmText)
                        .keyboardType(.decimalPad)
                }
            }
            if session.kind == .basketball {
                Section("Your numbers") {
                    Stepper("Minutes played: \(Int(minutesPlayed))", value: $minutesPlayed, in: 0...240, step: 1)
                    Stepper("Shots made: \(made)", value: $made, in: 0...500)
                    Stepper("Shots attempted: \(attempted)", value: $attempted, in: 0...500)
                }
            }
            Section {
                Button {
                    store.savePhoneActivity(finished)
                } label: {
                    Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Discard", role: .destructive) { confirmDiscard = true }
            }
        }
        .navigationTitle("Nice work")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if minutesPlayed == 0 { minutesPlayed = (session.activeSeconds / 60).rounded() }
        }
        .onChange(of: made) { _, value in if value > attempted { attempted = value } }
        .onChange(of: attempted) { _, value in if value < made { made = value } }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.discardPhoneActivity() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var finished: CardioSession {
        var result = session
        result.effort = effort
        if session.kind == .run && session.indoor,
           let km = Double(kmText.replacingOccurrences(of: ",", with: ".")), km > 0 {
            result.distanceKm = km
        }
        if session.kind == .basketball {
            result.minutesPlayed = minutesPlayed > 0 ? minutesPlayed : nil
            result.shotsMade = attempted > 0 ? made : nil
            result.shotsAttempted = attempted > 0 ? attempted : nil
        }
        return result
    }
}

/// A run or game you didn't record: log it afterwards.
struct ManualCardioLogView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let kind: ActivityKind
    @State private var date = Date().addingTimeInterval(-3600)
    @State private var minutes: Double = 30
    @State private var indoor = false
    @State private var kmText = ""
    @State private var effort = 6
    @State private var type: BasketballType = .game
    @State private var made = 0
    @State private var attempted = 0

    var body: some View {
        Form {
            Section {
                DatePicker("Started", selection: $date, in: ...Date())
                Stepper("Duration: \(Int(minutes)) min", value: $minutes, in: 5...300, step: 5)
                if kind == .run {
                    Picker("Where", selection: $indoor) {
                        Text("Outdoor").tag(false)
                        Text("Treadmill").tag(true)
                    }
                    TextField("Distance (km)", text: $kmText).keyboardType(.decimalPad)
                } else {
                    Picker("Session", selection: $type) {
                        ForEach(BasketballType.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Shots made: \(made)", value: $made, in: 0...500)
                    Stepper("Shots attempted: \(attempted)", value: $attempted, in: 0...500)
                }
            }
            Section {
                EffortScale(effort: $effort)
            }
            Section {
                Button {
                    var session = CardioSession(id: UUID(), kind: kind, indoor: kind == .basketball || indoor, startedAt: date,
                                                endedAt: date.addingTimeInterval(minutes * 60), activeSeconds: minutes * 60,
                                                distanceKm: kind == .run ? Double(kmText.replacingOccurrences(of: ",", with: ".")) : nil,
                                                basketballType: kind == .basketball ? type : nil)
                    session.effort = effort
                    if kind == .basketball {
                        session.minutesPlayed = minutes
                        if attempted > 0 {
                            session.shotsMade = made
                            session.shotsAttempted = attempted
                        }
                    }
                    store.logManualActivity(session)
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } footer: {
                Text("Shows on your week row (as an extra — only weight training counts toward the goal), feeds the coach's leg-fatigue check, and is saved to Apple Health.")
            }
        }
        .navigationTitle(kind == .run ? "Log a run" : "Log basketball")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: made) { _, value in if value > attempted { attempted = value } }
        .onChange(of: attempted) { _, value in if value < made { made = value } }
    }
}
