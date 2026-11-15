import SwiftUI

/// MK24: the home screen's cards, moved out of TodayView.swift (it had grown past 800 lines).

// MARK: - Top card: today's session

/// The one card that answers "what am I doing today?" — with the Start button on it.
struct HomeHeroCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    let today: HomeToday
    @State private var cardioSetup: ActivityKind?

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
            .sheet(item: $cardioSetup) { kind in
                NavigationStack { ActivityStartSheet(kind: kind) }
                    .presentationDetents([.medium, .large])
            }
    }

    private var accent: Color {
        switch today {
        case .inProgress, .done, .run: return .green
        case .sick: return .red
        case .travel: return .teal
        case .rest: return .indigo
        case .basketball, .askCourt: return .orange
        case .train, .noRoutines: return .accentColor
        }
    }

    @ViewBuilder
    private var content: some View {
        switch today {
        case .inProgress: inProgress
        case .sick: sick
        case .travel: travel
        case .askCourt(let day): askCourt(day)
        case .basketball(let day): basketball(day)
        case .run: run
        case .train(let routine, let split): train(routine, split: split)
        case .done(let logs, let next): done(logs, next: next)
        case .rest(let title, let lines, let next): rest(title: title, lines: lines, next: next)
        case .noRoutines: noRoutines
        }
    }

    // MARK: Pieces

    private func eyebrow(_ text: String, _ icon: String) -> some View {
        Label(text.uppercased(), systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(accent)
    }

    private func notes(_ lines: [String]) -> some View {
        ForEach(lines, id: \.self) { line in
            Text(line)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "3 exercises · ≈36 min · last done 5 days ago"
    private func meta(_ routine: WorkoutRoutine) -> String {
        let count = routine.exercises.count
        var parts = ["\(count) exercise\(count == 1 ? "" : "s")"]
        if count > 0 { parts.append("≈\(TimeBudget.estimateMinutes(ActiveWorkoutState(routine: routine))) min") }
        let last = store.lastDone(routine)
        parts.append(last > .distantPast ? "last done " + last.formatted(.relative(presentation: .named)) : "not done yet")
        return parts.joined(separator: " · ")
    }

    /// Deload, or where you are in the training block and how hard to push.
    @ViewBuilder
    private var blockLine: some View {
        if store.profile.isDeloadActive() {
            HStack {
                Label("Deload: one less set, ~10% lighter", systemImage: "leaf.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                if store.profile.deloadUntil != nil {
                    Button("End") { store.endDeload() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        } else if let position = store.profile.program?.position(at: .now) {
            let effort = EffortTarget.text(EffortTarget.reps(profile: store.profile))
            Label("Week \(position.week) of \(position.block.weeks) · \(position.block.phase.title) block · \(effort)",
                  systemImage: "chart.bar.doc.horizontal")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var courtChange: some View {
        if store.fixedSplitOn, store.courtToday != nil {
            Button("Change basketball answer") { store.courtToday = nil }
                .font(.caption)
        }
    }

    private func bigButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(accent)
    }

    /// The routine after today's, offered quietly (rest days and once you've trained).
    private func nextUp(_ routine: WorkoutRoutine) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                SessionPreviewView(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UP NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(routine.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Start") { Task { await store.startWorkout(routine) } }
                .buttonStyle(.bordered)
                .disabled(routine.exercises.isEmpty)
        }
        .padding(.top, 2)
    }

    // MARK: States

    @ViewBuilder
    private var inProgress: some View {
        if let active = store.activeWorkout {
            VStack(alignment: .leading, spacing: 10) {
                eyebrow("In progress", "record.circle")
                Text(active.routine.name).font(.title.bold())
                Text("\(active.totalCompletedSets) of \(active.totalPlannedSets) sets done")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SwiftUI.ProgressView(value: Double(min(active.totalCompletedSets, active.totalPlannedSets)),
                                     total: Double(max(active.totalPlannedSets, 1)))
                    .tint(.green)
                bigButton("Resume workout", "play.fill") { store.showWorkout = true }
            }
        }
    }

    private func train(_ routine: WorkoutRoutine, split: FixedSplit.Day?) -> some View {
        let light = ((store.readiness?.suggestLightSession ?? false) || store.comebackSuggested) && !store.profile.isDeloadActive()
        return VStack(alignment: .leading, spacing: 12) {
            eyebrow(split.map { "Today · \($0.title)" } ?? "Up next", "bolt.fill")
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name).font(.title.bold())
                Text(meta(routine)).font(.subheadline).foregroundStyle(.secondary)
            }
            notes(split?.notes ?? [])
            blockLine
            // "+ Watch" only when the Watch app is really there.
            bigButton(store.watchBridge.isWatchReady ? "Start on iPhone + Watch" : "Start workout", "play.fill") {
                Task { await store.startWorkout(routine) }
            }
            .disabled(routine.exercises.isEmpty)
            HStack(spacing: 8) {
                NavigationLink {
                    SessionPreviewView(routine: routine)
                } label: {
                    Label("Plan & coaching", systemImage: "list.bullet.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if light {
                    Button {
                        Task { await store.startWorkout(routine, light: true) }
                    } label: {
                        Label("Light session", systemImage: "leaf").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(routine.exercises.isEmpty)
                }
            }
            .font(.subheadline)
            courtChange
        }
    }

    private func done(_ logs: [WorkoutLog], next: WorkoutRoutine?) -> some View {
        let sets = logs.reduce(0) { $0 + $1.totalSets }
        let minutes = Int((logs.reduce(0.0) { $0 + $1.duration } / 60).rounded())
        let latest = logs.max { $0.startedAt < $1.startedAt }
        return VStack(alignment: .leading, spacing: 10) {
            eyebrow("Done today", "checkmark.seal.fill")
            Text(logs.map(\.routineName).joined(separator: " + ")).font(.title.bold())
            Text("\(sets) sets · \(minutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            blockLine
            if let latest {
                Button {
                    store.summaryLog = latest
                } label: {
                    Label("View summary", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            if let next { nextUp(next) }
        }
    }

    private func rest(title: String, lines: [String], next: WorkoutRoutine?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Rest day", "moon.zzz.fill")
            Text(title).font(.title.bold())
            notes(lines)
            blockLine
            if let next { nextUp(next) }
        }
    }

    private func askCourt(_ day: FixedSplit.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Today", "basketball.fill")
            Text("Playing basketball today?").font(.title2.bold())
            notes(day.notes)
            VStack(spacing: 8) {
                Button { store.courtToday = .fullCourt } label: {
                    Label("Full-court / hard pickup: skip chest", systemImage: "basketball.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { store.courtToday = .light } label: {
                    Label("Light shootaround: 25-min micro chest", systemImage: "basketball").frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { store.courtToday = FixedSplit.Court.none } label: {
                    Label("No basketball: full chest day", systemImage: "dumbbell.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
    }

    private func basketball(_ day: FixedSplit.Day?) -> some View {
        let played = store.workoutLogs.contains { $0.routineID == CardioIDs.basketball && Calendar.current.isDateInToday($0.startedAt) }
        return VStack(alignment: .leading, spacing: 10) {
            eyebrow(day == nil ? "Planned today" : "Today", "basketball.fill")
            Text(day?.title ?? "Basketball").font(.title.bold())
            notes(day?.notes ?? [])
            if played {
                Label("Basketball logged today", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                bigButton("Start basketball", "basketball.fill") { cardioSetup = .basketball }
                    .disabled(store.phoneRecorder.isActive)
            }
            courtChange
        }
    }

    private var run: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Planned today", "figure.run")
            Text("Run").font(.title.bold())
            bigButton("Start run", "figure.run") { cardioSetup = .run }
                .disabled(store.phoneRecorder.isActive)
        }
    }

    private var sick: some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("Sick day", "cross.case.fill")
            Text("Rest up").font(.title.bold())
            Text("This week's goal is lowered and Sergeant Cluck is standing down.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var travel: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Travel day", "airplane")
            Text("Hotel workout").font(.title.bold())
            Text("No gym? 20 minutes: push-ups, squats, pike push-ups, lunges, glute bridges and a plank. It doesn't count against your week either way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            bigButton("Start hotel workout", "figure.strengthtraining.functional") {
                Task { await store.startTravelWorkout() }
            }
        }
    }

    private var noRoutines: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("Get started", "sparkles")
            Text("No workouts yet").font(.title.bold())
            Text("Build your first routine and it shows up here, ready to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NavigationLink {
                RoutineBuilderView()
            } label: {
                Label("Build a routine", systemImage: "hammer").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - This week

/// The week at a glance: sessions against your goal, the day row, other goals, Sergeant Cluck.
struct HomeWeekCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let stats = store.consistency
        let goals = TrainingGoalTracker.progress(goals: store.profile.trainingGoals, liftGoal: store.thisWeekGoal,
                                                 logs: store.workoutLogs, cardio: store.cardioSessions)
            .filter { $0.kind != .lifting }
        let loggedToday = store.workoutLogs.contains { Calendar.current.isDateInToday($0.startedAt) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.headline)
                Spacer()
                Text("\(stats.thisWeekCount) / \(stats.weeklyGoal)").font(.title3.bold().monospacedDigit())
                Text("sessions").font(.subheadline).foregroundStyle(.secondary)
            }
            GymWeekRow(logs: store.workoutLogs, restDays: store.extras.restDays, plans: store.extras.dayPlans)

            // Streak, the last 4 weeks, your running / basketball goals, and the way in to change them.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if stats.streakWeeks > 0 {
                        chip("\(stats.streakWeeks)-week streak", icon: "flame.fill", color: .orange)
                    }
                    if stats.last4WeeksTarget > 0 {
                        chip("Last 4 weeks \(stats.last4WeeksCount)/\(stats.last4WeeksTarget)", icon: nil, color: .secondary)
                    }
                    ForEach(goals) { goal in
                        chip("\(goal.title) \(goal.text)", icon: goal.met ? "checkmark" : nil, color: goal.met ? .green : .secondary)
                    }
                    NavigationLink { TrainingGoalsView() } label: {
                        chip("Goals", icon: "target", color: .accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            if store.profile.cluckEnabled {
                CluckBanner(snapshot: store.cluckSnapshot) { store.snoozeCluckToday() }
            }

            HStack(spacing: 8) {
                if !loggedToday {
                    Button {
                        store.toggleRestDay()
                    } label: {
                        Label(store.isRestDay(.now) ? "Undo rest day" : "Rest day today",
                              systemImage: store.isRestDay(.now) ? "arrow.uturn.backward" : "moon.zzz")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(store.isRestDay(.now) ? .gray : .indigo)
                }
                NavigationLink { WeekPlanView() } label: {
                    Label("Plan week", systemImage: "calendar").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
            .lineLimit(1)
        }
        .card()
    }

    private func chip(_ text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
        .fixedSize()
    }
}

// MARK: - For you

/// Everything that used to be its own card when it needed you — weigh-in, reviews, planning, recovery,
/// phase warnings, the coach's top note — as one-line rows. Hidden when there's nothing.
struct HomeHeadsUpCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @EnvironmentObject private var dayfold: DayfoldStore
    @Binding var showWeighIn: Bool

    var body: some View {
        let readiness = store.readiness
        let lowRecovery = readiness?.suggestLightSession ?? false
        let review = store.blockReview
        let phase = store.phaseCoach
        let phaseAlert = phase.muscleWarning ?? phase.deloadSuggestion ?? phase.miniCutPrompt
        let insight = store.coachInsights.first { $0.kind != .recovery || readiness == nil }
        // MK23: when the routine card above already lists the weigh-in step, don't ask for it twice.
        let inRoutine = dayfold.todayRows().contains { RoutineOrder.needsWeighIn($0, store: store) }
        let weighIn = Calendar.current.component(.weekday, from: .now) == 1 && store.extras.weighIn(on: .now) == nil && !inRoutine
        let backupStale = !Demo.isOn && BackupStatus.isStale(workouts: store.workoutLogs.count)
        // With the fixed-day split on, the split already says which days you train — no prompt to plan.
        let planWeek = store.weekNeedsPlan && store.todayPlanKind == nil && !store.fixedSplitOn
        let reviewDue = store.weeklyReviewDue
        let hasPhase = phase.miniCutDone || phaseAlert != nil
        let urgent = weighIn || reviewDue || review != nil || planWeek || lowRecovery || backupStale
        if urgent || hasPhase || insight != nil {
            VStack(alignment: .leading, spacing: 0) {
                Text("For you").font(.headline).padding(.bottom, 4)
                if weighIn {
                    Button { showWeighIn = true } label: {
                        row("scalemass.fill", .accentColor, "Sunday weigh-in", "Log this week's weight and body fat.")
                    }
                }
                if backupStale {
                    NavigationLink { SettingsDataPage() } label: {
                        row("externaldrive.badge.exclamationmark", .orange,
                            BackupStatus.daysSinceFull.map { "Last full backup was \($0) days ago" } ?? "No full backup yet",
                            "More Training can't be recovered after a re-sign without one. Turn on the automatic backup.")
                    }
                }
                if reviewDue {
                    Button { store.showWeeklyReview = true } label: {
                        row("chart.bar.doc.horizontal", .accentColor, "Your weekly review is ready", nil)
                    }
                }
                if let review {
                    NavigationLink { BlockReviewView(review: review) } label: {
                        row("flag.checkered", .accentColor, "Block review", review.headline)
                    }
                }
                if planWeek {
                    NavigationLink { WeekPlanView() } label: {
                        row("calendar", .accentColor, "Plan your week", "Pick your training and rest days — planned rest keeps Sergeant Cluck calm.")
                    }
                }
                if lowRecovery, let readiness {
                    NavigationLink { RecoveryView() } label: {
                        row("bed.double.fill", .orange, "Recovery is low (\(readiness.score))", "Consider the light session today.")
                    }
                }
                if phase.miniCutDone {
                    NavigationLink { PhaseView() } label: {
                        row("flag.checkered", .green, "Mini-cut finished", "Back to bulking?")
                    }
                } else if let phaseAlert {
                    NavigationLink { PhaseView() } label: {
                        row(phaseAlert.severe ? "exclamationmark.triangle.fill" : "lightbulb.fill",
                            phaseAlert.severe ? .red : .orange, phaseAlert.title, nil)
                    }
                }
                if let insight {
                    NavigationLink { CoachView() } label: {
                        row(insight.systemImage, .accentColor, insight.title, insight.message)
                    }
                }
            }
            .buttonStyle(.plain)
            .card()
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Nutrition (compact)

/// Today's protein and creatine in one small card. The full cards (phase picker, calories, macros,
/// typing a total) are one tap away in Nutrition & phase.
struct HomeFuelCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let day = store.nutritionToday()
        let target = store.proteinTargetG
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrition").font(.headline)
                Spacer()
                NavigationLink { NutritionView() } label: {
                    HStack(spacing: 3) {
                        Text("Details")
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Protein").font(.subheadline)
                Spacer()
                Text("\(Int(day.proteinG))" + (target.map { " / \(Int($0)) g" } ?? " g"))
                    .font(.subheadline.bold().monospacedDigit())
            }
            if let target, target > 0 {
                SwiftUI.ProgressView(value: min(day.proteinG / target, 1))
                    .tint(day.proteinG >= target ? .green : .accentColor)
            }
            HStack(spacing: 8) {
                Button("+20 g") { store.addProtein(20) }
                Button("+40 g") { store.addProtein(40) }
                Spacer(minLength: 0)
                Button {
                    store.toggleCreatine()
                } label: {
                    Label("Creatine", systemImage: day.creatine ? "checkmark.circle.fill" : "circle")
                }
                .tint(day.creatine ? .green : .gray)
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
            if let kcal = day.calories, kcal > 0 {
                Text("\(Int(kcal)) kcal logged today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

// MARK: - Quick starts

/// Your other routines as compact rows (tap for the plan, Start to go), then run / basketball.
struct HomeQuickStart: View {
    @EnvironmentObject private var store: PhoneAppStore
    /// The routine already on the top card.
    let excluding: UUID?

    var body: some View {
        let routines = store.routines.filter { $0.id != excluding }
        VStack(alignment: .leading, spacing: 12) {
            if !routines.isEmpty {
                Text(excluding == nil ? "Workouts" : "More workouts").font(.title3.bold())
                VStack(spacing: 0) {
                    ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                        if index > 0 { Divider() }
                        row(routine)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
            CardioStartCard()
        }
    }

    private func row(_ routine: WorkoutRoutine) -> some View {
        let last = store.lastDone(routine)
        let count = routine.exercises.count
        let detail = "\(count) exercise\(count == 1 ? "" : "s") · "
            + (last > .distantPast ? "last done " + last.formatted(.relative(presentation: .named)) : "not done yet")
        return HStack(spacing: 10) {
            NavigationLink {
                SessionPreviewView(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("Start") { Task { await store.startWorkout(routine) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(routine.exercises.isEmpty || store.activeWorkout != nil)
        }
        .padding(.vertical, 9)
    }
}

struct ReadinessCard: View {
    let readiness: Readiness

    private var color: Color {
        switch readiness.level {
        case .ready: return .green
        case .moderate: return .yellow
        case .low: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(readiness.title, systemImage: "bed.double.fill")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("\(readiness.score)")
                    .font(.title2.bold())
                    .foregroundStyle(color)
            }
            Text(readiness.reasons.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if readiness.suggestLightSession {
                Text("Consider a light session today — one less set and ~10% lighter, without affecting your progression.")
                    .font(.footnote)
            }
        }
        .card()
    }
}
