import AppIntents
import Foundation
import UIKit
import UserNotifications

// MK24: Apple Health without HealthKit. Sideloading removes Splitday's Health access, but the Shortcuts
// app keeps its own. A personal automation in Shortcuts reads Health and hands the numbers to Splitday
// through these actions (and the other way round for workouts). Everything lands in the same store as
// an Apple Health export import, so charts, the coach, readiness and backups all see it.

extension Notification.Name {
    static let healthBridgeChanged = Notification.Name("splitday.healthBridgeChanged")
    /// MK24.2: the Health Shortcut handed control back (object: "health-done", "health-cancel" or "health-error").
    static let healthShortcutReturned = Notification.Name("splitday.healthShortcutReturned")
}

extension HealthImportData {
    /// Adds `newer` to what's already here. Weight and body fat keep every reading (an exact repeat only
    /// counts once); sleep, resting heart rate and HRV keep one value per day, the newer one winning.
    /// Returns how many readings were actually new.
    func merging(_ newer: HealthImportData) -> (data: HealthImportData, added: Int) {
        let calendar = Calendar.current
        var result = self
        var added = 0
        func readings(_ old: [BodyMetricPoint], _ new: [BodyMetricPoint]) -> [BodyMetricPoint] {
            let key = { (p: BodyMetricPoint) in "\(Int(p.date.timeIntervalSince1970 / 60))|\(Int((p.value * 10).rounded()))" }
            let seen = Set(old.map(key))
            let fresh = new.filter { !seen.contains(key($0)) }
            added += fresh.count
            return (old + fresh).sorted { $0.date < $1.date }
        }
        func daily(_ old: [BodyMetricPoint], _ new: [BodyMetricPoint]) -> [BodyMetricPoint] {
            let oldDays = Set(old.map { calendar.startOfDay(for: $0.date) })
            added += new.filter { !oldDays.contains(calendar.startOfDay(for: $0.date)) }.count
            let newDays = Set(new.map { calendar.startOfDay(for: $0.date) })
            return (old.filter { !newDays.contains(calendar.startOfDay(for: $0.date)) } + new).sorted { $0.date < $1.date }
        }
        result.weights = readings(weights, newer.weights)
        result.fats = readings(fats, newer.fats)
        result.restingHeartRate = daily(restingHeartRate, newer.restingHeartRate)
        result.heartRateVariability = daily(heartRateVariability, newer.heartRateVariability)
        let oldNights = Set(sleep.map { calendar.startOfDay(for: $0.date) })
        added += newer.sleep.filter { !oldNights.contains(calendar.startOfDay(for: $0.date)) }.count
        let newNights = Set(newer.sleep.map { calendar.startOfDay(for: $0.date) })
        result.sleep = (sleep.filter { !newNights.contains(calendar.startOfDay(for: $0.date)) } + newer.sleep).sorted { $0.date < $1.date }
        result.heightCm = newer.heightCm ?? heightCm
        result.birthDate = newer.birthDate ?? birthDate
        result.sex = newer.sex ?? sex
        result.importedAt = newer.importedAt
        return (result, added)
    }
}

enum HealthBridge {
    private static let lastKey = "healthbridge.last"
    private static let lastSummaryKey = "healthbridge.lastSummary"
    private static let readingKey = "healthbridge.reading"

    /// When the Shortcut last sent something, and what.
    static var last: (date: Date, summary: String)? {
        guard let date = UserDefaults.standard.object(forKey: lastKey) as? Date else { return nil }
        return (date, UserDefaults.standard.string(forKey: lastSummaryKey) ?? "")
    }

    /// MK24.2: what the latest run brought in, for the weigh-in and sleep buttons.
    struct Reading: Codable, Equatable {
        var receivedAt: Date
        var weightKg: Double?
        var bodyFat: Double?
        /// When the scale took the weight (the Shortcut's "Weighed at"). nil = an older Shortcut that doesn't send it.
        var weighedAt: Date?
        var night: SleepNight?
    }

    static var lastReading: Reading? {
        guard let data = UserDefaults.standard.data(forKey: readingKey) else { return nil }
        return try? JSONDecoder().decode(Reading.self, from: data)
    }

