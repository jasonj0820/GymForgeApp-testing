import SwiftUI

/// Live workout on iPhone (opens full screen when a workout starts).
/// Every change is sent to the Watch, and Watch changes update this screen.
struct PhoneActiveWorkoutView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var minutesText = ""
    @State private var kmText = ""
    @State private var confirmDiscard = false
    @State private var editingNote = false
    @State private var noteDraft = ""
    /// The exercise the note being edited belongs to (it may stop being the current one meanwhile).
    @State private var noteExerciseID: UUID?
    /// Reps left in the tank for the set being entered (nil = not rated).
    @State private var effort: Int?
    @State private var warmupsDone: Set<String> = []
    @State private var flaggingPain: ExerciseDefinition?
    @State private var editingSet: SetEditTarget?
    @State private var managingExercise: ExerciseSlotTarget?
    /// Routine item id of the exercise getting a new swap option.
    @State private var addingSwapTo: UUID?
    @State private var swapNameDraft = ""
    @State private var addingExercise = false
    @FocusState private var focusedField: Field?

    private enum Field { case weight, reps, minutes, km }

    private func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
    private var typedWeight: Double? { number(weightText) }
    private var typedReps: Int? { Int(repsText.trimmingCharacters(in: .whitespaces)) }
    private var typedSeconds: Double? { number(minutesText).map { $0 * 60 } }
    private var typedKm: Double? { number(kmText) }

    var body: some View {
        // Split in two so the long modifier chain type-checks quickly.
        dialogs(screen)
    }

    private var screen: some View {
        Group {
            if let state = store.activeWorkout {
                workoutList(state)
            } else {
                ContentUnavailableView(
                    "No active workout",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Finished workouts are in Workouts → History.")
                )
            }
        }
        .navigationTitle(store.activeWorkout?.routine.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if let pr = store.prBanner {
                PRBanner(pr: pr)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: store.prBanner)
        .overlay {
            if let tick = store.setTick {
                SetTickOverlay(tick: tick)
                    .id(tick.id)
            }
        }
        .overlay {
            if store.activeWorkout?.finishRequested == true {
                VStack(spacing: 12) {
                    SwiftUI.ProgressView()
                    Text("Saving on Apple Watch…").font(.headline)
                    Text("Heart rate and calories are being saved to Apple Health.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .onChange(of: prefillKey) { _, _ in
            // New set: start with empty fields.
            weightText = ""
            repsText = ""
            minutesText = ""
            kmText = ""
            effort = nil
        }
        .onChange(of: weightText) { _, _ in sendDraft() }
        .onChange(of: repsText) { _, _ in sendDraft() }
        .onChange(of: minutesText) { _, _ in sendDraft() }
        .onChange(of: kmText) { _, _ in sendDraft() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    store.showWorkout = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Minimise")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingExercise = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add exercise")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { store.finishWorkout() }
                    .bold()
                    .disabled(store.activeWorkout?.finishRequested == true)
            }
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .weight {
                    Button("Next") { focusedField = .reps }
                } else if focusedField == .minutes {
                    Button("Next") { focusedField = .km }
                }
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    /// Sheets, alerts and dialogs for the workout screen.
    private func dialogs<Content: View>(_ content: Content) -> some View {
        content
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { store.cancelWorkout() }
        } message: {
            Text("Logged sets won't be saved and the Watch workout will end.")
        }
        .sheet(item: $flaggingPain) { exercise in
            PainFlagSheet(exercise: exercise) { flag in store.addPainFlag(flag) }
        }
        .sheet(item: $editingSet) { target in
            NavigationStack {
                EditSetView(target: target)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editingSet = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $addingExercise) {
            NavigationStack {
                ExercisePickerSheet(title: "Add exercise",
                                    suggestions: ExerciseLibrary.addSuggestions(for: store.activeWorkout?.routine),
                                    showRoutineToggle: true) { name, alsoToRoutine in
                    if let exercise = store.makeExercise(named: name) {
                        store.addExerciseToWorkout(exercise, alsoToRoutine: alsoToRoutine)
                    }
                }
            }
        }
        .sheet(item: $managingExercise) { target in
            ExerciseSetsSheet(target: target)
                .presentationDetents([.medium, .large])
        }
        .alert("New swap option", isPresented: Binding(
            get: { addingSwapTo != nil },
            set: { if !$0 { addingSwapTo = nil } }
        )) {
            TextField("e.g. Machine Chest Press", text: $swapNameDraft)
                .textInputAutocapitalization(.words)
            Button("Add & swap now") { addSwapOption(swapNow: true) }
                .disabled(swapNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Just add") { addSwapOption(swapNow: false) }
                .disabled(swapNameDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved to this exercise in your routine, so it's a swap option next time too (and on your Watch). It keeps its own history.")
        }
        .alert("Exercise note", isPresented: $editingNote) {
            TextField("e.g. Seat height 4", text: $noteDraft)
            Button("Save") {
                if let id = noteExerciseID ?? store.activeWorkout?.currentItem?.exercise.id {
                    store.updateNote(exerciseID: id, text: noteDraft)
                }
                noteExerciseID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown on your iPhone and Watch whenever this exercise comes up.")
        }
    }

    private func addSwapOption(swapNow: Bool) {
        guard let id = addingSwapTo,
              let index = store.activeWorkout?.routine.exercises.firstIndex(where: { $0.id == id }) else { return }
        store.addSwapOption(named: swapNameDraft, at: index, swapNow: swapNow)
        addingSwapTo = nil
    }

    private var prefillKey: String {
        guard let state = store.activeWorkout, let item = state.currentItem else { return "none" }
        return "\(state.workoutID)-\(item.exercise.id)-\(state.sets(for: item).count)"
    }

    private func sendDraft() {
        if store.activeWorkout?.currentItem?.exercise.isCardio == true {
            store.sendDraft(weightKg: nil, reps: nil, durationSeconds: typedSeconds, distanceKm: typedKm)
        } else {
            store.sendDraft(weightKg: typedWeight, reps: typedReps)
        }
    }

    @ViewBuilder
    private func workoutList(_ state: ActiveWorkoutState) -> some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Label(GFFormat.duration(context.date.timeIntervalSince(state.startedAt)), systemImage: "timer")
                        Spacer()
                        Text("\(state.totalCompletedSets) / \(state.totalPlannedSets) sets")
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
                if state.deload {
                    Label("Light session — one less set, ~10% lighter. Won't affect progression.", systemImage: "leaf.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if let phase = state.phaseName {
                    Label("\(phase) block", systemImage: "chart.bar.doc.horizontal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if state.isResting, let end = state.restEndDate {
                    restRow(state: state, end: end)
                }
            }

            Section {
                CluckCoachCard(state: state)
                motivationCard(state)
                SpeechMiniPlayer()
            }

            if let item = state.currentItem, !state.isComplete {
                currentExercise(state, item)
            } else {
                Section {
                    Label("All planned sets done", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                    Text("Tap Finish to save, or tap an exercise below to add an extra set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(Array(state.routine.exercises.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Button {
                            if index == state.exerciseIndex && !state.isFinished(item) {
                                // Already on it: show its sets instead (jumping would cancel the rest timer).
                                managingExercise = ExerciseSlotTarget(id: item.id)
                            } else if state.isFinished(item) && !state.isSkipped(item) {
                                store.addExtraSet(toExercise: index)
                            } else {
                                store.jumpToExercise(index)
                            }
                        } label: {
                            exerciseRow(state: state, index: index, item: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            managingExercise = ExerciseSlotTarget(id: item.id)
                        } label: {
                            Image(systemName: "pencil.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit sets for \(item.exercise.name)")
                    }
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Tap an exercise to do it next (done ones get an extra set). Tap ✎ to fix logged sets or change how many sets are planned.")
            }

            Section {
                SessionTagChips(selected: Set(state.sessionTags ?? [])) { store.toggleSessionTag($0) }
            } header: {
                Text("Today's context")
            } footer: {
                Text("Short on time, kit taken, easy on purpose or run down? Tag it and the coach won't read lower numbers as lost strength.")
            }

            Section {
                Button {
                    store.finishWorkout()
                } label: {
                    Label("Finish & save workout", systemImage: "flag.checkered")
                }
                Button("Discard workout", role: .destructive) { confirmDiscard = true }
            } footer: {
                Text("Heart rate and calories are recorded by the Watch and saved to Apple Health when the workout finishes.")
            }
        }
    }

    /// Coach quote, in its own section above the current exercise. Changes after every set.
    private func motivationCard(_ state: ActiveWorkoutState) -> some View {
        let style = store.profile.coachStyle
        let line = style.workoutLine(workout: state.workoutID, step: state.totalCompletedSets)
        return VStack(alignment: .leading, spacing: 6) {
            Label(style.title.uppercased(), systemImage: "quote.opening")
                .font(.caption2.bold())
                .foregroundStyle(.tint)
            Text(line)
                .font(.title3.weight(.semibold))
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .id(line)
                .transition(.opacity)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.4), value: line)
    }

    private func exerciseRow(state: ActiveWorkoutState, index: Int, item: RoutineExercise) -> some View {
        HStack {
            Image(systemName: state.isFinished(item) ? "checkmark.circle.fill" : (index == state.exerciseIndex ? "arrow.right.circle.fill" : "circle"))
                .foregroundStyle(state.isFinished(item) ? Color.green : Color.accentColor)
            if let label = state.supersetLabel(for: index) {
                Text(label)
                    .font(.caption.bold())
                    .foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name).foregroundStyle(.primary)
                if let original = state.swappedFrom(item) {
                    Text("swapped from \(original.name)").font(.caption2).foregroundStyle(.secondary)
                }
                if state.isSkipped(item) {
                    Text("skipped — tap to do it").font(.caption2).foregroundStyle(.orange)
                }
                let logged = state.sets(for: item)
                if !logged.isEmpty {
                    Text(logged.map(\.summaryText).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text("\(state.sets(for: item).count) / \(item.exercise.defaultSets)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func restRow(state: ActiveWorkoutState, end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = end.timeIntervalSince(context.date)
            HStack {
                if remaining > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Rest \(GFFormat.duration(remaining.rounded(.up)))", systemImage: "hourglass")
                            .monospacedDigit()
                        if failedHeavySet(state) {
                            Text("Last set was to failure — take 30 s more")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Label("Rest done — next set ready", systemImage: "bell.fill")
                }
                Spacer()
                Button("+30s") { store.addRest(seconds: 30) }
                    .buttonStyle(.bordered)
                Button("Skip") { store.skipRest() }
                    .buttonStyle(.bordered)
            }
        }
    }

    /// The set just logged was to failure on a tiring lift: worth a little more rest.
    private func failedHeavySet(_ state: ActiveWorkoutState) -> Bool {
        guard let last = state.lastLoggedSet, last.rir == 0,
              let exerciseID = state.completedSets.first(where: { $0.value.contains { $0.id == last.id } })?.key,
              let exercise = state.exerciseDefinition(id: exerciseID),
              let info = ExerciseLibrary.profile(for: exercise.name) else { return false }
        return info.fatigue >= 2
    }

    @ViewBuilder
    private func currentExercise(_ state: ActiveWorkoutState, _ item: RoutineExercise) -> some View {
        let exercise = item.exercise
        let index = state.exerciseIndex
        let done = state.sets(for: item)
        let previous = store.previousLog(for: exercise, before: state.startedAt)
        let recommendation = ProgressionEngine.recommendation(for: exercise, previous: previous)
        let plan = store.setPlan(for: item)
        let options = state.swapOptions(for: item)

        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    if let label = state.supersetLabel(for: index) {
                        Text("Superset \(label)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15), in: Capsule())
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                    Menu {
                        ForEach(options) { option in
                            Button(option.name) { store.swapExercise(at: index, to: option) }
                        }
                        if !options.isEmpty { Divider() }
                        Button {
                            swapNameDraft = ""
                            addingSwapTo = item.id
                        } label: {
                            Label("Add swap option…", systemImage: "plus")
                        }
                    } label: {
                        Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                    }
                    Button {
                        flaggingPain = exercise
                    } label: {
                        Label("Pain", systemImage: "bandage").font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                    Button {
                        store.skipExercise(at: index)
                    } label: {
                        Label("Skip", systemImage: "forward.fill").font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
                Text(exercise.name).font(.title3.bold())
                if let machine = exercise.equipmentName {
                    Label(machine + (exercise.loadConvention == .total ? "" : " · " + exercise.loadConvention.title.lowercased()),
                          systemImage: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let original = state.swappedFrom(item) {
                    HStack {
                        Text("Instead of \(original.name) — logged separately")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !store.isPermanent(item, in: state) {
                            Button("Make permanent") { store.makeSwapPermanent(at: index) }
                                .font(.caption.bold())
                                .buttonStyle(.borderless)
                        } else {
                            Label("Now in routine", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                        }
                    }
                }
                Text(exercise.isCardio
                     ? "Target \(exercise.cardioMinutes) min"
                     : "Set \(min(done.count + 1, exercise.defaultSets)) of \(exercise.defaultSets) · \(exercise.repMin)–\(exercise.repMax) reps")
                    .foregroundStyle(.secondary)

                Button {
                    noteDraft = exercise.notes ?? ""
                    noteExerciseID = exercise.id
                    editingNote = true
                } label: {
                    if let note = exercise.notes, !note.isEmpty {
                        Label(note, systemImage: "note.text")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                    } else {
                        Label("Add note", systemImage: "note.text.badge.plus")
                            .font(.footnote)
                    }
                }
                .buttonStyle(.borderless)

                if !exercise.isCardio {
                    VariationRow(state: state, item: item)
                }

                if let plateau = store.phaseCoach.plateau(for: exercise) {
                    WorkoutPlateauBanner(plateau: plateau)
                        .id(exercise.historyKey)
                }

                let flags = store.extras.activePainFlags(for: exercise)
                if let flag = flags.last {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(flag.advice(swap: options.first?.name), systemImage: "bandage.fill")
                            .font(.footnote)
                            .foregroundStyle(flag.severity >= 3 ? Color.red : Color.orange)
                        Button("Feels fine now") { store.resolvePainFlags(for: exercise) }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                    }
                }

                if let previous {
                    Text("Last time: " + previous.sets.map { previous.summary($0) }.joined(separator: ", "))
                        .font(.footnote)
                }
                Text(exercise.isCardio || plan.reason.isEmpty ? recommendation.message : plan.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            planRow(plan, exercise: exercise, done: done)

            if !exercise.isCardio {
                Stepper(value: Binding(get: { exercise.defaultSets },
                                       set: { store.setPlannedSets($0, at: index) }),
                        in: max(1, done.count)...max(20, done.count)) {
                    HStack {
                        Label("Sets today", systemImage: "square.stack.3d.up")
                        Spacer()
                        Text("\(exercise.defaultSets)")
                            .font(.body.bold().monospacedDigit())
                    }
                }
            }

            if exercise.isCardio {
                cardioFields(item)
            } else {
                if done.isEmpty {
                    warmupRow(state: state, item: item)
                }
                strengthFields(item)
                effortPicker
            }

            ForEach(done) { set in
                Button {
                    editingSet = SetEditTarget(id: set.id, exerciseID: exercise.id)
                } label: {
                    HStack {
                        Text(exercise.isCardio ? "Logged" : "Set \(set.setNumber)")
                            .foregroundStyle(.primary)
                        if set.isPR == true {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                        }
                        Spacer()
                        if let recovery = set.heartRateRecovery {
                            Text("HR ↓\(Int(recovery))").font(.caption).foregroundStyle(.green)
                        }
                        Text(set.summary(load: exercise.load)).foregroundStyle(.secondary)
                        // MK10.1: against the same set last time.
                        if !exercise.isCardio, let index = done.firstIndex(where: { $0.id == set.id }),
                           let versus = SetComparison.arrow(set: set, index: index, previous: previous) {
                            Text("\(versus.text) \(versus.arrow.rawValue)")
                                .font(.caption2.bold().monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(versus.arrow == .up ? Color.green : (versus.arrow == .down ? Color.red : Color.secondary))
                        }
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.deleteSet(id: set.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            if !exercise.isCardio, done.count >= 2,
               let advice = SetComparison.advice(current: done, previous: previous, repMin: exercise.repMin,
                                                 repMax: exercise.repMax, assisted: exercise.isAssisted) {
                Label((done.count >= exercise.defaultSets ? "" : "So far: ") + advice, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                logSet(exercise)
            } label: {
                Label(exercise.isCardio ? "Log cardio" : "Complete set & rest", systemImage: exercise.isCardio ? "checkmark" : "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(exercise.isCardio ? (typedSeconds ?? 0) <= 0 : (typedReps == nil || (typedWeight == nil && !exercise.isBodyweight)))
        } header: {
            Text("Now")
        } footer: {
            Text(exercise.isCardio
                 ? "Type minutes (and km if you like), or use the timer on your Watch."
                 : "Grey numbers are today's plan for this set — type what you actually did. If a set goes clearly better or worse, the rest are re-aimed; if one falls short of the range, a lighter weight is suggested (your call). Tap a logged set to fix it; swipe it left to delete. Use Sets today to add or drop a set.")
        }
    }

    /// Today's target for every set: ✓ done, the current one highlighted, plus any re-aim note.
    @ViewBuilder
    private func planRow(_ plan: SetPlan, exercise: ExerciseDefinition, done: [WorkoutSetLog]) -> some View {
        if !exercise.isCardio, !plan.targets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("TODAY'S PLAN").font(.caption2.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<max(plan.targets.count, done.count), id: \.self) { index in
                            planChip(index: index, plan: plan, exercise: exercise, done: done)
                        }
                    }
                }
                if let effort = effortLine(plan) {
                    Label(effort, systemImage: "gauge.with.dots.needle.33percent")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let note = plan.adjustment {
                    Label(note, systemImage: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let lighter = plan.suggestedWeightKg, done.count < exercise.defaultSets {
                    HStack {
                        Button("Use \(exercise.formatLoad(lighter))") {
                            weightText = GFFormat.kg(lighter)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        Button("Keep weight") {
                            if let last = done.last { weightText = GFFormat.kg(last.weightKg) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.footnote)
                }
            }
        }
    }

    /// "Block week 2 of 4 · stop each set with ~2 reps left (last set ~1)".
    private func effortLine(_ plan: SetPlan) -> String? {
        guard let first = plan.targets.first?.rir else { return nil }
        let last = plan.targets.last?.rir ?? first
        var text = "Effort: " + EffortTarget.text(first)
        if last != first { text += " (last set " + EffortTarget.text(last) + ")" }
        if let label = store.activeWorkout?.blockLabel { text = label + " · " + text }
        return text
    }

    private func planChip(index: Int, plan: SetPlan, exercise: ExerciseDefinition, done: [WorkoutSetLog]) -> some View {
        let isDone = index < done.count
        let isCurrent = index == done.count
        let weight = isDone ? done[index].weightKg : (plan.target(at: index)?.weightKg ?? 0)
        let reps = isDone ? done[index].reps : (plan.target(at: index)?.reps ?? 0)
        let weightText = weight > 0 ? GFFormat.kg(weight) : (exercise.isBodyweight ? "BW" : "?")
        return Text((isDone ? "✓ " : "\(index + 1) · ") + "\(weightText)×\(reps)")
            .font(.caption.monospacedDigit().weight(isCurrent ? .bold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isDone ? Color.green.opacity(0.18) : (isCurrent ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12))))
    }

    @ViewBuilder
    private func strengthFields(_ item: RoutineExercise) -> some View {
        let hint = store.prefill(for: item)
        let exercise = item.exercise
        HStack {
            Text(exercise.isAssisted ? "Assistance" : (exercise.isBodyweight ? "Added weight" : (exercise.loadConvention == .stackLevel ? "Level" : "Weight")))
            if exercise.isAssisted {
                Text("less = harder").font(.caption).foregroundStyle(.secondary)
            } else if exercise.isBodyweight {
                Text("optional").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TextField(GFFormat.kg(hint.weightKg), text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .weight)
                .frame(width: 90)
            Text(exercise.isAssisted ? "kg" : exercise.loadConvention.unit).foregroundStyle(.secondary)
        }
        HStack {
            Text("Reps")
            Spacer()
            TextField("\(hint.reps)", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .reps)
                .frame(width: 90)
            Text("reps").foregroundStyle(.secondary)
        }
    }

    /// One warm-up at 40% of today's working weight before the first set.
    @ViewBuilder
    private func warmupRow(state: ActiveWorkoutState, item: RoutineExercise) -> some View {
        let key = "\(state.workoutID)-\(item.exercise.id)"
        let working = store.prefill(for: item).weightKg
        // From the exercise library: ramp-up sets for heavy compounds, none for isolation work.
        let ramps = CoachBrain.warmups(for: item.exercise, working: working)
        if !warmupsDone.contains(key), ramps?.isEmpty != true {
            let step = item.exercise.weightIncrementKg > 0 ? item.exercise.weightIncrementKg : 2.5
            let assisted = item.exercise.isAssisted
            // Assisted: warm up with MORE help (≈ +40%); otherwise 40% of the working weight.
            let warm = assisted ? max(((working * 1.4) / step).rounded(.up) * step, working + step) : (working * 0.4 / step).rounded() * step
            let detail = ramps.map { rampText($0, exercise: item.exercise) } ?? warmupText(assisted: assisted, warm: warm, working: working)
            HStack {
                Image(systemName: "flame").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Warm-up first").font(.subheadline.bold())
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { warmupsDone.insert(key) }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func rampText(_ ramps: [SetTarget], exercise: ExerciseDefinition) -> String {
        if ramps.allSatisfy({ $0.weightKg <= 0 }) { return "Ramp up: an empty bar / light set × 10, then a couple of easy sets" }
        return "Ramp up: " + ramps.map { "\(exercise.formatLoad($0.weightKg)) × \($0.reps)" }.joined(separator: " · ")
    }

    private func warmupText(assisted: Bool, warm: Double, working: Double) -> String {
        if working <= 0 {
            return assisted ? "Easy set × 6 with plenty of assistance" : "Light weight × 10–12 (~40% of your working weight)"
        }
        if assisted {
            return "\(GFFormat.kg(warm)) kg assist × 6 (more help than your \(GFFormat.kg(working)) kg working sets)"
        }
        return "\(GFFormat.kg(warm)) kg × 10 (40% of \(GFFormat.kg(working)) kg)"
    }

    /// Reps left in the tank: guides progression (failure on the last set = repeat the weight).
    private var effortPicker: some View {
        HStack(spacing: 6) {
            Text("Reps left")
            Spacer()
            ForEach([0, 1, 2, 3, 4], id: \.self) { value in
                Button {
                    effort = effort == value ? nil : value
                } label: {
                    Text(value == 0 ? "Fail" : (value == 4 ? "4+" : "\(value)"))
                        .font(.subheadline.bold())
                        .frame(minWidth: 30)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(effort == value ? Color.accentColor : Color.secondary.opacity(0.15)))
                        .foregroundStyle(effort == value ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func cardioFields(_ item: RoutineExercise) -> some View {
        let hint = store.cardioPrefill(for: item)
        HStack {
            Text("Time")
            Spacer()
            TextField(GFFormat.km(hint.minutes), text: $minutesText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .minutes)
                .frame(width: 90)
            Text("min").foregroundStyle(.secondary)
        }
        HStack {
            Text("Distance")
            Spacer()
            TextField(hint.km.map { GFFormat.km($0) } ?? "optional", text: $kmText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: .km)
                .frame(width: 90)
            Text("km").foregroundStyle(.secondary)
        }
    }

    private func logSet(_ exercise: ExerciseDefinition) {
        focusedField = nil
        if exercise.isCardio {
            guard let seconds = typedSeconds, seconds > 0 else { return }
            store.completeSetOnPhone(weightKg: 0, reps: 0, durationSeconds: seconds, distanceKm: typedKm)
        } else if let count = typedReps, let weight = typedWeight ?? (exercise.isBodyweight ? 0 : nil) {
            store.completeSetOnPhone(weightKg: weight, reps: count, rir: effort)
        }
    }
}

struct PRBanner: View {
    let pr: PRHit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("New PR — \(pr.headline)").font(.headline)
                Text("\(pr.exerciseName): \(GFFormat.kg(pr.weightKg)) kg × \(pr.reps)").font(.subheadline)
                Text(pr.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.6), lineWidth: 1))
    }
}
