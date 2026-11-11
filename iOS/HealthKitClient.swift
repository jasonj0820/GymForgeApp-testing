import CoreLocation
import Foundation
import HealthKit
import Combine
import Compression

@MainActor
final class HealthKitClient: ObservableObject {
    @Published var bodyWeight: [BodyMetricPoint] = []
    @Published var bodyFat: [BodyMetricPoint] = []
    @Published var sleep: [SleepNight] = []
    @Published var restingHeartRate: [BodyMetricPoint] = []
    @Published var heartRateVariability: [BodyMetricPoint] = []
    @Published var authorizationError: String?
    @Published var hasRequestedAuthorization = false

    private let healthStore = HKHealthStore()
    /// MK20.2: Apple Health readings and the weigh-ins you typed in. `bodyWeight` / `bodyFat` are both merged.
    private var healthWeight: [BodyMetricPoint] = []
    private var healthFat: [BodyMetricPoint] = []
    private var manualWeight: [BodyMetricPoint] = []
    private var manualFat: [BodyMetricPoint] = []
    private var manualSource: [WeighIn]?
    /// MK20.4: from an Apple Health export file, and live recovery data (merged into the published arrays).
    private(set) var imported: HealthImportData? = HealthImportData.load()
    private var healthSleep: [SleepNight] = []
    /// MK21: nights kept in the app because Apple Health couldn't save them.
    private var localSleep: [SleepNight] = []
    private var healthResting: [BodyMetricPoint] = []
    private var healthHRV: [BodyMetricPoint] = []
    /// Retained so the mirrored session from the Watch isn't deallocated immediately.
    private var mirroredSession: HKWorkoutSession?

