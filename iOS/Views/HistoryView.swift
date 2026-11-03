import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var missedRoutine: WorkoutRoutine?
    @State private var missedDate = Date()
    @State private var pickingDate = false

    var body: some View {
        List {
            if store.workoutLogs.isEmpty {
                ContentUnavailableView("No workouts yet", systemImage: "clock.arrow.circlepath", description: Text("Finished workouts appear here."))
            }
            ForEach(store.sortedLogs) { log in
                NavigationLink {
                    WorkoutDetailView(log: log)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(log.routineName).font(.headline)
                            if log.prCount > 0 {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow).font(.caption)
                            }
                            if log.isDeload == true {
                                Image(systemName: "leaf.fill").foregroundStyle(.green).font(.caption)
                            }
                            if log.isManual == true {
                                Image(systemName: "hand.draw").foregroundStyle(.secondary).font(.caption)
                            }
                            Spacer()
                            Text(log.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(GFFormat.duration(log.duration)) · \(log.totalSets) sets · \(GFFormat.kg(log.totalVolumeKg.rounded())) kg volume")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                let logs = store.sortedLogs
                for index in offsets { store.deleteWorkout(logs[index]) }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Log a missed session") {
                        ForEach(store.routines.filter { !$0.exercises.isEmpty }) { routine in
                            Button(routine.name) {
                                missedDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                                missedRoutine = routine
                                pickingDate = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Log a missed session")
            }
        }
        .sheet(isPresented: $pickingDate) {
            NavigationStack {
                Form {
                    DatePicker("Day you trained", selection: $missedDate, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                .navigationTitle(missedRoutine?.name ?? "Missed session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { pickingDate = false; missedRoutine = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        NavigationLink("Next") {
                            if let routine = missedRoutine {
                                WorkoutCorrectionView(missed: routine, logs: store.workoutLogs, on: missedDate) {
                                    pickingDate = false
                                    missedRoutine = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    private let original: WorkoutLog
    @State private var editing = false

    init(log: WorkoutLog) { original = log }

    /// The saved version (it changes after an edit).
    private var log: WorkoutLog { store.workoutLogs.first { $0.id == original.id } ?? original }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Date", value: log.startedAt.formatted(date: .complete, time: .shortened))
                LabeledContent("Duration", value: GFFormat.duration(log.duration))
                LabeledContent("Total volume", value: "\(GFFormat.kg(log.totalVolumeKg.rounded())) kg")
                LabeledContent("Sets / reps", value: "\(log.totalSets) / \(log.totalReps)")
                if let kcal = log.activeCaloriesKcal {
                    LabeledContent("Active calories", value: "\(Int(kcal)) kcal")
                }
                if let avg = log.averageHeartRateBPM {
                    LabeledContent("Average heart rate", value: "\(Int(avg)) bpm")
                }
                if let max = log.maxHeartRateBPM {
                    LabeledContent("Max heart rate", value: "\(Int(max)) bpm")
                }
                Group {
                    if let recovery = log.averageHeartRateRecovery {
                        LabeledContent("HR recovery (1 min)", value: "\(Int(recovery.rounded())) bpm")
                    }
                    if log.cardioSeconds > 0 {
                        LabeledContent("Cardio", value: GFFormat.minutes(log.cardioSeconds))
                    }
                    if log.isDeload == true {
                        Label("Light / deload session — not used for progression", systemImage: "leaf.fill")
                            .foregroundStyle(.green)
                    }
                    if let phase = log.phaseName {
                        LabeledContent("Program block", value: phase)
                    }
                    if log.isManual == true {
                        Label("Logged by hand", systemImage: "hand.draw")
                            .foregroundStyle(.secondary)
                    }
                    if log.source == "strong" {
                        Label("Imported from Strong", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HeartRateSection(log: log)
            SessionTagSection(log: log)

            ForEach(log.exercises) { exercise in
                let previous = store.workoutLogs.previousLog(where: { $0.matches(exercise) }, before: log.startedAt)
                let comparison = ProgressionEngine.compare(current: exercise, previous: previous, context: log.tagSet)
                Section {
                    ForEach(exercise.sets) { set in
                        HStack {
                            Text("Set \(set.setNumber)")
                            if set.isPR == true {
                                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            }
                            Spacer()
                            if let recovery = set.heartRateRecovery {
                                Text("HR ↓\(Int(recovery))").font(.caption).foregroundStyle(.green)
                            }
                            Text(exercise.summary(set)).bold()
                            if !set.isCardio, let targetReps = set.targetReps, let targetWeight = set.targetWeightKg {
                                Text("plan \(GFFormat.kg(targetWeight))×\(targetReps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Label(comparison.summary, systemImage: icon(for: comparison.kind))
                        .font(.footnote)
                        .foregroundStyle(color(for: comparison.kind))
                } header: {
                    Text(exercise.isCardio ? exercise.exerciseName : "\(exercise.exerciseName) · \(exercise.repMinAtTime)–\(exercise.repMaxAtTime)" + (exercise.variation.map { " · \($0)" } ?? ""))
                } footer: {
                    if let original = exercise.swappedFromName {
                        Text("Swapped in for \(original)")
                    }
                }
            }
        }
        .navigationTitle(log.routineName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack { WorkoutCorrectionView(editing: log) }
        }
        // Deleted from the edit sheet: leave this screen.
        .onChange(of: store.workoutLogs.contains { $0.id == original.id }) { _, exists in
            if !exists { dismiss() }
        }
    }

    private func icon(for kind: SessionComparison.Kind) -> String {
        switch kind {
        case .improved: return "arrow.up.circle.fill"
        case .matched: return "equal.circle.fill"
        case .declined: return "arrow.down.circle.fill"
        case .firstTime: return "star.circle.fill"
        }
    }

    private func color(for kind: SessionComparison.Kind) -> Color {
        switch kind {
        case .improved: return .green
        case .matched: return .secondary
        case .declined: return .orange
        case .firstTime: return .blue
        }
    }
}
