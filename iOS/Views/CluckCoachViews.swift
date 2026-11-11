import SwiftUI

// MK11.1: Sergeant Cluck as your coach on the workout screen, and session-context tags.

/// Live cue card: session intro → current-set cue → rest cue, accepted-plan reminders, and "Explain, Sergeant".
struct CluckCoachCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    let state: ActiveWorkoutState
    /// MK20.8: just his line; tap to unfold the reminders and "Explain, Sergeant".
    var compact = false
    @State private var expanded = false
    @State private var explaining = false

    private var painFlag: PainFlag? {
        guard let item = state.currentItem else { return nil }
        return store.extras.painFlags.first { !$0.resolved && $0.exerciseKey == item.exercise.historyKey }
    }

    private var cue: CluckCue {
        let item = state.currentItem
        let plan = item.map { store.setPlan(for: $0) }
        let recommendation = item.map { ProgressionEngine.recommendation(for: $0.exercise, previous: store.previousLog(for: $0.exercise, before: state.startedAt)) }
        let done = item.map { state.sets(for: $0).count } ?? 0
        let cues = item.map { FormCues.cues(for: $0.exercise) } ?? []
        let formCue = cues.isEmpty ? nil : cues[done % cues.count]
        var cue = CluckCoach.cue(state: state, plan: plan, recommendation: recommendation, formCue: formCue,
                                 suggestions: store.extras.suggestions)
        if let painFlag {
            cue.reasons.insert("You flagged pain on \(painFlag.exerciseName). Pain-free range only — stop the set if it bites.", at: 0)
        }
        return cue
    }

    var body: some View {
        let current = cue
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                CluckView(mood: painFlag != nil ? .protective : .lockedIn, animated: true)
                    .frame(width: compact ? 36 : 48, height: compact ? 36 : 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERGEANT CLUCK").font(.caption2.bold()).foregroundStyle(.tint)
                    Text(current.headline)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .id(current.headline)
                        .transition(.opacity)
                }
                if compact, !current.reminders.isEmpty || !current.reasons.isEmpty {
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if compact { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }
            }
            if !compact || expanded {
                ForEach(current.reminders, id: \.self) { reminder in
                    Label(reminder, systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !current.reasons.isEmpty, !compact || expanded {
                Button {
                    explaining = true
                } label: {
                    Label("Explain, Sergeant", systemImage: "questionmark.bubble")
                        .font(.footnote.bold())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.3), value: current.headline)
        .sheet(isPresented: $explaining) {
            ExplainSergeantView(reasons: current.reasons)
                .presentationDetents([.medium, .large])
        }
    }
}

/// "Explain, Sergeant": the reasoning behind today's targets, in his words.
struct ExplainSergeantView: View {
    let reasons: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        CluckView(mood: .analytical, animated: true).frame(width: 60, height: 60)
                        Text("Here's the reasoning, recruit. No orders without reasons.")
                            .font(.subheadline)
                    }
                }
                Section("Why") {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason).font(.subheadline)
                    }
                }
            }
            .navigationTitle("Explain, Sergeant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } }
            }
        }
    }
}

/// Tap-to-toggle chips for the four session-context tags.
struct SessionTagChips: View {
    let selected: Set<SessionTag>
    /// MK20.8: one sideways-scrolling row (the live workout screen) instead of a two-column grid.
    var singleRow = false
    let toggle: (SessionTag) -> Void

    var body: some View {
        if singleRow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips(fill: false) }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                chips(fill: true)
            }
        }
    }

    private func chips(fill: Bool) -> some View {
        ForEach(SessionTag.allCases) { tag in
            Button {
                toggle(tag)
            } label: {
                Label(tag.title, systemImage: selected.contains(tag) ? "checkmark.circle.fill" : tag.icon)
                    .font(.subheadline)
                    .lineLimit(fill ? nil : 1)
                    .fixedSize(horizontal: !fill, vertical: false)
                    .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(selected.contains(tag) ? .orange : .gray)
            .accessibilityAddTraits(selected.contains(tag) ? .isSelected : [])
        }
    }
}

/// Session context on a saved workout (summary and history).
struct SessionTagSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    let log: WorkoutLog

    var body: some View {
        Section {
            SessionTagChips(selected: log.tagSet) { store.toggleSessionTag($0, on: log) }
        } header: {
            Text("What kind of day was it?")
        } footer: {
            Text("Tag an unusual session so the coach doesn't read it as lost strength or a plateau. Easy-on-purpose and run-down sessions aren't used as \"last time\" for your next targets.")
        }
    }
}
