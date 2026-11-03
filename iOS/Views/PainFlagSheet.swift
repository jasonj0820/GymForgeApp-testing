import SwiftUI

/// Flag pain on an exercise mid-workout. Next time it comes up you'll see advice
/// (go lighter / swap) until you mark it "Feels fine now".
struct PainFlagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: ExerciseDefinition
    let onSave: (PainFlag) -> Void
    @State private var area: PainArea = .shoulder
    @State private var severity = 1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Where") {
                    Picker("Area", selection: $area) {
                        ForEach(PainArea.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Picker("How bad", selection: $severity) {
                        Text("Niggle").tag(1)
                        Text("Sore").tag(2)
                        Text("Sharp").tag(3)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How bad")
                } footer: {
                    Text(severity == 3
                         ? "Sharp pain: stop this exercise today. If it keeps happening, see a physio."
                         : "Next time this exercise comes up you'll get advice (lighter weight or a swap) until you mark it as fine.")
                }
                Section("Note (optional)") {
                    TextField("e.g. front of shoulder at the bottom", text: $note)
                }
            }
            .navigationTitle("Pain · \(exercise.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = note.trimmingCharacters(in: .whitespaces)
                        onSave(PainFlag(exercise: exercise, area: area, severity: severity,
                                        note: trimmed.isEmpty ? nil : trimmed))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
