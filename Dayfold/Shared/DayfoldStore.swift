import Foundation
import Combine

extension Notification.Name {
    /// A Dayfold snapshot arrived from the other device (posted by GymForge's Watch bridge).
    static let dayfoldReceived = Notification.Name("dayfold.received")
}

final class DayfoldStore: ObservableObject {
    @Published private(set) var snapshot: DayfoldSnapshot
    @Published var syncStatus = "Not synced yet"
    @Published var errorMessage: String?
    #if os(iOS)
    let notifications = DayfoldNotifications()
    /// Tomorrow's planned GymForge session name, if any (set by GymForge).
    var gymTomorrow: () -> String? = { nil }
    /// No session planned or logged today (set by GymForge), for abs once a week.
    var isRestDay: () -> Bool = { false }
    /// Sunday's meal-prep step, sized from the protein target (set by GymForge).
    var mealPrepTitle: () -> String? = { nil }
    /// Called after any check-off or edit (GymForge refreshes the wind-down Live Activity).
    var onChange: () -> Void = {}
    #endif
    private let url: URL
    private var observer: NSObjectProtocol?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = directory.appendingPathComponent("dayfold-v2.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { snapshot = try JSONDecoder().decode(DayfoldSnapshot.self, from: Data(contentsOf: url)) }
            catch {
                // Preserve the original for recovery; never silently overwrite a corrupt file.
                let backup = directory.appendingPathComponent("dayfold-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: backup)
                snapshot = DayfoldSnapshot(configuration: .initial())
                errorMessage = "Could not read saved routines. A recovery copy was kept. \(error.localizedDescription)"
            }
        } else {
            #if os(watchOS)
            // Phone owns configuration. Watch starts empty until first phone sync.
            snapshot = DayfoldSnapshot(configuration: DayfoldConfiguration(revision: .distantPast, tasks: [], routines: []))
            #else
            snapshot = DayfoldSnapshot(configuration: .initial())
            #endif
        }
        #if os(iOS)
        // MK15: setups from before the wake-up checklist get its starter steps once.
        let seededKey = "dayfold.wakeSeeded"
        if !UserDefaults.standard.bool(forKey: seededKey) {
            UserDefaults.standard.set(true, forKey: seededKey)
            if !snapshot.configuration.tasks.contains(where: \.wake) {
                let next = (snapshot.configuration.tasks.map(\.order).max() ?? -1) + 1
                snapshot.configuration.tasks += RoutineTask.wakeStarters(startOrder: next)
                snapshot.configuration.revision = Date()
            }
        }
        #endif
        observer = NotificationCenter.default.addObserver(forName: .dayfoldReceived, object: nil, queue: .main) { [weak self] note in
            if let incoming = note.object as? DayfoldSnapshot { self?.receive(incoming) }
        }
        persist()
    }

    func rows(_ kind: RoutineKind, now: Date = Date()) -> [TaskOccurrence] {
        var state = snapshot
        #if os(iOS)
        if kind == .daily, let session = gymTomorrow() { state.configuration.tasks.append(.gymPack(session, now: now)) }
        if kind == .weekly, let prep = mealPrepTitle() { state.configuration.tasks.append(.mealPrep(prep)) }
        if kind == .weekly, let abs = ScheduleEngine.absTask(completions: snapshot.completions, restDay: isRestDay(), now: now) {
            state.configuration.tasks.append(abs)
        }
        #endif
        return ScheduleEngine.rows(state, kind: kind, now: now)
    }

    /// Tonight's before-bed checklist: every before-bed task due today (done ones included, for progress).
    func bedtimeRows(now: Date = Date()) -> [TaskOccurrence] {
        RoutineKind.allCases.flatMap { rows($0, now: now) }.filter { $0.task.bedtime && ($0.retryToday || $0.done) }
    }

    /// This morning's wake-up checklist: every wake-up task due today.
    func wakeRows(now: Date = Date()) -> [TaskOccurrence] {
        RoutineKind.allCases.flatMap { rows($0, now: now) }.filter { $0.task.wake && ($0.retryToday || $0.done) }
    }

    /// Ticks the weigh-in once Apple Health has a weight reading on or after its due day.
    // shortcut: matches tasks by "weigh" in the title; add a per-task "from Apple Health" switch if you rename it.
    func autoTickWeighIn(weightDates: [Date]) {
        guard let latest = weightDates.max() else { return }
        var ticked = false
        for row in RoutineKind.allCases.flatMap({ rows($0) })
        where !row.done && row.task.title.localizedCaseInsensitiveContains("weigh") && latest >= row.due {
            snapshot.completions[row.id] = DayfoldCompletion(id: row.id, taskID: row.task.id, occurrence: row.due, done: true, changedAt: latest)
            ticked = true
        }
        if ticked { changed() }
    }

