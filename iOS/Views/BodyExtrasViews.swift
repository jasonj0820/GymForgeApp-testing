import SwiftUI

// MARK: - Water (101)

struct WaterCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let ml = store.waterToday
        let target = store.waterTarget
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Water", systemImage: "drop.fill").font(.headline).foregroundStyle(.cyan)
                Spacer()
                Text(String(format: "%.1f / %.1f L", Double(ml) / 1000, Double(target) / 1000)).font(.title3.bold().monospacedDigit())
            }
            SwiftUI.ProgressView(value: min(Double(ml) / Double(max(target, 1)), 1)).tint(.cyan)
            HStack(spacing: 6) {
                ForEach([250, 500, 750], id: \.self) { amount in
                    Button("+\(amount) ml") { store.addWater(amount); Haptics.tap() }.buttonStyle(.bordered)
                }
                Button { store.addWater(-250) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                    .disabled(ml <= 0)
            }
            .font(.subheadline.bold())
            Text("35 ml per kg of body weight, plus half a litre on training days.").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - Caffeine (102)

struct CaffeineCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage(PhoneAppStore.caffeineHoursKey) private var hours = 8.0

    private let drinks: [(String, Int)] = [("Coffee", 95), ("Espresso", 65), ("Pre-workout", 200), ("Energy drink", 160)]

    var body: some View {
        let today = store.caffeineToday.reduce(0) { $0 + $1.mg }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Caffeine", systemImage: "cup.and.saucer.fill").font(.headline).foregroundStyle(.brown)
                Spacer()
                Text("\(today) mg today").font(.subheadline.bold().monospacedDigit())
            }
            if let cutoff = store.caffeineCutoff {
                let past = Date.now > cutoff
                Label(past ? "Past your cut-off (\(cutoff.formatted(date: .omitted, time: .shortened))). Anything now is still in you at bedtime."
                           : "Last caffeine by \(cutoff.formatted(date: .omitted, time: .shortened)), \(GFNumber.text(hours)) h before bed.",
                      systemImage: past ? "exclamationmark.circle" : "clock")
                    .font(.subheadline)
                    .foregroundStyle(past ? Color.orange : Color.primary)
                if let atBed = store.caffeineAtBed, atBed >= 1 {
                    Text("≈ \(Int(atBed)) mg still in you at bedtime (half-life about 5 hours). Under 50 mg is kind to sleep.")
                        .font(.caption).foregroundStyle(atBed > 50 ? Color.orange : Color.secondary)
                }
            } else {
                Text("Set a sleep schedule (Body → Sleep & recovery) to get a cut-off time.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(drinks, id: \.0) { drink in
                        Button("\(drink.0) \(drink.1)") {
                            store.addCaffeine(drink.1)
                            if let cutoff = store.caffeineCutoff, Date.now > cutoff { Haptics.warning() } else { Haptics.tap() }
                        }
                        .buttonStyle(.bordered)
                    }
                    Button { store.undoCaffeine() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(store.caffeineToday.isEmpty)
                }
                .font(.subheadline)
            }
            Stepper("Cut-off \(GFNumber.text(hours)) h before bed", value: $hours, in: 4...12, step: 1).font(.caption)
        }
        .card()
    }
}

// MARK: - Weekly averages vs weight change (103)

struct WeeklyAveragesView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let rows = store.weeklyAverages
        List {
            Section {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Week of \(row.weekStart.formatted(.dateTime.day().month(.abbreviated)))").font(.headline)
                        HStack {
                            value("kcal", row.calories.map { "\(Int($0))" })
                            value("protein", row.protein.map { "\(Int($0)) g" })
                            value("weight", row.weight.map { "\(GFFormat.kg($0)) kg" })
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.weightChange.map { String(format: "%+.1f kg", $0) } ?? "–")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(color(row.weightChange))
                                Text("change").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } footer: {
                Text("Averages of the days you logged. Compare a week's calories with the next week's weight change to find your maintenance. About 7,700 kcal is 1 kg.")
            }
        }
        .navigationTitle("Weekly averages")
    }

    private func value(_ label: String, _ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text ?? "–").font(.subheadline.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ change: Double?) -> Color {
        guard let change, abs(change) >= 0.1 else { return .secondary }
        let gaining = store.nutritionPhase == .bulking
        return (change > 0) == gaining ? .green : .orange
    }
}

// MARK: - Goal weight (104)

struct GoalWeightCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var editing = false
    @State private var kgText = ""
    @State private var hasDate = true
    @State private var by = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Goal weight", systemImage: "target").font(.headline)
                Spacer()
                Button(store.extras.goalWeight == nil ? "Set" : "Change") {
                    kgText = store.extras.goalWeight.map { GFFormat.kg($0.kg) } ?? ""
                    hasDate = store.extras.goalWeight?.by != nil || store.extras.goalWeight == nil
                    by = store.extras.goalWeight?.by ?? by
                    editing = true
                }
                .font(.subheadline.weight(.semibold))
            }
            if let goal = store.extras.goalWeight {
                Text("\(GFFormat.kg(goal.kg)) kg" + (goal.by.map { " by \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                    .font(.title3.bold())
                if let status = store.goalWeightStatus { Text(line(status)).font(.subheadline).foregroundStyle(.secondary) }
            } else {
                Text("A target and a date. Shows the weekly rate you need against the rate you're going.").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextField("Goal (kg)", text: $kgText).keyboardType(.decimalPad)
                    Toggle("By a date", isOn: $hasDate)
                    if hasDate { DatePicker("Date", selection: $by, in: Date.now..., displayedComponents: .date) }
                    if store.extras.goalWeight != nil {
                        Button("Remove goal", role: .destructive) { store.setGoalWeight(nil); editing = false }
                    }
                }
                .navigationTitle("Goal weight")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let kg = Double(kgText.replacingOccurrences(of: ",", with: ".")), kg > 20 {
                                let old = store.extras.goalWeight
                                let start = (old?.kg == kg ? old?.startKg : nil) ?? store.weekAverageWeight ?? store.latestBodyWeightKg
                                store.setGoalWeight(GoalWeight(kg: kg, by: hasDate ? by : nil, startKg: start))
                            }
                            editing = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func line(_ status: WeightGoalMath.Status) -> String {
        func rate(_ value: Double) -> String { String(format: "%+.2f kg a week", value) }
        switch status {
        case .reached:
            return "You're there. Hold it, or set the next one."
        case .needs(let perWeek, let trend):
            let needed = "Needs \(rate(perWeek))"
            guard let trend else { return needed + ". A few more weigh-ins show your current rate." }
            let onTrack = perWeek < 0 ? trend <= perWeek * 0.8 : trend >= perWeek * 0.8
            return needed + "; you're going \(rate(trend)). " + (onTrack ? "On track." : "Behind: " + (perWeek < 0 ? "a little less food, or more steps." : "a little more food."))
        case .noDate(let trend):
            return trend.map { "Going \(rate($0)) over the last 4 weeks." } ?? "A few more weigh-ins show your rate."
        }
    }
}

// MARK: - Big night out (110)

/// The morning after a big night: what it means for today.
struct BigNightBanner: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        if store.dayAfterBigNight {
            Label("Big night out last night. Today's session is marked \"Unusually tired\", so lower numbers won't count against you. Water up; tomorrow's weigh-in may run high.",
                  systemImage: "moon.zzz.fill")
                .font(.footnote)
                .card()
        }
    }
}
