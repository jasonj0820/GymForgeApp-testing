import Foundation
import Combine
import SwiftUI
import WidgetKit
import UserNotifications

@MainActor
final class PhoneAppStore: ObservableObject {
    @Published var routines: [WorkoutRoutine] = []
    @Published var workoutLogs: [WorkoutLog] = [] {
        didSet { refreshCluck() }
    }
    @Published var weeklyGoal: Int = 5
    @Published var profile = UserProfile()
    @Published var activeWorkout: ActiveWorkoutState? {
        didSet {
            activeWorkoutChanged(from: oldValue)
            // Starting (or ending) a workout calms Sergeant Cluck down.
            if (oldValue == nil) != (activeWorkout == nil) { refreshCluck() }
        }
    }
    /// Live workout screen is open (full screen). Starting a workout opens it straight away.
    @Published var showWorkout = false
    /// Finished-workout summary sheet.
    @Published var summaryLog: WorkoutLog?
    /// Banner shown on the workout screen when a set is a PR.
    @Published var prBanner: PRHit?
    /// The green tick that pops up when a set is logged (on iPhone or Watch).
    @Published var setTick: SetTick?
    /// Weekly review sheet (Sunday night notification, or the Today card).
    @Published var showWeeklyReview = false
    /// Runs and basketball (details; each also has a workout log so it counts for the week).
    @Published var cardioSessions: [CardioSession] = []
    /// Live numbers from the Watch during a run / basketball session.
    @Published var liveCardio: ActivityProgress?
    /// Shown after a run / basketball session arrives from the Watch.
    @Published var cardioSummary: CardioSession?
    /// Set when data was restored from iCloud on a fresh install.
    @Published var restoredBackupDate: Date?
    /// Day this week's "Not today" snooze was used.
    @Published var cluckSnoozedDay: Date? = CluckStore.load()?.snoozedDay
    /// Rest days, pain flags, nutrition, tape measurements.
    @Published var extras = GymExtras()

    let healthKit = HealthKitClient()
    let watchBridge = PhoneWatchBridge()
    /// Dayfold (routines + before-bed checklist), merged into GymForge in MK12.
    private(set) var dayfold: DayfoldStore?

    /// One instance for the app and the background Shortcuts action, with Dayfold wired in.
    static let shared: PhoneAppStore = {
        let store = PhoneAppStore()
        let dayfold = DayfoldStore()
        store.dayfold = dayfold
        dayfold.gymTomorrow = { [weak store] in store?.gymSessionTomorrow() }
        dayfold.onChange = { [weak store] in store?.dayfoldChanged() }
        dayfold.isRestDay = { [weak store] in store?.isRestDay() ?? false }
        dayfold.mealPrepTitle = { [weak store] in MealPrep.title(target: store?.proteinTargetG) }
        return store
    }()
    let cloud = CloudBackup()
    let liveActivity = LiveActivityManager()
    /// MK10: runs / basketball recorded on the iPhone (no Watch).
    let phoneRecorder = PhoneActivityRecorder()
    /// When the Watch last sent run / basketball numbers (the card is cleared if they stop coming).
    var lastCardioProgressAt: Date?
    var cardioStaleTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var seenPRs = Set<UUID>()
    private var bannerTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var restBuzzTask: Task<Void, Never>?
    private var restBuzzEnd: Date?
    private var hadLocalData = false
    /// Workouts cancelled or ended with nothing logged: late updates for them are ignored.
    private var endedWorkoutIDs = Set<UUID>()
    /// On a fresh install, don't back up (and overwrite iCloud) until we've checked for a backup to restore.
    private var backupReady = false

    init() {
        load()
        healthKit.setManual(extras.weighIns)
        ensurePhaseRecord()
        migrateAssistedPullUps()
        backupReady = hadLocalData
        if routines.isEmpty {
            routines = SeedData.starterRoutines
            save()
        }

        // Nested ObservableObjects: forward their changes so views refresh.
        watchBridge.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        healthKit.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        cloud.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        watchBridge.onCompletedWorkout = { [weak self] log in
            Task { @MainActor in self?.receiveCompletedWorkout(log) }
        }
        watchBridge.onActiveWorkoutUpdate = { [weak self] state in
            Task { @MainActor in self?.receiveActiveState(state) }
        }
        watchBridge.onCancelWorkout = { [weak self] id in
            Task { @MainActor in self?.receiveCancel(id) }
        }
        watchBridge.onNeedsSnapshot = { [weak self] in
            Task { @MainActor in self?.pushSnapshotToWatch() }
        }
        watchBridge.onNeedsActiveWorkout = { [weak self] in
            Task { @MainActor in self?.resendActiveWorkout() }
        }
        watchBridge.onActivityProgress = { [weak self] progress in
            Task { @MainActor in self?.receiveActivityProgress(progress) }
        }
        watchBridge.onCompletedActivity = { [weak self] session in
            Task { @MainActor in self?.receiveCompletedActivity(session) }
        }
        phoneRecorder.onProgress = { [weak self] progress in
            self?.receiveActivityProgress(progress)
        }
        phoneRecorder.recoverCheckpoint()
        watchBridge.activate()
        PhoneWatchBridge.current = watchBridge
        NotificationCenter.default.publisher(for: .cluckChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.cluckSnoozedDay = CluckStore.load()?.snoozedDay
                self.refreshCluck()
            }
            .store(in: &cancellables)
        refreshCluck()

        if !hadLocalData {
            Task {
                await restoreFromCloudIfFreshInstall()
                backupReady = true
            }
        }
        restoreActiveWorkout()
    }

    // MARK: Derived data

    var snapshot: AppSnapshot {
        var snapshot = AppSnapshot(routines: routines, workoutLogs: workoutLogs, weeklyGoal: weeklyGoal, profile: profile, extras: extras)
        snapshot.cardioSessions = cardioSessions
        return snapshot
    }

    var consistency: ConsistencyStats {
        var stats = ConsistencyCalculator.stats(logs: workoutLogs, weeklyGoal: weeklyGoal, breaks: extras.breaks.map(\.interval))
        // Sick / travel days take sessions off this week's goal.
        stats.weeklyGoal = thisWeekGoal
        return stats
    }

