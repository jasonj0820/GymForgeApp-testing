import SwiftUI

/// MK10.2: today's calorie target for your phase (bulk / recomp / cut / mini-cut), what you've logged,
/// macros, and the "bulk adding mostly fat" check.
struct CalorieCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var typing = false
    @State private var typed = ""
    @State private var showDetail = false

    var body: some View {
        let coach = store.calorieCoach
        let today = store.nutritionToday()
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calories").font(.headline)
                Spacer()
                Button {
                    showDetail.toggle()
                } label: {
                    Image(systemName: showDetail ? "chevron.up" : "info.circle")
                }
                .buttonStyle(.borderless)
            }
            if let target = coach.target {
                let eaten = Int(today.calories ?? 0)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(eaten) / \(target.kcal) kcal").font(.title3.bold().monospacedDigit())
                    Spacer()
                    Text(target.label).font(.caption).foregroundStyle(.secondary)
                }
                SwiftUI.ProgressView(value: min(Double(eaten) / Double(max(target.kcal, 1)), 1))
                    .tint(eaten > target.kcal + 150 ? .orange : .green)
                Text("Protein \(target.proteinG) g · fat \(target.fatG) g · carbs \(target.carbG) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach([100.0, 250.0, 500.0], id: \.self) { kcal in
                        Button("+\(Int(kcal))") { store.addCalories(kcal) }
                            .buttonStyle(.bordered)
                    }
                    Button {
                        typed = today.calories.map { "\(Int($0))" } ?? ""
                        typing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline)
                if showDetail {
                    Text(target.note).font(.caption).foregroundStyle(.secondary)
                }
                if let check = coach.fatGainCheck {
                    fatGain(check)
                }
            } else {
                Text("Log your weight (and body fat, if your scale has it) in Apple Health to get a daily calorie target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .alert("Calories today", isPresented: $typing) {
            TextField("kcal", text: $typed).keyboardType(.numberPad)
            Button("Save") { store.setCalories(Double(typed.trimmingCharacters(in: .whitespaces))) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Total eaten today. Leave empty to clear it.")
        }
    }

    private func fatGain(_ check: CalorieCoach.FatGainCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(check.title, systemImage: check.level == .act ? "exclamationmark.triangle.fill" : "eye")
                .font(.subheadline.bold())
                .foregroundStyle(check.level == .act ? .orange : .yellow)
            Text(String(format: "Last 6 weeks: +%.1f kg, about %.1f kg of it fat (%.0f%%) · body fat %+.1f%%/month.",
                        check.weightGain, check.fatGain, check.fatShare * 100, check.bodyFatRisePerMonth))
                .font(.caption)
            ForEach(check.advice, id: \.self) { line in
                Text("• " + line).font(.caption).foregroundStyle(.secondary)
            }
            Text("The target above already includes the −\(check.trim) kcal. Scale body fat is noisy, so this uses 2-week averages.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
