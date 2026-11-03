#if os(iOS) || os(watchOS)
import Foundation
import HealthKit

/// MK11: sleep from Apple Health (iPhone and Watch), and the manual "Going to sleep / I'm awake" log.
/// The Watch's own sleep tracking wins: a manual entry only counts where nothing else covers that time.
public enum SleepHealth {
    static let manualKey = "GymForgeManualSleep"

    public static var shareTypes: Set<HKSampleType> {
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis).map { [$0] } ?? []
    }

    public static func nights(days: Int, store: HKHealthStore) async -> [SleepNight] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let all = (samples as? [HKCategorySample] ?? []).filter { asleep.contains($0.value) && $0.endDate > $0.startDate }
                let tracked = all.filter { $0.metadata?[manualKey] == nil }
                let manual = all.filter { sample in
                    sample.metadata?[manualKey] != nil
                        && !tracked.contains { $0.startDate < sample.endDate && $0.endDate > sample.startDate }
                }
                let intervals = (tracked + manual).map { DateInterval(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: ReadinessEngine.nights(from: intervals))
            }
            store.execute(query)
        }
    }

    /// Saves a manually logged night to Apple Health (as "asleep").
    public static func saveManual(start: Date, end: Date, store: HKHealthStore) async throws {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis), end > start else { return }
        let sample = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                      start: start, end: end,
                                      metadata: [HKMetadataKeyWasUserEntered: true, manualKey: true])
        try await store.save(sample)
    }

    // MARK: Manual log state (per device)

    private static let startedKey = "gymforge.sleepStartedAt"

    /// When you tapped "Going to sleep" on this device (nil = not sleeping).
    public static var manualStart: Date? {
        get { UserDefaults.standard.object(forKey: startedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: startedKey) }
    }

    /// "I'm awake": saves the night if it's at least 30 min (and under 16 h), then clears it.
    @discardableResult
    public static func finishManual(store: HKHealthStore, now: Date = .now) async -> Bool {
        guard let start = manualStart else { return false }
        manualStart = nil
        let length = now.timeIntervalSince(start)
        guard length >= 30 * 60, length <= 16 * 3600 else { return false }
        try? await saveManual(start: start, end: now, store: store)
        return true
    }
}
#endif
