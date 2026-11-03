import SwiftUI

/// Swipe up/down between the set screen and workout controls (like Apple's Workout app).
struct WatchActiveWorkoutView: View {
    let state: ActiveWorkoutState

    var body: some View {
        TabView {
            Group {
                if let item = state.currentItem, !state.isComplete {
                    SetEntryView(state: state, item: item)
                } else {
                    WorkoutCompleteView(state: state)
                }
            }
            WorkoutControlsView(state: state)
        }
        .tabViewStyle(.verticalPage)
    }
}

struct WorkoutMetricsRow: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Text(GFFormat.duration(context.date.timeIntervalSince(workout.startDate ?? startedAt)))
                    .foregroundStyle(.yellow)
                Spacer(minLength: 2)
                Label("\(Int(workout.heartRateBPM))", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                Label("\(Int(workout.activeEnergyKcal))", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .font(.caption2.monospacedDigit())
            .labelStyle(.titleAndIcon)
        }
    }
}

struct WorkoutCompleteView: View {
    @EnvironmentObject private var store: WatchAppStore
    let state: ActiveWorkoutState

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("All sets done").font(.headline)
                Text("\(state.totalCompletedSets) sets logged").font(.caption).foregroundStyle(.secondary)
                WorkoutMetricsRow(startedAt: state.startedAt)
                Button {
                    Task { await store.finishWorkout() }
                } label: {
                    Label("Finish workout", systemImage: "flag.checkered")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(store.isFinishing)
                Text("Swipe up to add an extra set.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkoutControlsView: View {
    @EnvironmentObject private var store: WatchAppStore
    let state: ActiveWorkoutState
    @State private var confirmDiscard = false

    var body: some View {
        List {
            WorkoutMetricsRow(startedAt: state.startedAt)

            Button {
                Task { await store.finishWorkout() }
            } label: {
                Label("Finish workout", systemImage: "flag.checkered")
            }
            .tint(.green)
            .disabled(store.isFinishing)

            Section("Exercises") {
                ForEach(Array(state.routine.exercises.enumerated()), id: \.element.id) { index, item in
                    Button {
                        if state.isFinished(item) && !state.isSkipped(item) {
                            store.addExtraSet(toExercise: index)
                        } else {
                            store.jumpToExercise(index)
                        }
                    } label: {
                        HStack {
                            if let label = state.supersetLabel(for: index) {
                                Text(label).foregroundStyle(.purple)
                            }
                            Text(item.exercise.name).lineLimit(2)
                            Spacer()
                            Text("\(state.sets(for: item).count)/\(item.exercise.defaultSets)")
                                .foregroundStyle(state.isFinished(item) ? Color.green : Color.secondary)
                        }
                        .font(.caption)
                    }
                }
            }

            Button("Discard", role: .destructive) { confirmDiscard = true }
        }
        .confirmationDialog("Discard workout?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { store.discardWorkout() }
        }
    }
}
