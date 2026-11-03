import SwiftUI
import UniformTypeIdentifiers

/// Imports history from Strong (Strong: Settings → Export Strong Data → CSV).
struct StrongImportView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var parsed: StrongParseResult?
    @State private var unit: WeightUnit = .kg
    /// Strong exercise name → your exercise's history key ("" = keep Strong's name).
    @State private var mapping: [String: String] = [:]
    @State private var errorText: String?
    @State private var resultText: String?

    var body: some View {
        Form {
            Section {
                Button {
                    picking = true
                } label: {
                    Label(parsed == nil ? "Choose Strong CSV file" : "Choose a different file", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("In Strong: Profile → ⚙︎ Settings → Export Strong Data. Save the CSV to Files, then pick it here. Warm-up sets are skipped and workouts you've already imported are ignored.")
            }

            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }

            if let resultText {
                Section {
                    Label(resultText, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Done") { dismiss() }
                }
            }

            if let parsed, resultText == nil {
                Section("Found") {
                    LabeledContent("Workouts", value: "\(parsed.workoutCount)")
                    LabeledContent("Sets", value: "\(parsed.rows.count)")
                    if let first = parsed.firstDate, let last = parsed.lastDate {
                        LabeledContent("Dates", value: "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if parsed.detectedUnit == nil {
                        Picker("Weights in the file are", selection: $unit) {
                            ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } else {
                        LabeledContent("Units", value: unit.rawValue)
                    }
                }

                Section {
                    ForEach(parsed.exerciseNames, id: \.self) { name in
                        Picker(name, selection: Binding(
                            get: { mapping[name] ?? "" },
                            set: { mapping[name] = $0 }
                        )) {
                            Text("Keep as is").tag("")
                            ForEach(myExercises) { exercise in
                                Text(exercise.name).tag(exercise.historyKey)
                            }
                        }
                    }
                } header: {
                    Text("Match exercises")
                } footer: {
                    Text("Match Strong's names (e.g. \"Bench Press (Barbell)\") to your exercises so their history and graphs merge. Unmatched ones are imported under their Strong name.")
                }

                Section {
                    Button {
                        runImport(parsed)
                    } label: {
                        Label("Import \(parsed.workoutCount) workouts", systemImage: "square.and.arrow.down")
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Import from Strong")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            load(result)
        }
    }

    private var myExercises: [ExerciseDefinition] {
        var seen = Set<String>()
        return store.routines.flatMap(\.allExercises).filter { seen.insert($0.historyKey).inserted }
    }

    private func load(_ result: Result<URL, Error>) {
        errorText = nil
        resultText = nil
        switch result {
        case .failure(let error):
            errorText = error.localizedDescription
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                    throw StrongImportError.notStrongFile
                }
                let result = try StrongImporter.parse(text)
                parsed = result
                unit = result.detectedUnit ?? .kg
                mapping = autoMatch(result.exerciseNames)
            } catch {
                parsed = nil
                errorText = error.localizedDescription
            }
        }
    }

    /// Pre-matches names that are the same once Strong's "(Barbell)"-style suffix is removed.
    private func autoMatch(_ names: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for name in names {
            let base = name.components(separatedBy: " (").first ?? name
            if let match = myExercises.first(where: {
                $0.historyKey == ExerciseLog.key(for: name) || $0.historyKey == ExerciseLog.key(for: base)
            }) {
                result[name] = match.historyKey
            }
        }
        return result
    }

    private func runImport(_ parsed: StrongParseResult) {
        var resolved: [String: ExerciseDefinition] = [:]
        for (name, key) in mapping where !key.isEmpty {
            if let exercise = myExercises.first(where: { $0.historyKey == key }) {
                resolved[name] = exercise
            }
        }
        let outcome = StrongImporter.buildWorkouts(from: parsed, unit: unit, mapping: resolved, existing: store.workoutLogs)
        store.importWorkouts(outcome.workouts)
        var text = "Imported \(outcome.workouts.count) workouts (\(outcome.setCount) sets)."
        if outcome.duplicatesSkipped > 0 { text += " Skipped \(outcome.duplicatesSkipped) already imported." }
        resultText = text
        self.parsed = nil
    }
}
