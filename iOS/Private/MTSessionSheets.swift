import SwiftUI

extension MTLevel {
    var color: Color {
        switch self {
        case .green: return Color(red: 0.35, green: 0.8, blue: 0.4)
        case .highGreen: return Color(red: 0.05, green: 0.55, blue: 0.25)
        case .yellow: return Color(red: 0.95, green: 0.78, blue: 0.1)
        case .red: return Color(red: 0.9, green: 0.2, blue: 0.2)
        }
    }
}

/// Text field bound to an optional number ("" = nil).
struct MTNumberField: View {
    let title: String
    @Binding var value: Double?
    let suffix: String
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("–", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .onChange(of: text) { _, newValue in
                    value = Double(newValue.replacingOccurrences(of: ",", with: "."))
                }
            Text(suffix).foregroundStyle(.secondary)
        }
        .onAppear {
            if let value { text = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value) }
        }
    }
}

// MARK: - Start a session (open timer or intervals)

struct MTStartSheet: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    let type: MTType

    @State private var useIntervals = false
    @State private var rounds = 3
    @State private var workMinutes = 10.0
    @State private var restMinutes = 2.0
    @State private var pressure: Double?
    @State private var tensionDisplay: Double?
    @State private var saveAsPreset = false
    @State private var presetName = ""
    @State private var nir = false

    private var unit: MTWeightUnit { vault.data.settings.weightUnit }

    var body: some View {
        Form {
            Section {
                Label(type.title, systemImage: type.symbol).font(.headline)
                if type.usesPressure {
                    MTNumberField(title: "Pressure", value: $pressure, suffix: "inHg")
                }
                if type.usesTension {
                    MTNumberField(title: "Tension", value: $tensionDisplay, suffix: unit.rawValue)
                }
                if type == .highTensionExtender {
                    Toggle("With NIR", isOn: $nir)
                }
            } footer: {
                if type.usesPressure || type.usesTension {
                    Text("Pre-filled with what you used last time.")
                }
            }

            Section {
                Picker("Timer", selection: $useIntervals) {
                    Text("Open timer").tag(false)
                    Text("Intervals").tag(true)
                }
                .pickerStyle(.segmented)
                if useIntervals {
                    Stepper("Rounds: \(rounds)", value: $rounds, in: 1...20)
                    Stepper("Work: \(MTStats.minutesText(workMinutes))", value: $workMinutes, in: 0.5...60, step: 0.5)
                    Stepper("Rest: \(MTStats.minutesText(restMinutes))", value: $restMinutes, in: 0...30, step: 0.5)
                    Toggle("Save as preset", isOn: $saveAsPreset)
                    if saveAsPreset {
                        TextField("Preset name", text: $presetName)
                    }
                } else if let limit = vault.data.settings.limit(for: type) {
                    Text("Time-limit alert at \(limit) min").foregroundStyle(.secondary)
                }
            } footer: {
                Text((useIntervals
                     ? "Buzzes and shows a discreet ⏱ notification at each change, even with the phone locked."
                     : "Runs until you stop it.")
                     + " The screen stays on, More Training stays open if you leave the app, and the Lock Screen / Dynamic Island show a plain \"Timer\".")
            }
        }
        .navigationTitle("Start \(type.shortTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pressure = vault.data.lastPressure(for: type)
            tensionDisplay = vault.data.lastTension(for: type).map { unit.display($0) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { start() }.bold()
            }
        }
    }

    private func start() {
        let tensionKg = tensionDisplay.map { unit.toKg($0) }
        if useIntervals {
            let step = MTPresetStep(type: type, rounds: rounds, workMinutes: workMinutes, restMinutes: restMinutes,
                                    pressureInHg: pressure, tensionKg: tensionKg, nir: nir && type == .highTensionExtender ? true : nil)
            let name = presetName.trimmingCharacters(in: .whitespaces).isEmpty ? type.title : presetName
            if saveAsPreset { vault.savePreset(MTPreset(name: name, steps: [step])) }
            Task { await vault.startInterval(name: name, steps: [step]) }
        } else {
            Task { await vault.startTimed(type, pressureInHg: pressure, tensionKg: tensionKg, nir: nir) }
        }
        dismiss()
    }
}