    var readiness: Readiness? {
        ReadinessEngine.evaluate(
            sleep: healthKit.sleep,
            restingHR: healthKit.restingHeartRate,
            hrv: healthKit.heartRateVariability
        )
    }

    var coachInsights: [CoachInsight] {
        CoachEngine.insights(CoachContext(
            profile: profile,
            weeklyGoal: weeklyGoal,
            routines: routines,
            logs: workoutLogs,
            bodyWeight: healthKit.bodyWeight,
            bodyFat: healthKit.bodyFat,
            readiness: readiness,
            consistency: consistency   // MK17: breaks and sick / travel days, same as Today
        ))
    }

    var categoryLookup: [String: ExerciseCategory] { MuscleVolume.lookup(from: routines) }

    /// Exercises across all routines, de-duplicated by name (they share history).
    var uniqueExercises: [ExerciseDefinition] {
        var seen = Set<String>()
        return routines.flatMap(\.exercises).map(\.exercise).filter { seen.insert($0.historyKey).inserted }
    }

    /// Routine exercises, their preset swaps, and anything else ever logged (e.g. imported from Strong).
    var progressExercises: [ExerciseDefinition] {
        var seen = Set<String>()
        var result = routines.flatMap(\.allExercises).filter { seen.insert($0.historyKey).inserted }
        for log in workoutLogs.loggedExercises() where seen.insert(ExerciseLog.key(for: log.exerciseName)).inserted {
            result.append(ExerciseDefinition(
                id: log.exerciseID,
                name: log.exerciseName,
                category: log.resolvedCategory,
                repMin: log.repMinAtTime,
                repMax: log.repMaxAtTime,
                weightIncrementKg: log.weightIncrementKgAtTime
            ))
        }
        return result
    }

    var sortedLogs: [WorkoutLog] { workoutLogs.sorted { $0.startedAt > $1.startedAt } }

    /// The routine you've gone longest without doing.
    var suggestedRoutine: WorkoutRoutine? {
        // Today's planned workout first, otherwise the one you've gone longest without.
        // MK20: the fixed split's session for today (with its extra sets / swaps) comes first.
        splitRoutineToday ?? plannedRoutineToday ?? routines.filter { !$0.exercises.isEmpty }.min { lastDone($0) < lastDone($1) }
    }

    func lastDone(_ routine: WorkoutRoutine) -> Date {
        workoutLogs.filter { $0.routineID == routine.id }.map(\.startedAt).max() ?? .distantPast
    }

    func previousLog(for exercise: ExerciseDefinition, before date: Date? = nil) -> ExerciseLog? {
        workoutLogs.previousLog(for: exercise, before: date)
    }

    func history(for exercise: ExerciseDefinition) -> [ExerciseHistoryPoint] {
        workoutLogs.history(for: exercise)
    }

    func monthlyReport(for month: Date) -> MonthlyReport {
        MonthlyReportBuilder.build(
            month: month,
            logs: workoutLogs,
            weeklyGoal: weeklyGoal,
            style: profile.coachStyle,
            bodyWeight: healthKit.bodyWeight,
            bodyFat: healthKit.bodyFat,
            sleep: healthKit.sleep,
            categoryLookup: categoryLookup
        )
    }

    // MARK: App lifecycle

    func requestHealthAccess() async {
        await healthKit.requestAuthorization()
    }

    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    private var lastNotificationStatus: UNAuthorizationStatus?

    /// Asks for notification permission if needed, and re-plans everything whenever permission
    /// changes (notifications planned before permission is granted are silently dropped by iOS).
    func ensureNotifications() async {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined && (profile.cluckEnabled || profile.reminders) {
            _ = await ReminderScheduler.requestPermission()
            status = await center.notificationSettings().authorizationStatus
        }
        notificationStatus = status
        if status != lastNotificationStatus {
            lastNotificationStatus = status
            CluckNotifier.registerCategory()
        }
    }

    func appBecameActive() async {
        // Recreates the workout Live Activity if it couldn't start in the background or was swiped away.
        liveActivity.sync(activeWorkout, style: profile.coachStyle)
        clearStaleCardio()
        await ensureNotifications()
        await healthKit.refreshBodyMetrics()
        await healthKit.refreshRecovery()
        checkBodyAlerts()
        ProteinNotifier.reschedule(store: self)   // target follows your latest weight
        QuoteNotifier.reschedule()
        refreshSleep()
        rescheduleReminders()
        AutoBackup.runIfDue(store: self)
    }

    // MARK: Routines

    func addRoutine(named name: String) {
        routines.append(WorkoutRoutine(name: name, exercises: []))
        persistAndSync()
    }

    func duplicateRoutine(_ routine: WorkoutRoutine) {
        // Fresh IDs, so editing the copy (e.g. renaming an exercise) never mixes up the original's history.
        // History is still shared by exercise name, as everywhere else.
        func fresh(_ exercise: ExerciseDefinition) -> ExerciseDefinition {
            var copy = exercise
            copy.id = UUID()
            copy.alternatives = exercise.alternatives?.map { alternative in
                var newAlternative = alternative
                newAlternative.id = UUID()
                return newAlternative
            }
            return copy
        }
        let copy = WorkoutRoutine(name: routine.name + " Copy", exercises: routine.exercises.map {
            RoutineExercise(exercise: fresh($0.exercise), order: $0.order, supersetWithNext: $0.supersetWithNext)
        })
        routines.append(copy)
        persistAndSync()
    }

    func deleteRoutines(at offsets: IndexSet) {
        routines.remove(atOffsets: offsets)
        persistAndSync()
    }

    func moveRoutines(from source: IndexSet, to destination: Int) {
        routines.move(fromOffsets: source, toOffset: destination)
        persistAndSync()
    }

    func updateRoutine(_ routine: WorkoutRoutine) {
        guard let idx = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[idx] = routine
        persistAndSync()
    }

