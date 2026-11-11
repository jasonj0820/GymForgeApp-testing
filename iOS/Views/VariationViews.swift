import SwiftUI

/// MK11.3: "Today: wide grip" for the current exercise. Sessions only compare with the same variation.
struct VariationRow: View {
    @EnvironmentObject private var store: PhoneAppStore
    let state: ActiveWorkoutState
    let item: RoutineExercise
    /// MK20.8: a small chip for the workout screen's action row (the last variation is in the menu).
    var compact = false
    @State private var typing = false
    @State private var draft = ""

    private static let quick = ["Wide grip", "Narrow grip", "Neutral grip", "Close stance", "Wide stance",
                                "Paused", "Slow tempo", "Belt", "Straps"]

    var body: some View {
        let today = state.variations?[item.exercise.id]
        let last = store.lastVariation(for: item.exercise, before: state.startedAt)
        Menu {
            if let last, last != today {
                Button("Same as last time (\(last))") { store.setVariation(last, for: item) }
            }
            ForEach(Self.quick, id: \.self) { option in
                Button(option) { store.setVariation(option, for: item) }
            }
            Button("Other…") {
                draft = today ?? ""
                typing = true
            }
            if today != nil {
                Button("Usual way (clear)", role: .destructive) { store.setVariation(nil, for: item) }
            }
        } label: {
            if compact {
                Label(today ?? "Variation", systemImage: today == nil ? "hand.raised.fingers.spread" : "checkmark")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label(today.map { "Today: \($0)" } ?? "Variation (grip, stance…)", systemImage: "hand.raised.fingers.spread")
                        .font(.footnote.bold())
                    if let last {
                        Text("Last time: \(last)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .alert("Today's variation", isPresented: $typing) {
            TextField("e.g. Wide grip", text: $draft)
            Button("Save") { store.setVariation(draft, for: item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only sessions with the same variation are compared.")
        }
    }
}
