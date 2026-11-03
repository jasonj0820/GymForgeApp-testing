import SwiftUI

/// One suggested change: what, a one-line why, Accept / Not now.
struct ProposalRow: View {
    @EnvironmentObject private var store: PhoneAppStore
    let proposal: CoachProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(proposal.title).font(.subheadline.bold())
            Text(proposal.reason).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(proposal.change == .info ? "Got it" : "Accept") {
                    withAnimation { store.acceptProposal(proposal) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                if proposal.change != .info {
                    Button("Not now") {
                        withAnimation { store.declineProposal(proposal) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Every suggestion, with the training focus switch.
struct CoachSuggestionsView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let proposals = store.coachProposals
        List {
            Section {
                FocusPicker()
            } footer: {
                Text("Size: moderate reps on everything. Strength: heavier 3–6 rep work on your main lifts (squat, bench, deadlift, press, rows, pull-ups), size work for the rest.")
            }
            Section {
                if proposals.isEmpty {
                    Label("Nothing to change right now — your plan looks good.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                ForEach(proposals) { ProposalRow(proposal: $0) }
            } header: {
                Text("Suggested changes")
            } footer: {
                Text("Nothing changes until you accept. \"Not now\" hides a suggestion for 4 weeks. Accepted changes are followed up in the weekly review.")
            }
        }
        .navigationTitle("Coach suggestions")
    }
}

struct FocusPicker: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        Picker("Training focus", selection: Binding(get: { store.profile.focus }, set: { store.setFocus($0) })) {
            ForEach(TrainingFocus.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Weekly sets per muscle (actual and planned) against the ranges most people grow on, strength
/// trends, your personal sweet spots, and the routine check.
struct MuscleVolumeView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let statuses = store.muscleStatus
        let audit = store.routineAudit
        List {
            Section {
                ForEach(statuses) { status in
                    muscleRow(status)
                }
            } header: {
                Text("Sets per week")
            } footer: {
                Text("Hard sets per week; secondary work (e.g. triceps on bench) counts half. Green = in the range most people grow on. Based on the last 3 weeks, or your plan if there's no history yet.")
            }

            let spots = statuses.compactMap { CoachBrain.sweetSpot($0.muscle, logs: store.workoutLogs) }
            if !spots.isEmpty {
                Section("What works for you") {
                    ForEach(spots, id: \.self) { Text($0).font(.subheadline) }
                }
            }

            Section {
                if audit.isEmpty {
                    Label("No problems found in your routines.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                ForEach(audit) { ProposalRow(proposal: $0) }
            } header: {
                Text("Routine check")
            } footer: {
                Text("Balance, missing muscles, exercise order, rest and rep ranges for your focus.")
            }
        }
        .navigationTitle("Muscles & routine check")
    }

    private func muscleRow(_ status: MuscleStatus) -> some View {
        let value = status.current
        let color: Color = value < status.low ? .orange : (value > status.muscle.weeklyCeiling ? .purple : .green)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.muscle.title).font(.subheadline.bold())
                Spacer()
                if let trend = status.trend {
                    Text(String(format: "%+.0f%%", trend))
                        .font(.caption.bold())
                        .foregroundStyle(trend >= 1 ? Color.green : (trend <= -3 ? Color.red : Color.secondary))
                }
                Text("\(format(value)) sets · aim \(format(status.low))–\(format(status.high))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            SwiftUI.ProgressView(value: min(value, status.high), total: max(status.high, 1))
                .tint(color)
            if status.actual != nil, abs(status.planned - value) >= 3 {
                Text("Planned \(format(status.planned)) — you've actually been doing \(format(value)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// Builds a full week of routines from days, time, focus and priority muscles.
struct RoutineBuilderView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var days = 4
    @State private var minutes = 60
    @State private var focus: TrainingFocus = .size
    @State private var priorities: Set<ExerciseCategory> = []
    @State private var loaded = false
    @State private var added = false

    private let priorityChoices: [ExerciseCategory] = [.chest, .back, .shoulders, .biceps, .triceps, .legs]

    var body: some View {
        let built = RoutineBuilder.build(RoutineBuildRequest(daysPerWeek: days, minutes: minutes, focus: focus,
                                                             priorities: Array(priorities)))
        let weekly = CoachBrain.plannedSets(routines: built, frequency: Dictionary(uniqueKeysWithValues: built.map { ($0.id, 1.0) }))
        Form {
            Section {
                Stepper("\(days) days a week", value: $days, in: 2...6)
                Picker("Time per session", selection: $minutes) {
                    ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Focus", selection: $focus) {
                    ForEach(TrainingFocus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(RoutineBuilder.splitName(days: days))
            }

            Section {
                ForEach(priorityChoices) { muscle in
                    Button {
                        if priorities.contains(muscle) { priorities.remove(muscle) } else { priorities.insert(muscle) }
                    } label: {
                        HStack {
                            Text(muscle.title).foregroundStyle(.primary)
                            Spacer()
                            if priorities.contains(muscle) { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        }
                    }
                }
            } header: {
                Text("Priority muscles")
            } footer: {
                Text("Priorities get an extra set and their isolation work moves earlier in the session.")
            }

            ForEach(built) { routine in
                Section {
                    ForEach(routine.exercises) { item in
                        HStack {
                            Text(item.exercise.name)
                            Spacer()
                            Text("\(item.exercise.defaultSets) × \(item.exercise.repMin)–\(item.exercise.repMax)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("\(routine.name) · ≈ \(TimeBudget.estimateMinutes(ActiveWorkoutState(routine: routine))) min")
                }
            }

            Section {
                let low = Muscle.allCases.filter { (weekly[$0] ?? 0) < $0.weeklyRange.low }
                Text(low.isEmpty
                     ? "Every muscle lands in the range most people grow on."
                     : "Below range: " + low.map(\.title).joined(separator: ", ") + (days <= 3 || minutes <= 45 ? " — more days or time would fix that." : "."))
                    .font(.footnote)
                Button {
                    store.addBuiltRoutines(built)
                    added = true
                } label: {
                    Label(added ? "Added" : "Add these \(built.count) routines", systemImage: added ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(added)
            } footer: {
                Text("They're added next to your current routines (nothing is replaced). Edit them like any routine; plan them on days with Plan week.")
            }
        }
        .navigationTitle("Build a routine")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            focus = store.profile.focus
            priorities = Set(store.extras.priorityMuscles)
            days = min(max(store.weeklyGoal, 2), 6)
        }
        .onChange(of: days) { _, _ in added = false }
        .onChange(of: minutes) { _, _ in added = false }
        .onChange(of: focus) { _, _ in added = false }
        .onChange(of: priorities) { _, _ in added = false }
    }
}
