import SwiftUI
import Combine

/// Full-screen view for a running Pump / PAC / extender / clamp session (open timer or intervals).
/// After it ends, the same screen asks for warning signs, then closes.
struct MTSessionScreen: View {
    @EnvironmentObject private var vault: MTVault
    let onMinimise: () -> Void
    let onClose: () -> Void

    @State private var limitBuzzed = false
    @State private var confirmCancel = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let run = vault.data.activeInterval {
                    intervalBody(run)
                } else if let active = vault.data.activeSession {
                    openBody(active)
                } else if !vault.pendingReview.isEmpty {
                    MTReviewSheet()
                } else {
                    Color.clear.onAppear { onClose() }
                }
            }
            .toolbar {
                if vault.data.isBusy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onMinimise()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .accessibilityLabel("Minimise")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel", role: .destructive) { confirmCancel = true }
                    }
                }
            }
            .confirmationDialog("Cancel without saving?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Discard session", role: .destructive) {
                    if vault.data.activeInterval != nil {
                        vault.cancelInterval()
                    } else {
                        vault.cancelTimed()
                    }
                }
            }
        }
        .onReceive(ticker) { now in
            vault.advanceInterval(now: now)
            checkLimit(now: now)
        }
    }

    // MARK: Open timer

    private func openBody(_ active: MTActiveSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(active.start)
            let limit = vault.data.settings.limit(for: active.type).map { Double($0 * 60) }
            let over = limit.map { elapsed >= $0 } ?? false
            VStack(spacing: 24) {
                header(type: active.type, pressure: active.pressureInHg, tension: active.tensionKg)
                Spacer()
                ring(progress: limit.map { min(1, elapsed / $0) } ?? 0, color: over ? .red : .indigo) {
                    VStack(spacing: 6) {
                        Text(over ? "LIMIT REACHED" : "ELAPSED")
                            .font(.caption.bold())
                            .foregroundStyle(over ? Color.red : Color.secondary)
                        Text(MTStats.clock(elapsed))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(over ? Color.red : Color.primary)
                        if let limit {
                            Text("Limit \(MTStats.clock(limit))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    vault.stopTimed()
                } label: {
                    Label("Stop & save", systemImage: "stop.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
        }
    }

    // MARK: Intervals

    private func intervalBody(_ run: MTActiveInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let phase = run.currentPhase, phase.stepIndex < run.steps.count {
                let step = run.steps[phase.stepIndex]
                let remaining = run.remaining(at: context.date)
                let isWork = phase.kind == .work
                VStack(spacing: 20) {
                    header(type: step.type, pressure: step.pressureInHg, tension: step.tensionKg)
                    if run.steps.count > 1 {
                        Text("\(run.name) · step \(phase.stepIndex + 1) of \(run.steps.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let cue = step.cue, isWork {
                        Text(cue)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)   // MK19: wrap fully, never "…"
                            .padding(.horizontal)
                    }
                    roundDots(total: max(step.rounds, 1), current: phase.round, isWork: isWork)
                    Spacer()
                    ring(progress: max(0, phase.seconds - remaining) / max(phase.seconds, 1), color: isWork ? .indigo : .green) {
                        VStack(spacing: 6) {
                            Text(isWork ? "WORK · ROUND \(phase.round)" : "REST")
                                .font(.caption.bold())
                                .foregroundStyle(isWork ? Color.indigo : Color.green)
                            Text(MTStats.clock(remaining))
                                .font(.system(size: 72, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            if run.isPaused {
                                Text("PAUSED").font(.caption.bold()).foregroundStyle(.orange)
                            } else if let next = nextLabel(run) {
                                Text(next).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button {
                            if run.isPaused { vault.resumeInterval() } else { vault.pauseInterval() }
                        } label: {
                            Label(run.isPaused ? "Resume" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            vault.extendPhase()
                        } label: {
                            Label("+1 min", systemImage: "plus")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add one minute")
                        Button {
                            vault.skipPhase()
                        } label: {
                            Label("Skip", systemImage: "forward.end.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                    }
                    if vault.skipUndo != nil {
                        Button {
                            vault.undoSkip()
                        } label: {
                            Label("Undo skip", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    Button {
                        vault.stopInterval()
                    } label: {
                        Label("Stop & save", systemImage: "stop.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
            }
        }
    }

    private func nextLabel(_ run: MTActiveInterval) -> String? {
        let nextIndex = run.index + 1
        guard nextIndex < run.phases.count else { return "Last one" }
        let next = run.phases[nextIndex]
        if next.kind == .rest { return "Then rest \(MTStats.clock(next.seconds))" }
        let type = next.stepIndex < run.steps.count ? run.steps[next.stepIndex].type.shortTitle : ""
        return "Then \(type) round \(next.round)"
    }

    // MARK: Pieces

    private func header(type: MTType, pressure: Double?, tension: Double?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: type.symbol)
                .font(.system(size: 34))
                .foregroundStyle(type == .pac ? Color.yellow : Color.indigo)
            Text(type.title).font(.title2.bold())
            if let pressure {
Text(String(format: "%.1f inHg · %.0f kPa", pressure, pressure * MTPlan.kPaPerInHg)).font(.headline).foregroundStyle(.secondary)
            } else if let tension {
                let unit = vault.data.settings.weightUnit
                Text(String(format: "%.1f %@", unit.display(tension), unit.rawValue)).font(.headline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func ring<Content: View>(progress: Double, color: Color, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.18), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            content()
        }
        .frame(width: 290, height: 290)
    }

    private func roundDots(total: Int, current: Int, isWork: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { round in
                Circle()
                    .fill(round < current || (round == current && !isWork) ? Color.indigo
                          : (round == current ? Color.indigo.opacity(0.5) : Color.gray.opacity(0.25)))
                    .frame(width: 12, height: 12)
            }
        }
    }

    /// Open timer: buzz three times once the limit is reached.
    private func checkLimit(now: Date) {
        guard let active = vault.data.activeSession,
              let minutes = vault.data.settings.limit(for: active.type) else {
            limitBuzzed = false
            return
        }
        if !limitBuzzed, now.timeIntervalSince(active.start) >= Double(minutes * 60) {
            limitBuzzed = true
            MTHaptics.timerUp()
        }
    }
}