    func setDone(_ row: TaskOccurrence, done: Bool) {
        snapshot.completions[row.id] = DayfoldCompletion(id: row.id, taskID: row.task.id, occurrence: row.due, done: done, changedAt: Date())
        changed()
    }

    func saveTask(_ task: RoutineTask) {
        if let index = snapshot.configuration.tasks.firstIndex(where: { $0.id == task.id }) {
            snapshot.configuration.tasks[index] = task
        } else { snapshot.configuration.tasks.append(task) }
        configChanged()
    }
    func deleteTask(_ id: UUID) {
        snapshot.configuration.tasks.removeAll { $0.id == id }
        configChanged()
    }
    func reorder(_ kind: RoutineKind, from offsets: IndexSet, to destination: Int) {
        var list = snapshot.configuration.tasks.filter { $0.routine == kind }.sorted { $0.order < $1.order }
        let moving = offsets.sorted().map { list[$0] }
        for index in offsets.sorted(by: >) { list.remove(at: index) }
        let position = destination - offsets.filter { $0 < destination }.count
        list.insert(contentsOf: moving, at: position)
        for (order, var task) in list.enumerated() {
            task.order = order
            if let index = snapshot.configuration.tasks.firstIndex(where: { $0.id == task.id }) { snapshot.configuration.tasks[index] = task }
        }
        configChanged()
    }
    func settings(_ kind: RoutineKind) -> RoutineSettings {
        snapshot.configuration.routines.first { $0.kind == kind } ?? RoutineSettings(kind: kind, hour: kind == .daily ? 8 : 9)
    }
    func saveSettings(_ settings: RoutineSettings) {
        if let index = snapshot.configuration.routines.firstIndex(where: { $0.kind == settings.kind }) {
            snapshot.configuration.routines[index] = settings
        } else { snapshot.configuration.routines.append(settings) }
        configChanged()
    }
    private func configChanged() {
        snapshot.configuration.revision = Date()
        changed()
    }
    private func changed() {
        persist()
        send(reliable: true)
        scheduleNotifications()
        #if os(iOS)
        onChange()
        #endif
    }
    private func receive(_ incoming: DayfoldSnapshot) {
        var next = snapshot
        #if os(watchOS)
        if incoming.configuration.revision > next.configuration.revision { next.configuration = incoming.configuration }
        #endif
        next.completions = ScheduleEngine.merge(next.completions, incoming.completions)
        syncStatus = "Synced \(Date().formatted(date: .omitted, time: .shortened))"
        if next.configuration != snapshot.configuration || next.completions != snapshot.completions {
            snapshot = next
            persist()
            scheduleNotifications()
            #if os(iOS)
            onChange()
            #endif
        }
        // Reply only while the other side is behind (e.g. a fresh Watch); stops once both match.
        if incoming.configuration != snapshot.configuration || incoming.completions != Self.recent(snapshot.completions) {
            send(reliable: false)
        }
    }
    func refresh() {
        objectWillChange.send()
        send(reliable: false)
        scheduleNotifications()
    }
    /// Goes through GymForge's own Watch connection (an app can only have one).
    private func send(reliable: Bool) {
        var outgoing = snapshot
        outgoing.completions = Self.recent(snapshot.completions)
        #if os(iOS)
        PhoneWatchBridge.current?.sendDayfold(outgoing, reliable: reliable)
        #elseif os(watchOS)
        WatchBridge.current?.sendDayfold(outgoing, reliable: reliable)
        #endif
    }
    /// Last 60 days only, to keep messages small; older check-offs stay on each device and merge never deletes.
    static func recent(_ completions: [String: DayfoldCompletion], now: Date = Date()) -> [String: DayfoldCompletion] {
        let cutoff = Calendar.current.startOfDay(for: now).addingTimeInterval(-60 * 86_400)
        return completions.filter { $0.value.occurrence > cutoff }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch { errorMessage = "Could not save: \(error.localizedDescription)" }
    }
    private func scheduleNotifications() {
        #if os(iOS)
        var state = snapshot
        if let prep = mealPrepTitle() { state.configuration.tasks.append(.mealPrep(prep)) }   // in the Weekly reminder too
        notifications.rebuild(state)
        #endif
    }
}
