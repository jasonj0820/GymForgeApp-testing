import Foundation

/// MK24 (G2): water, caffeine, weekly averages, goal weight, big nights out.
extension PhoneAppStore {
    // MARK: Water (101)

    var waterToday: Int { extras.water[WaterMath.key(.now)] ?? 0 }

    var waterTarget: Int {
        let trained = workoutLogs.contains { $0.countsAsTraining && Calendar.current.isDateInToday($0.startedAt) }
        return WaterMath.target(weightKg: latestBodyWeightKg, training: trained || plannedSessionName(on: .now) != nil)
    }

    func addWater(_ ml: Int) {
        let key = WaterMath.key(.now)
        extras.water[key] = max(0, (extras.water[key] ?? 0) + ml)
        // Keep 400 days.
        let cutoff = WaterMath.key(Date.now.addingTimeInterval(-400 * 86_400))
        extras.water = extras.water.filter { $0.key >= cutoff }
        saveExtras()
        if (extras.water[key] ?? 0) >= waterTarget { dayfold?.autoTick(.water) }   // MK24 (124)
    }

    // MARK: Caffeine (102)

    var caffeineToday: [CaffeineEntry] { extras.caffeine.filter { Calendar.current.isDateInToday($0.date) } }

    static let caffeineHoursKey = "caffeine.hoursBeforeBed"
    var caffeineHoursBeforeBed: Double { UserDefaults.standard.object(forKey: Self.caffeineHoursKey) as? Double ?? 8 }

    /// Tonight's cut-off, from the sleep schedule.
    var caffeineCutoff: Date? {
        tonightsBedtime().map { CaffeineMath.cutoff(bedtime: $0, hoursBefore: caffeineHoursBeforeBed) }
    }

    /// Caffeine still in you at bedtime, from what's logged so far.
    var caffeineAtBed: Double? {
        guard let bed = tonightsBedtime() else { return nil }
        return CaffeineMath.remaining(extras.caffeine.filter { $0.date > bed.addingTimeInterval(-24 * 3600) }, at: bed)
    }

    func addCaffeine(_ mg: Int) {
        extras.caffeine.append(CaffeineEntry(mg: mg))
        extras.caffeine.removeAll { $0.date < Date.now.addingTimeInterval(-60 * 86_400) }
        saveExtras()
    }

    func undoCaffeine() {
        guard let last = caffeineToday.last else { return }
        extras.caffeine.removeAll { $0.id == last.id }
        saveExtras()
    }

    // MARK: Weekly averages (103) and daily weigh-ins (105)

    var weightSeries: [(date: Date, kg: Double)] { healthKit.bodyWeight.map { (date: $0.date, kg: $0.value) } }

    var weeklyAverages: [WeekAverage] { WeeklyAverages.make(nutrition: extras.nutrition, weights: weightSeries) }

    /// Average of the last 7 days' weigh-ins.
    var weekAverageWeight: Double? {
        let recent = weightSeries.filter { $0.date > Date.now.addingTimeInterval(-7 * 86_400) }
        return recent.isEmpty ? nil : recent.map(\.kg).reduce(0, +) / Double(recent.count)
    }

    var weekAverageChange: Double? {
        let before = weightSeries.filter { $0.date > Date.now.addingTimeInterval(-14 * 86_400) && $0.date <= Date.now.addingTimeInterval(-7 * 86_400) }
        guard let now = weekAverageWeight, !before.isEmpty else { return nil }
        return now - before.map(\.kg).reduce(0, +) / Double(before.count)
    }

    // MARK: Weigh-in from Apple Health (MK24.2)

    /// A weight that came in through the Splitday Health Shortcut becomes the day's weigh-in, dated when the
    /// scale took it. `force` is the "Get from Apple Health" button: any reading measured today, replacing
    /// what's logged today. Otherwise (every time readings arrive) only on your weigh-in day, or any day with
    /// daily weigh-ins, and only when nothing is logged yet that day. Returns the weigh-in, or why there isn't one
    /// (nil problem = nothing to do).
    @discardableResult
    func adoptHealthWeighIn(force: Bool, now: Date = .now) -> (entry: WeighIn?, problem: String?) {
        let cal = Calendar.current
        guard let reading = HealthBridge.lastReading, reading.weightKg != nil || reading.bodyFat != nil else {
            return (nil, force ? "No weight or body fat came back from Apple Health." : nil)
        }
        guard let measured = reading.weighedAt else {
            return (nil, force ? "The Shortcut didn't say when the weight was taken. In its last action, set Weighed at to the weight's Start Date." : nil)
        }
        guard cal.isDate(measured, inSameDayAs: now) else {
            return (nil, force ? "The newest weight in Apple Health is from \(measured.formatted(date: .abbreviated, time: .shortened)). If you've just weighed in, give the scale's app a minute to sync, then try again." : nil)
        }
        let logged = extras.weighIn(on: now)
        if !force {
            let weighInDay = WeighIn.daily || cal.component(.weekday, from: now) == WeighIn.weekday
            guard weighInDay, logged == nil else { return (nil, nil) }
        }
        let entry = WeighIn(id: logged?.id ?? UUID(), date: measured, weightKg: reading.weightKg, bodyFatPercent: reading.bodyFat)
        if logged != entry { saveWeighIn(entry) }
        return (entry, nil)
    }

    // MARK: Goal weight (104)

    func setGoalWeight(_ goal: GoalWeight?) {
        extras.goalWeight = goal
        saveExtras()
    }

    var goalWeightStatus: WeightGoalMath.Status? {
        guard let goal = extras.goalWeight, let current = weekAverageWeight ?? latestBodyWeightKg else { return nil }
        return WeightGoalMath.status(goal: goal, current: current, weights: weightSeries)
    }

    // MARK: Big night out (110)

    func isBigNight(_ date: Date) -> Bool {
        extras.dayTags.contains { $0.kind == .bigNight && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// Tonight counts until 4 am.
    var bigNightTonightDate: Date { Date.now.addingTimeInterval(-4 * 3600) }

    func toggleBigNight() {
        let day = bigNightTonightDate
        if isBigNight(day) {
            extras.dayTags.removeAll { $0.kind == .bigNight && Calendar.current.isDate($0.date, inSameDayAs: day) }
        } else {
            extras.dayTags.append(DayTag(date: day, kind: .bigNight))
        }
        extras.dayTags.removeAll { $0.date < Date.now.addingTimeInterval(-400 * 86_400) }
        saveExtras()
    }

    /// The morning after: lower numbers are expected, so today's session is tagged "Unusually tired".
    var dayAfterBigNight: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return false }
        return isBigNight(yesterday)
    }
}