// MARK: - After a session: warning signs & notes

struct MTReviewSheet: View {
    @EnvironmentObject private var vault: MTVault
    @State private var warnings = Set<MTWarning>()
    @State private var notes = ""
    @State private var girthBefore: Double?
    @State private var girthAfter: Double?
    @State private var lengthBefore: Double?
    @State private var lengthAfter: Double?

    private var types: Set<MTType> {
        let ids = Set(vault.pendingReview)
        return Set(vault.data.sessions.filter { ids.contains($0.id) }.map(\.type))
    }

    /// MK19: stays up until the before/after measurements for this session are in.
    private var filled: Bool {
        let girthOK = !(types.contains(.pump) || types.contains(.pac)) || Self.percent(girthBefore, girthAfter) != nil
        let lengthOK = !types.contains(.highTensionExtender) || Self.percent(lengthBefore, lengthAfter) != nil
        return girthOK && lengthOK
    }

    /// (after ÷ before − 1) × 100, when both were typed.
    static func percent(_ before: Double?, _ after: Double?) -> Double? {
        guard let before, let after, before > 0, after > 0 else { return nil }
        return (after / before - 1) * 100
    }

    var body: some View {
        Form {
            let unit = vault.data.settings.unit.label
            if vault.skipUndo != nil {
                Section {
                    Button { vault.undoSkip() } label: {
                        Label("Back to timer (undo skip)", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            if types.contains(.pump) || types.contains(.pac) {
                Section {
                    MTNumberField(title: "Girth before", value: $girthBefore, suffix: unit)
                    MTNumberField(title: "Girth straight after", value: $girthAfter, suffix: unit)
                    if let pct = Self.percent(girthBefore, girthAfter) {
                        Text(String(format: "Expansion %.1f%%", pct)).foregroundStyle(pct >= 6 && pct <= 12 ? Color.green : Color.orange)
                    }
                } header: { Text("Expansion") } footer: { Text("Aim for 6–12%. Below that at the same settings means it's time for a small step up; above it, don't push pressure further.") }
            }
            if types.contains(.highTensionExtender) {
                Section {
                    MTNumberField(title: "Stretched length before", value: $lengthBefore, suffix: unit)
                    MTNumberField(title: "Right after extending", value: $lengthAfter, suffix: unit)
                    if let pct = Self.percent(lengthBefore, lengthAfter) {
                        Text(String(format: "Stretch %.1f%%", pct)).foregroundStyle(pct >= 3 ? Color.green : Color.orange)
                    }
                } footer: { Text("Aim for about 3–4%.") }
            }
            Section {
                ForEach(MTWarning.allCases) { warning in
                    Toggle(warning.title, isOn: Binding(
                        get: { warnings.contains(warning) },
                        set: { if $0 { warnings.insert(warning) } else { warnings.remove(warning) } }
                    ))
                }
            } header: {
                Text("Any warning signs?")
            } footer: {
                Text("Leave all off if everything felt normal. Logged signs drive the rest-day suggestions.")
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
            if !filled {
                Section {
                    Button("Couldn't measure this time") {
                        vault.applyReview(warnings: warnings, notes: notes,
                                          girthExpansion: Self.percent(girthBefore, girthAfter),
                                          lengthExpansion: Self.percent(lengthBefore, lengthAfter))
                    }
                } footer: {
                    Text("Saves the session (with any warning signs and notes above) without the missing reading, so it isn't counted in the progression cards. Better than a guess.")
                }
            }
        }
        .navigationTitle("Session saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    vault.applyReview(warnings: warnings, notes: notes,
                                      girthExpansion: Self.percent(girthBefore, girthAfter),
                                      lengthExpansion: Self.percent(lengthBefore, lengthAfter))
                }.bold()
                .disabled(!filled)
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Presets

struct MTPresetEditor: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    @State var preset: MTPreset

    private var unit: MTWeightUnit { vault.data.settings.weightUnit }

    var body: some View {
        Form {
            Section("Name") {
                TextField("e.g. Pump + PAC", text: $preset.name)
            }
            ForEach($preset.steps) { $step in
                Section {
                    Picker("Type", selection: $step.type) {
                        ForEach(MTType.timed) { Text($0.title).tag($0) }
                    }
                    Stepper("Rounds: \(step.rounds)", value: $step.rounds, in: 1...20)
                    Stepper("Work: \(MTStats.minutesText(step.workMinutes))", value: $step.workMinutes, in: 0.5...60, step: 0.5)
                    Stepper("Rest: \(MTStats.minutesText(step.restMinutes))", value: $step.restMinutes, in: 0...30, step: 0.5)
                    if step.type.usesPressure {
                        MTNumberField(title: "Pressure", value: $step.pressureInHg, suffix: "inHg")
                    }
                    if step.type.usesTension {
                        MTNumberField(title: "Tension", value: Binding(
                            get: { step.tensionKg.map { unit.display($0) } },
                            set: { step.tensionKg = $0.map { unit.toKg($0) } }
                        ), suffix: unit.rawValue)
                    }
                    Button("Remove step", role: .destructive) {
                        preset.steps.removeAll { $0.id == step.id }
                    }
                } header: {
                    Text("Step")
                }
            }
            Section {
                Button("Add step", systemImage: "plus") {
                    let type = preset.steps.last?.type ?? .pump
                    preset.steps.append(MTPresetStep(type: type, rounds: 3, workMinutes: 10, restMinutes: 2,
                                                     pressureInHg: vault.data.lastPressure(for: type)))
                }
            } footer: {
                Text("Total about \(MTStats.minutesText(preset.totalMinutes)). Steps run in order.")
            }
        }
        .navigationTitle(preset.name.isEmpty ? "New preset" : preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    vault.savePreset(preset)
                    dismiss()
                }
                .disabled(preset.name.trimmingCharacters(in: .whitespaces).isEmpty || preset.steps.isEmpty)
            }
        }
    }
}

// MARK: - Add a past session

struct MTAddSessionView: View {
    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    @State private var type: MTType = .pump
    @State private var start = Date().addingTimeInterval(-1800)
    @State private var minutes = 20
    @State private var pressure: Double?
    @State private var tension: Double?
    @State private var level: MTLevel = .green
    @State private var notes = ""

    private var unit: MTWeightUnit { vault.data.settings.weightUnit }

    var body: some View {
        Form {
            Picker("Type", selection: $type) {
                ForEach(MTType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            DatePicker("Started", selection: $start, in: ...Date())
            Stepper("Duration: \(MTStats.formatDuration(Double(minutes * 60)))", value: $minutes, in: 1...1440,
                    step: type == .allDayStretcher ? 15 : 1)
            if type.usesPressure {
                MTNumberField(title: "Pressure", value: $pressure, suffix: "inHg")
            }
            if type.usesTension {
                MTNumberField(title: "Tension", value: $tension, suffix: unit.rawValue)
            }
            if type == .allDayStretcher {
                Picker("Level", selection: $level) {
                    ForEach(MTLevel.allCases) { Text($0.title).tag($0) }
                }
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
        .navigationTitle("Add session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    vault.addSession(MTSession(
                        type: type, start: start, end: start.addingTimeInterval(Double(minutes * 60)),
                        notes: notes.isEmpty ? nil : notes,
                        pressureInHg: type.usesPressure ? pressure : nil,
                        tensionKg: type.usesTension ? tension.map { unit.toKg($0) } : nil,
                        level: type == .allDayStretcher ? level : nil
                    ))
                    dismiss()
                }
            }
        }
    }
}
