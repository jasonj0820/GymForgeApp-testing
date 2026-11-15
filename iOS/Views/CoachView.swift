import SwiftUI

struct CoachView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let proposals = store.coachProposals
        List {
            // MK24: plain-English questions, and why this week looks the way it does.
            Section {
                NavigationLink { AskCoachView() } label: { Label("Ask the coach", systemImage: "bubble.left.and.text.bubble.right") }
                NavigationLink { WeekChangesView() } label: { Label("This week's changes and why", systemImage: "arrow.up.arrow.down") }
            }
            if store.rotationDue {
                Section {
                    NavigationLink { AccessoryRotationView() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("New block: rotate accessories?", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                            Text("\(store.accessoryRotationPlan.count) accessor\(store.accessoryRotationPlan.count == 1 ? "y has" : "ies have") a swap option ready.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            BusyWeekSection()
            Section {
                FocusPicker()
                ForEach(proposals.prefix(3)) { ProposalRow(proposal: $0) }
                if proposals.isEmpty {
                    Label("No changes suggested — your plan looks good.", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                if proposals.count > 3 {
                    NavigationLink("All \(proposals.count) suggestions") { CoachSuggestionsView() }
                }
            } header: {
                Text("Suggested changes")
            } footer: {
                Text("Nothing changes until you accept.")
            }

            TrainingBlockSection()
            LiftGoalsSection()

            Section {
                NavigationLink {
                    MuscleVolumeView()
                } label: {
                    Label("Muscles & routine check", systemImage: "figure.arms.open")
                }
                NavigationLink {
                    RoutineBuilderView()
                } label: {
                    Label("Build a routine", systemImage: "hammer")
                }
                NavigationLink {
                    MonthlyReportView()
                } label: {
                    Label("Monthly report", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    AccessoryRotationView()
                } label: {
                    Label("Rotate accessories", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if let readiness = store.readiness {
                Section("Today's recovery") {
                    ReadinessCard(readiness: readiness)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(store.coachInsights) { insight in
                    VStack(alignment: .leading, spacing: 8) {
                        InsightRow(insight: insight)
                        if let action = insight.action, let title = insight.actionTitle {
                            Button(title) { store.perform(action) }
                                .buttonStyle(.bordered)
                                .padding(.leading, 40)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Insights")
            } footer: {
                Text("Goal: \(store.profile.goal.title) · Style: \(store.profile.coachStyle.title). Change these in Settings.")
            }

            Section("Next session targets") {
                ForEach(store.uniqueExercises) { base in
                    let exercise = store.profile.effective(base)
                    let recommendation = ProgressionEngine.recommendation(for: exercise, previous: store.previousLog(for: exercise))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.headline)
                        Text(recommendation.title).font(.subheadline.bold())
                        Text(recommendation.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Coach")
        .toolbar {
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
        }
    }
}
