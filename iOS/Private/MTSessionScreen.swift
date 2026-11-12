import SwiftUI
import Combine

/// Full-screen view for a running Pump / PAC / extender / clamp session (open timer or intervals).
/// After it ends, the same screen asks for warning signs, then closes.
///
/// MK22.1: turn the iPhone on its side and the timer lays out sideways — the ring on the left as big as the
/// height allows, what to do and the buttons on the right. The rest of the app stays portrait.
struct MTSessionScreen: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let onMinimise: () -> Void
    let onClose: () -> Void

    /// iPhone on its side.
    private var landscape: Bool { verticalSizeClass == .compact }

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
        .onAppear { OrientationLock.allowLandscape(true, for: "mt.session") }
        .onDisappear { OrientationLock.allowLandscape(false, for: "mt.session") }
    }

    // MARK: Open timer

    private func openBody(_ active: MTActiveSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(active.start)
            let limit = vault.data.settings.limit(for: active.type).map { Double($0 * 60) }
            let over = limit.map { elapsed >= $0 } ?? false
            if landscape {
                sideBySide { size in
                    openRing(elapsed: elapsed, limit: limit, over: over, size: size)
                } side: {
                    header(type: active.type, pressure: active.pressureInHg, tension: active.tensionKg)
                    if active.nir == true {
                        Text("NIR on").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    stopButton { vault.stopTimed() }
                }
            } else {
                VStack(spacing: 24) {
                    header(type: active.type, pressure: active.pressureInHg, tension: active.tensionKg)
                    Spacer()
                    openRing(elapsed: elapsed, limit: limit, over: over, size: Self.portraitRing)
                    Spacer()
                    stopButton { vault.stopTimed() }
                }
                .padding()
            }
        }
    }

    private func openRing(elapsed: Double, limit: Double?, over: Bool, size: CGFloat) -> some View {
        ring(progress: limit.map { min(1, elapsed / $0) } ?? 0, color: over ? .red : .indigo, size: size) {
            VStack(spacing: 6) {
                Text(over ? "LIMIT REACHED" : "ELAPSED")
                    .font(.caption.bold())
                    .foregroundStyle(over ? Color.red : Color.secondary)
                Text(MTStats.clock(elapsed))
                    .font(.system(size: min(64, size * 0.21), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(over ? Color.red : Color.primary)
                if let limit {
                    Text("Limit \(MTStats.clock(limit))").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, size * 0.1)
        }
    }

    // MARK: Intervals

    private func intervalBody(_ run: MTActiveInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let phase = run.currentPhase, phase.stepIndex < run.steps.count {
                let step = run.steps[phase.stepIndex]
                let remaining = run.remaining(at: context.date)
                let isWork = phase.kind == .work
                if landscape {
                    sideBySide { size in
                        intervalRing(run, phase: phase, remaining: remaining, isWork: isWork, size: size)
                    } side: {
                        header(type: step.type, pressure: step.pressureInHg, tension: step.tensionKg)
                        intervalDetails(run, step: step, phase: phase, isWork: isWork, now: context.date)
                        Spacer(minLength: 0)
                        intervalButtons(run)
                    }
                } else {
                    VStack(spacing: 20) {
                        header(type: step.type, pressure: step.pressureInHg, tension: step.tensionKg)
                        intervalDetails(run, step: step, phase: phase, isWork: isWork, now: context.date)
                        Spacer()
                        intervalRing(run, phase: phase, remaining: remaining, isWork: isWork, size: Self.portraitRing)
                        Spacer()
                        intervalButtons(run)
                    }
                    .padding()
                }
            }
        }
    }

    /// Which step, what to do in it (during a rest: what to get ready for), and the round dots.
    @ViewBuilder
    private func intervalDetails(_ run: MTActiveInterval, step: MTPresetStep, phase: MTPhase, isWork: Bool, now: Date) -> some View {
        if run.steps.count > 1 {
            Text("\(run.name) · step \(phase.stepIndex + 1) of \(run.steps.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // The step's own instruction (guided PAC); for the extender, whether NIR is on or off now (MK22.1).
        if isWork, let cue = step.cue ?? MTLiveTimer.nirHint(run, stepIndex: phase.stepIndex) {
            Text(cue)
                .font(landscape ? Font.subheadline.weight(.semibold) : Font.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)   // MK19: wrap fully, never "…"
                .padding(.horizontal)
        } else if !isWork, let next = MTLiveTimer.widgetCue(for: vault.data, now: now) {
            // MK22.1: resting — show what's coming, so you can set up for it.
            Text(next)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
        roundDots(total: max(step.rounds, 1), current: phase.round, isWork: isWork)
    }

    private func intervalRing(_ run: MTActiveInterval, phase: MTPhase, remaining: Double, isWork: Bool, size: CGFloat) -> some View {
        ring(progress: max(0, phase.seconds - remaining) / max(phase.seconds, 1), color: isWork ? .indigo : .green, size: size) {
            VStack(spacing: 6) {
                Text(isWork ? "WORK · ROUND \(phase.round)" : "REST")
                    .font(.caption.bold())
                    .foregroundStyle(isWork ? Color.indigo : Color.green)
                Text(MTStats.clock(remaining))
                    .font(.system(size: min(72, size * 0.24), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if run.isPaused {
                    Text("PAUSED").font(.caption.bold()).foregroundStyle(.orange)
                } else if let next = nextLabel(run) {
                    Text(next).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, size * 0.1)
        }
    }

    @ViewBuilder
    private func intervalButtons(_ run: MTActiveInterval) -> some View {
        let height: CGFloat = landscape ? 42 : 48
        HStack(spacing: 12) {
            Button {
                if run.isPaused { vault.resumeInterval() } else { vault.pauseInterval() }
            } label: {
                Label(run.isPaused ? "Resume" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
            .buttonStyle(.bordered)
            Button {
                vault.extendPhase()
            } label: {
                Label("+1 min", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add one minute")
            Button {
                vault.skipPhase()
            } label: {
                Label("Skip", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity, minHeight: height)
            }
            .buttonStyle(.bordered)
        }
        if vault.skipUndo != nil {
            Button {
                vault.undoSkip()
            } label: {
                Label("Undo skip", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, minHeight: landscape ? 38 : 44)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        stopButton { vault.stopInterval() }
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

    /// The ring's outer size upright: a 290 pt circle plus its 16 pt line.
    private static let portraitRing: CGFloat = 306

    /// MK22.1: iPhone on its side — the ring on the left, as large as the height allows; everything else in
    /// a column on the right (it scrolls if it can't all fit, e.g. with large text).
    private func sideBySide<Ring: View, Side: View>(@ViewBuilder ring: @escaping (CGFloat) -> Ring,
                                                    @ViewBuilder side: @escaping () -> Side) -> some View {
        GeometryReader { geo in
            let size = max(150, min(geo.size.height, geo.size.width * 0.46, 340))
            HStack(spacing: 24) {
                ring(size)
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 12) { side() }
                    ScrollView { VStack(spacing: 12) { side() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func stopButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Stop & save", systemImage: "stop.fill")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: landscape ? 46 : 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    @ViewBuilder
    private func header(type: MTType, pressure: Double?, tension: Double?) -> some View {
        let color = type == .pac ? Color.yellow : Color.indigo
        let setting = settingText(pressure: pressure, tension: tension)
        if landscape {
            // One line: the height is needed for what to do and the buttons.
            HStack(spacing: 8) {
                Image(systemName: type.symbol).font(.title3).foregroundStyle(color)
                Text(type.title).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                if let setting {
                    Text(setting).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: type.symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(color)
                Text(type.title).font(.title2.bold())
                if let setting {
                    Text(setting).font(.headline).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    /// "8.0 inHg · 27 kPa" / "1.8 kg".
    private func settingText(pressure: Double?, tension: Double?) -> String? {
        if let pressure {
            return String(format: "%.1f inHg · %.0f kPa", pressure, pressure * MTPlan.kPaPerInHg)
        }
        if let tension {
            let unit = vault.data.settings.weightUnit
            return String(format: "%.1f %@", unit.display(tension), unit.rawValue)
        }
        return nil
    }

    private func ring<Content: View>(progress: Double, color: Color, size: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let line: CGFloat = size >= Self.portraitRing ? 16 : max(10, size * 0.055)
        return ZStack {
            Circle().stroke(Color.gray.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            content()
        }
        .padding(line / 2)
        .frame(width: size, height: size)
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
