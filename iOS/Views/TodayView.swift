import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var askMoreTraining = false
    @State private var showMoreTraining = false

    var body: some View {
        let stats = store.consistency
        let readiness = store.readiness
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    // Long-press the title to open the private More Training section.
                    Text("Today")
                        .font(.largeTitle.bold())
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.8) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            askMoreTraining = true
                        }

                    if let restored = store.restoredBackupDate {
                        Label("Restored your data from the iCloud backup of \(restored.formatted(date: .abbreviated, time: .shortened)).",
                              systemImage: "icloud.and.arrow.down")
                            .font(.footnote)
                            .card()
                    }
                }

                if let active = store.activeWorkout {
                    Button {
                        store.showWorkout = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Workout in progress", systemImage: "play.circle.fill").font(.headline)
                            Text("\(active.routine.name) · \(active.totalCompletedSets)/\(active.totalPlannedSets) sets")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if store.profile.isDeloadActive() {
                    HStack {
                        Label("Deload: one less set, ~10% lighter", systemImage: "leaf.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                        if store.profile.deloadUntil != nil {
                            Button("End") { store.endDeload() }.buttonStyle(.bordered)
                        }
                    }
                    .card()
                } else if let position = store.profile.program?.position(at: .now) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Week \(position.week) of \(position.block.weeks) · \(position.block.phase.title) block", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline)
                        Text("Effort this week: " + EffortTarget.text(EffortTarget.reps(profile: store.profile)) + " on working sets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("This week").font(.headline)
                        Spacer()
                        Text("\(stats.thisWeekCount) / \(stats.weeklyGoal)").font(.title3.bold())
                    }
                    if store.profile.cluckEnabled {
                        CluckBanner(snapshot: store.cluckSnapshot) { store.snoozeCluckToday() }
                    }
                    GymWeekRow(logs: store.workoutLogs, restDays: store.extras.restDays, plans: store.extras.dayPlans)
                    if !store.workoutLogs.contains(where: { Calendar.current.isDateInToday($0.startedAt) }) {
                        Button {
                            store.toggleRestDay()
                        } label: {
                            Label(store.isRestDay(.now) ? "Undo rest day" : "Rest day today",
                                  systemImage: store.isRestDay(.now) ? "arrow.uturn.backward" : "moon.zzz")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .tint(store.isRestDay(.now) ? .gray : .indigo)
                    }
                    SwiftUI.ProgressView(value: stats.thisWeekAdherence)
                    HStack {
                        Text("\(GFFormat.percent(stats.thisWeekAdherence)) adherence")
                        Spacer()
                        if stats.streakWeeks > 0 {
                            Label("\(stats.streakWeeks)-week streak", systemImage: "flame.fill")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if stats.last4WeeksTarget > 0 {
                        Text("Last 4 weeks: \(stats.last4WeeksCount) / \(stats.last4WeeksTarget) (\(GFFormat.percent(stats.last4WeeksAdherence)))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()

                Group {
                    TodayPlanCard()
                    BlockReviewCard()
                    Group {
                        BreakBanner()
                        CardioStartCard()
                        TrainingGoalsCard()
                    }
                    if store.weeklyReviewDue {
                        Button {
                            store.showWeeklyReview = true
                        } label: {
                            Label("Your weekly review is ready", systemImage: "chart.bar.doc.horizontal")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .card()
                    }
                    if let readiness {
                        ReadinessCard(readiness: readiness)
                    }
                    PhaseCard()
                    NutritionCard()
                    CalorieCard()
                    SleepCard()
                }

                if let insight = store.coachInsights.first(where: { $0.kind != .recovery || readiness == nil }) {
                    NavigationLink { CoachView() } label: {
                        InsightRow(insight: insight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    .buttonStyle(.plain)
                }

                if !store.watchBridge.isWatchReady {
                    Label(store.watchBridge.statusText, systemImage: "applewatch.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Start a workout").font(.title2.bold())

                if let next = store.suggestedRoutine {
                    routineCard(next, highlighted: true, lightSuggested: (readiness?.suggestLightSession ?? false) || store.comebackSuggested)
                }
                ForEach(store.routines.filter { $0.id != store.suggestedRoutine?.id }) { routine in
                    routineCard(routine, highlighted: false, lightSuggested: (readiness?.suggestLightSession ?? false) || store.comebackSuggested)
                }
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("More training?", isPresented: $askMoreTraining) {
            Button("Yes") {
                // Latest body fat (only if measured in the last ~4 months), read-only for the gap advice.
                let latestFat = store.healthKit.bodyFat.max(by: { $0.date < $1.date })
                MTVault.gymBodyFatPercent = latestFat.flatMap { $0.date > Date.now.addingTimeInterval(-120 * 86_400) ? $0.value : nil }
                Task {
                    if await MTVault.shared.unlock() { showMoreTraining = true }
                }
            }
            Button("No", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showMoreTraining) {
            MTRootView()
                .environmentObject(MTVault.shared)
        }
        .refreshable { await store.appBecameActive() }
        .onReceive(NotificationCenter.default.publisher(for: .openMoreTraining)) { _ in
            if !showMoreTraining { askMoreTraining = true }
        }
        .toolbar {
            // MK15: More Training in plain sight (still Face ID / passcode). Long-pressing the title still works.
            Button { askMoreTraining = true } label: { Label("More Training", systemImage: "lock.shield.fill") }
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
        }
    }

    @ViewBuilder
    private func routineCard(_ routine: WorkoutRoutine, highlighted: Bool, lightSuggested: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if highlighted {
                Text("UP NEXT").font(.caption.bold()).foregroundStyle(.tint)
            }
            NavigationLink {
                SessionPreviewView(routine: routine)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name).font(.title3.bold())
                        Text(lastDoneText(routine)).font(.subheadline).foregroundStyle(.secondary)
                        Text("Plan & coaching").font(.caption.bold()).foregroundStyle(.tint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                Task { await store.startWorkout(routine) }
            } label: {
                Label("Start on iPhone + Watch", systemImage: "applewatch")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(routine.exercises.isEmpty || store.activeWorkout != nil)

            if lightSuggested && !store.profile.isDeloadActive() {
                Button {
                    Task { await store.startWorkout(routine, light: true) }
                } label: {
                    Label("Start light session", systemImage: "leaf")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(routine.exercises.isEmpty || store.activeWorkout != nil)
            }
        }
        .card()
    }

    private func lastDoneText(_ routine: WorkoutRoutine) -> String {
        let last = store.lastDone(routine)
        let count = "\(routine.exercises.count) exercises"
        guard last > .distantPast else { return count + " · not done yet" }
        return count + " · last done " + last.formatted(.relative(presentation: .named))
    }
}

struct ReadinessCard: View {
    let readiness: Readiness

    private var color: Color {
        switch readiness.level {
        case .ready: return .green
        case .moderate: return .yellow
        case .low: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(readiness.title, systemImage: "bed.double.fill")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("\(readiness.score)")
                    .font(.title2.bold())
                    .foregroundStyle(color)
            }
            Text(readiness.reasons.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if readiness.suggestLightSession {
                Text("Consider a light session today — one less set and ~10% lighter, without affecting your progression.")
                    .font(.footnote)
            }
        }
        .card()
    }
}