    /// Saves readings from the Shortcut. Values outside sensible ranges are ignored (a Shortcut that found
    /// nothing tends to send 0).
    ///
    /// MK24.2: sleep can come as the Health samples' start and end times (two lists), which gives the real
    /// night (fell asleep, woke, hours asleep without counting overlaps twice) instead of a sum worked out in
    /// Shortcuts. A weight carries the time it was measured, so yesterday's reading sent again this morning
    /// isn't saved as a new one.
    @discardableResult
    static func record(weightKg: Double?, weighedAt: Date? = nil, bodyFatPercent: Double?, sleepHours: Double?,
                       sleepStarts: [Date] = [], sleepEnds: [Date] = [], restingHR: Double?, hrv: Double?,
                       at date: Date) -> String {
        let existing = HealthImportData.load() ?? HealthImportData(importedAt: .distantPast)
        var batch = HealthImportData()
        var parts: [String] = []
        var reading = Reading(receivedAt: Date())
        // A time in the future (a typo in the Shortcut) is treated as "now".
        let weighed = weighedAt.map { min($0, date) }
        if let weightKg, (25...300).contains(weightKg) {
            reading.weightKg = weightKg
            reading.weighedAt = weighed
            // Without a time, the same number as the last reading in the past 3 days is the same reading again.
            let repeated = weighed == nil && existing.weights.last.map {
                abs($0.value - weightKg) < 0.05 && date.timeIntervalSince($0.date) < 3 * 86_400
            } == true
            if !repeated { batch.weights = [BodyMetricPoint(metric: .bodyWeight, date: weighed ?? date, value: weightKg)] }
            parts.append(String(format: "weight %.1f kg", weightKg))
        }
        // Health hands body fat to Shortcuts as 0.156 or 15.6 depending on how it's read: accept both.
        if var fat = bodyFatPercent, fat > 0 {
            if fat < 1 { fat *= 100 }
            if (3...60).contains(fat) {
                reading.bodyFat = fat
                let repeated = weighed == nil && existing.fats.last.map {
                    abs($0.value - fat) < 0.05 && date.timeIntervalSince($0.date) < 3 * 86_400
                } == true
                if !repeated { batch.fats = [BodyMetricPoint(metric: .bodyFatPercentage, date: weighed ?? date, value: fat)] }
                parts.append(String(format: "body fat %.1f%%", fat))
            }
        }
        if let night = SleepMath.night(starts: sleepStarts, ends: sleepEnds, now: date) {
            batch.sleep = [night]
            reading.night = night
            parts.append(String(format: "sleep %.1f h", night.hoursAsleep)
                         + (night.start.map { ", " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
                         + (night.end.map { "–" + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
        } else if let sleepHours, (1...16).contains(sleepHours) {
            let night = SleepNight(date: Calendar.current.startOfDay(for: date), hoursAsleep: sleepHours)
            batch.sleep = [night]
            reading.night = night
            parts.append(String(format: "sleep %.1f h", sleepHours))
        } else if !sleepStarts.isEmpty {
            parts.append("no night of 3+ hours in the sleep samples")
        }
        if let restingHR, (30...130).contains(restingHR) {
            batch.restingHeartRate = [BodyMetricPoint(metric: .restingHeartRate, date: date, value: restingHR)]
            parts.append("resting HR \(Int(restingHR.rounded()))")
        }
        if let hrv, (5...300).contains(hrv) {
            batch.heartRateVariability = [BodyMetricPoint(metric: .heartRateVariability, date: date, value: hrv)]
            parts.append("HRV \(Int(hrv.rounded())) ms")
        }
        guard !parts.isEmpty else { return "Nothing to save: every value was empty or out of range." }
        var merged = existing.merging(batch).data
        merged.importedAt = existing.importedAt   // the date of the last full export, not of this reading
        do {
            try merged.save()
        } catch {
            AppLog.error("Shortcuts", "Couldn't save readings from Shortcuts: \(error.localizedDescription)")
            return "Couldn't save: \(error.localizedDescription)"
        }
        let summary = parts.joined(separator: ", ")
        UserDefaults.standard.set(Date(), forKey: lastKey)
        UserDefaults.standard.set(summary, forKey: lastSummaryKey)
        if let data = try? JSONEncoder().encode(reading) { UserDefaults.standard.set(data, forKey: readingKey) }
        DispatchQueue.main.async { NotificationCenter.default.post(name: .healthBridgeChanged, object: nil) }
        return "Saved " + summary + "."
    }
}

/// MK24.2: runs your "Splitday Health" Shortcut from inside Splitday and comes straight back
/// (gymforge://health-done), for the weigh-in and sleep buttons. Shortcuts keeps its own Apple Health access,
/// which a sideloaded app loses.
@MainActor
enum HealthShortcut {
    nonisolated static let nameKey = "healthShortcut.name"
    static let defaultName = "Splitday Health"

    static var name: String {
        get {
            let saved = (UserDefaults.standard.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return saved.isEmpty ? defaultName : saved
        }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    /// When the last run was started from a button.
    private(set) static var startedAt: Date?

    static var url: URL? {
        var parts = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")
        parts?.queryItems = [URLQueryItem(name: "name", value: name),
                             URLQueryItem(name: "x-success", value: "gymforge://health-done"),
                             URLQueryItem(name: "x-cancel", value: "gymforge://health-cancel"),
                             URLQueryItem(name: "x-error", value: "gymforge://health-error")]
        return parts?.url
    }

    static func run() {
        guard !Demo.isOn, let url else { return }
        startedAt = Date()
        UIApplication.shared.open(url)
    }

    /// From the app's link handler.
    static func returned(_ host: String) {
        NotificationCenter.default.post(name: .healthShortcutReturned, object: host)
    }

    /// Readings from the run started at `startedAt` (a few seconds of slack for the clock).
    static var freshReading: HealthBridge.Reading? {
        guard let started = startedAt, let reading = HealthBridge.lastReading,
              reading.receivedAt >= started.addingTimeInterval(-5) else { return nil }
        return reading
    }
}

/// "Send to Splitday": the action a Shortcuts automation runs after reading Apple Health.
struct LogHealthReadingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Health readings to Splitday"
    static var description = IntentDescription("Saves weight, body fat, last night's sleep, resting heart rate and HRV in Splitday. Leave out anything you don't have.")
    static var openAppWhenRun = false

    @Parameter(title: "Weight (kg)") var weightKg: Double?
    /// MK24.2: the weight sample's Start Date, so an old reading isn't saved as today's.
    @Parameter(title: "Weighed at") var weighedAt: Date?
    @Parameter(title: "Body fat (%)") var bodyFatPercent: Double?
    /// MK24.2: the sleep samples' Start Dates and End Dates (Get Details of Health Samples, twice).
    @Parameter(title: "Sleep starts") var sleepStarts: [Date]?
    @Parameter(title: "Sleep ends") var sleepEnds: [Date]?
    @Parameter(title: "Sleep last night (hours)") var sleepHours: Double?
    @Parameter(title: "Resting heart rate (bpm)") var restingHeartRate: Double?
    @Parameter(title: "HRV (ms)") var hrv: Double?
    @Parameter(title: "Date (default: now)") var date: Date?

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let message = HealthBridge.record(weightKg: weightKg, weighedAt: weighedAt, bodyFatPercent: bodyFatPercent,
                                          sleepHours: sleepHours, sleepStarts: sleepStarts ?? [], sleepEnds: sleepEnds ?? [],
                                          restingHR: restingHeartRate, hrv: hrv, at: date ?? Date())
        return .result(value: message)
    }
}

// MARK: - Workouts out to Health (39)

/// A finished Splitday workout, for a Shortcut that logs it into Apple Health.
struct SplitdayWorkoutEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Splitday workout"
    static var defaultQuery = SplitdayWorkoutQuery()

    var id: UUID
    @Property(title: "Name") var name: String
    @Property(title: "Start") var start: Date
    @Property(title: "End") var end: Date
    @Property(title: "Minutes") var minutes: Double
    @Property(title: "Active calories (kcal)") var activeCalories: Double
    @Property(title: "Sets") var sets: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(start.formatted(date: .abbreviated, time: .shortened)) · \(Int(minutes)) min")
    }

    init(_ log: WorkoutLog) {
        id = log.id
        name = log.routineName
        start = log.startedAt
        let finish = max(log.endedAt, log.startedAt)
        end = finish
        minutes = (finish.timeIntervalSince(log.startedAt) / 60).rounded()
        // No calorie reading (no Watch): a rough 5 kcal a minute for weights.
        activeCalories = (log.activeCaloriesKcal ?? max(0, finish.timeIntervalSince(log.startedAt) / 60 * 5)).rounded()
        sets = log.exercises.reduce(0) { $0 + $1.sets.count }
    }

    /// Reads the saved data file directly (the app may not be open).
    static func load() -> [WorkoutLog] {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("gymforge.json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder.gymForge.decode(AppSnapshot.self, from: data) else { return [] }
        return snapshot.workoutLogs
    }
}

struct SplitdayWorkoutQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SplitdayWorkoutEntity] {
        SplitdayWorkoutEntity.load().filter { identifiers.contains($0.id) }.map(SplitdayWorkoutEntity.init)
    }

    func suggestedEntities() async throws -> [SplitdayWorkoutEntity] {
        SplitdayWorkoutEntity.load().sorted { $0.startedAt > $1.startedAt }.prefix(10).map(SplitdayWorkoutEntity.init)
    }
}

/// "Get Splitday workouts": the ones finished in the last N hours, newest last.
struct RecentWorkoutsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Splitday workouts"
    static var description = IntentDescription("Workouts finished in the last few hours, with their start, end, minutes and calories, ready to log in Apple Health.")
    static var openAppWhenRun = false

    @Parameter(title: "Finished in the last (hours)", default: 24) var hours: Int

    func perform() async throws -> some IntentResult & ReturnsValue<[SplitdayWorkoutEntity]> {
        let since = Date().addingTimeInterval(-Double(max(1, hours)) * 3600)
        let logs = SplitdayWorkoutEntity.load()
            .filter { $0.endedAt >= since && $0.countsAsTraining }
            .sorted { $0.startedAt < $1.startedAt }
        return .result(value: logs.map(SplitdayWorkoutEntity.init))
    }
}

// MARK: - Monthly export reminder (40)

enum HealthImportReminder {
    static let id = "health.import.monthly"
    private static let key = "health.import.remind"

    /// On by default once you've imported an export.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key); schedule() }
    }

    /// The 1st of each month, 10:00, while there's an import to keep fresh.
    static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard !Demo.isOn, enabled, HealthImportData.load() != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "Top up your Health data"
        content.body = "Export from the Health app (your picture → Export All Health Data) and import it in Splitday. Only what's new is added."
        content.sound = .default
        var when = DateComponents()
        when.day = 1
        when.hour = 10
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }
}