    init() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.mirroredSession = session }
        }
        if imported != nil {   // MK20.4: show an earlier export right away
            mergeBodyMetrics()
            mergeRecovery()
        }
    }

    func requestAuthorization() async {
        authorizationError = nil   // MK19.3.1: a fresh result each tap, shown under the button in Settings
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data isn't available on this device."
            return
        }

        guard
            let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate),
            let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
            let bodyFatPercentage = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)
        else { return }

        let workout = HKObjectType.workoutType()
        var read: Set<HKObjectType> = [heartRate, activeEnergy, bodyMass, bodyFatPercentage, workout]
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { read.insert(sleepType) }
        if let resting = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { read.insert(resting) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { read.insert(hrv) }
        var share: Set<HKSampleType> = [workout, activeEnergy, heartRate, HKSeriesType.workoutRoute()]
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { share.insert(distance) }
        share.formUnion(SleepHealth.shareTypes)   // MK11: manual "Going to sleep / I'm awake"

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            hasRequestedAuthorization = true
            await refreshBodyMetrics()
            await refreshRecovery()
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    /// MK10: asks for the run types (distance, route) if they haven't been asked yet — no-op otherwise.
    func requestCardioAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), distance, HKSeriesType.workoutRoute()]
        try? await healthStore.requestAuthorization(toShare: share, read: [HKObjectType.workoutType()])
    }

    /// MK10: saves a run / basketball session recorded on the iPhone (or logged by hand) to Apple Health,
    /// with distance and the GPS route when there is one.
    func saveCardio(_ session: CardioSession, route: [CLLocation]) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = session.kind == .run ? .running : .basketball
        configuration.locationType = session.indoor || session.kind == .basketball ? .indoor : .outdoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: session.startedAt)
            if let km = session.distanceKm, km > 0,
               let type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: km),
                                              start: session.startedAt, end: Swift.max(session.endedAt, session.startedAt.addingTimeInterval(1)))
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: Swift.max(session.endedAt, session.startedAt.addingTimeInterval(1)))
            if let workout = try await builder.finishWorkout(), route.count >= 2 {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                try await routeBuilder.insertRouteData(route)
                _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            print("Could not save \(session.kind.rawValue) to Health: \(error.localizedDescription)")
        }
    }

    /// Wakes the Watch app. The Watch receives `handle(_ workoutConfiguration:)` and starts the HealthKit session.
    func launchWatchStrengthWorkout() async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // No async version exists; the completion can also hang if the Watch is off, so don't wait on it.
        healthStore.startWatchApp(with: configuration) { success, error in
            if !success {
                print("Could not launch Watch workout app: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }

    /// Opens GymForge on the Watch for a run or basketball session (it starts recording straight away).
    func launchWatchActivity(kind: ActivityKind, indoor: Bool) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = kind == .run ? .running : .basketball
        configuration.locationType = indoor || kind == .basketball ? .indoor : .outdoor
        healthStore.startWatchApp(with: configuration) { success, error in
            if !success { print("Could not launch Watch for \(kind.rawValue): \(error?.localizedDescription ?? "unknown")") }
        }
    }

    /// Reads ~10 years so every chart range (including "All") has data.
    func refreshBodyMetrics(days: Int = 3650) async {
        async let weight = queryQuantity(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            metric: .bodyWeight,
            days: days,
            transform: { $0 }
        )
        async let fat = queryQuantity(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            metric: .bodyFatPercentage,
            days: days,
            transform: { $0 * 100 }
        )

        healthWeight = await weight
        healthFat = await fat
        mergeBodyMetrics()
    }

    /// MK20.2: your typed-in weigh-ins, shown alongside Apple Health everywhere (charts, coach, calories).
    func setManual(_ weighIns: [WeighIn]) {
        guard weighIns != manualSource else { return }
        manualSource = weighIns
        let points = weighIns.flatMap(\.points)
        manualWeight = points.filter { $0.metric == .bodyWeight }
        manualFat = points.filter { $0.metric == .bodyFatPercentage }
        mergeBodyMetrics()
    }

    private func mergeBodyMetrics() {
        // An exported reading that's also in live Apple Health (same time and value) only counts once.
        func dedupe(_ live: [BodyMetricPoint], _ old: [BodyMetricPoint]) -> [BodyMetricPoint] {
            let seen = Set(live.map { "\(Int($0.date.timeIntervalSince1970 / 60))|\(Int(($0.value * 10).rounded()))" })
            return old.filter { !seen.contains("\(Int($0.date.timeIntervalSince1970 / 60))|\(Int(($0.value * 10).rounded()))") }
        }
        bodyWeight = (healthWeight + dedupe(healthWeight, imported?.weights ?? []) + manualWeight).sorted { $0.date < $1.date }
        bodyFat = (healthFat + dedupe(healthFat, imported?.fats ?? []) + manualFat).sorted { $0.date < $1.date }
    }

    /// Sleep, resting heart rate and HRV for readiness and the monthly report (last ~120 days).
    func refreshRecovery(days: Int = 120) async {
        async let nights = querySleep(days: days)
        async let resting = queryQuantity(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            metric: .restingHeartRate,
            days: days,
            transform: { $0 }
        )
        async let variability = queryQuantity(
            identifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli),
            metric: .heartRateVariability,
            days: days,
            transform: { $0 }
        )
        healthSleep = await nights
        healthResting = await resting
        healthHRV = await variability
        mergeRecovery()
    }

    /// MK20.4: use (or, with nil, remove) data imported from an Apple Health export.
    func setImported(_ data: HealthImportData?) {
        imported = data
        mergeBodyMetrics()
        mergeRecovery()
    }

    /// MK21: nights you logged by hand that live in the app (see `finishManualSleep`).
    func setLocalSleep(_ intervals: [DateInterval]) {
        localSleep = ReadinessEngine.nights(from: intervals)
        mergeRecovery()
    }

    /// Live Apple Health wins on any day it has; then nights kept in the app; the export fills in the rest.
    private func mergeRecovery() {
        let cal = Calendar.current
        var taken = Set(healthSleep.map { cal.startOfDay(for: $0.date) })
        let kept = localSleep.filter { !taken.contains(cal.startOfDay(for: $0.date)) }
        taken.formUnion(kept.map { cal.startOfDay(for: $0.date) })
        let old = (imported?.sleep ?? []).filter { !taken.contains(cal.startOfDay(for: $0.date)) }
        sleep = (old + kept + healthSleep).sorted { $0.date < $1.date }
        func merge(_ live: [BodyMetricPoint], _ old: [BodyMetricPoint]) -> [BodyMetricPoint] {
            let days = Set(live.map { cal.startOfDay(for: $0.date) })
            return (old.filter { !days.contains(cal.startOfDay(for: $0.date)) } + live).sorted { $0.date < $1.date }
        }
        restingHeartRate = merge(healthResting, imported?.restingHeartRate ?? [])
        heartRateVariability = merge(healthHRV, imported?.heartRateVariability ?? [])
    }

    private func querySleep(days: Int) async -> [SleepNight] {
        await SleepHealth.nights(days: days, store: healthStore)
    }

    /// MK11: "Going to sleep" / "I'm awake" on the iPhone.
    func startManualSleep() { SleepHealth.manualStart = .now }

    /// "I'm awake": saves the night (30 min – 16 h) to Apple Health. MK21: when Health can't take it — no
    /// Health access on this install, or sleep writing switched off — the night is returned so the app keeps
    /// it itself; before, it was dropped without a word.
    func finishManualSleep(now: Date = .now) async -> DateInterval? {
        guard let start = SleepHealth.manualStart else { return nil }
        SleepHealth.manualStart = nil
        let length = now.timeIntervalSince(start)
        guard length >= 30 * 60, length <= 16 * 3600 else { return nil }
        do {
            try await SleepHealth.saveManual(start: start, end: now, store: healthStore)
            await refreshRecovery()
            return nil
        } catch {
            return DateInterval(start: start, end: now)
        }
    }

    private func queryQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        metric: BodyMetricPoint.Metric,
        days: Int,
        transform: @escaping (Double) -> Double
    ) async -> [BodyMetricPoint] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let store = healthStore

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let points = (samples as? [HKQuantitySample] ?? []).map { sample in
                    BodyMetricPoint(
                        metric: metric,
                        date: sample.startDate,
                        value: transform(sample.quantity.doubleValue(for: unit))
                    )
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }
}

