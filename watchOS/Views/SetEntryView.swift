import SwiftUI

/// During a set: time, exercise, set number, heart rate.
/// Weight/reps come from what you type on the iPhone; +/- only appears if the phone is out of range.
struct SetEntryView: View {
    @EnvironmentObject private var store: WatchAppStore
    @EnvironmentObject private var workout: WatchWorkoutManager
    let state: ActiveWorkoutState
    let item: RoutineExercise

    @State private var weightKg: Double = 0
    @State private var reps: Int = 8
    @State private var loadedKey = ""
    @State private var showingSwap = false
    @State private var showingExercises = false
    @State private var confirmSkip = false

    private var setNumber: Int { state.sets(for: item).count + 1 }
    private var unit: String { item.exercise.isAssisted ? "kg" : item.exercise.loadConvention.unit }
    private var stateKey: String { "\(state.workoutID)-\(item.exercise.id)-\(setNumber)" }
    private var step: Double { item.exercise.weightIncrementKg > 0 ? item.exercise.weightIncrementKg : 2.5 }
    private var index: Int { state.routine.exercises.firstIndex(where: { $0.id == item.id }) ?? state.exerciseIndex }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(GFFormat.duration(context.date.timeIntervalSince(workout.startDate ?? state.startedAt)))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.yellow)
                }

                if let label = state.supersetLabel(for: index) {
                    Text("SUPERSET \(label)")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                }

                Text(item.exercise.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let variation = state.variations?[item.exercise.id] {
                    Text(variation).font(.caption2.bold()).foregroundStyle(.orange)
                }

                if let original = state.swappedFrom(item) {
                    Text("instead of \(original.name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if item.exercise.isCardio {
                    Text("Target \(item.exercise.cardioMinutes) min")
                        .font(.subheadline.bold())
                } else {
                    Text("Set \(setNumber) of \(item.exercise.defaultSets)")
                        .font(.subheadline.bold())
                    setDots
                    if setNumber == 1, weightKg > 0 {
                        let warm = item.exercise.isAssisted
                            ? max(((weightKg * 1.4) / step).rounded(.up) * step, weightKg + step)
                            : (weightKg * 0.4 / step).rounded() * step
                        Label(item.exercise.isAssisted ? "Warm-up \(GFFormat.kg(warm)) kg assist × 6" : "Warm-up \(GFFormat.kg(warm)) kg × 10", systemImage: "flame")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(workout.heartRateBPM > 0 ? "\(Int(workout.heartRateBPM))" : "--")
                        .font(.title2.monospacedDigit().bold())
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                }

                if let note = item.exercise.notes, !note.isEmpty {
                    Label(note, systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if item.exercise.isCardio {
                    cardioSection
                } else {
                    numbersSection
                    // With the iPhone connected, sets are logged on the iPhone; the Watch's
                    // Rest button only appears as a fallback when the phone is out of range.
                    if !store.phoneReachable {
                        Button {
                            logSet()
                        } label: {
                            Label("Rest", systemImage: "timer").bold().frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!canLog)
                    }
                }

                HStack(spacing: 6) {
                    actionButton("Exercises", systemImage: "list.bullet") { showingExercises = true }
                    if !state.swapOptions(for: item).isEmpty {
                        actionButton("Swap", systemImage: "arrow.triangle.2.circlepath") { showingSwap = true }
                    }
                    actionButton("Skip", systemImage: "forward.fill") { confirmSkip = true }
                }
                .padding(.top, 4)
            }
        }
        .onAppear { loadFallbackIfNeeded() }
        .onChange(of: stateKey) { _, _ in loadFallbackIfNeeded() }
        .sheet(isPresented: $showingExercises) {
            ExercisePickerView(state: state) { chosen in
                let target = state.routine.exercises[chosen]
                if state.isFinished(target) && !state.isSkipped(target) {
                    store.addExtraSet(toExercise: chosen)
                } else {
                    store.jumpToExercise(chosen)
                }
                showingExercises = false
            }
        }
        .confirmationDialog("Skip \(item.exercise.name)?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Skip for today") { store.skipExercise(at: index) }
        } message: {
            Text("You can come back to it from Exercises.")
        }
        .sheet(isPresented: $showingSwap) {
            SwapPickerView(options: state.swapOptions(for: item)) { choice in
                store.swapExercise(at: index, to: choice)
                showingSwap = false
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage).font(.body)
                Text(title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
    }

    /// ● ● ○  — filled for sets done.
    private var setDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(item.exercise.defaultSets, 1), id: \.self) { dot in
                Circle()
                    .fill(dot < setNumber - 1 ? Color.green : (dot == setNumber - 1 ? Color.white : Color.gray.opacity(0.4)))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: Strength

    @ViewBuilder
    private var numbersSection: some View {
        if let draft = store.currentDraft, draft.isCompleteStrength || store.phoneReachable {
            Text("\(draft.weightKg.map { GFFormat.kg($0) } ?? "–") \(unit) × \(draft.reps.map { "\($0)" } ?? "–")")
                .font(.title3.bold().monospacedDigit())
        } else if store.phoneReachable {
            if let previous = store.previousLog(for: item.exercise), !previous.sets.isEmpty {
                let old = previous.sets[min(setNumber - 1, previous.sets.count - 1)]
                Text("Last: \(previous.summary(old))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let target = store.prefill(for: item)
            if target.weightKg > 0 || item.exercise.isBodyweight {
                Text("Plan: \(item.exercise.formatLoad(target.weightKg)) × \(target.reps)"
                     + (store.activeWorkout?.targetRIR.map { " · " + EffortTarget.text($0) } ?? ""))
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
            Text("Enter weight & reps on iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text("iPhone out of range").font(.caption2).foregroundStyle(.orange)
            adjuster(text: "\(GFFormat.kg(weightKg)) \(unit)" + (item.exercise.isAssisted ? " assist" : ""), minus: { weightKg = max(0, weightKg - step) }, plus: { weightKg += step })
            adjuster(text: "\(reps) reps", minus: { reps = max(0, reps - 1) }, plus: { reps += 1 })
        }
    }

    /// A half-typed set on an out-of-range iPhone never blocks logging here (the +/- values are used instead).
    private var canLog: Bool {
        if let draft = store.currentDraft, draft.isCompleteStrength { return true }
        return !store.phoneReachable
    }

    private func logSet() {
        if let draft = store.currentDraft, let weight = draft.weightKg, let count = draft.reps {
            store.completeCurrentSet(weightKg: weight, reps: count)
        } else if !store.phoneReachable {
            store.completeCurrentSet(weightKg: weightKg, reps: reps)
        }
    }

    private func adjuster(text: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button(action: minus) { Image(systemName: "minus") }
                .frame(width: 40)
            Text(text)
                .font(.title3.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button(action: plus) { Image(systemName: "plus") }
                .frame(width: 40)
        }
    }

    // MARK: Cardio

    @ViewBuilder
    private var cardioSection: some View {
        if let draft = store.currentDraft, draft.isCompleteCardio {
            Text(phoneCardioText(draft))
                .font(.title3.bold())
            Button {
                store.completeCurrentSet(weightKg: 0, reps: 0, durationSeconds: draft.durationSeconds, distanceKm: draft.distanceKm)
            } label: {
                Label("Log cardio", systemImage: "checkmark").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else if let started = store.cardioStartedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(GFFormat.duration(context.date.timeIntervalSince(started)))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
            }
            Button {
                let seconds = Date().timeIntervalSince(started)
                store.completeCurrentSet(weightKg: 0, reps: 0, durationSeconds: seconds, distanceKm: store.currentDraft?.distanceKm)
            } label: {
                Label("Stop & log", systemImage: "stop.fill").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            if let previous = store.previousLog(for: item.exercise), let set = previous.sets.first {
                Text("Last: \(set.summaryText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                store.startCardioTimer()
            } label: {
                Label("Start timer", systemImage: "play.fill").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Text("Or type minutes/km on iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func phoneCardioText(_ draft: WorkoutDraft) -> String {
        var text = GFFormat.minutes(draft.durationSeconds ?? 0)
        if let km = draft.distanceKm, km > 0 { text += " · \(GFFormat.km(km)) km" }
        return text
    }

    /// Fallback values (last session) for when the phone isn't around.
    private func loadFallbackIfNeeded() {
        guard loadedKey != stateKey else { return }
        let suggestion = store.prefill(for: item)
        weightKg = suggestion.weightKg
        reps = suggestion.reps
        loadedKey = stateKey
    }
}

struct SwapPickerView: View {
    let options: [ExerciseDefinition]
    let onPick: (ExerciseDefinition) -> Void

    var body: some View {
        List {
            Section {
                ForEach(options) { option in
                    Button {
                        onPick(option)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.headline)
                            Text(option.isCardio ? "\(option.cardioMinutes) min" : "\(option.defaultSets) × \(option.repMin)–\(option.repMax)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Swap for today")
            } footer: {
                Text("Logged separately with its own history.")
            }
        }
    }
}

/// All exercises in today's workout — tap one to do it next.
struct ExercisePickerView: View {
    let state: ActiveWorkoutState
    let onPick: (Int) -> Void

    var body: some View {
        List {
            Section {
                ForEach(Array(state.routine.exercises.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onPick(index)
                    } label: {
                        HStack {
                            Image(systemName: icon(index: index, item: item))
                                .foregroundStyle(color(index: index, item: item))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.exercise.name).font(.caption).lineLimit(2)
                                Text(detail(item)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Do next")
            } footer: {
                Text("Done ones add an extra set. Skipped ones come back.")
            }
        }
    }

    private func icon(index: Int, item: RoutineExercise) -> String {
        if state.isSkipped(item) { return "forward.circle" }
        if state.isFinished(item) { return "checkmark.circle.fill" }
        return index == state.exerciseIndex ? "arrow.right.circle.fill" : "circle"
    }

    private func color(index: Int, item: RoutineExercise) -> Color {
        if state.isSkipped(item) { return .orange }
        if state.isFinished(item) { return .green }
        return index == state.exerciseIndex ? .accentColor : .secondary
    }

    private func detail(_ item: RoutineExercise) -> String {
        if state.isSkipped(item) { return "Skipped" }
        if item.exercise.isCardio { return state.sets(for: item).isEmpty ? "Cardio" : "Done" }
        return "\(state.sets(for: item).count)/\(item.exercise.defaultSets) sets"
    }
}
