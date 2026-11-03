import SwiftUI

/// Daily creatine tick + protein tracker with a target from your phase and body weight
/// (cutting / recomp 2.2 g/kg, bulking 1.6 g/kg).
struct NutritionCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var typing = false
    @State private var typedGrams = ""

    var body: some View {
        let day = store.nutritionToday()
        let target = store.proteinTargetG
        let phase = store.nutritionPhase

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrition").font(.headline)
                Spacer()
                Menu {
                    ForEach(NutritionPhase.allCases) { option in
                        Button {
                            store.setNutritionPhase(option)
                        } label: {
                            if option == phase {
                                Label("\(option.title) · \(GFFormat.kg(option.gramsPerKg)) g/kg", systemImage: "checkmark")
                            } else {
                                Text("\(option.title) · \(GFFormat.kg(option.gramsPerKg)) g/kg")
                            }
                        }
                    }
                } label: {
                    Label(phase.title, systemImage: "chevron.up.chevron.down")
                        .font(.caption.bold())
                }
            }

            Button {
                store.toggleCreatine()
            } label: {
                HStack {
                    Image(systemName: day.creatine ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(day.creatine ? Color.green : Color.secondary)
                    Text("Creatine (3–5 g)")
                    Spacer()
                    if day.creatine { Text("Done").font(.caption.bold()).foregroundStyle(.green) }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Protein")
                    Spacer()
                    let proteinText: String = "\(Int(day.proteinG))" + (target.map { " / \(Int($0)) g" } ?? " g")
                    Text(proteinText)
                        .font(.title3.bold().monospacedDigit())
                }
                if let target, target > 0 {
                    SwiftUI.ProgressView(value: min(day.proteinG / target, 1))
                        .tint(day.proteinG >= target ? .green : .accentColor)
                    Text(day.proteinG >= target
                         ? "Target hit. Sergeant Cluck nods."
                         : "\(Int(target - day.proteinG)) g to go · \(GFFormat.kg(phase.gramsPerKg)) g/kg × \(GFFormat.kg(store.latestBodyWeightKg ?? 0)) kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Log your weight in Apple Health (or the Body tab) to get a daily protein target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach([10.0, 20.0, 30.0, 40.0], id: \.self) { grams in
                        Button("+\(Int(grams))") { store.addProtein(grams) }
                            .buttonStyle(.bordered)
                    }
                    Button {
                        typedGrams = ""
                        typing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        store.addProtein(-10)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(day.proteinG <= 0)
                }
                .font(.subheadline.bold())
            }
        }
        .card()
        .alert("Protein today", isPresented: $typing) {
            TextField("Total grams", text: $typedGrams)
                .keyboardType(.decimalPad)
            Button("Set") {
                if let grams = Double(typedGrams.replacingOccurrences(of: ",", with: ".")) { store.setProtein(grams) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter today's total.")
        }
    }
}
