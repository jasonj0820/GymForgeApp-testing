import SwiftUI

/// Coach → Training block: start a fixed-length block (build weeks + a deload), or see where you are.
struct TrainingBlockSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var buildWeeks = 4
    @State private var confirmEnd = false

    var body: some View {
        Section {
            if let position = store.profile.program?.position(at: .now) {
                LabeledContent(store.profile.program?.name ?? "Program",
                               value: position.block.phase == .deload ? "Deload week" : "Week \(position.week) of \(position.block.weeks)")
                Text("Effort this week: " + EffortTarget.text(EffortTarget.reps(profile: store.profile)) + " on working sets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Change program") { ProgramSettingsView() }
                // MK15: end it here, then start a real block from today below.
                Button("End this block", role: .destructive) { confirmEnd = true }
                    .confirmationDialog("End \(store.profile.program?.name ?? "this block")? Your workouts and history stay; you can start a fresh block from today straight after.",
                                        isPresented: $confirmEnd, titleVisibility: .visible) {
                        Button("End block", role: .destructive) { store.endProgram() }
                    }
            } else {
                Stepper("Build weeks: \(buildWeeks)", value: $buildWeeks, in: 3...6)
                Button {
                    store.startCoachedBlock(buildWeeks: buildWeeks)
                } label: {
                    Label("Start a \(buildWeeks + 1)-week block today", systemImage: "calendar.badge.plus")
                }
            }
        } header: {
            Text("Training block")
        } footer: {
            Text("A block is \(buildWeeks) build weeks then a deload week, repeating. Effort rises through the block (about 3 reps left in week 1, down to 1 by the end); from week 2 the coach suggests a set more where you're recovering well. The deload is planned, so you never grind into the ground.")
        }
    }
}

/// Today: "Your block review is ready" during the deload and the week after.
struct BlockReviewCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        if let review = store.blockReview {
            NavigationLink {
                BlockReviewView(review: review)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Block review", systemImage: "flag.checkered")
                        .font(.headline)
                    Text(review.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

struct BlockReviewView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let review: BlockReview

    var body: some View {
        List {
            Section {
                Text(review.headline).font(.headline)
                Text(review.nextBlock).font(.subheadline)
            } header: {
                Text("\(review.start.formatted(date: .abbreviated, time: .omitted)) – \(review.end.formatted(date: .abbreviated, time: .omitted))")
            }
            if !review.lifts.isEmpty {
                Section("Strength (start vs end of block)") {
                    ForEach(review.lifts, id: \.name) { lift in
                        HStack {
                            Text(lift.name)
                            Spacer()
                            Text(String(format: "%+.1f%%", lift.percent))
                                .monospacedDigit()
                                .foregroundStyle(lift.percent >= 1 ? Color.green : (lift.percent <= -2 ? Color.red : Color.secondary))
                        }
                    }
                }
            }
            Section {
                ForEach(Muscle.allCases.filter { (review.muscleSets[$0] ?? 0) > 0 }) { muscle in
                    let sets = review.muscleSets[muscle] ?? 0
                    HStack {
                        Text(muscle.title)
                        Spacer()
                        Text(String(format: "%.1f", sets)).monospacedDigit()
                        Text("/ \(Int(muscle.weeklyRange.low))–\(Int(muscle.weeklyRange.high))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Hard sets per week")
            } footer: {
                Text("Sets with 4+ reps left count as half.")
            }
            Section {
                NavigationLink("See suggestions for next block") { CoachSuggestionsView() }
            }
        }
        .navigationTitle("Block review")
    }
}
