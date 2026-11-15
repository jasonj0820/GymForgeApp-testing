import SwiftUI

// MARK: - What today is

/// MK21: what the home screen's top card is about today.
enum HomeToday {
    case inProgress
    case sick
    case travel
    /// Friday in the fixed split, before you've said whether you're playing.
    case askCourt(FixedSplit.Day)
    /// A basketball day (from the split, or planned in Plan week when `day` is nil).
    case basketball(FixedSplit.Day?)
    case run
    case train(WorkoutRoutine, FixedSplit.Day?)
    case done([WorkoutLog], next: WorkoutRoutine?)
    case rest(title: String, notes: [String], next: WorkoutRoutine?)
    case noRoutines

    /// The routine already offered in the top card (left out of "More workouts").
    var featuredRoutineID: UUID? {
        switch self {
        case .train(let routine, _): return routine.id
        case .done(_, let next), .rest(_, _, let next): return next?.id
        default: return nil
        }
    }
}

extension PhoneAppStore {
    /// A run / basketball planned for today (Plan week) and not done yet.
    var plannedCardioToday: ActivityKind? {
        guard let id = extras.dayPlan(on: .now)?.routineID else { return nil }
        let kind: ActivityKind? = id == CardioIDs.run ? .run : (id == CardioIDs.basketball ? .basketball : nil)
        guard let kind, !workoutLogs.contains(where: { $0.routineID == id && Calendar.current.isDateInToday($0.startedAt) }) else { return nil }
        return kind
    }

    /// Today in one answer: a workout in progress, a sick / travel day, the fixed split's day, what's
    /// planned, what's already done, a rest day — otherwise the routine you've gone longest without.
    var homeToday: HomeToday {
        if activeWorkout != nil { return .inProgress }
        switch todayPlanKind {
        case .ill?: return .sick
        case .travel?: return .travel
        default: break
        }
        let trained = workoutLogs.filter { $0.countsAsTraining && Calendar.current.isDateInToday($0.startedAt) }
        let split: FixedSplit.Day? = fixedSplitOn ? splitToday : nil
        // MK23: on the fixed split, "up next" is the split's next session (it used to show whichever
        // routine you'd gone longest without, e.g. Leg Day on a Sunday when Monday is chest).
        let next = (split != nil ? splitNextRoutine : nil) ?? suggestedRoutine
        if let split {
            switch split.kind {
            case .askCourt:
                return .askCourt(split)
            case .basketball:
                return .basketball(split)
            case .rest:
                if trained.isEmpty { return .rest(title: split.title, notes: split.notes, next: next) }
            case .train, .microChest:
                break
            }
        }
        if let routine = splitRoutineToday ?? plannedRoutineToday { return .train(routine, split) }
        if let cardio = plannedCardioToday { return cardio == .run ? .run : .basketball(nil) }
        if !trained.isEmpty { return .done(trained, next: next) }
        if isRestDay(.now) {
            return .rest(title: "Recover today", notes: ["No session today. Undo it under This week if plans change."], next: next)
        }
        if let next { return .train(next, nil) }
        return .noRoutines
    }
}

// MARK: - Home

/// MK21: the home screen, pared back to what you open a gym app for — today's session with Start at the
/// top, the week, anything that needs you, protein, and quick starts. The longer cards moved to the Body
/// tab: Nutrition & phase (full protein / calories / bulk-cut) and Sleep & recovery (sleep + readiness).
struct TodayView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var askMoreTraining = false
    @State private var showMoreTraining = false
    @State private var showWeighIn = false
    @State private var quickAdd: QuickAdd?
    @AppStorage("checkin.dismissedDay") private var dismissedDay = ""
    private var checkInDismissed: Bool {
        get { dismissedDay == Date.now.formatted(.iso8601.year().month().day()) }
        nonmutating set { dismissedDay = newValue ? Date.now.formatted(.iso8601.year().month().day()) : "" }
    }

    var body: some View {
        let today = store.homeToday
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Long-press the title to open the private More Training section.
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Today")
                        .font(.largeTitle.bold())
                }
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.8) {
                    Haptics.heavy()
                    askMoreTraining = true
                }

                if let restored = store.restoredBackupDate {
                    Label("Restored your data from the iCloud backup of \(restored.formatted(date: .abbreviated, time: .shortened)).",
                          systemImage: "icloud.and.arrow.down")
                        .font(.footnote)
                        .card()
                }
                BreakBanner()
                BigNightBanner()   // MK24 (110)
                // MK23: a failed save used to be silent.
                if let problem = store.saveProblem {
                    NavigationLink { DiagnosticsView() } label: {
                        Label("Your latest changes aren't being saved (\(problem)). Tap for details; don't close the app until this clears.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                            .card()
                    }
                    .buttonStyle(.plain)
                }

                HomeHeroCard(today: today)
                // MK24: no sleep or heart-rate data for today, and no check-in yet: ask in three taps.
                if store.readiness == nil, Calendar.current.component(.hour, from: .now) < 15, !checkInDismissed {
                    ReadinessCheckInCard()
                        .overlay(alignment: .topTrailing) {
                            Button { checkInDismissed = true } label: { Image(systemName: "xmark").font(.caption.bold()) }
                                .buttonStyle(.borderless).padding(14).accessibilityLabel("Not today")
                        }
                }
                SundayResetCard()
                DayTimelineCard()
                DayNotesCard()
                HomeRoutineCard(showWeighIn: $showWeighIn)
                HomeWeekCard()
                HomeHeadsUpCard(showWeighIn: $showWeighIn)
                // Sleep shows here only when it's time to act: around bedtime, or while "Going to sleep" is running.
                // The rest of the time it's on Body → Sleep & recovery.
                if store.inBedtimeWindow() || SleepHealth.manualStart != nil {
                    SleepCard()
                }
                HomeFuelCard()
                HomeQuickStart(excluding: today.featuredRoutineID)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("More training?", isPresented: $askMoreTraining) {
            Button("Yes") {
                // Latest body fat (only if measured in the last ~4 months), read-only for the gap advice.
                let latestFat = store.healthKit.bodyFat.max(by: { $0.date < $1.date })
                MTVault.gymBodyFatPercent = latestFat.flatMap { $0.date > Date.now.addingTimeInterval(-120 * 86_400) ? $0.value : nil }
                Task {
                    if await MTVault.shared.unlock() { showMoreTraining = true }
                }
            }
            Button("No", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showMoreTraining) {
            MTRootView()
                .environmentObject(MTVault.shared)
        }
        .sheet(isPresented: $showWeighIn) { WeighInSheet().environmentObject(store) }
        .sheet(item: $quickAdd) { QuickAddSheet(kind: $0).environmentObject(store) }
        .refreshable { await store.appBecameActive() }
        .onReceive(NotificationCenter.default.publisher(for: .openMoreTraining)) { _ in
            if !showMoreTraining { askMoreTraining = true }
        }
        .toolbar {
            // MK15: More Training in plain sight (still Face ID / passcode). Long-pressing the title still works.
            Button { askMoreTraining = true } label: { Label("More Training", systemImage: "lock.shield.fill") }
            QuickAddMenu(sheet: $quickAdd, showWeighIn: $showWeighIn)
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
        }
    }
}