// MARK: - Apple Health export import (MK20.4)

/// What came out of an Apple Health export (Health app → profile → Export All Health Data).
/// Saved on this iPhone and merged with live Apple Health / typed-in data.
struct HealthImportData: Codable {
    var importedAt = Date()
    var weights: [BodyMetricPoint] = []
    var fats: [BodyMetricPoint] = []
    var restingHeartRate: [BodyMetricPoint] = []
    /// One point per day (daily average), to keep it small.
    var heartRateVariability: [BodyMetricPoint] = []
    var sleep: [SleepNight] = []
    var heightCm: Double?
    var birthDate: Date?
    var sex: String?

    var summary: String {
        var parts: [String] = []
        if !weights.isEmpty { parts.append("\(weights.count) weights") }
        if !fats.isEmpty { parts.append("\(fats.count) body fat") }
        if !sleep.isEmpty { parts.append("\(sleep.count) nights of sleep") }
        if !restingHeartRate.isEmpty { parts.append("\(restingHeartRate.count) resting HR") }
        if !heartRateVariability.isEmpty { parts.append("\(heartRateVariability.count) days of HRV") }
        if heightCm != nil { parts.append("height") }
        if birthDate != nil { parts.append("birthday") }
        if sex != nil { parts.append("sex") }
        return parts.isEmpty ? "Nothing found" : parts.joined(separator: " · ")
    }

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("health-import.json")
    }

    static func load() -> HealthImportData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HealthImportData.self, from: data)
    }

    func save() throws { try JSONEncoder().encode(self).write(to: Self.url, options: .atomic) }

    static func delete() { try? FileManager.default.removeItem(at: url) }
}

enum HealthImportError: LocalizedError {
    case unreadable, noExportXML, unsupportedZip(String)
    var errorDescription: String? {
        switch self {
        case .unreadable: return "Couldn't open that file."
        case .noExportXML: return "That zip has no export.xml in it. Pick the export.zip from Health → Export All Health Data."
        case .unsupportedZip(let why): return "Couldn't read the zip (\(why)). Unzip it in Files and pick export.xml instead."
        }
    }
}