    func deleteWorkout(_ log: WorkoutLog) {
        // Later sets may become PRs once this session is gone.
        workoutLogs = workoutLogs.filter { $0.id != log.id }.recomputingPRs()
        persistAndSync()
        rescheduleReminders()
    }

    /// Updates an exercise's notes everywhere it appears (including as a preset swap) and in the live workout.
    func updateNote(exerciseID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : trimmed
        for r in routines.indices {
            for e in routines[r].exercises.indices {
                if routines[r].exercises[e].exercise.id == exerciseID {
                    routines[r].exercises[e].exercise.notes = value
                }
                if var alternatives = routines[r].exercises[e].exercise.alternatives {
                    for a in alternatives.indices where alternatives[a].id == exerciseID {
                        alternatives[a].notes = value
                    }
                    routines[r].exercises[e].exercise.alternatives = alternatives
                }
            }
        }
        if var state = activeWorkout {
            state.updateNotes(exerciseID: exerciseID, notes: value)
            activeWorkout = state
            watchBridge.sendActiveState(state, reliable: false)
        }
        persistAndSync()
    }

    // MARK: Settings & coaching

    func setWeeklyGoal(_ value: Int) {
        weeklyGoal = min(max(value, 1), 7)
        persistAndSync()
        rescheduleReminders()
    }

    /// MK11.1: running and basketball goals (lifting stays `weeklyGoal`).
    func setTrainingGoals(_ goals: TrainingGoals) {
        var updated = profile
        updated.trainingGoals = goals == TrainingGoals() ? nil : goals
        guard updated != profile else { return }
        setProfile(updated)
    }

    func setProfile(_ value: UserProfile) {
        profile = value
        persistAndSync()
        rescheduleReminders()
    }

    func startDeloadWeek() {
        var updated = profile
        updated.deloadUntil = Calendar.current.date(byAdding: .day, value: 7, to: .now)
        setProfile(updated)
    }

    func endDeload() {
        var updated = profile
        updated.deloadUntil = nil
        setProfile(updated)
    }

    func perform(_ action: CoachAction) {
        switch action {
        case .startDeloadWeek: startDeloadWeek()
        case .endDeload: endDeload()
        case .openMonthlyReport: break
        }
    }

    func setReminders(enabled: Bool) async {
        var updated = profile
        if enabled {
            updated.reminders = await ReminderScheduler.requestPermission()
        } else {
            updated.reminders = false
        }
        setProfile(updated)
    }

    func rescheduleReminders() {
        // MK11.3: no "you're behind" reminders on a full break.
        var reminderProfile = profile
        if activeBreak?.mode == .full { reminderProfile.reminders = false }
        ReminderScheduler.reschedule(profile: reminderProfile, logs: workoutLogs.filter(\.countsAsTraining), weeklyGoal: max(thisWeekGoal, 1))
        WeighInReminder.reschedule(weighIns: extras.weighIns)
        refreshCluck()
    }

    // MARK: Sergeant Cluck

