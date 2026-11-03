import Foundation

/// MK10.2: daily calorie target from your phase, a maintenance estimate that corrects itself from
/// what you eat and how your weight actually moves, macros, and the "bulk going too fat" check.
struct CalorieCoach {
    let phase: NutritionPhase
    let isMiniCut: Bool
    let weights: [BodyMetricPoint]
    let fats: [BodyMetricPoint]
    let nutrition: [NutritionDay]
    let logs: [WorkoutLog]
    let cardio: [CardioSession]
    let proteinTarget: Double?
    /// Strength trend from PhaseCoach (% over 4 weeks), for the fat-gain advice.
    let strengthChange: Double?
    let miniCutThreshold: Double
    var now: Date = .now

    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func average(_ points: [BodyMetricPoint], from: Date, to: Date) -> Double? {
        let values = points.filter { $0.date >= from && $0.date < to }.map(\.value)
        guard values.count >= 2 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var weightKg: Double? {
        average(weights, from: daysAgo(10), to: now) ?? weights.max { $0.date < $1.date }?.value
    }

    var bodyFatPercent: Double? {
        average(fats, from: daysAgo(14), to: now) ?? fats.max { $0.date < $1.date }?.value
    }

    // MARK: Maintenance

    enum Method: String {
        case adaptive = "from your intake and weight trend"
        case leanMass = "estimated from your weight and body fat"
        case weightOnly = "rough estimate from your weight"
    }

    struct Maintenance {
        let kcal: Double
        let method: Method
        /// Days of logged calories in the window (adaptive needs 14+).
        let loggedDays: Int
    }

    /// Activity multiplier from strength sessions per week (last 4 weeks).
    private var activityFactor: Double {
        let sessions = Double(logs.filter { $0.startedAt >= daysAgo(28) && $0.countsAsTraining }.count) / 4
        switch sessions {
        case ..<1: return 1.35
        case ..<3.5: return 1.45
        case ..<5.5: return 1.55
        default: return 1.65
        }
    }

    /// Extra daily burn from runs and basketball (their calories, or ~7 kcal a minute).
    private var cardioPerDay: Double {
        let recent = cardio.filter { $0.startedAt >= daysAgo(28) }
        let total = recent.reduce(0.0) { $0 + ($1.activeCalories ?? $1.activeSeconds / 60 * 7) }
        return total / 28
    }

    var formulaMaintenance: Maintenance? {
        guard let weight = weightKg else { return nil }
        let logged = loggedCalorieDays.count
        if let fat = bodyFatPercent, fat > 3, fat < 50 {
            // Katch–McArdle: 370 + 21.6 × lean mass.
            let lean = weight * (1 - fat / 100)
            return Maintenance(kcal: (370 + 21.6 * lean) * activityFactor + cardioPerDay, method: .leanMass, loggedDays: logged)
        }
        return Maintenance(kcal: weight * 22 * activityFactor + cardioPerDay, method: .weightOnly, loggedDays: logged)
    }

    private var loggedCalorieDays: [NutritionDay] {
        nutrition.filter { $0.day >= daysAgo(28) && $0.day < Calendar.current.startOfDay(for: now) && ($0.calories ?? 0) > 500 }
    }

    /// Intake minus what the scale says you stored (7,700 kcal per kg), over the last 4 weeks.
    var adaptiveMaintenance: Maintenance? {
        let days = loggedCalorieDays
        let recentWeights = weights.filter { $0.date >= daysAgo(28) }
        guard days.count >= 14, recentWeights.count >= 8,
              let first = recentWeights.map(\.date).min(), let last = recentWeights.map(\.date).max(),
              last.timeIntervalSince(first) >= 14 * 86_400,
              let slope = PhaseCoach.slopePerDay(recentWeights.map { (date: $0.date, value: $0.value) }) else { return nil }
        let intake = days.compactMap(\.calories).reduce(0, +) / Double(days.count)
        let maintenance = intake - slope * 7_700
        // Sanity: ignore it if it's wildly off the formula (missed logs, water swings).
        if let formula = formulaMaintenance?.kcal, abs(maintenance - formula) > formula * 0.35 { return nil }
        return Maintenance(kcal: maintenance, method: .adaptive, loggedDays: days.count)
    }

    var maintenance: Maintenance? { adaptiveMaintenance ?? formulaMaintenance }

    // MARK: Target

    struct Target {
        let kcal: Int
        let maintenance: Maintenance
        let adjustment: Int
        let proteinG: Int
        let fatG: Int
        let carbG: Int
        let label: String
        let note: String
    }

    /// Phase surplus / deficit (plus the fat-gain trim on a bulk).
    var target: Target? {
        guard let maintenance, let weight = weightKg else { return nil }
        var adjustment: Int
        let label: String
        switch phase {
        case .bulking:
            adjustment = 300
            label = "Bulk: maintenance + 300"
        case .recomp:
            adjustment = 0
            label = "Recomp: about maintenance"
        case .cutting:
            adjustment = isMiniCut ? -750 : -500
            label = isMiniCut ? "Mini-cut: maintenance − 750" : "Cut: maintenance − 500"
        }
        if phase == .bulking, let check = fatGainCheck { adjustment -= check.trim }
        let kcal = Int(((maintenance.kcal + Double(adjustment)) / 10).rounded() * 10)
        let protein = Int((proteinTarget ?? weight * phase.gramsPerKg).rounded())
        let fat = Int(max(weight * 0.8, Double(kcal) * 0.25 / 9).rounded())
        let carbs = max(0, (kcal - protein * 4 - fat * 9) / 4)
        var note = "Maintenance ≈ \(Int(maintenance.kcal.rounded())) kcal (\(maintenance.method.rawValue))."
        if maintenance.method != .adaptive {
            note += " Log calories for 2 weeks and it switches to your real number (formulas are often 200–300 kcal off)."
        }
        note += " Same target every day — put more of the carbs around training."
        return Target(kcal: kcal, maintenance: maintenance, adjustment: adjustment, proteinG: protein, fatG: fat, carbG: carbs,
                      label: label, note: note)
    }

    // MARK: Bulk going too fat

    struct FatGainCheck {
        enum Level { case watch, act }
        let level: Level
        let weightGain: Double
        let fatGain: Double
        let fatShare: Double
        let bodyFatRisePerMonth: Double
        /// kcal to take off the bulk target.
        let trim: Int
        let title: String
        let advice: [String]
    }

    /// Compares the first and last 2 weeks of the last 6: how much of the gain was fat.
    var fatGainCheck: FatGainCheck? {
        guard phase == .bulking, !isMiniCut else { return nil }
        guard let earlyWeight = average(weights, from: daysAgo(42), to: daysAgo(28)),
              let lateWeight = average(weights, from: daysAgo(14), to: now),
              let earlyFat = average(fats, from: daysAgo(42), to: daysAgo(28)),
              let lateFat = average(fats, from: daysAgo(14), to: now) else { return nil }
        // Past the mini-cut limit: the mini-cut reminder takes over.
        if lateFat > miniCutThreshold { return nil }
        let gain = lateWeight - earlyWeight
        let fatGain = lateWeight * lateFat / 100 - earlyWeight * earlyFat / 100
        let rise = (lateFat - earlyFat) * 30 / 28
        let share = gain > 0.4 ? fatGain / gain : 0
        let level: FatGainCheck.Level
        if share >= 0.67 || rise >= 1.0 {
            level = .act
        } else if share >= 0.5 || rise >= 0.5 {
            level = .watch
        } else {
            return nil
        }
        let trim = level == .act ? 200 : 100
        var advice: [String] = []
        advice.append("Trim the surplus by about \(trim) kcal a day — from fats and snacks, not protein.")
        let recentProtein = nutrition.filter { $0.day >= daysAgo(14) && $0.proteinG > 0 }.map(\.proteinG)
        if recentProtein.count >= 5 {
            // MK17: the same target as the protein card and nags (phase × body weight), not a second number.
            let goal = proteinTarget ?? lateWeight * NutritionPhase.bulking.gramsPerKg
            let average = recentProtein.reduce(0, +) / Double(recentProtein.count)
            if average < goal * 0.95 {
                advice.append("Protein is averaging \(Int(average)) g — get it to your \(Int(goal.rounded())) g target first: it makes more of the gain muscle.")
            }
        }
        advice.append("Most carbs before and after training; lighter late at night and on rest days.")
        advice.append("Cut liquid calories first (juice, alcohol, mass-gainer shakes) and keep steps at 7–10k a day.")
        if let strength = strengthChange {
            advice.append(strength >= 1
                ? String(format: "Lifts are up %.0f%%, so the bulk is working — only the surplus is too big.", strength)
                : "Lifts are flat while fat rises: the extra food isn't being used. Trim it, and check sleep and recovery.")
        }
        let title = level == .act ? "Bulk is adding mostly fat" : "Keep an eye on the bulk"
        return FatGainCheck(level: level, weightGain: gain, fatGain: fatGain, fatShare: share,
                            bodyFatRisePerMonth: rise, trim: trim, title: title, advice: advice)
    }
}