/// Reads an Apple Health export — export.zip as it comes, or the unzipped export.xml — a chunk at a time,
/// so a multi-GB file never has to fit in memory. Only body, sleep and recovery records are kept.
enum HealthExportImporter {
    /// Sleep, resting HR and HRV older than this aren't kept (weight and body fat keep everything).
    static let recoveryYears = 2

    static func run(url: URL, progress: @escaping @Sendable (Double) -> Void) throws -> HealthImportData {
        let scanner = HealthExportScanner(recoverySince: Calendar.current.date(byAdding: .year, value: -recoveryYears, to: .now) ?? .distantPast)
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw HealthImportError.unreadable }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: 4) ?? Data()
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            try readZip(handle, size: size, scanner: scanner, progress: progress)
        } else {
            try handle.seek(toOffset: 0)
            var done: UInt64 = 0
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                autoreleasepool { scanner.feed(chunk) }
                done += UInt64(chunk.count)
                if size > 0 { progress(Double(done) / Double(size)) }
            }
        }
        scanner.finish()
        return scanner.result()
    }

    // MARK: Zip (stored or deflate, zip64 aware), finding the big export XML

    private struct Entry { let name: String; let method: UInt16; let compressed: UInt64; let uncompressed: UInt64; let localOffset: UInt64 }

    private static func u16(_ d: Data, _ o: Int) -> UInt16 { d.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt16.self)) } }
    private static func u32(_ d: Data, _ o: Int) -> UInt32 { d.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) } }
    private static func u64(_ d: Data, _ o: Int) -> UInt64 { d.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt64.self)) } }

    private static func readZip(_ handle: FileHandle, size: UInt64, scanner: HealthExportScanner, progress: @escaping @Sendable (Double) -> Void) throws {
        // End of central directory: in the last 64 KB + 22 bytes.
        let tailLength = min(size, 65_557)
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard tail.count >= 22, let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: { u32(tail, $0) == 0x06054B50 }) else {
            throw HealthImportError.unsupportedZip("no directory")
        }
        var count = UInt64(u16(tail, eocd + 10))
        var dirSize = UInt64(u32(tail, eocd + 12))
        var dirOffset = UInt64(u32(tail, eocd + 16))
        // Zip64 end record (big exports).
        if dirOffset == 0xFFFF_FFFF || count == 0xFFFF, eocd >= 20, u32(tail, eocd - 20) == 0x07064B50 {
            let z64 = u64(tail, eocd - 20 + 8)
            try handle.seek(toOffset: z64)
            let rec = try handle.read(upToCount: 56) ?? Data()
            guard rec.count >= 56, u32(rec, 0) == 0x06064B50 else { throw HealthImportError.unsupportedZip("zip64 record") }
            count = u64(rec, 32); dirSize = u64(rec, 40); dirOffset = u64(rec, 48)
        }
        try handle.seek(toOffset: dirOffset)
        let dir = try handle.read(upToCount: Int(dirSize)) ?? Data()
        var entries: [Entry] = []
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= dir.count, u32(dir, p) == 0x02014B50 else { break }
            let method = u16(dir, p + 10)
            var compressed = UInt64(u32(dir, p + 20)), uncompressed = UInt64(u32(dir, p + 24))
            let nameLen = Int(u16(dir, p + 28)), extraLen = Int(u16(dir, p + 30)), commentLen = Int(u16(dir, p + 32))
            var offset = UInt64(u32(dir, p + 42))
            let name = String(decoding: dir[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            // Zip64 extra field: the 0xFFFFFFFF values, in order.
            var e = p + 46 + nameLen
            let extraEnd = e + extraLen
            while e + 4 <= extraEnd {
                let id = u16(dir, e), len = Int(u16(dir, e + 2))
                if id == 0x0001 {
                    var q = e + 4
                    if uncompressed == 0xFFFF_FFFF { uncompressed = u64(dir, q); q += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = u64(dir, q); q += 8 }
                    if offset == 0xFFFF_FFFF { offset = u64(dir, q) }
                }
                e += 4 + len
            }
            entries.append(Entry(name: name, method: method, compressed: compressed, uncompressed: uncompressed, localOffset: offset))
            p = extraEnd + commentLen
        }
        // export.xml (named in your language, e.g. 导出.xml) is the biggest .xml that isn't the clinical CDA file.
        guard let entry = entries
            .filter({ $0.name.lowercased().hasSuffix(".xml") && !$0.name.lowercased().contains("cda") })
            .max(by: { $0.uncompressed < $1.uncompressed }) else { throw HealthImportError.noExportXML }

        try handle.seek(toOffset: entry.localOffset)
        let local = try handle.read(upToCount: 30) ?? Data()
        guard local.count == 30, u32(local, 0) == 0x04034B50 else { throw HealthImportError.unsupportedZip("entry header") }
        let dataStart = entry.localOffset + 30 + UInt64(u16(local, 26)) + UInt64(u16(local, 28))
        try handle.seek(toOffset: dataStart)

        guard entry.method == 8 || entry.method == 0 else { throw HealthImportError.unsupportedZip("method \(entry.method)") }
        var remaining = entry.compressed
        var filter: OutputFilter?
        if entry.method == 8 {   // deflate = Compression's .zlib (raw DEFLATE)
            filter = try OutputFilter(.decompress, using: .zlib, writingTo: { data in
                if let data { autoreleasepool { scanner.feed(data) } }
            })
        }
        while remaining > 0 {
            let chunk = try handle.read(upToCount: Int(min(remaining, 1 << 20))) ?? Data()
            if chunk.isEmpty { break }
            remaining -= UInt64(chunk.count)
            if let filter { try filter.write(chunk) } else { autoreleasepool { scanner.feed(chunk) } }
            if entry.compressed > 0 { progress(1 - Double(remaining) / Double(entry.compressed)) }
        }
        try filter?.finalize()
    }
}

