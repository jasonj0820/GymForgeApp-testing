import SwiftUI

/// Tap a routine on Today → today's plan: targets, last time, coaching per exercise,
/// with Start pinned at the bottom.
struct SessionPreviewView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let routine: WorkoutRoutine
    @State private var plateaus: [PhaseCoach.Plateau] = []
    @State private var deload: PhaseCoach.Warning?
    @State private var showPlateaus = false
    @State private var checkedPlateaus = false
    /// Time budget in minutes (nil = the full session).
    @State private var budget: Int?
    @State private var addingExercise = false

    var body: some View {
        let current = store.routines.first { $0.id == routine.id } ?? routine
        let readiness = store.readiness
        let plan = SessionCoach.plan(for: current, logs: store.workoutLogs, profile: store.profile, readiness: readiness)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(plan, routine: current)
                ForEach(plan.exercises) { preview in
                    ExercisePreviewCard(preview: preview, routineID: current.id)
                }
                if plan.exercises.isEmpty {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                           description: Text("Add one below, or in the Workouts tab."))
                }
                // MK10.1: add an exercise to this routine from here.
                Button {
                    addingExercise = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            startBar(routine: current, plan: plan, lightSuggested: (readiness?.suggestLightSession ?? false) || store.comebackSuggested)
        }
        .onAppear {
            // MK11.3: on a maintenance break, sessions default to 30 minutes.
            if store.activeBreak?.mode == .maintenance, budget == nil { budget = 30 }
            // Every time you open a routine: check its lifts for plateaus (or strength loss on a cut).
            guard !checkedPlateaus else { return }
            checkedPlateaus = true
            let coach = store.phaseCoach
            plateaus = coach.plateaus(in: current)
            deload = coach.deloadSuggestion
            showPlateaus = !plateaus.isEmpty
        }
        .sheet(isPresented: $addingExercise) {
            NavigationStack {
                ExercisePickerSheet(title: "Add to \(current.name)",
                                    suggestions: ExerciseLibrary.addSuggestions(for: current)) { name, _ in
                    if let exercise = store.makeExercise(named: name) { store.addExercise(exercise, toRoutine: current.id) }
                }
            }
        }
        .sheet(isPresented: $showPlateaus) {
            PlateauSheet(routineName: current.name, plateaus: plateaus, deload: deload)
        }
        .toolbar {
            if !plateaus.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPlateaus = true
                    } label: {
                        Label("\(plateaus.count)", systemImage: "chart.line.flattrend.xyaxis")
                    }
                    .tint(.orange)
                }
            }
        }
    }

    // MARK: Top summary

    private func summary(_ plan: SessionPlan, routine: WorkoutRoutine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip("≈ \(plan.estimatedMinutes) min", "clock")
                if plan.totalSets > 0 { chip("\(plan.totalSets) sets", "square.stack.3d.up") }
                chip("\(plan.exercises.count) exercises", "dumbbell")
            }
            let last = store.lastDone(routine)
            if last > .distantPast {
                Text("Last done \(last.formatted(.relative(presentation: .named)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let warnings = CoachBrain.recoveryWarnings(for: routine, logs: store.workoutLogs, cardio: store.cardioSessions)
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "battery.25")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if !plan.headline.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Coach · \(store.profile.coachStyle.title)", systemImage: "figure.strengthtraining.traditional")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                    ForEach(plan.headline, id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    // MARK: Start bar

    private func startBar(routine: WorkoutRoutine, plan: SessionPlan, lightSuggested: Bool) -> some View {
        VStack(spacing: 8) {
            if store.activeWorkout != nil {
                Button {
                    store.showWorkout = true
                } label: {
                    Label("Resume current workout", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                budgetPicker(routine: routine, fullMinutes: store.timeBudgetPreview(routine, minutes: nil).minutes)
                Button {
                    start(routine, light: false)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(routine.exercises.isEmpty)

                if lightSuggested && !plan.isDeload {
                    Button {
                        start(routine, light: true)
                    } label: {
                        Label("Start light session", systemImage: "leaf")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(routine.exercises.isEmpty)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func start(_ routine: WorkoutRoutine, light: Bool) {
        // Back to Today underneath, so finishing the workout doesn't land you on an old plan.
        dismiss()
        let minutes = budget
        Task { await store.startWorkout(routine, light: light, budgetMinutes: minutes) }
    }

    /// "I have 45 min": trims sets from the least important exercises first, then skips whole ones.
    @ViewBuilder
    private func budgetPicker(routine: WorkoutRoutine, fullMinutes: Int) -> some View {
        let options = [30, 45, 60, 75, 90].filter { $0 < fullMinutes }
        if !options.isEmpty {
            let preview = store.timeBudgetPreview(routine, minutes: budget)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock")
                    Text("Time")
                    Spacer()
                    Picker("Time", selection: $budget) {
                        Text("Full (≈ \(fullMinutes) min)").tag(Int?.none)
                        ForEach(options, id: \.self) { minutes in
                            Text("\(minutes) min").tag(Int?.some(minutes))
                        }
                    }
                    .pickerStyle(.menu)
                }
                .font(.subheadline)
                if budget != nil {
                    Text(preview.cuts.isEmpty
                         ? "Fits as planned."
                         : "≈ \(preview.minutes) min. Cuts: " + preview.cuts.joined(separator: " · ") + ". Skipped ones can still be tapped mid-workout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ExercisePreviewCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    let preview: ExercisePreview
    /// MK10.1: set to edit the routine from the card (replace / move / remove).
    var routineID: UUID? = nil
    @State private var replacing = false
    @State private var confirmRemove = false

    private var trendColor: Color {
        switch preview.trend {
        case .improving: return .green
        case .flat: return .orange
        case .declining: return .red
        case .steady: return .secondary
        case .new: return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name + trend
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let label = preview.supersetLabel {
                    Text(label)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
                Text(preview.exercise.name).font(.headline)
                Spacer()
                Label(preview.trend.label, systemImage: preview.trend.symbol)
                    .font(.caption.bold())
                    .foregroundStyle(trendColor)
                if let routineID {
                    Menu {
                        Button { replacing = true } label: { Label("Replace permanently…", systemImage: "arrow.triangle.2.circlepath") }
                        Button { store.moveExercise(routineID: routineID, itemID: preview.id, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                        Button { store.moveExercise(routineID: routineID, itemID: preview.id, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                        Button(role: .destructive) { confirmRemove = true } label: { Label("Remove from routine", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $replacing) {
                NavigationStack {
                    ExercisePickerSheet(title: "Replace \(preview.exercise.name)",
                                        suggestions: ExerciseLibrary.swapSuggestions(for: preview.exercise,
                                                                                    in: store.routines.first { $0.id == routineID })) { name, _ in
                        if let routineID, let exercise = store.makeExercise(named: name, sets: preview.exercise.defaultSets, like: preview.exercise) {
                            store.replaceExercise(routineID: routineID, itemID: preview.id, with: exercise)
                        }
                    }
                }
            }
            .confirmationDialog("Remove \(preview.exercise.name) from this routine?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let routineID { store.removeExercise(routineID: routineID, itemID: preview.id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its history is kept.")
            }

            // Today's target
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY").font(.caption2.bold()).foregroundStyle(.secondary)
                Text(preview.targetTitle).font(.title3.bold())
                if let sets = preview.setPlanText {
                    Label(sets, systemImage: "list.number")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.tint)
                }
                if let detail = preview.targetDetail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if let why = preview.planReason, !why.isEmpty {
                    Text("Why: " + why)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Last time
            if let last = preview.lastTime {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last time" + (preview.lastDate.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(last).font(.subheadline.monospacedDigit())
                    }
                    if preview.hadPR {
                        Spacer()
                        Label("PR", systemImage: "trophy.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Coaching
            if !preview.coaching.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(preview.coaching, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "megaphone.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                            Text(line).font(.subheadline)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
            }

            // Form cues
            if !preview.formCues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FORM").font(.caption2.bold()).foregroundStyle(.secondary)
                    ForEach(preview.formCues, id: \.self) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cue).font(.subheadline)
                        }
                    }
                }
            }

            // Pain flags
            if let flag = store.extras.activePainFlags(for: preview.exercise).last {
                Label(flag.advice(swap: preview.swaps.first), systemImage: "bandage.fill")
                    .font(.footnote)
                    .foregroundStyle(flag.severity >= 3 ? Color.red : Color.orange)
            }

            // Notes + swaps
            if let note = preview.exercise.notes, !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !preview.swaps.isEmpty {
                Label("Swap options: " + preview.swaps.joined(separator: ", "), systemImage: "arrow.triangle.swap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
