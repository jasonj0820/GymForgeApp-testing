import Foundation
import CryptoKit
import CommonCrypto
import LocalAuthentication
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

enum MTVaultError: LocalizedError {
    case keychain
    case wrongPasscode
    case badFile
    case photosUnreadable(Int)

    var errorDescription: String? {
        switch self {
        case .keychain: return "Couldn't access the secure key."
        case .wrongPasscode: return "Wrong passcode, or this isn't a More Training export."
        case .badFile: return "This file couldn't be read."
        case .photosUnreadable(let count): return "\(count) private photo\(count == 1 ? "" : "s") couldn't be read, so the export was stopped rather than leave them out."
        }
    }
}

/// Encrypted storage for the More Training section.
/// - Data and photos are AES-GCM encrypted with a key kept in the Keychain (this device only).
/// - Files live in a folder excluded from iCloud/iTunes backups.
/// - Nothing is in memory while locked.
@MainActor
final class MTVault: ObservableObject {
    static let shared = MTVault()

    @Published private(set) var isUnlocked = false
    @Published var data = MTData()
    @Published private(set) var thumbnails: [UUID: UIImage] = [:]

    private init() {}

    /// Latest body fat % from the gym side (Apple Health), handed in when the section opens.
    /// Read-only and one-way: nothing from here ever goes back to the gym side.
    static var gymBodyFatPercent: Double?

    // MARK: Unlock / lock