    /// Everything the widget and the nags need. An in-progress workout counts as trained today.
    var cluckSnapshot: CluckSnapshot {
        let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: .now) ?? .distantPast
        // MK10.2: only weight training calms him down (a run or a game doesn't count).
        var dates = workoutLogs.filter(\.countsAsTraining).map(\.startedAt).filter { $0 >= cutoff }
        if let active = activeWorkout, active.routine.exercises.contains(where: { !$0.exercise.isCardio }) { dates.append(active.startedAt) }
        // MK11: streak, worry signals, gym pattern and sleep for his new moods.
        let stats = ConsistencyCalculator.stats(logs: workoutLogs, weeklyGoal: weeklyGoal, breaks: extras.breaks.map(\.interval))
        let streak = stats.streakWeeks - (stats.thisWeekCount >= stats.weeklyGoal ? 1 : 0)
        let report = sleepReport
        let painRecent = extras.painFlags.contains { !$0.resolved && $0.date > Date().addingTimeInterval(-14 * 86_400) }
        // MK11.1: late nights only come up at bedtime (Lights out mood) — during the day he talks gym.
        let worried = readiness?.level == .low
        // MK11.3: no "inconsistent training" comments about a break you took in the last 4 weeks.
        let recentBreak = extras.breaks.contains { $0.finish > Date().addingTimeInterval(-28 * 86_400) }
        let pattern: (line: String?, skipWeekday: Int?) = recentBreak ? (nil, nil)
            : CluckPatterns.gym(logs: workoutLogs, plans: extras.dayPlans, weeklyGoal: weeklyGoal)
        // MK11.3: a break week has the break's goal (2, or 0 on a full break).
        let cluckGoal = GymBreakRules.breakInWeek(of: .now, breaks: extras.breaks)?.weekGoal(normal: weeklyGoal) ?? weeklyGoal
        var snapshot = CluckSnapshot(goal: cluckGoal, workoutDates: dates, snoozedDay: cluckSnoozedDay,
                             coachStyle: profile.coachStyle.rawValue, enabled: profile.cluckEnabled,
                             updatedAt: .now, restDays: extras.restDays.filter { $0 >= cutoff },
                             excusedDays: extras.dayPlans.filter { $0.kind.isExcused && $0.day >= cutoff }.map(\.day),
                             plannedRestDays: extras.plannedRestDays.filter { $0 >= cutoff && extras.isRestDay($0) })
        snapshot.streakWeeks = max(streak, 0)
        snapshot.worried = worried
        // MK11.1: Locked In mid-workout, Protective with a pain flag, Empathetic after a run-down session.
        snapshot.inWorkout = activeWorkout != nil
        snapshot.breakUntil = activeBreak?.finish
        snapshot.pain = painRecent
        snapshot.toughDay = workoutLogs.contains { Calendar.current.isDateInToday($0.startedAt) && $0.tagSet.contains(.unusualFatigue) }
        snapshot.skipWeekday = pattern.skipWeekday
        snapshot.patternLine = pattern.line
        snapshot.bedtimes = profile.sleepSchedule?.bedtime
        snapshot.lateNights = profile.sleepSchedule == nil ? nil : report.lateNights7
        return snapshot
    }

    func refreshCluck() {
        let snapshot = cluckSnapshot
        CluckStore.save(snapshot)
        CluckNotifier.reschedule(snapshot)
        scheduleRecap()
        WidgetCenter.shared.reloadTimelines(ofKind: CluckStore.widgetKind)
        watchBridge.sendCluck(snapshot)
        CluckActivityManager.sync(snapshot, workoutActive: activeWorkout != nil)
    }

    /// This week so far, for the Sunday recap.
    private func scheduleRecap(now: Date = .now) {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return }
        let thisWeek = workoutLogs.filter { $0.startedAt >= week.start && $0.startedAt < week.end && $0.countsAsTraining }
        let earlier = workoutLogs.filter { $0.startedAt < week.start }
        let prs = thisWeek.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.filter { $0.isPR == true }.count } }
        var liftsUp = Set<String>()
        for log in thisWeek {
            for exercise in log.exercises where !exercise.isCardio {
                let key = ExerciseLog.key(for: exercise.exerciseName)
                let before = earlier.flatMap(\.exercises).filter { ExerciseLog.key(for: $0.exerciseName) == key }
                    .map(\.bestWeightKg).max() ?? 0
                if before > 0 && exercise.bestWeightKg > before + 0.001 { liftsUp.insert(key) }
            }
        }
        let rest = extras.restDays.filter { $0 >= week.start && $0 < week.end }.count
        let wins = phaseCoach.weeklyWins
        CluckNotifier.scheduleReviewReminder(standalone: !profile.cluckEnabled)
        CluckNotifier.scheduleRecap(enabled: profile.cluckEnabled, sessions: thisWeek.count, goal: max(thisWeekGoal, 1),
                                    prs: prs, liftsUp: liftsUp.count, restDays: rest, style: profile.coachStyle.rawValue,
                                    strongerLifts: wins.liftsUp, leanChange: wins.leanUp, phase: nutritionPhase.rawValue)
    }

    // MARK: Rest days, pain flags, nutrition, tape

    func saveExtras() {
        persistAndSync()
        refreshCluck()
    }

    func isRestDay(_ date: Date) -> Bool { extras.isRestDay(date) }

    func toggleRestDay(_ date: Date = .now) {
        let cal = Calendar.current
        if extras.isRestDay(date) {
            extras.restDays.removeAll { cal.isDate($0, inSameDayAs: date) }
            extras.plannedRestDays.removeAll { cal.isDate($0, inSameDayAs: date) }
        } else {
            let day = cal.startOfDay(for: date)
            extras.restDays.append(day)
            if day > cal.startOfDay(for: .now) { extras.plannedRestDays.append(day) }
        }
        saveExtras()
    }

    func addPainFlag(_ flag: PainFlag) {
        extras.painFlags.append(flag)
        saveExtras()
    }

    func resolvePainFlags(for exercise: ExerciseDefinition) {
        for index in extras.painFlags.indices where extras.painFlags[index].exerciseKey == exercise.historyKey {
            extras.painFlags[index].resolved = true
        }
        saveExtras()
    }

    func resolvePainFlag(_ id: UUID) {
        if let index = extras.painFlags.firstIndex(where: { $0.id == id }) {
            extras.painFlags[index].resolved = true
            saveExtras()
        }
    }

    var nutritionPhase: NutritionPhase {
        extras.nutritionPhase ?? NutritionPhase.from(goal: profile.goal)
    }

    func setNutritionPhase(_ phase: NutritionPhase) {
        setPhase(phase)
    }

    /// One-time: assisted pull-ups / chin-ups use 6–10 reps (the weight is assistance, so less = harder).
    private func migrateAssistedPullUps() {
        let key = "migration.assistedPull610"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        func fix(_ exercise: inout ExerciseDefinition) -> Bool {
            let name = exercise.name.lowercased()
            guard exercise.isAssisted, name.contains("pull") || name.contains("chin") else { return false }
            exercise.repMin = 6
            exercise.repMax = 10
            return true
        }
        var changed = false
        for r in routines.indices {
            for e in routines[r].exercises.indices {
                if fix(&routines[r].exercises[e].exercise) { changed = true }
                var alternatives = routines[r].exercises[e].exercise.alternativeList
                for a in alternatives.indices where fix(&alternatives[a]) { changed = true }
                routines[r].exercises[e].exercise.alternativeList = alternatives
            }
        }
        if changed { persistAndSync() }
    }

    // MARK: Phase (bulk / recomp / cut)

    var currentPhaseRecord: PhaseRecord? { extras.currentPhaseRecord }

    /// Older data has no phase history: start one from today.
    private func ensurePhaseRecord() {
        guard extras.currentPhaseRecord == nil else { return }
        extras.phases.append(PhaseRecord(phase: nutritionPhase, start: Calendar.current.startOfDay(for: .now)))
    }

    /// One setting drives the nutrition target, the coach's goal and the phase reports.
    func setPhase(_ phase: NutritionPhase, start: Date = .now, miniCut: Bool = false) {
        let now = Date()
        if let index = extras.phases.lastIndex(where: { $0.end == nil }) {
            if extras.phases[index].phase == phase && !miniCut && !extras.phases[index].isMiniCut { return }
            extras.phases[index].end = now
        }
        extras.phases.append(PhaseRecord(phase: phase, start: Calendar.current.startOfDay(for: start), isMiniCut: miniCut,
                                         plannedEnd: miniCut ? Calendar.current.date(byAdding: .weekOfYear, value: 5, to: now) : nil))
        extras.nutritionPhase = phase
        var updated = profile
        updated.goal = phase.trainingGoal
        profile = updated
        persistAndSync()
        rescheduleReminders()
    }

    func setPhaseStart(_ date: Date) {
        guard let index = extras.phases.lastIndex(where: { $0.end == nil }) else { return }
        extras.phases[index].start = Calendar.current.startOfDay(for: date)
        persistAndSync()
    }

    func startMiniCut() { setPhase(.cutting, miniCut: true) }
    func endMiniCut() { setPhase(.bulking) }

    var miniCutThreshold: Double { extras.miniCutThreshold ?? 20 }

    func setMiniCutThreshold(_ value: Double) {
        extras.miniCutThreshold = value
        persistAndSync()
    }

    var phaseCoach: PhaseCoach {
        PhaseCoach(phase: nutritionPhase, phaseRecord: currentPhaseRecord, logs: workoutLogs, routines: routines,
                   weights: healthKit.bodyWeight, fats: healthKit.bodyFat, sleep: healthKit.sleep,
                   nutrition: extras.nutrition, proteinTarget: proteinTargetG, weeklyGoal: weeklyGoal,
                   deloadUntil: profile.deloadUntil, miniCutThreshold: miniCutThreshold)
    }

    var latestBodyWeightKg: Double? {
        healthKit.bodyWeight.max(by: { $0.date < $1.date })?.value
    }

    /// Grams of protein per day for your phase and latest body weight.
    var proteinTargetG: Double? {
        latestBodyWeightKg.map { ($0 * nutritionPhase.gramsPerKg).rounded() }
    }

    func nutritionToday(_ date: Date = .now) -> NutritionDay {
        extras.nutrition(on: date) ?? NutritionDay(day: Calendar.current.startOfDay(for: date))
    }

    private func updateNutrition(_ date: Date = .now, _ change: (inout NutritionDay) -> Void) {
        let cal = Calendar.current
        var day = nutritionToday(date)
        change(&day)
        extras.nutrition.removeAll { cal.isDate($0.day, inSameDayAs: date) }
        extras.nutrition.append(day)
        // Keep a year of daily ticks.
        if let cutoff = cal.date(byAdding: .day, value: -400, to: date) {
            extras.nutrition.removeAll { $0.day < cutoff }
        }
        persistAndSync()
        ProteinNotifier.reschedule(store: self)
    }

    func toggleCreatine() { updateNutrition { $0.creatine.toggle() } }
    func addProtein(_ grams: Double) { updateNutrition { $0.proteinG = max(0, $0.proteinG + grams) } }
    func setProtein(_ grams: Double) { updateNutrition { $0.proteinG = max(0, grams) } }
    func addCalories(_ kcal: Double) { updateNutrition { $0.calories = max(0, ($0.calories ?? 0) + kcal) } }
    func setCalories(_ kcal: Double?) { updateNutrition { $0.calories = kcal.map { max(0, $0) } } }

    /// MK10.2: calorie target, maintenance and the bulk fat-gain check.
    var calorieCoach: CalorieCoach {
        let coach = phaseCoach
        return CalorieCoach(phase: nutritionPhase, isMiniCut: currentPhaseRecord?.isMiniCut == true,
                            weights: healthKit.bodyWeight, fats: healthKit.bodyFat, nutrition: extras.nutrition,
                            logs: workoutLogs, cardio: cardioSessions, proteinTarget: proteinTargetG,
                            strengthChange: coach.strengthChange, miniCutThreshold: miniCutThreshold)
    }

    /// Mini-cut time / bulk adding mostly fat: a notification (at most once every 2 weeks each).
    func checkBodyAlerts() {
        let defaults = UserDefaults.standard
        func notify(_ key: String, title: String, body: String) {
            if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 14 * 86_400 { return }
            defaults.set(Date(), forKey: key)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content,
                                                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
        }
        if let prompt = phaseCoach.miniCutPrompt {
            notify("gymforge.body.minicut", title: prompt.title, body: prompt.message)
        } else if let check = calorieCoach.fatGainCheck, check.level == .act {
            notify("gymforge.body.fatgain", title: check.title,
                   body: String(format: "About %.0f%% of your last %.1f kg was fat. ", check.fatShare * 100, check.weightGain)
                       + (check.advice.first ?? ""))
        }
    }

    // MARK: Sunday weigh-in (MK20.2)

    /// Saves a typed-in weigh-in. One per day: a second one the same day replaces the first.
    func saveWeighIn(_ entry: WeighIn) {
        extras.weighIns.removeAll { $0.id == entry.id || Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
        extras.weighIns.append(entry)
        extras.weighIns.sort { $0.date < $1.date }
        weighInsChanged()
    }

    func deleteWeighIn(_ id: UUID) {
        extras.weighIns.removeAll { $0.id == id }
        weighInsChanged()
    }

    /// This Sunday's weigh-in (or the last Sunday's, Monday to Saturday), if logged.
    var thisWeeksWeighIn: WeighIn? {
        let sunday = WeighIn.sunday(onOrBefore: .now)
        return extras.weighIns.last { $0.date >= sunday }
    }

    private func weighInsChanged() {
        healthKit.setManual(extras.weighIns)
        persistAndSync()
        WeighInReminder.reschedule(weighIns: extras.weighIns)
        checkBodyAlerts()
        ProteinNotifier.reschedule(store: self)   // target follows your latest weight
        dayfold?.autoTickWeighIn(weightDates: healthKit.bodyWeight.map(\.date))
    }

    func addTape(_ entry: TapeEntry) {
        extras.tape.append(entry)
        extras.tape.sort { $0.date < $1.date }
        persistAndSync()
    }

    func deleteTape(_ id: UUID) {
        extras.tape.removeAll { $0.id == id }
        persistAndSync()
    }

    /// "Not today" from the Today card. Returns false if this week's snooze is already used.
    @discardableResult
    func snoozeCluckToday() -> Bool {
        CluckStore.save(cluckSnapshot)
        let used = CluckStore.snoozeToday()
        cluckSnoozedDay = CluckStore.load()?.snoozedDay
        refreshCluck()
        return used
    }

    // MARK: Import & backup

    func importWorkouts(_ logs: [WorkoutLog]) {
        workoutLogs.append(contentsOf: logs)
        workoutLogs.sort { $0.startedAt < $1.startedAt }
        persistAndSync()
    }

    func restore(_ snapshot: AppSnapshot) {
        routines = snapshot.routines
        workoutLogs = snapshot.workoutLogs
        weeklyGoal = snapshot.weeklyGoal
        profile = snapshot.profile ?? UserProfile()
        extras = snapshot.extras ?? GymExtras()
        healthKit.setManual(extras.weighIns)
        cardioSessions = snapshot.cardioSessions ?? []
        ensurePhaseRecord()
        save()
        pushSnapshotToWatch()
        rescheduleReminders()
    }

    func backupNow() async {
        backupReady = true
        await cloud.backupNow(snapshot)
    }

    private func restoreFromCloudIfFreshInstall() async {
        guard cloud.isEnabled, cloud.isSignedIn, workoutLogs.isEmpty else { return }
        guard let backup = try? await cloud.fetchLatest(), !backup.snapshot.workoutLogs.isEmpty else { return }
        // The fetch can take a while: don't overwrite a workout logged in the meantime.
        guard workoutLogs.isEmpty, activeWorkout == nil else { return }
        restore(backup.snapshot)
        restoredBackupDate = backup.date
    }

    // MARK: Live workout (shared with the Watch)

    func startWorkout(_ routine: WorkoutRoutine, light: Bool = false, budgetMinutes: Int? = nil) async {
        guard !routine.exercises.isEmpty, activeWorkout == nil else {
            showWorkout = activeWorkout != nil
            return
        }
        var state = ActiveWorkoutState.start(routine: routine, profile: profile, light: light)
        if let budgetMinutes {
            // Short on time: trim sets from the least important exercises first, then skip whole ones.
            state = TimeBudget.fit(state, minutes: budgetMinutes, priority: budgetPriority(for: state)).state
            state.sessionTags = [.limitedTime]   // MK11.1: so a trimmed session isn't read as a weaker one
        }
        if activeBreak != nil, state.sessionTags == nil {
            state.sessionTags = [.limitedTime]   // MK11.3: break sessions stay out of trends
        }
        activeWorkout = state
        showWorkout = true
        pushSnapshotToWatch()
        watchBridge.sendStartWorkout(state)
        await healthKit.launchWatchStrengthWorkout()
        _ = await ReminderScheduler.requestPermission()
    }

    func prefill(for item: RoutineExercise) -> (weightKg: Double, reps: Int) {
        guard let state = activeWorkout else { return (0, item.exercise.repMin) }
        return state.prefill(for: item, logs: workoutLogs)
    }

    /// Today's per-set plan for an exercise in the workout in progress.
    func setPlan(for item: RoutineExercise) -> SetPlan {
        activeWorkout?.setPlan(for: item, logs: workoutLogs) ?? SetPlan(targets: [], reason: "")
    }

    func cardioPrefill(for item: RoutineExercise) -> (minutes: Double, km: Double?) {
        guard let state = activeWorkout else { return (Double(item.exercise.cardioMinutes), nil) }
        return state.cardioPrefill(for: item, logs: workoutLogs)
    }

    func completeSetOnPhone(weightKg: Double, reps: Int, durationSeconds: Double? = nil, distanceKm: Double? = nil, rir: Int? = nil) {
        guard var state = activeWorkout, let item = state.currentItem else { return }
        let target = state.prefill(for: item, logs: workoutLogs)
        let isCardio = item.exercise.isCardio
        _ = state.completeSet(
            weightKg: weightKg,
            reps: reps,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm,
            rir: isCardio ? nil : rir,
            targetWeightKg: isCardio ? nil : target.weightKg,
            targetReps: isCardio ? nil : target.reps,
            history: workoutLogs
        )
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// Mirrors what you're typing to the Watch so its Rest button can log it.
    func sendDraft(weightKg: Double?, reps: Int?, durationSeconds: Double? = nil, distanceKm: Double? = nil) {
        guard let state = activeWorkout, let item = state.currentItem else { return }
        watchBridge.sendDraft(WorkoutDraft(
            workoutID: state.workoutID,
            exerciseID: item.exercise.id,
            setNumber: state.sets(for: item).count + 1,
            weightKg: weightKg,
            reps: reps,
            durationSeconds: durationSeconds,
            distanceKm: distanceKm
        ))
    }

    func jumpToExercise(_ index: Int) {
        guard var state = activeWorkout else { return }
        state.jump(toExercise: index)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: false)
    }

    func skipExercise(at index: Int) {
        guard var state = activeWorkout else { return }
        state.skipExercise(at: index)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    func addExtraSet(toExercise index: Int) {
        guard var state = activeWorkout else { return }
        state.addExtraSet(to: index)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    func swapExercise(at index: Int, to replacement: ExerciseDefinition) {
        guard var state = activeWorkout else { return }
        state.swapExercise(at: index, to: replacement)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// Fixes a set you already logged (any exercise in this workout).
    func editSet(id: UUID, weightKg: Double, reps: Int, durationSeconds: Double? = nil, distanceKm: Double? = nil, rir: Int?) {
        guard var state = activeWorkout else { return }
        state.editSet(id: id, weightKg: weightKg, reps: reps, durationSeconds: durationSeconds,
                      distanceKm: distanceKm, rir: rir, history: workoutLogs)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    func deleteSet(id: UUID) {
        guard var state = activeWorkout else { return }
        state.deleteSet(id: id, history: workoutLogs)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// More or fewer sets planned for an exercise today.
    /// MK11.1: session context on the workout in progress.
    func toggleSessionTag(_ tag: SessionTag) {
        guard var state = activeWorkout else { return }
        state.toggleTag(tag)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// MK11.1: session context on a saved workout (re-runs the coaching that depends on it).
    func toggleSessionTag(_ tag: SessionTag, on log: WorkoutLog) {
        guard var copy = workoutLogs.first(where: { $0.id == log.id }) else { return }
        var tags = copy.sessionTags ?? []
        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
        copy.sessionTags = tags.isEmpty ? nil : tags
        saveCorrectedWorkout(copy)
    }

    func setPlannedSets(_ count: Int, at index: Int) {
        guard var state = activeWorkout else { return }
        state.setPlannedSets(count, at: index)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
    }

    /// Adds a new swap option to an exercise mid-workout. It's saved to the routine too,
    /// so it's there next time (and on the Watch).
    @discardableResult
    func addSwapOption(named rawName: String, at index: Int, swapNow: Bool) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var state = activeWorkout,
              index >= 0, index < state.routine.exercises.count else { return false }
        let item = state.routine.exercises[index]
        let planned = state.plannedExercise(for: item)
        let key = ExerciseLog.key(for: name)

        // Already an option (or the planned exercise itself)? Just use it.
        if let existing = planned.withAlternatives.first(where: { $0.historyKey == key }) {
            if swapNow, existing.id != item.exercise.id { swapExercise(at: index, to: existing) }
            return true
        }

        // Today's copy keeps today's phase rep range / deload sets; the routine gets the normal settings.
        var option = planned.makeAlternative(named: name)
        if let r = routines.firstIndex(where: { $0.id == state.routine.id }),
           let e = routines[r].exercises.firstIndex(where: { $0.id == item.id }) {
            var saved = routines[r].exercises[e].exercise.makeAlternative(named: name)
            saved.id = option.id
            routines[r].exercises[e].exercise.alternativeList.append(saved)
        }
        option.notes = nil
        state.addSwapOption(option, at: index)
        if swapNow { state.swapExercise(at: index, to: option) }
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)
        persistAndSync()
        return true
    }

    func skipRest() {
        guard var state = activeWorkout else { return }
        state.endRest()
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: false)
    }

    func addRest(seconds: Int) {
        guard var state = activeWorkout else { return }
        state.extendRest(by: seconds)
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: false)
    }

    /// The Watch owns the HealthKit session, so ask it to finish. If it can't be reached,
    /// save on iPhone now; the Watch's version (with heart rate + calories) replaces it if it arrives later.
    func finishWorkout() {
        guard var state = activeWorkout else { return }
        state.finishRequested = true
        state.revision += 1
        activeWorkout = state
        watchBridge.sendActiveState(state, reliable: true)

        guard watchBridge.isReachable else {
            saveLocally(state)
            return
        }
        let id = state.workoutID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, let current = self.activeWorkout, current.workoutID == id else { return }
            self.saveLocally(current)
        }
    }

    func cancelWorkout() {
        guard let state = activeWorkout else { return }
        endedWorkoutIDs.insert(state.workoutID)
        showWorkout = false
        activeWorkout = nil
        watchBridge.sendCancel(state.workoutID)
    }

    private func saveLocally(_ state: ActiveWorkoutState) {
        if state.totalCompletedSets > 0 {
            receiveCompletedWorkout(state.makeLog())
        } else {
            endedWorkoutIDs.insert(state.workoutID)
            showWorkout = false
            activeWorkout = nil
        }
    }

    private func activeWorkoutChanged(from old: ActiveWorkoutState?) {
        liveActivity.sync(activeWorkout, style: profile.coachStyle)
        persistActiveWorkout()

        if let state = activeWorkout, state.isResting, let end = state.restEndDate {
            // Locked iPhone: the notification vibrates the iPhone, or the Watch if you're wearing it.
            // (When GymForge is open on the Watch it buzzes on its own, so skip the duplicate.)
            if watchBridge.isReachable {
                ReminderScheduler.cancelRestEnd()
            } else {
                ReminderScheduler.scheduleRestEnd(at: end, nextExercise: state.currentItem?.exercise.name ?? "next set")
            }
            // App open on the iPhone: vibrate the iPhone itself when rest ends.
            if restBuzzEnd != end {
                restBuzzEnd = end
                restBuzzTask?.cancel()
                restBuzzTask = Task { @MainActor [weak self] in
                    let wait = end.timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                    guard !Task.isCancelled, let self, self.activeWorkout?.restEndDate == end || self.activeWorkout?.isResting == false else { return }
                    if UIApplication.shared.applicationState == .active {
                        RestSound.play(announcement: self.restAnnouncement())
                        MTHaptics.longStrong(seconds: 1.5)
                    }
                }
            }
        } else {
            ReminderScheduler.cancelRestEnd()
            // Rest skipped by hand (more than a moment early) or workout ended: no buzz.
            if activeWorkout == nil || (restBuzzEnd.map { $0.timeIntervalSinceNow > 2 } ?? false) {
                restBuzzTask?.cancel()
                restBuzzEnd = nil
            }
        }

        // A new set was logged (here or on the Watch): green tick.
        if let state = activeWorkout, let old, old.workoutID == state.workoutID {
            let oldIDs = Set(old.completedSets.values.flatMap { $0 }.map(\.id))
            let fresh = state.completedSets.flatMap { key, list in
                list.filter { !oldIDs.contains($0.id) }.map { (exerciseID: key, set: $0) }
            }
            // Only fresh ones: sets queued while the app was closed don't tick when it opens.
            if let newest = fresh.max(by: { $0.set.completedAt < $1.set.completedAt }),
               newest.set.completedAt.timeIntervalSinceNow > -15 {
                showSetTick(newest.set, exerciseID: newest.exerciseID, in: state)
            }
        }

        // PR set deleted or edited down: take its banner away.
        if let banner = prBanner, activeWorkout?.lastPR?.id != banner.id {
            prBanner = nil
            bannerTask?.cancel()
        }

        if let pr = activeWorkout?.lastPR, !seenPRs.contains(pr.id) {
            seenPRs.insert(pr.id)
            prBanner = pr
            bannerTask?.cancel()
            bannerTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.prBanner = nil }
            }
        }
    }

    /// What the train voice says when rest ends: the exercise you're about to do and its target.
    private func restAnnouncement() -> String? {
        guard let state = activeWorkout, let item = state.currentItem else { return nil }
        let lastID = state.lastLoggedSet?.id
        let previousExerciseID = lastID.flatMap { id in
            state.completedSets.first { $0.value.contains { $0.id == id } }?.key
        }
        let reps = item.exercise.isCardio ? nil : state.prefill(for: item, logs: workoutLogs).reps
        return RestSound.announcement(for: state, previousExerciseID: previousExerciseID, reps: reps)
    }

    private func showSetTick(_ set: WorkoutSetLog, exerciseID: UUID, in state: ActiveWorkoutState) {
        let finishedItem = state.routine.exercises.first {
            $0.exercise.id == exerciseID && state.isFinished($0) && !state.isSkipped($0)
        }
        let caption: String? = state.isComplete ? "All sets done" : finishedItem.map { "\($0.exercise.name) done" }
        let tick = SetTick(id: set.id, isPR: set.isPR == true, caption: caption)
        let visible = showWorkout && UIApplication.shared.applicationState == .active
        if visible && SetTick.hapticEnabled { SetTick.playHaptic(pr: tick.isPR) }
        guard visible && SetTick.animationEnabled else { return }
        setTick = tick
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: tick.isPR || caption != nil ? 1_700_000_000 : 1_100_000_000)
            guard !Task.isCancelled, self?.setTick?.id == tick.id else { return }
            self?.setTick = nil
        }
    }

    private func resendActiveWorkout() {
        guard let state = activeWorkout else { return }
        watchBridge.sendActiveState(state, reliable: false)
    }

    // MARK: Incoming from Watch

    private func receiveCompletedWorkout(_ log: WorkoutLog) {
        endedWorkoutIDs.insert(log.id)
        if let idx = workoutLogs.firstIndex(where: { $0.id == log.id }) {
            let existing = workoutLogs[idx]
            if log.activeCaloriesKcal != nil || log.totalSets >= existing.totalSets {
                workoutLogs[idx] = log
            }
        } else if log.totalSets > 0 {
            workoutLogs.append(log)
        }

        let wasActive = activeWorkout?.workoutID == log.id
        if wasActive {
            showWorkout = false
            activeWorkout = nil
        }
        persistAndSync()
        rescheduleReminders()

        // Show the summary for a workout that just ended (not for an old one arriving late).
        if (wasActive || summaryLog?.id == log.id), Date().timeIntervalSince(log.endedAt) < 30 * 60 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self?.summaryLog = log
            }
        }
    }

    private func receiveActiveState(_ state: ActiveWorkoutState) {
        if workoutLogs.contains(where: { $0.id == state.workoutID }) { return }
        if endedWorkoutIDs.contains(state.workoutID) {
            // A late update for a workout you already cancelled here: tell the Watch again.
            watchBridge.sendCancel(state.workoutID)
            return
        }
        if let current = activeWorkout {
            if current.workoutID != state.workoutID {
                // Never let a different workout replace one with sets logged.
                if current.totalCompletedSets > 0 {
                    watchBridge.sendActiveState(current, reliable: true)
                    return
                }
            } else if state.revision < current.revision {
                // Older copy — but a Finish from the Watch side still counts.
                guard state.finishRequested, !current.finishRequested else { return }
                let merged = current.merged(with: state)
                activeWorkout = merged
                watchBridge.sendActiveState(merged, reliable: true)
                return
            } else if state.revision == current.revision {
                // Both devices changed at the same moment. Only the Watch settles ties (it merges both
                // copies and sends a newer one, which we adopt) — merging on both sides would ping-pong.
                return
            }
        } else {
            guard abs(state.startedAt.timeIntervalSinceNow) < 6 * 3600 else { return }
            // A workout started on the Watch: open it here too.
            showWorkout = true
        }
        activeWorkout = state
    }

    private func receiveCancel(_ id: UUID) {
        endedWorkoutIDs.insert(id)
        if activeWorkout?.workoutID == id {
            showWorkout = false
            activeWorkout = nil
        }
    }

    func pushSnapshotToWatch() {
        watchBridge.sync(snapshot: snapshot.trimmedForWatch())
    }

    // MARK: Persistence

    private var snapshotURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("gymforge.json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        hadLocalData = true
        do {
            let loaded = try FileStore.shared.loadSnapshot(from: snapshotURL)
            routines = loaded.routines
            workoutLogs = loaded.workoutLogs
            weeklyGoal = loaded.weeklyGoal
            profile = loaded.profile ?? UserProfile()
            extras = loaded.extras ?? GymExtras()
            cardioSessions = loaded.cardioSessions ?? []
        } catch {
            // Never overwrite data we couldn't read (e.g. an older build installed over a newer one):
            // keep a copy, then behave like a fresh install (offers the iCloud backup, holds new backups until then).
            print("Could not load snapshot: \(error)")
            let stamp = Int(Date().timeIntervalSince1970)
            let keep = snapshotURL.deletingLastPathComponent().appendingPathComponent("gymforge-unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: snapshotURL, to: keep)
            hadLocalData = false
        }
    }

    // MARK: Workout in progress (survives iOS closing the app mid-session)

    private var activeWorkoutURL: URL {
        snapshotURL.deletingLastPathComponent().appendingPathComponent("gymforge-active.json")
    }

    private func persistActiveWorkout() {
        if let state = activeWorkout, let data = try? JSONEncoder.gymForge.encode(state) {
            try? data.write(to: activeWorkoutURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else {
            try? FileManager.default.removeItem(at: activeWorkoutURL)
        }
    }

    private func restoreActiveWorkout() {
        guard activeWorkout == nil,
              let data = try? Data(contentsOf: activeWorkoutURL),
              let state = try? JSONDecoder.gymForge.decode(ActiveWorkoutState.self, from: data),
              abs(state.startedAt.timeIntervalSinceNow) < 6 * 3600,
              !workoutLogs.contains(where: { $0.id == state.workoutID }) else {
            try? FileManager.default.removeItem(at: activeWorkoutURL)
            liveActivity.sync(nil, style: profile.coachStyle)
            return
        }
        activeWorkout = state
        showWorkout = true
        // If the Watch has moved on since, it sends its newer copy back. Wait for the connection first.
        let id = state.workoutID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, let current = self.activeWorkout, current.workoutID == id else { return }
            self.watchBridge.sendActiveState(current, reliable: false)
        }
    }

    private func save() {
        do {
            try FileStore.shared.save(snapshot, to: snapshotURL)
        } catch {
            print("Could not save snapshot: \(error)")
        }
        if backupReady { cloud.scheduleBackup(snapshot) }
    }

    func persistAndSync() {
        save()
        pushSnapshotToWatch()
    }
}
