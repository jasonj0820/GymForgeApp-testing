import SwiftUI

/// Shown after a workout finishes: totals, PRs, what improved vs last time, and next-session targets.
struct WorkoutSummaryView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let log: WorkoutLog

    private var heartText: String {
        let average = log.averageHeartRateBPM.map { "\(Int($0))" } ?? "–"
        let peak = log.maxHeartRateBPM.map { "\(Int($0))" } ?? "–"
        return average == "–" && peak == "–" ? "–" : "\(average) / \(peak)"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Workout saved", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(log.routineName).font(.largeTitle.bold())
                    Text(log.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                    if log.isDeload == true {
                        Label("Light / deload session", systemImage: "leaf.fill").font(.footnote).foregroundStyle(.green)
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("Time", GFFormat.duration(log.duration))
                    stat("Volume", GFFormat.volume(log.totalVolumeKg))
                    stat("Sets", "\(log.totalSets)")
                    stat("PRs", "\(log.prCount)")
                    stat("Calories", log.activeCaloriesKcal.map { "\(Int($0))" } ?? "–")
                    stat("HR avg / peak", heartText)
                }
                .padding(.vertical, 4)
                if let recovery = log.averageHeartRateRecovery {
                    LabeledContent("Heart-rate recovery", value: "\(Int(recovery.rounded())) bpm in 1 min")
                }
                if log.cardioSeconds > 0 {
                    LabeledContent("Cardio", value: GFFormat.minutes(log.cardioSeconds) + (log.cardioKm > 0 ? " · \(GFFormat.km(log.cardioKm)) km" : ""))
                }
            }

            // MK11.1: the saved version, so tagging the day updates the brief right away.
            let live = store.workoutLogs.first { $0.id == log.id } ?? log
            CoachBriefSection(log: live)
            SessionTagSection(log: live)
            HeartRateSection(log: log)

            if log.prCount > 0 {
                Section("Personal records") {
                    ForEach(log.exercises.filter(\.hasPR)) { exercise in
                        ForEach(exercise.sets.filter { $0.isPR == true }) { set in
                            Label("\(exercise.exerciseName): \(exercise.summary(set))", systemImage: "trophy.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            Section("Compared with last time") {
                ForEach(log.exercises) { exercise in
                    let previous = store.workoutLogs.previousLog(where: { $0.matches(exercise) }, before: log.startedAt)
                    let comparison = ProgressionEngine.compare(current: exercise, previous: previous, context: live.tagSet)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.exerciseName + (exercise.variation.map { " · \($0)" } ?? ""))
                            Text(exercise.sets.map { exercise.summary($0) }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(comparison.summary)
                            .font(.caption.bold())
                            .foregroundStyle(color(for: comparison.kind))
                            .multilineTextAlignment(.trailing)
                    }
                    if let advice = SetComparison.advice(current: exercise.sets, previous: previous, repMin: exercise.repMinAtTime,
                                                         repMax: exercise.repMaxAtTime, assisted: exercise.isAssisted) {
                        Label(advice, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Next time") {
                ForEach(log.exercises) { exercise in
                    if let definition = store.progressExercises.first(where: { exercise.matches($0) }) {
                        let recommendation = ProgressionEngine.recommendation(for: definition, previous: exercise)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.exerciseName).font(.subheadline.bold())
                            Text(recommendation.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