    /// Face ID (falls back to the device passcode).
    func unlock() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock More Training")
            guard ok else { return false }
            // If the saved data can't be read, stay locked: never show (and later save) an empty vault over it.
            do { try load() } catch {
                print("More Training data unreadable: \(error)")
                return false
            }
            loadThumbnails()
            isUnlocked = true
            advanceInterval()
            MTLiveTimer.sync(data)   // a timer that kept running while locked gets its card back
            rescheduleMeasureReminder()
            rescheduleTrainingReminder()
            return true
        } catch {
            return false
        }
    }

    func lock() {
        if isUnlocked { save() }
        skipUndo = nil
        isUnlocked = false
        data = MTData()
        thumbnails = [:]
        backgroundedAt = nil
    }

    // MARK: MK22.1 — timer buttons while locked

    /// True only inside `applyWhileLocked`, so its change can be saved without unlocking.
    private var workingLocked = false

    /// A timer button (widget, Lock Screen card, Dynamic Island) pressed while the section is locked: iOS
    /// closed the app in the background, or you locked it yourself with a timer running. Reads the saved
    /// timer, applies the change and saves it — without unlocking, without showing anything, and with
    /// nothing left in memory afterwards. False if there was nothing to apply it to (no timer running, or
    /// the iPhone itself is locked so the file can't be read).
    func applyWhileLocked(_ change: () -> Void) -> Bool {
        guard !isUnlocked, !workingLocked else { return false }
        defer {
            workingLocked = false
            skipUndo = nil
            data = MTData()
        }
        do { try load() } catch { return false }
        guard data.timerRunning else { return false }
        workingLocked = true
        change()
        return true
    }

    // MARK: MK17 — stay open while a timer runs

    private var backgroundedAt: Date?
    /// When the running interval program was due to finish (nil = open timer), noted on leaving the app.
    private var timerEndsAt: Date?

    /// Leaving the app: stays unlocked while a timer runs (so it's still open when you come back and the
    /// screen locking doesn't end it); otherwise locks as before. Returns false if it locked.
    func stayOpenForTimer(now: Date = .now) -> Bool {
        guard isUnlocked, data.timerRunning else { return false }
        save()
        backgroundedAt = now
        timerEndsAt = MTLiveTimer.content(for: data, now: now)?.state.endsAt
        return true
    }

    /// Back in the app: catch up the timer; if it finished more than 10 minutes ago, lock after all.
    func returnedToApp(now: Date = .now) {
        guard isUnlocked, let away = backgroundedAt else { return }
        backgroundedAt = nil
        if unsavedChanges { save() }   // changes made from the widget while the iPhone was locked
        advanceInterval(now: now)
        tickStamina(now: now)
        let free = max(away, timerEndsAt ?? away)
        if !data.timerRunning, now.timeIntervalSince(free) > 10 * 60 { lock() }
    }

    // MARK: All Day Stretcher (Phallosan Forte)

    func startStretcher(level: MTLevel) {
        guard data.stretcherStartedAt == nil else { return }
        data.stretcherStartedAt = .now
        data.stretcherLevel = level
        save()
    }

    /// Ends the current wear segment and logs it.
    func pauseStretcher() {
        guard let start = data.stretcherStartedAt else { return }
        let end = Date()
        if end.timeIntervalSince(start) >= 30 {
            data.sessions.append(MTSession(type: .allDayStretcher, start: start, end: end, level: data.stretcherLevel))
        }
        data.stretcherStartedAt = nil
        save()
    }

    /// Switches level without a gap: closes the current segment and starts a new one.
    func changeStretcherLevel(_ level: MTLevel) {
        guard data.stretcherStartedAt != nil, data.stretcherLevel != level else {
            data.stretcherLevel = level
            save()
            return
        }
        pauseStretcher()
        startStretcher(level: level)
    }

    /// Stretcher wear time today, including the running segment.
    func stretcherToday(at now: Date = .now) -> TimeInterval {
        let today = Calendar.current.startOfDay(for: now)
        let logged = data.sessions
            .filter { $0.type == .allDayStretcher && $0.end > today }
            .reduce(0) { $0 + $1.end.timeIntervalSince(max($1.start, today)) }
        let running = data.stretcherStartedAt.map { now.timeIntervalSince(max($0, today)) } ?? 0
        return logged + max(0, running)
    }

    // MARK: Timed sessions

    /// Sessions just saved that should get a quick "how did it go?" (warning signs, notes).
    /// MK19: stored in the vault file, so the measuring screen comes back (after Face ID) until it's filled in.
    var pendingReview: [UUID] {
        get { data.pendingReview ?? [] }
        set { data.pendingReview = newValue.isEmpty ? nil : newValue }
    }
    /// MK19: one-step undo for Skip. Memory only; cleared when the next phase ends on its own or the review is saved.
    struct SkipUndo { let run: MTActiveInterval; let elapsed: Double; let logged: [UUID]; let sessions: [MTSession] }
    @Published private(set) var skipUndo: SkipUndo?
    /// Sessions logged so far by the running interval program.
    private var intervalLogged: [UUID] = []

    func startTimed(_ type: MTType, pressureInHg: Double?, tensionKg: Double?, nir: Bool = false) async {
        guard !data.isBusy, type != .allDayStretcher else { return }
        data.activeSession = MTActiveSession(type: type, start: .now, pressureInHg: pressureInHg, tensionKg: tensionKg,
                                             nir: nir && type == .highTensionExtender ? true : nil)
        save()
        if let minutes = data.settings.limit(for: type) {
            await scheduleLimitAlert(after: TimeInterval(minutes * 60))
        }
    }

    func stopTimed() {
        guard let active = data.activeSession else { return }
        let session = MTSession(type: active.type, start: active.start, end: .now,
                                pressureInHg: active.pressureInHg, tensionKg: active.tensionKg, nir: active.nir)
        data.sessions.append(session)
        data.activeSession = nil
        cancelLimitAlert()
        pendingReview = [session.id]
        save()
    }

    func cancelTimed() {
        data.activeSession = nil
        cancelLimitAlert()
        save()
    }

    /// Adds warning signs / notes (and MK18: expansion %) to the sessions that were just saved.
    func applyReview(warnings: Set<MTWarning>, notes: String, girthExpansion: Double? = nil, lengthExpansion: Double? = nil) {
        let ids = Set(pendingReview)
        let reviewed = data.sessions.indices.filter { ids.contains(data.sessions[$0].id) }
        for index in reviewed {
            data.sessions[index].warnings = warnings.isEmpty ? nil : MTWarning.allCases.filter { warnings.contains($0) }
            if !notes.isEmpty { data.sessions[index].notes = notes }
        }
        // MK19.1: each measurement counts once — on the latest pump/PAC and the latest extender session.
        if let girthExpansion, let index = reviewed.last(where: { [.pump, .pac].contains(data.sessions[$0].type) }) {
            data.sessions[index].expansionPercent = girthExpansion
        }
        if let lengthExpansion, let index = reviewed.last(where: { data.sessions[$0].type == .highTensionExtender }) {
            data.sessions[index].expansionPercent = lengthExpansion
        }
        pendingReview = []
        skipUndo = nil
        save()
    }

    func addSession(_ session: MTSession) {
        data.sessions.append(session)
        data.sessions.sort { $0.start < $1.start }
        save()
    }

    func deleteSession(_ id: UUID) {
        data.sessions.removeAll { $0.id == id }
        save()
    }

    // MARK: Interval timer

    func startInterval(name: String, steps: [MTPresetStep]) async {
        guard !data.isBusy, !steps.isEmpty else { return }
        data.activeInterval = MTActiveInterval.build(name: name, steps: steps, now: .now)
        intervalLogged = []
        skipUndo = nil
        save()
        _ = await ReminderScheduler.requestPermission()
        scheduleIntervalAlerts()
    }

    /// Moves through any phases whose time has passed (also catches up after the app was closed).
    func advanceInterval(now: Date = .now) {
        guard var run = data.activeInterval, !run.isPaused else { return }
        var changed = false
        var logged: [UUID] = []
        while let phase = run.currentPhase, let end = run.phaseEnd(), end <= now {
            if phase.kind == .work {
                run.workDone[phase.stepIndex, default: 0] += phase.seconds
                let moreWork = run.phases[(run.index + 1)...].contains { $0.stepIndex == phase.stepIndex && $0.kind == .work }
                if !moreWork, let id = logStep(run, stepIndex: phase.stepIndex, end: end) { logged.append(id) }
            }
            run.index += 1
            run.phaseStartedAt = end
            if let next = run.currentPhase, run.stepStarts[next.stepIndex] == nil {
                run.stepStarts[next.stepIndex] = end
            }
            changed = true
        }
        guard changed else { return }
        skipUndo = nil
        if run.currentPhase == nil {
            data.activeInterval = nil
        } else {
            data.activeInterval = run
        }
        MTHaptics.timerUp()
        // Keep the next batch of alerts queued (only a limited number are scheduled at a time).
        if data.activeInterval != nil { scheduleIntervalAlerts() } else { cancelIntervalAlerts() }
        intervalLogged += logged
        if data.activeInterval == nil {
            pendingReview = intervalLogged
            intervalLogged = []
        }
        save()
    }

    func pauseInterval() {
        guard var run = data.activeInterval, !run.isPaused else { return }
        run.pausedRemaining = run.remaining(at: .now)
        data.activeInterval = run
        cancelIntervalAlerts()
        save()
    }

    func resumeInterval() {
        guard var run = data.activeInterval, let remaining = run.pausedRemaining, let phase = run.currentPhase else { return }
        run.phaseStartedAt = Date().addingTimeInterval(-(phase.seconds - remaining))
        run.pausedRemaining = nil
        data.activeInterval = run
        save()
        scheduleIntervalAlerts()
    }

    /// MK19.1: one more minute on the step you're on (e.g. PAC's final set 10 → 12 min).
    func extendPhase(by seconds: Double = 60) {
        guard var run = data.activeInterval, run.currentPhase != nil else { return }
        run.phases[run.index].seconds += seconds
        if let paused = run.pausedRemaining { run.pausedRemaining = paused + seconds }
        data.activeInterval = run
        cancelIntervalAlerts()
        save()
        scheduleIntervalAlerts()
    }

    /// Ends the current phase now (work done so far counts).
    func skipPhase() {
        guard var run = data.activeInterval, let phase = run.currentPhase else { return }
        let before = run, loggedBefore = intervalLogged, sessionsBefore = data.sessions
        let now = Date()
        let elapsed = phase.seconds - run.remaining(at: now)
        run.phases[run.index].seconds = max(elapsed, 0)
        run.pausedRemaining = nil
        run.phaseStartedAt = now.addingTimeInterval(-max(elapsed, 0))
        data.activeInterval = run
        cancelIntervalAlerts()
        advanceInterval(now: now)
        // MK19.1: also after skipping the last phase — the measuring screen then offers "Back to timer".
        skipUndo = SkipUndo(run: before, elapsed: max(elapsed, 0), logged: loggedBefore, sessions: sessionsBefore)
        scheduleIntervalAlerts()
    }

    /// MK20.6: straight on to the next step (exercise) — the rest of this step's rounds and rests are dropped.
    func nextStep() {
        guard var run = data.activeInterval, let phase = run.currentPhase else { return }
        var i = run.index + 1
        while i < run.phases.count, run.phases[i].stepIndex == phase.stepIndex {
            run.phases[i].seconds = 0
            i += 1
        }
        data.activeInterval = run
        skipPhase()
    }

    /// Back to the phase you skipped, with the time it had left; drops any session the skip saved.
    func undoSkip() {
        guard let undo = skipUndo, data.activeSession == nil else { return }
        skipUndo = nil
        data.sessions = undo.sessions   // drops (or un-folds) whatever the skip saved
        intervalLogged = undo.logged
        pendingReview = []
        var run = undo.run
        if run.pausedRemaining == nil { run.phaseStartedAt = Date().addingTimeInterval(-undo.elapsed) }
        data.activeInterval = run
        cancelIntervalAlerts()
        save()
        scheduleIntervalAlerts()
    }

    func cancelInterval() {
        cancelIntervalAlerts()
        data.activeInterval = nil
        intervalLogged = []
        skipUndo = nil
        save()
    }

    /// Stops early and saves the work done so far.
    func stopInterval() {
        guard let run = data.activeInterval else { return }
        cancelIntervalAlerts()
        var final = run
        var ids: [UUID] = []
        if let phase = run.currentPhase {
            if phase.kind == .work {
                final.workDone[phase.stepIndex, default: 0] += phase.seconds - run.remaining(at: .now)
            }
            // During the rest after a step's last round, that step was already logged when its work ended.
            let alreadyLogged = phase.kind == .rest
                && !run.phases[(run.index + 1)...].contains { $0.stepIndex == phase.stepIndex && $0.kind == .work }
            if !alreadyLogged, (final.workDone[phase.stepIndex] ?? 0) >= 30,
               let id = logStep(final, stepIndex: phase.stepIndex, end: .now) {
                ids.append(id)
            }
        }
        data.activeInterval = nil
        skipUndo = nil
        pendingReview = intervalLogged + ids
        intervalLogged = []
        save()
    }

    private func logStep(_ run: MTActiveInterval, stepIndex: Int, end: Date) -> UUID? {
        data.logStep(run, stepIndex: stepIndex, end: end)   // MK19.1: guided PAC folds into one session (MTModels.swift)
    }

    private func scheduleIntervalAlerts() {
        cancelIntervalAlerts()
        guard let run = data.activeInterval, !run.isPaused, var time = run.phaseEnd() else { return }
        let center = UNUserNotificationCenter.current()
        var index = run.index
        var count = 0
        // At most 40 at a time (iOS keeps 64 pending for the whole app; Sergeant Cluck's later nags are
        // re-planned when the app is next opened). More are queued as phases end while it's open.
        while index < run.phases.count, count < 40 {
            let nextIndex = index + 1
            let content = MTVault.timerContent()
            let interval = time.timeIntervalSinceNow
            if interval > 1 {
                center.add(UNNotificationRequest(identifier: "\(Self.intervalPrefix)\(count)", content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
            }
            count += 1
            index = nextIndex
            if index < run.phases.count { time = time.addingTimeInterval(run.phases[index].seconds) }
        }
    }

    private func cancelIntervalAlerts() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<50).map { "\(Self.intervalPrefix)\($0)" })
    }

    private static let intervalPrefix = "gymforge.mt.int."

    /// Timer notification: just "⏱" plus sound/vibration. iOS drops notifications with no
    /// visible content (and won't forward them to the Watch), so this symbol is the minimum.
    nonisolated static func timerContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.body = "⏱"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        return content
    }

    /// Strong haptic pattern for timer events (silent, no text).
    static func buzz(times: Int) {
        Task { @MainActor in
            let generator = UINotificationFeedbackGenerator()
            for index in 0..<times {
                generator.notificationOccurred(.warning)
                if index < times - 1 { try? await Task.sleep(nanoseconds: 450_000_000) }
            }
        }
    }

    // MARK: Presets

    func savePreset(_ preset: MTPreset) {
        var list = data.presetList
        if let index = list.firstIndex(where: { $0.id == preset.id }) { list[index] = preset } else { list.append(preset) }
        data.presetList = list
        save()
    }

    func deletePreset(_ id: UUID) {
        data.presetList.removeAll { $0.id == id }
        save()
    }

    // MARK: Stamina training

    private static let staminaAlertIDs = ["gymforge.mt.stamina.goal", "gymforge.mt.stamina.cool"]

    func startStamina(goalMinutes: Int, withPorn: Bool) {
        guard data.activeStamina == nil else { return }
        let now = Date()
        data.activeStamina = MTActiveStamina(start: now, goalSeconds: Double(goalMinutes * 60), withPorn: withPorn, runningSince: now)
        data.settings.staminaLastWithPorn = withPorn
        save()
        scheduleStaminaAlerts()
    }

    /// "Close — cool down": stops the goal timer and starts the cool-down countdown.
    func staminaCoolDown() {
        guard var run = data.activeStamina, let since = run.runningSince else { return }
        let now = Date()
        run.accumulated += now.timeIntervalSince(since)
        run.runningSince = nil
        run.cooldownUntil = now.addingTimeInterval(Double(data.settings.cooldownSeconds))
        run.cooldownAnnounced = false
        run.pauses += 1
        data.activeStamina = run
        save()
        scheduleStaminaAlerts()
    }

    func staminaExtendCooldown(seconds: Int) {
        guard var run = data.activeStamina, let until = run.cooldownUntil else { return }
        run.cooldownUntil = max(until, .now).addingTimeInterval(Double(seconds))
        run.cooldownAnnounced = false
        data.activeStamina = run
        save()
        scheduleStaminaAlerts()
    }

    func staminaResume() {
        guard var run = data.activeStamina, run.runningSince == nil else { return }
        run.cooldownUntil = nil
        run.runningSince = .now
        data.activeStamina = run
        save()
        scheduleStaminaAlerts()
    }

    /// Called every second by the stamina screen: buzzes at the goal and when cool-down ends.
    func tickStamina(now: Date = .now) {
        guard var run = data.activeStamina else { return }
        var changed = false
        if !run.goalAnnounced, run.active(at: now) >= run.goalSeconds {
            run.goalAnnounced = true
            changed = true
            MTHaptics.timerUp()
        }
        if let until = run.cooldownUntil, !run.cooldownAnnounced, now >= until {
            run.cooldownAnnounced = true
            changed = true
            MTHaptics.timerUp()
        }
        if changed {
            data.activeStamina = run
            save()
        }
    }

    func finishStamina(notes: String? = nil) {
        guard let run = data.activeStamina else { return }
        let now = Date()
        let session = MTStaminaSession(start: run.start, end: now, goalSeconds: run.goalSeconds,
                                       activeSeconds: run.active(at: now), pauses: run.pauses,
                                       notes: (notes ?? "").isEmpty ? nil : notes, withPorn: run.withPorn)
        if session.activeSeconds >= 30 { data.staminaList.append(session) }
        data.activeStamina = nil
        cancelStaminaAlerts()
        save()
    }

    func cancelStamina() {
        data.activeStamina = nil
        cancelStaminaAlerts()
        save()
    }

    func setStaminaTag(_ id: UUID, withPorn: Bool) {
        guard let index = data.staminaList.firstIndex(where: { $0.id == id }) else { return }
        data.staminaList[index].withPorn = withPorn
        save()
    }

    func deleteStamina(_ id: UUID) {
        data.staminaList.removeAll { $0.id == id }
        save()
    }

    private func scheduleStaminaAlerts() {
        cancelStaminaAlerts()
        guard let run = data.activeStamina else { return }
        let center = UNUserNotificationCenter.current()
        let now = Date()
        if let since = run.runningSince, !run.goalAnnounced {
            let fire = since.addingTimeInterval(run.goalSeconds - run.accumulated).timeIntervalSince(now)
            if fire > 1 {
                let content = MTVault.timerContent()
                center.add(UNNotificationRequest(identifier: Self.staminaAlertIDs[0], content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false)))
            }
        }
        if let until = run.cooldownUntil {
            let fire = until.timeIntervalSince(now)
            if fire > 1 {
                let content = MTVault.timerContent()
                center.add(UNNotificationRequest(identifier: Self.staminaAlertIDs[1], content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false)))
            }
        }
    }

    private func cancelStaminaAlerts() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.staminaAlertIDs)
    }

    // MARK: Daily check-in

    func todaysCheckIn(now: Date = .now) -> MTCheckIn? {
        let today = Calendar.current.startOfDay(for: now)
        return data.checkInList.first { $0.day == today }
    }

    func checkIn(eq: Int?, morningWood: Bool?) {
        let today = Calendar.current.startOfDay(for: .now)
        var list = data.checkInList
        if let index = list.firstIndex(where: { $0.day == today }) {
            list[index].eq = eq
            list[index].morningWood = morningWood
        } else {
            list.append(MTCheckIn(day: today, eq: eq, morningWood: morningWood))
        }
        data.checkInList = list.sorted { $0.day < $1.day }
        save()
    }

    // MARK: Measurements

    func addMeasurement(_ measurement: MTMeasurement) {
        data.measurements.append(measurement)
        data.measurements.sort { $0.date < $1.date }
        save()
        rescheduleMeasureReminder()
    }

    func deleteMeasurement(_ id: UUID) {
        data.measurements.removeAll { $0.id == id }
        save()
    }

    /// MK11.3: switch to the daily routine (PAC plan off, 7 days a week, adds the preset) — or back.
    func setDailyRoutine(_ on: Bool) {
        var settings = data.settings
        guard settings.dailyRoutineOn != on else { return }
        if on {
            settings.targetDaysBeforeRoutine = settings.targetDaysPerWeek
            settings.targetDaysPerWeek = 7
        } else {
            settings.targetDaysPerWeek = settings.targetDaysBeforeRoutine ?? settings.targetDaysPerWeek
            settings.targetDaysBeforeRoutine = nil
        }
        settings.dailyRoutine = on
        updateSettings(settings)
    }

    func updateSettings(_ settings: MTSettings) {
        data.settings = settings
        save()
        rescheduleMeasureReminder()
    }

    // MARK: Photos (never touch the photo library)

    func addPhoto(_ image: UIImage, date: Date = .now, notes: String? = nil, folderID: UUID? = nil) {
        let photo = MTPhoto(date: date, notes: notes, folderID: folderID)
        guard let full = image.jpegData(compressionQuality: 0.85),
              let thumb = image.preparingThumbnail(of: CGSize(width: 360, height: 360 * image.size.height / max(image.size.width, 1)))?
                .jpegData(compressionQuality: 0.7) else { return }
        do {
            try writeEncrypted(full, to: photoURL(photo.id, thumb: false))
            try writeEncrypted(thumb, to: photoURL(photo.id, thumb: true))
            data.photos.append(photo)
            data.photos.sort { $0.date < $1.date }
            thumbnails[photo.id] = UIImage(data: thumb)
            save()
        } catch {
            print("Photo save failed: \(error)")
        }
    }

    func fullImage(_ id: UUID) -> UIImage? {
        guard isUnlocked, let bytes = try? readEncrypted(photoURL(id, thumb: false)) else { return nil }
        return UIImage(data: bytes)
    }

    /// Cached thumbnail (all are decrypted once on unlock, never during a view update).
    func thumbnail(_ id: UUID) -> UIImage? {
        thumbnails[id]
    }

    private func loadThumbnails() {
        var cache: [UUID: UIImage] = [:]
        for photo in data.photos {
            if let bytes = try? readEncrypted(photoURL(photo.id, thumb: true)), let image = UIImage(data: bytes) {
                cache[photo.id] = image
            }
        }
        thumbnails = cache
    }

    // MARK: Photo folders

    /// First visit: start with the two folders most people want.
    func seedPhotoFoldersIfNeeded() {
        guard data.photoFolders == nil else { return }
        data.photoFolders = [MTPhotoFolder(name: "Measurement"), MTPhotoFolder(name: "Pump")]
        save()
    }

    @discardableResult
    func addPhotoFolder(named name: String) -> MTPhotoFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = MTPhotoFolder(name: trimmed)
        data.folderList.append(folder)
        save()
        return folder
    }

    func renamePhotoFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = data.folderList.firstIndex(where: { $0.id == id }) else { return }
        data.folderList[index].name = trimmed
        save()
    }

    /// Deletes the folder only — its photos are kept and become unfiled.
    func deletePhotoFolder(_ id: UUID) {
        data.folderList.removeAll { $0.id == id }
        for index in data.photos.indices where data.photos[index].folderID == id {
            data.photos[index].folderID = nil
        }
        save()
    }

    func movePhoto(_ photoID: UUID, to folderID: UUID?) {
        guard let index = data.photos.firstIndex(where: { $0.id == photoID }) else { return }
        data.photos[index].folderID = folderID
        save()
    }

    func folderName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return data.folderList.first { $0.id == id }?.name
    }

    func deletePhoto(_ id: UUID) {
        try? FileManager.default.removeItem(at: photoURL(id, thumb: false))
        try? FileManager.default.removeItem(at: photoURL(id, thumb: true))
        data.photos.removeAll { $0.id == id }
        thumbnails[id] = nil
        save()
    }

    // MARK: Rest days

    func isRestDay(_ date: Date) -> Bool {
        data.restDayList.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    func toggleRestDay(_ date: Date = .now) {
        let cal = Calendar.current
        if isRestDay(date) {
            data.restDayList.removeAll { cal.isDate($0, inSameDayAs: date) }
        } else {
            data.restDayList.append(cal.startOfDay(for: date))
        }
        save()
    }

    func deleteEverything() {
        try? FileManager.default.removeItem(at: Self.folder)
        data = MTData()
        thumbnails = [:]
        cancelLimitAlert()
        cancelIntervalAlerts()
        cancelStaminaAlerts()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["gymforge.mt.measure"])
        save()
    }

    // MARK: Passcode-protected export / import

    /// Everything in this section (data + full-size photos) as JSON — encrypt before it leaves the app.
    /// Fails (instead of silently leaving things out) if any photo can't be read.
    func exportPayloadJSON() throws -> Data {
        try exportPayloadJSON(of: data)
    }

    /// For the automatic weekly backup: reads the encrypted data straight from disk without
    /// Face ID (the key never leaves this device). The result is encrypted again with your
    /// backup passcode before it's written anywhere.
    func exportPayloadJSONForAutoBackup() throws -> Data {
        if isUnlocked { return try exportPayloadJSON(of: data) }
        guard FileManager.default.fileExists(atPath: Self.dataURL.path) else { return try exportPayloadJSON(of: MTData()) }
        let stored = try JSONDecoder.gymForge.decode(MTData.self, from: try readEncrypted(Self.dataURL))
        return try exportPayloadJSON(of: stored)
    }

    private func exportPayloadJSON(of data: MTData) throws -> Data {
        var photos: [String: Data] = [:]
        var unreadable = 0
        for photo in data.photos {
            if let bytes = try? readEncrypted(photoURL(photo.id, thumb: false)) {
                photos[photo.id.uuidString] = bytes
            } else {
                unreadable += 1
            }
        }
        if unreadable > 0 { throw MTVaultError.photosUnreadable(unreadable) }
        return try JSONEncoder.gymForge.encode(MTExport(data: data, photos: photos))
    }

    /// What an export JSON contains, for the confirmation message.
    nonisolated static func summary(ofPayload json: Data) -> MTExportSummary? {
        guard let payload = try? JSONDecoder.gymForge.decode(MTExport.self, from: json) else { return nil }
        return MTExportSummary(sessions: payload.data.sessions.count,
                               measurements: payload.data.measurements.count,
                               photos: payload.photos.count,
                               stamina: payload.data.staminaList.count,
                               checkIns: payload.data.checkInList.count)
    }

    func exportData(passcode: String) throws -> Data {
        try Self.seal(try exportPayloadJSON(), passcode: passcode, magic: "GFMT1")
    }

    /// Merges an export into this vault (items already present are skipped).
    func importData(_ file: Data, passcode: String) throws -> Int {
        let json = try Self.open(file, passcode: passcode, magic: "GFMT1")
        return try importPayloadJSON(json)
    }

    /// Merges exported JSON. On an empty vault (fresh install) its settings are restored too.
    func importPayloadJSON(_ json: Data) throws -> Int {
        guard let payload = try? JSONDecoder.gymForge.decode(MTExport.self, from: json) else { throw MTVaultError.badFile }
        let wasEmpty = data.sessions.isEmpty && data.measurements.isEmpty && data.photos.isEmpty && data.staminaList.isEmpty

        var added = 0
        let sessionIDs = Set(data.sessions.map(\.id))
        for session in payload.data.sessions where !sessionIDs.contains(session.id) {
            data.sessions.append(session); added += 1
        }
        let measurementIDs = Set(data.measurements.map(\.id))
        for measurement in payload.data.measurements where !measurementIDs.contains(measurement.id) {
            data.measurements.append(measurement); added += 1
        }
        let photoIDs = Set(data.photos.map(\.id))
        for photo in payload.data.photos where !photoIDs.contains(photo.id) {
            guard let bytes = payload.photos[photo.id.uuidString], let image = UIImage(data: bytes) else { continue }
            let thumb = image.preparingThumbnail(of: CGSize(width: 360, height: 360 * image.size.height / max(image.size.width, 1)))?
                .jpegData(compressionQuality: 0.7) ?? bytes
            // Only list the photo if its files were really written (a missing file would block every later backup).
            do {
                try writeEncrypted(bytes, to: photoURL(photo.id, thumb: false))
                try writeEncrypted(thumb, to: photoURL(photo.id, thumb: true))
            } catch {
                continue
            }
            data.photos.append(photo); added += 1
        }
        // Folders: same ID or same name (e.g. the default "Pump" made on a fresh install) merge into one.
        var folderRemap: [UUID: UUID] = [:]
        for folder in payload.data.folderList {
            if data.folderList.contains(where: { $0.id == folder.id }) { continue }
            if let existing = data.folderList.first(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) {
                folderRemap[folder.id] = existing.id
            } else {
                data.folderList.append(folder)
            }
        }
        for index in data.photos.indices {
            if let old = data.photos[index].folderID, let new = folderRemap[old] { data.photos[index].folderID = new }
        }
        for day in payload.data.restDayList where !data.restDayList.contains(day) {
            data.restDayList.append(day)
        }
        let checkInDays = Set(data.checkInList.map(\.day))
        for checkIn in payload.data.checkInList where !checkInDays.contains(checkIn.day) {
            data.checkInList.append(checkIn); added += 1
        }
        let presetIDs = Set(data.presetList.map(\.id))
        for preset in payload.data.presetList where !presetIDs.contains(preset.id) {
            data.presetList.append(preset); added += 1
        }
        let staminaIDs = Set(data.staminaList.map(\.id))
        for session in payload.data.staminaList where !staminaIDs.contains(session.id) {
            data.staminaList.append(session); added += 1
        }
        if wasEmpty {
            data.settings = payload.data.settings
            if data.stretcherStartedAt == nil {
                data.stretcherStartedAt = payload.data.stretcherStartedAt
                data.stretcherLevel = payload.data.stretcherLevel
            }
        }
        data.staminaList.sort { $0.start < $1.start }
        data.checkInList.sort { $0.day < $1.day }
        data.sessions.sort { $0.start < $1.start }
        data.measurements.sort { $0.date < $1.date }
        data.photos.sort { $0.date < $1.date }
        save()
        loadThumbnails()
        rescheduleMeasureReminder()
        return added
    }

    // MARK: Passcode encryption (shared with the full backup)

    nonisolated static func seal(_ plain: Data, passcode: String, magic: String) throws -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let key = passcodeKey(passcode, salt: salt)
        guard let sealed = try AES.GCM.seal(plain, using: key).combined else { throw MTVaultError.badFile }
        return Data(magic.utf8) + salt + sealed
    }

    nonisolated static func open(_ file: Data, passcode: String, magic: String) throws -> Data {
        let header = Data(magic.utf8)
        guard file.count > header.count + 16, file.prefix(header.count) == header else { throw MTVaultError.badFile }
        let salt = file.subdata(in: header.count..<(header.count + 16))
        let sealed = file.subdata(in: (header.count + 16)..<file.count)
        let key = passcodeKey(passcode, salt: salt)
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key) else { throw MTVaultError.wrongPasscode }
        return plain
    }

    // MARK: Storage

    private static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(".mt", isDirectory: true)
    }

    private static var dataURL: URL { folder.appendingPathComponent("data.bin") }

    private func photoURL(_ id: UUID, thumb: Bool) -> URL {
        Self.folder.appendingPathComponent("p", isDirectory: true)
            .appendingPathComponent(id.uuidString + (thumb ? "-t" : "") + ".bin")
    }

    private func ensureFolders() throws {
        var folder = Self.folder
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("p", isDirectory: true), withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: Self.dataURL.path) else {
            data = MTData()
            return
        }
        data = try JSONDecoder.gymForge.decode(MTData.self, from: try readEncrypted(Self.dataURL))
    }

    /// MK20.7: a save that couldn't be written yet. The file and its key are only readable while the iPhone
    /// is unlocked, so a widget button pressed on the Lock Screen / StandBy changes the timer in memory
    /// first and is written the next time the app is opened.
    private var unsavedChanges = false

    private func save() {
        guard isUnlocked || workingLocked else { return }
        do {
            let bytes = try JSONEncoder.gymForge.encode(data)
            try writeEncrypted(bytes, to: Self.dataURL)
            unsavedChanges = false
        } catch {
            unsavedChanges = true
            print("More Training save failed: \(error)")
        }
        // Even when the write has to wait, the card, the widget and the reminders follow the timer.
        rescheduleTrainingReminder()
        MTLiveTimer.sync(data)
    }

    private func writeEncrypted(_ bytes: Data, to url: URL) throws {
        try ensureFolders()
        guard let sealed = try AES.GCM.seal(bytes, using: try Self.key()).combined else { throw MTVaultError.badFile }
        try sealed.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func readEncrypted(_ url: URL) throws -> Data {
        let sealed = try Data(contentsOf: url)
        return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: try Self.key())
    }

    // MARK: Keys

    private static let keychainService = "com.gymforge.mt"

    private static func key() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "key",
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let stored = result as? Data {
            return SymmetricKey(data: stored)
        }
        // Only make a new key if there truly is none (a locked/failed Keychain read must not replace it).
        guard status == errSecItemNotFound else { throw MTVaultError.keychain }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "key",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw MTVaultError.keychain }
        return newKey
    }

    /// PBKDF2-SHA256, 200k rounds.
    nonisolated private static func passcodeKey(_ passcode: String, salt: Data) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let passwordLength = passcode.utf8.count
        _ = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passcode, passwordLength,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000,
                &derived, derived.count
            )
        }
        return SymmetricKey(data: derived)
    }

    // MARK: Time-limit alert (discreet wording)

    private static let alertID = "gymforge.mt.limit"

    private func scheduleLimitAlert(after seconds: TimeInterval) async {
        _ = await ReminderScheduler.requestPermission()
        let content = MTVault.timerContent()
        let request = UNNotificationRequest(identifier: Self.alertID, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// "Reminder — Time to log your progress." every N weeks after the last measurement.
    func rescheduleMeasureReminder() {
        let id = "gymforge.mt.measure"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let weeks = data.settings.reminderWeeks
        guard weeks > 0 else { return }
        let calendar = Calendar.current
        let last = data.measurements.map(\.date).max() ?? .now
        var fire = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: last)) ?? .now
        fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: fire) ?? fire
        if fire <= .now, let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) {
            fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = "Time to log your progress."
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }

    private func cancelLimitAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.alertID])
    }
}

