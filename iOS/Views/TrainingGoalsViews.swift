import SwiftUI

/// MK11.1: lifting, running and basketball goals. MK21: opened from the Goals chip on Today's week card,
/// which shows this week's progress for each.
struct TrainingGoalsView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var goals = TrainingGoals()

    var body: some View {
        Form {
            Section {
                Stepper("Lifting: \(store.weeklyGoal) sessions", value: Binding(get: { store.weeklyGoal }, set: { store.setWeeklyGoal($0) }), in: 1...7)
            } header: {
                Text("Lifting")
            } footer: {
                Text("Sergeant Cluck enforces this one.")
            }
            Section {
                Stepper(runsText, value: int(\.runsPerWeek), in: 0...7)
                Stepper(kmText, value: km, in: 0...150, step: 5)
            } header: {
                Text("Running")
            } footer: {
                Text("0 = no goal.")
            }
            Section {
                Stepper(ballText, value: int(\.basketballPerWeek), in: 0...7)
            } header: {
                Text("Basketball")
            } footer: {
                Text("Tracked on its own — 0 just counts your games.")
            }
        }
        .navigationTitle("Training goals")
        .onAppear { goals = store.profile.trainingGoals ?? TrainingGoals() }
        .onChange(of: goals) { _, value in store.setTrainingGoals(value) }
    }

    private var runsText: String { (goals.runsPerWeek ?? 0) == 0 ? "Runs: no goal" : "Runs: \(goals.runsPerWeek ?? 0) a week" }
    private var kmText: String { (goals.runKmPerWeek ?? 0) == 0 ? "Distance: no goal" : String(format: "Distance: %.0f km a week", goals.runKmPerWeek ?? 0) }
    private var ballText: String { (goals.basketballPerWeek ?? 0) == 0 ? "Games: just track" : "Games: \(goals.basketballPerWeek ?? 0) a week" }

    private func int(_ keyPath: WritableKeyPath<TrainingGoals, Int?>) -> Binding<Int> {
        Binding(get: { goals[keyPath: keyPath] ?? 0 }, set: { goals[keyPath: keyPath] = $0 == 0 ? nil : $0 })
    }

    private var km: Binding<Double> {
        Binding(get: { goals.runKmPerWeek ?? 0 }, set: { goals.runKmPerWeek = $0 == 0 ? nil : $0 })
    }
}
