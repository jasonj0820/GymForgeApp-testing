import SwiftUI

struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercise: ExerciseDefinition
    /// False when editing a preset swap (swaps can't have their own swaps).
    var allowsAlternatives = true
    let onSave: (ExerciseDefinition) -> Void

    /// Typed as text (one cue per line; empty = built-in cues) and only split up on Save,
    /// so Return works anywhere — including between two cues.
    @State private var cuesDraft = ""
    /// Typed as text so the decimal pad (no Return key) still saves what you typed.
    @State private var incrementText = ""
    @State private var loadedDrafts = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                    .onChange(of: exercise.name) { _, name in
                        // New assisted pull-ups / chin-ups start at 6–10 reps.
                        let lower = name.lowercased()
                        if exercise.isAssisted, lower.contains("pull") || lower.contains("chin"),
                           exercise.repMin == 8, exercise.repMax == 12 {
                            exercise.repMin = 6
                            exercise.repMax = 10
                        }
                    }
                Picker("Category", selection: $exercise.category) {
                    ForEach(ExerciseCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                // Recognised exercise: one tap for the coach's recommended settings.
                if let info = ExerciseLibrary.profile(for: exercise.name), info.category != .cardio,
                   exercise.repMin != info.repMin || exercise.repMax != info.repMax
                    || exercise.restSeconds != info.restSeconds || exercise.weightIncrementKg != info.increment {
                    Button {
                        ExerciseLibrary.apply(defaultsTo: &exercise)
                        incrementText = GFFormat.kg(exercise.weightIncrementKg)
                    } label: {
                        Label("Use coach settings for \(info.name): \(info.repMin)–\(info.repMax) reps, \(GFFormat.duration(TimeInterval(info.restSeconds))) rest, \(GFFormat.kg(info.increment)) kg steps",
                              systemImage: "wand.and.stars")
                            .font(.footnote)
                    }
                }
            } header: {
                Text("Exercise")
            } footer: {
                if exercise.isAssisted {
                    Text("Assisted exercise: the weight is the machine's help, so LESS weight is harder. Progression takes assistance away when you hit the top of the rep range, and a PR is your least assistance ever.")
                }
            }

            if !exercise.isCardio {
                Section {
                    TextField("Machine / brand (optional), e.g. Hammer Strength", text: Binding(
                        get: { exercise.equipment ?? "" },
                        set: { exercise.equipment = $0.isEmpty ? nil : $0 }
                    ))
                    Picker("Weight is", selection: Binding(
                        get: { exercise.loadConvention },
                        set: { newValue in
                            exercise.load = newValue == .total ? nil : newValue
                            // Pin-stack levels go up one level at a time.
                            if newValue == .stackLevel, exercise.weightIncrementKg == 2.5 {
                                exercise.weightIncrementKg = 1
                                incrementText = "1"
                            }
                        }
                    )) {
                        ForEach(LoadConvention.allCases) { convention in
                            Text(convention.title).tag(convention)
                        }
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text(exercise.equipmentName.map { _ in "Logged as \"\(exercise.loggedName)\" — this machine keeps its own history, PRs and progression. Use a different exercise (or a swap option) for another machine." }
                         ?? "Different machines for the same exercise? Name the machine so each keeps its own history and progression. Per side / per hand / pin-stack levels are shown with the right unit.")
                }
            }

            if exercise.isCardio {
                Section {
                    Stepper("Target: \(exercise.cardioMinutes) min", value: $exercise.cardioMinutes, in: 1...180)
                } header: {
                    Text("Cardio")
                } footer: {
                    Text("Log time (and distance if you like). On the Watch you can run a timer instead.")
                }
            } else {
                Section("Progression") {
                    Stepper("Sets: \(exercise.defaultSets)", value: $exercise.defaultSets, in: 1...10)
                    Stepper("Minimum reps: \(exercise.repMin)", value: $exercise.repMin, in: 1...50)
                    Stepper("Maximum reps: \(exercise.repMax)", value: $exercise.repMax, in: exercise.repMin...60)
                        .onChange(of: exercise.repMin) { _, newMin in
                            if exercise.repMax < newMin { exercise.repMax = newMin }
                        }

                    HStack {
                        Text(exercise.isAssisted ? "Assistance step" : (exercise.loadConvention == .stackLevel ? "Level step" : "Weight increase"))
                        Spacer()
                        TextField("kg", text: $incrementText)
                            .keyboardType(.decimalPad)
                            .onChange(of: incrementText) { _, text in
                                if let value = Double(text.replacingOccurrences(of: ",", with: ".")
                                    .trimmingCharacters(in: .whitespaces)), value >= 0 {
                                    exercise.weightIncrementKg = value
                                }
                            }
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(exercise.loadConvention == .stackLevel ? "lvl" : "kg").foregroundStyle(.secondary)
                    }
                    if exercise.weightIncrementKg <= 0 {
                        Text("A step of 0 marks a bodyweight exercise: no weight to type, progression is by reps.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Rest") {
                Stepper("\(GFFormat.duration(TimeInterval(exercise.restSeconds))) rest", value: $exercise.restSeconds, in: 0...600, step: 15)
            }

            Section {
                TextField("e.g. Seat height 4, use the left cable", text: $exercise.noteText, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Notes")
            } footer: {
                Text("Shown on your iPhone and Watch whenever this exercise comes up.")
            }

            Section {
                TextField(FormCues.builtIn(for: exercise).joined(separator: "\n"), text: $cuesDraft, axis: .vertical)
                    .lineLimit(2...8)
                if cuesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Start from the built-in cues") {
                        cuesDraft = FormCues.builtIn(for: exercise).joined(separator: "\n")
                    }
                } else {
                    Button("Reset to built-in cues", role: .destructive) { cuesDraft = "" }
                }
            } header: {
                Text("Form cues")
            } footer: {
                Text("One cue per line. Shown on the session preview when you tap a routine. Leave empty to use the built-in cues (shown in grey).")
            }

            if allowsAlternatives {
                Section {
                    ForEach(exercise.alternativeList) { alternative in
                        NavigationLink {
                            ExerciseEditorView(exercise: alternative, allowsAlternatives: false) { updated in
                                if let index = exercise.alternativeList.firstIndex(where: { $0.id == updated.id }) {
                                    exercise.alternativeList[index] = updated
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alternative.name)
                                Text(alternative.isCardio ? "\(alternative.cardioMinutes) min" : "\(alternative.defaultSets) × \(alternative.repMin)–\(alternative.repMax)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        exercise.alternativeList.remove(atOffsets: offsets)
                    }

                    NavigationLink {
                        ExerciseEditorView(exercise: exercise.makeAlternative(), allowsAlternatives: false) { created in
                            exercise.alternativeList.append(created)
                        }
                    } label: {
                        Label("Add swap option", systemImage: "plus")
                    }
                } header: {
                    Text("Swap options")
                } footer: {
                    Text("Preset exercises you can switch to mid-workout (e.g. Chest Press → Bench Press or Incline Bench). Each keeps its own weights and history.")
                }
            }

            if !exercise.isCardio {
                Section {
                    Text(exercise.isAssisted
                         ? "When every working set reaches \(exercise.repMax) reps, Splitday will recommend \(GFFormat.kg(exercise.weightIncrementKg)) kg LESS assistance and rebuilding from \(exercise.repMin) reps."
                         : "When every working set reaches \(exercise.repMax) reps, Splitday will recommend adding \(GFFormat.kg(exercise.weightIncrementKg)) kg and rebuilding from \(exercise.repMin) reps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(exercise.name.isEmpty ? "New Exercise" : exercise.name)
        .onAppear {
            // Once only (coming back from a swap option's editor must not wipe what you typed).
            guard !loadedDrafts else { return }
            loadedDrafts = true
            cuesDraft = (exercise.formCues ?? []).joined(separator: "\n")
            incrementText = GFFormat.kg(exercise.weightIncrementKg)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if exercise.repMax < exercise.repMin { exercise.repMax = exercise.repMin }
                    let cues = cuesDraft.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    exercise.formCues = cues.isEmpty ? nil : cues
                    if exercise.isCardio {
                        exercise.targetMinutes = exercise.cardioMinutes
                        exercise.weightIncrementKg = 0
                    }
                    onSave(exercise)
                    dismiss()
                }
                .disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