private struct MTExport: Codable {
    var data: MTData
    var photos: [String: Data]
}

/// File wrapper for the passcode-protected export.
struct MTExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var bytes: Data

    init(bytes: Data) { self.bytes = bytes }

    init(configuration: ReadConfiguration) throws {
        bytes = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

struct MTExportSummary {
    var sessions: Int
    var measurements: Int
    var photos: Int
    var stamina: Int
    var checkIns: Int

    var text: String {
        "\(sessions) PE sessions, \(measurements) measurements, \(photos) photos, \(stamina) stamina sessions, \(checkIns) check-ins"
    }
}


// MARK: - MK10.2: a quiet nudge after 3 days without training

/// A day counts as trained with 1 h+ of All Day Stretcher wear, more than 30 min of High Tension
/// Extender, or any PAC / pump session.
enum MTTrainingDays {
    static func trainedDays(_ data: MTData, calendar: Calendar = .current) -> Set<Date> {
        var adsMinutes: [Date: Double] = [:]
        var hteMinutes: [Date: Double] = [:]
        var days = Set<Date>()
        for session in data.sessions {
            let day = calendar.startOfDay(for: session.start)
            switch session.type {
            case .allDayStretcher: adsMinutes[day, default: 0] += session.duration / 60
            case .highTensionExtender: hteMinutes[day, default: 0] += session.duration / 60
            case .pac, .pump: days.insert(day)
            case .clamp: break
            }
        }
        for (day, minutes) in adsMinutes where minutes >= 60 { days.insert(day) }
        for (day, minutes) in hteMinutes where minutes > 30 { days.insert(day) }
        return days
    }

    static func lastTrainedDay(_ data: MTData, calendar: Calendar = .current) -> Date? {
        trainedDays(data, calendar: calendar).max()
    }
}

extension MTVault {
    static let trainingReminderIDs = ["gymforge.mt.train.1", "gymforge.mt.train.2"]

    /// "⏱" at 7:30pm on day 3 without training, once more on day 6, then nothing. Silent on rest days
    /// you marked, while wearing the stretcher, and when the safety check says rest.
    func rescheduleTrainingReminder(now: Date = .now) {
        rescheduleDailyReminder(now: now)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.trainingReminderIDs)
        guard isUnlocked || workingLocked, data.settings.trainingNudgeOn, data.stretcherStartedAt == nil, !data.isBusy,
              !MTSafety.advice(data, now: now).contains(where: { $0.level == .rest }) else { return }
        let calendar = Calendar.current
        guard let last = MTTrainingDays.lastTrainedDay(data, calendar: calendar) else { return }
        let rest = Set(data.restDayList.map { calendar.startOfDay(for: $0) })

        for (index, offset) in [3, 6].enumerated() {
            guard var day = calendar.date(byAdding: .day, value: offset, to: last) else { continue }
            var pushed = 0
            while rest.contains(day), pushed < 7, let next = calendar.date(byAdding: .day, value: 1, to: day) {
                day = next
                pushed += 1
            }
            guard let fire = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: day), fire > now else { continue }
            let content = UNMutableNotificationContent()
            content.body = "⏱"
            content.interruptionLevel = .passive   // no sound, no lighting up the screen
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: Self.trainingReminderIDs[index], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    static let dailyReminderIDs = (0..<7).map { "gymforge.mt.daily.\($0)" }

    /// MK19: "Time to train" at 8:45pm on days with no More Training logged. Time Sensitive, so it gets through Focus.
    func rescheduleDailyReminder(now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.dailyReminderIDs)
        guard isUnlocked || workingLocked else { return }
        let calendar = Calendar.current
        for (index, fire) in MTPlan.reminderDates(data, now: now, calendar: calendar).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time to train"
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: Self.dailyReminderIDs[index], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
}