/// Line-by-line scan of export.xml. Every record starts on its own line, so this doesn't need a full
/// XML parse (which some iOS versions' exports break with a bad DTD).
final class HealthExportScanner {
    private let recoverySince: Date
    private var carry = Data()
    private var data = HealthImportData()
    private var sleepIntervals: [DateInterval] = []
    private var hrvByDay: [Date: (sum: Double, count: Int)] = [:]
    private var height: (date: Date, cm: Double)?

    private static let recordPrefix = Array("<Record type=\"".utf8)
    private static let mePrefix = Array("<Me ".utf8)
    private static let wanted: Set<String> = [
        "HKQuantityTypeIdentifierBodyMass", "HKQuantityTypeIdentifierBodyFatPercentage", "HKQuantityTypeIdentifierHeight",
        "HKQuantityTypeIdentifierRestingHeartRate", "HKQuantityTypeIdentifierHeartRateVariabilitySDNN",
        "HKCategoryTypeIdentifierSleepAnalysis"
    ]
    private static let asleepValues: Set<String> = [
        "HKCategoryValueSleepAnalysisAsleep", "HKCategoryValueSleepAnalysisAsleepUnspecified",
        "HKCategoryValueSleepAnalysisAsleepCore", "HKCategoryValueSleepAnalysisAsleepDeep", "HKCategoryValueSleepAnalysisAsleepREM"
    ]
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(recoverySince: Date) { self.recoverySince = recoverySince }

