import SwiftUI

struct RestTimerView: View {
    @EnvironmentObject private var store: WatchAppStore
    @EnvironmentObject private var workout: WatchWorkoutManager
    let state: ActiveWorkoutState

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("REST").font(.caption.bold()).foregroundStyle(.secondary)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, (state.restEndDate ?? context.date).timeIntervalSince(context.date).rounded(.up))
                    Text(GFFormat.duration(remaining))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }

                if let item = state.currentItem {
                    VStack(spacing: 2) {
                        Text("NEXT").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(item.exercise.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(item.exercise.isCardio ? "Cardio" : "Set \(state.sets(for: item).count + 1) of \(item.exercise.defaultSets)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("+30s") { store.addRest(seconds: 30) }
                    Button("Skip") { store.skipRest() }
                }
                .font(.caption)

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workout.heartRateBPM > 0 ? "\(Int(workout.heartRateBPM)) BPM" : "-- BPM")
                        .monospacedDigit()
                    if let start = store.restHeartRateStart, workout.heartRateBPM > 0, start > workout.heartRateBPM {
                        Text("↓\(Int(start - workout.heartRateBPM))")
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                }
                .font(.caption)

                if let line = store.profile.coachStyle.liveLine(workout: state.workoutID, step: state.totalCompletedSets) {
                    Text(line)
                        .font(.caption2.italic())
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if store.profile.autoRest {
                    Text("Auto-ends below \(store.profile.autoRestBPM) BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Full-screen alert shown (with three buzzes) when the rest timer runs out.
/// Scrolls on small Watches so "Go" is always reachable.
struct RestFinishedView: View {
    @EnvironmentObject private var store: WatchAppStore
    let state: ActiveWorkoutState

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("Rest finished")
                    .font(.headline)
                if let item = state.currentItem {
                    Text(item.exercise.name)
                        .font(.subheadline.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(item.exercise.isCardio ? "Cardio" : "Set \(state.sets(for: item).count + 1) of \(item.exercise.defaultSets)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    store.dismissRestFinished()
                } label: {
                    Label("Go", systemImage: "arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A set was just logged on (or sent to) the Watch.
struct WatchSetTick: Identifiable, Equatable {
    let id: UUID
    let caption: String?
}

/// Small green circle with the tick drawing itself; never blocks taps.
struct WatchSetTickOverlay: View {
    let tick: WatchSetTick
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.4
    @State private var drawn: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.green.gradient)
                    .frame(width: 74, height: 74)
                WatchTickShape()
                    .trim(from: 0, to: drawn)
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 36, height: 28)
            }
            .scaleEffect(scale)
            if let caption = tick.caption {
                Text("\(caption) ✓")
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion {
                scale = 1
                drawn = 1
                withAnimation(.easeIn(duration: 0.15)) { opacity = 1 }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                    scale = 1
                    opacity = 1
                }
                withAnimation(.easeOut(duration: 0.3).delay(0.1)) { drawn = 1 }
            }
            let hold = tick.caption == nil ? 0.6 : 1.2
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
                withAnimation(.easeIn(duration: 0.2)) { opacity = 0 }
            }
        }
    }
}

struct WatchTickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Full-screen PR celebration (auto-dismisses after a few seconds).
struct PRCelebrationView: View {
    @EnvironmentObject private var store: WatchAppStore
    let pr: PRHit

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)
            Text("NEW PR!")
                .font(.title2.bold())
                .foregroundStyle(.yellow)
            Text(pr.exerciseName)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("\(GFFormat.kg(pr.weightKg)) kg × \(pr.reps)")
                .font(.title3.bold().monospacedDigit())
            Text(pr.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { store.dismissCelebration() }
    }
}

/// Shown after finishing a workout on the Watch.
struct WatchSummaryView: View {
    @EnvironmentObject private var store: WatchAppStore
    let log: WorkoutLog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Workout saved", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(log.routineName).font(.title3.bold())
                // MK10.1: the coach's one-line rating (the full brief is on the iPhone).
                Text(WorkoutBriefBuilder.make(for: log, logs: store.workoutLogs, style: store.profile.coachStyle,
                                              targetRIR: log.targetRIR).rating)
                    .font(.headline)
                    .foregroundStyle(.yellow)

                Group {
                    row("Time", GFFormat.duration(log.duration))
                    row("Sets", "\(log.totalSets)")
                    row("Volume", GFFormat.volume(log.totalVolumeKg))
                    if let kcal = log.activeCaloriesKcal { row("Active kcal", "\(Int(kcal))") }
                    if let avg = log.averageHeartRateBPM { row("Avg HR", "\(Int(avg))") }
                    if let peak = log.maxHeartRateBPM { row("Peak HR", "\(Int(peak))") }
                    if let recovery = log.averageHeartRateRecovery { row("HR recovery", "\(Int(recovery.rounded())) bpm/min") }
                    if log.cardioSeconds > 0 { row("Cardio", GFFormat.minutes(log.cardioSeconds)) }
                }

                if log.prCount > 0 {
                    Label("\(log.prCount) PR\(log.prCount == 1 ? "" : "s")", systemImage: "trophy.fill")
                        .foregroundStyle(.yellow)
                        .font(.headline)
                    ForEach(log.exercises.filter(\.hasPR)) { exercise in
                        Text(exercise.exerciseName).font(.caption2)
                    }
                }

                Button("Done") { store.closeSummary() }
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