    func feed(_ chunk: Data) {
        var buffer = carry
        buffer.append(chunk)
        var lineStart = 0
        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let count = raw.count
            while lineStart < count, let found = memchr(base + lineStart, 0x0A, count - lineStart) {
                let end = base.distance(to: UnsafeRawPointer(found))
                line(UnsafeRawBufferPointer(rebasing: raw[lineStart..<end]))
                lineStart = end + 1
            }
        }
        carry = lineStart < buffer.count ? buffer.subdata(in: lineStart..<buffer.count) : Data()
    }

    func finish() {
        if !carry.isEmpty { carry.withUnsafeBytes { line($0) } }
        carry = Data()
    }

    func result() -> HealthImportData {
        var out = data
        out.weights.sort { $0.date < $1.date }
        out.fats.sort { $0.date < $1.date }
        out.restingHeartRate.sort { $0.date < $1.date }
        out.heartRateVariability = hrvByDay.map { BodyMetricPoint(metric: .heartRateVariability, date: $0.key.addingTimeInterval(12 * 3600), value: $0.value.sum / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
        out.sleep = ReadinessEngine.nights(from: sleepIntervals)
        out.heightCm = height?.cm
        out.importedAt = .now
        return out
    }

    // MARK: One line

    private func line(_ bytes: UnsafeRawBufferPointer) {
        // Skip leading spaces, then only <Record type="…"> and <Me …> lines are of interest.
        var i = 0
        while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x09 { i += 1 }
        let rest = UnsafeRawBufferPointer(rebasing: bytes[i...])
        if rest.starts(with: Self.recordPrefix) {
            // Read the type without building a String for the millions of heart-rate / step lines.
            let typeStart = Self.recordPrefix.count
            guard let quote = rest[typeStart...].firstIndex(of: 0x22) else { return }
            let type = String(decoding: rest[typeStart..<quote], as: UTF8.self)
            guard Self.wanted.contains(type) else { return }
            record(type: type, line: String(decoding: rest, as: UTF8.self))
        } else if rest.starts(with: Self.mePrefix) {
            me(String(decoding: rest, as: UTF8.self))
        }
    }

    private func attribute(_ name: String, in line: String) -> String? {
        guard let start = line.range(of: " \(name)=\"") else { return nil }
        guard let end = line[start.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(line[start.upperBound..<end])
    }

    private func record(type: String, line: String) {
        guard let startText = attribute("startDate", in: line), let start = dateFormatter.date(from: startText) else { return }
        let unit = attribute("unit", in: line) ?? ""
        let value = attribute("value", in: line)
        let number = value.flatMap(Double.init)
        switch type {
        case "HKQuantityTypeIdentifierBodyMass":
            guard var kg = number else { return }
            if unit == "lb" { kg *= 0.45359237 } else if unit == "g" { kg /= 1000 } else if unit == "st" { kg *= 6.35029318 }
            guard (20...400).contains(kg) else { return }
            data.weights.append(BodyMetricPoint(metric: .bodyWeight, date: start, value: kg))
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            guard var pct = number else { return }
            if pct <= 1 { pct *= 100 }   // exported as a fraction (0.18 = 18%)
            guard (2...70).contains(pct) else { return }
            data.fats.append(BodyMetricPoint(metric: .bodyFatPercentage, date: start, value: pct))
        case "HKQuantityTypeIdentifierHeight":
            guard var cm = number else { return }
            switch unit { case "m": cm *= 100; case "in": cm *= 2.54; case "ft": cm *= 30.48; case "mm": cm /= 10; default: break }
            guard (100...250).contains(cm), start >= (height?.date ?? .distantPast) else { return }
            height = (start, cm)
        case "HKQuantityTypeIdentifierRestingHeartRate":
            guard let bpm = number, start >= recoverySince, (25...150).contains(bpm) else { return }
            data.restingHeartRate.append(BodyMetricPoint(metric: .restingHeartRate, date: start, value: bpm))
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN":
            guard let ms = number, start >= recoverySince, ms > 0, ms < 400 else { return }
            let day = Calendar.current.startOfDay(for: start)
            let old = hrvByDay[day] ?? (0, 0)
            hrvByDay[day] = (old.sum + ms, old.count + 1)
        case "HKCategoryTypeIdentifierSleepAnalysis":
            guard start >= recoverySince, let value, Self.asleepValues.contains(value),
                  let endText = attribute("endDate", in: line), let end = dateFormatter.date(from: endText), end > start,
                  end.timeIntervalSince(start) < 20 * 3600 else { return }
            sleepIntervals.append(DateInterval(start: start, end: end))
        default:
            break
        }
    }

    private func me(_ line: String) {
        if let dob = attribute("HKCharacteristicTypeIdentifierDateOfBirth", in: line), let date = dayFormatter.date(from: dob) {
            data.birthDate = date
        }
        switch attribute("HKCharacteristicTypeIdentifierBiologicalSex", in: line) {
        case "HKBiologicalSexMale": data.sex = "male"
        case "HKBiologicalSexFemale": data.sex = "female"
        default: break
        }
    }
}
