import SwiftUI
import Combine

/// More Training main screen: this week, PAC rhythm, check-in, safety, stretcher, timers and presets.
struct MTLogView: View {
    @EnvironmentObject private var vault: MTVault
    @State private var startType: MTType?
    @State private var pacWarningType: MTType?
    @State private var pacWarningPreset: MTPreset?
    @State private var addingSession = false
    @State private var editingPreset: MTPreset?
    @State private var selectedDay: Date?
    @State private var showSession = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                MTCluckCard()
                MTWeekRow(selectedDay: $selectedDay)
                if let day = selectedDay {
                    dayDetail(day)
                }
                let restTarget = selectedDay ?? .now
                Button {
                    vault.toggleRestDay(restTarget)
                } label: {
                    Label(vault.isRestDay(restTarget)
                          ? "Undo rest day"
                          : (Calendar.current.isDateInToday(restTarget) ? "Rest day today" : "Mark \(restTarget.formatted(.dateTime.weekday(.wide))) as rest"),
                          systemImage: "moon.zzz")
                }
            }

            if vault.data.settings.dailyRoutineOn {
                routineSection
            } else {
                pacSection
            }
            progressionSection
            checkInSection

            ForEach(MTSafety.advice(vault.data)) { advice in
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(advice.title).font(.headline)
                            Text(advice.message).font(.subheadline)
                        }
                    } icon: {
                        Image(systemName: advice.level == .rest ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(advice.level == .rest ? Color.red : Color.orange)
                    }
                }
            }

            stretcherSection
            totalsSection
            staminaSection

            if vault.data.isBusy {
                runningCard
            }

            presetSection
            startSection
            recentSection
        }
        .navigationTitle("More Training")
        .onReceive(ticker) { _ in vault.advanceInterval() }
        .sheet(item: $startType) { type in
            NavigationStack { MTStartSheet(type: type) }
                .environmentObject(vault)
        }
        .sheet(isPresented: $addingSession) {
            NavigationStack { MTAddSessionView() }
                .environmentObject(vault)
        }
        .sheet(item: $editingPreset) { preset in
            NavigationStack { MTPresetEditor(preset: preset) }
                .environmentObject(vault)
        }
        .fullScreenCover(isPresented: $showSession) {
            MTSessionScreen(onMinimise: { showSession = false }, onClose: { showSession = false })
                .environmentObject(vault)
        }
        .onAppear {
            if vault.data.isBusy { showSession = true }
        }
        .onChange(of: vault.data.isBusy) { _, busy in
            guard busy else { return }
            // Wait for the start sheet to finish closing, then open the session screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if vault.data.isBusy { showSession = true }
            }
        }
        .sheet(isPresented: Binding(
            get: { !vault.pendingReview.isEmpty && !showSession },
            set: { if !$0 { vault.applyReview(warnings: [], notes: "") } }
        )) {
            NavigationStack { MTReviewSheet() }
                .environmentObject(vault)
        }
        .confirmationDialog(pacWarningText, isPresented: Binding(
            get: { pacWarningType != nil || pacWarningPreset != nil },
            set: { if !$0 { pacWarningType = nil; pacWarningPreset = nil } }
        ), titleVisibility: .visible) {
            Button("Start anyway") {
                if let preset = pacWarningPreset {
                    Task { await vault.startInterval(name: preset.name, steps: preset.steps) }
                } else {
                    startType = pacWarningType
                }
                pacWarningType = nil
                pacWarningPreset = nil
            }
            Button("Cancel", role: .cancel) {
                pacWarningType = nil
                pacWarningPreset = nil
            }
        } message: {
            Text("Your plan is PAC every other day.")
        }
    }

    // MARK: Week & day detail

    @ViewBuilder
    private func dayDetail(_ day: Date) -> some View {
        let sessions = vault.data.sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.subheadline.bold())
        if sessions.isEmpty {
            Text("No training").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(sessions) { session in
            sessionRow(session)
        }
    }

    // MARK: Daily routine (MK11.3)

    private var routineSection: some View {
        let day = MTPlan.day(vault.data.sessions)
        let done = MTPlan.done(vault.data.sessions, day: day)
        let complete = MTPlan.isComplete(done, day: day)
        let pumpName = day.pumpType == .pac ? "PAC" : "Pump"
        func mins(_ value: Double, _ goal: Double) -> String { "\(Int(min(value, goal).rounded()))/\(Int(goal))" }
        return Section {
            HStack(spacing: 12) {
                Image(systemName: complete ? "checkmark.circle.fill" : "arrow.left.and.right")
                    .font(.title2)
                    .foregroundStyle(complete ? Color.green : Color.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(complete ? "Routine done today ✓" : (day.nir ? "Today's routine · NIR day" : "Today's routine")).font(.headline)
                    Text("HTE \(mins(done.extender, day.extenderMinutes)) min" + (day.nir ? " (NIR \(mins(done.nir, MTPlan.nirMinutes)))" : "")
                         + " · \(pumpName) \(mins(done.pump, day.pumpMinutes)) min")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !complete {
                    Button("Start") {
                        let steps = MTPlan.steps(day, pressure: vault.data.lastPressure(for: day.pumpType),
                                                 tension: vault.data.lastTension(for: .highTensionExtender))
                        Task { await vault.startInterval(name: "Daily routine", steps: steps) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(vault.data.isBusy)
                }
            }
            if day.pumpType == .pac { pacGuideLink }
        } header: {
            Text("Daily routine · NIR every other day")
        } footer: {
            Text((day.nir
                  ? "Today: 15 min extending with NIR, then 35 min without"
                  : "Today: 40 min extending (NIR is tomorrow)")
                 + (pumpName == "PAC" ? ", then guided PAC (25 min)." : ", then static pump 4 × 5 min.")
                 + " Static pump and PAC take turns day to day.")
        }
    }

    // MARK: When to progress (MK18)

    @ViewBuilder
    private var progressionSection: some View {
        let advice = MTProgression.advice(vault.data)
        if !advice.isEmpty {
            Section {
                ForEach(advice) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            Text(item.message).font(.subheadline)
                        }
                    } icon: {
                        Image(systemName: Self.symbol(item.kind)).foregroundStyle(Self.color(item.kind))
                    }
                }
            } header: {
                Text("When to progress")
            } footer: {
                Text("Step up only when your settings stop doing their job, one or two things at a time: about 0.5–1 inHg or 1 lb, held for 2+ weeks. Judge growth 2–3 months after a change, on measurements taken after 3+ days off.")
            }
        }
    }

    private static func symbol(_ kind: MTProgression.Advice.Kind) -> String {
        switch kind {
        case .keep: return "checkmark.seal.fill"
        case .addTime: return "clock.badge.checkmark"
        case .raise: return "arrow.up.circle.fill"
        case .hold: return "pause.circle.fill"
        case .backOff: return "exclamationmark.octagon.fill"
        case .takeBreak: return "bed.double.fill"
        case .tooMuch: return "gauge.with.dots.needle.67percent"
        case .needData: return "ruler"
        }
    }

    private static func color(_ kind: MTProgression.Advice.Kind) -> Color {
        switch kind {
        case .keep: return .green
        case .backOff: return .red
        case .tooMuch, .takeBreak: return .orange
        default: return .indigo
        }
    }

    // MARK: PAC every other day

    private var pacSection: some View {
        let status = MTPACSchedule.status(vault.data.sessions)
        let consistency = MTPACSchedule.consistency(vault.data.sessions)
        return Section {
            HStack(spacing: 12) {
                Image(systemName: "circle.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pacTitle(status)).font(.headline)
                    Text(pacDetail(status)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if case .due = status {
                    startPACButton
                } else if case .neverDone = status {
                    startPACButton
                }
            }
            pacGuideLink
            Text("PAC days in the last 4 weeks: \(consistency.done) of \(consistency.planned) planned")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("PAC · every other day")
        }
    }

    private var startPACButton: some View {
        Button("Start") { Task { await vault.startInterval(name: "PAC", steps: MTPlan.pacSteps) } }
            .buttonStyle(.borderedProminent).tint(.yellow)
            .disabled(vault.data.isBusy)
    }

    private var pacGuideLink: some View {
        NavigationLink { MTPACGuideView() } label: { Label("How to do PAC", systemImage: "book") }
    }

    private func pacTitle(_ status: MTPACStatus) -> String {
        switch status {
        case .neverDone: return "PAC due today"
        case .doneToday: return "PAC done today ✓"
        case .restDay: return "PAC rest day"
        case .due(let overdue): return overdue > 0 ? "PAC due (\(overdue) day\(overdue == 1 ? "" : "s") late)" : "PAC due today"
        }
    }

    private func pacDetail(_ status: MTPACStatus) -> String {
        switch status {
        case .neverDone: return "Start your every-other-day rhythm."
        case .doneToday(let next), .restDay(let next): return "Next PAC: \(next.formatted(.dateTime.weekday(.wide)))"
        case .due: return "Every other day keeps recovery in between."
        }
    }

    private var pacWarningText: String {
        switch MTPACSchedule.status(vault.data.sessions) {
        case .doneToday: return "You've already done PAC today."
        case .restDay: return "Today is a PAC rest day — you did PAC yesterday."
        default: return "Start PAC?"
        }
    }

    private var pacIsResting: Bool {
        guard !vault.data.settings.dailyRoutineOn else { return false }   // no PAC plan to break
        switch MTPACSchedule.status(vault.data.sessions) {
        case .doneToday, .restDay: return true
        default: return false
        }
    }

    private func requestStart(_ type: MTType) {
        if type == .pac && pacIsResting {
            pacWarningType = type
            return
        }
        startType = type
    }

    // MARK: Check-in

    private var checkInSection: some View {
        let today = vault.todaysCheckIn()
        return Section {
            HStack {
                Text("EQ")
                Spacer()
                ForEach(1...5, id: \.self) { value in
                    Button {
                        vault.checkIn(eq: value, morningWood: today?.morningWood)
                    } label: {
                        Text("\(value)")
                            .font(.headline)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(today?.eq == value ? Color.indigo : Color.gray.opacity(0.15)))
                            .foregroundStyle(today?.eq == value ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Morning wood")
                Spacer()
                Picker("Morning wood", selection: Binding(
                    get: { today?.morningWood },
                    set: { vault.checkIn(eq: today?.eq, morningWood: $0) }
                )) {
                    Text("–").tag(Bool?.none)
                    Text("Yes").tag(Bool?.some(true))
                    Text("No").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
        } header: {
            Text(today?.eq == nil ? "Today's check-in" : "Today's check-in ✓")
        } footer: {
            Text("1 = poor, 5 = excellent. A falling EQ trend is the earliest overtraining sign.")
        }
    }

    // MARK: All Day Stretcher

    private var stretcherSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wearing = vault.data.stretcherStartedAt
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(MTStats.clock(vault.stretcherToday(at: context.date)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("today").foregroundStyle(.secondary)
                    }
                    if let wearing {
                        HStack {
                            if let level = vault.data.stretcherLevel {
                                Text(level.title)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(level.color))
                                    .foregroundStyle(level == .yellow ? Color.black : Color.white)
                            }
                            Text("on for \(MTStats.clock(context.date.timeIntervalSince(wearing)))")
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    } else {
                        Text("Not wearing").foregroundStyle(.secondary)
                    }
                }
            }
            if vault.data.stretcherStartedAt == nil {
                Menu {
                    ForEach(MTLevel.allCases) { level in
                        Button(level.title) { vault.startStretcher(level: level) }
                    }
                } label: {
                    Label("Put on — choose level", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Menu {
                    ForEach(MTLevel.allCases) { level in
                        Button(level.title) { vault.changeStretcherLevel(level) }
                    }
                } label: {
                    Label("Change level", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    vault.pauseStretcher()
                } label: {
                    Label("Take off — pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        } header: {
            Text("All Day Stretcher · Phallosan Forte")
        }
    }

    // MARK: Total extended

    private var totalsSection: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let totals = MTStretcherTotals.compute(vault.data, now: context.date)
                let goal = vault.data.settings.dailyGoal
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total extended").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(String(format: "%.1f h", totals.lifetimeHours))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(String(format: "%.0f h before the app + %.1f h logged", vault.data.settings.baseHours, totals.appHours))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ZStack {
                            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 9)
                            Circle()
                                .trim(from: 0, to: min(1, totals.todayWeighted / max(goal, 0.1)))
                                .stroke(totals.todayWeighted >= goal ? Color.green : Color.indigo,
                                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text(String(format: "%.1f", totals.todayWeighted)).font(.headline).monospacedDigit()
                                Text(String(format: goal == goal.rounded() ? "of %.0f h" : "of %.1f h", goal)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 84, height: 84)
                    }

                    HStack {
                        totalStat("This week", String(format: "%.1f h", totals.weekHours))
                        totalStat("This month", String(format: "%.1f h", totals.monthHours))
                        totalStat("Goal streak", "\(totals.goalStreak) d")
                    }

                    if let next = totals.nextMilestone {
                        let previous = totals.reachedMilestones.last ?? 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("Next: \(Int(next)) h", systemImage: "flag.checkered")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(String(format: "%.0f h to go", next - totals.lifetimeHours))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            SwiftUI.ProgressView(value: totals.lifetimeHours - previous, total: next - previous)
                                .tint(.indigo)
                        }
                    }

                    if !totals.reachedMilestones.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(totals.reachedMilestones, id: \.self) { hours in
                                    Label("\(Int(hours)) h", systemImage: "medal.fill")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(Color.indigo.opacity(0.15)))
                                        .foregroundStyle(Color.indigo)
                                }
                            }
                        }
                    }

                    let levels = MTLevel.allCases.filter { (totals.byLevel[$0] ?? 0) > 0 }
                    if !levels.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(levels) { level in
                                HStack(spacing: 4) {
                                    Circle().fill(level.color).frame(width: 8, height: 8)
                                    Text(String(format: "%@ %.0f h", level.title, totals.byLevel[level] ?? 0))
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Phallosan totals")
        } footer: {
            Text("Daily goal counts Red hours ×3, High Green/Yellow ×1.5, Green ×1 — so 2 h Red, 4 h High Green/Yellow or 6 h Green each fill the ring.")
        }
    }

    private func totalStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Stamina

    private var staminaSection: some View {
        Section {
            NavigationLink {
                MTStaminaView()
            } label: {
                HStack {
                    Image(systemName: "timer").foregroundStyle(.blue).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vault.data.activeStamina == nil ? "Stamina training" : "Stamina — in progress")
                            .foregroundStyle(vault.data.activeStamina == nil ? Color.primary : Color.blue)
                        Text(staminaSubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var staminaSubtitle: String {
        let goal = "Goal \(vault.data.settings.staminaGoal) min"
        guard let last = vault.data.staminaList.max(by: { $0.start < $1.start }) else { return goal }
        return goal + " · last \(MTStats.clock(last.activeSeconds)), \(last.pauses) pause\(last.pauses == 1 ? "" : "s")"
    }

    // MARK: Running session (minimised)

    private var runningCard: some View {
        Section {
            Button {
                showSession = true
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack {
                        Image(systemName: runningType?.symbol ?? "timer")
                            .font(.title2)
                            .foregroundStyle(runningType == .pac ? Color.yellow : Color.indigo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(runningType?.title ?? "Session") in progress").font(.headline)
                            Text("Tap to open").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(runningClock(at: context.date))
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var runningType: MTType? {
        if let run = vault.data.activeInterval, let phase = run.currentPhase, phase.stepIndex < run.steps.count {
            return run.steps[phase.stepIndex].type
        }
        return vault.data.activeSession?.type
    }

    private func runningClock(at date: Date) -> String {
        if let run = vault.data.activeInterval { return MTStats.clock(run.remaining(at: date)) }
        if let active = vault.data.activeSession { return MTStats.clock(date.timeIntervalSince(active.start)) }
        return ""
    }

    // MARK: Presets & starting

    private var presetSection: some View {
        Section {
            ForEach(vault.data.presetList) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).font(.headline)
                        Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if preset.steps.contains(where: { $0.type == .pac }) && pacIsResting {
                            pacWarningPreset = preset
                        } else {
                            Task { await vault.startInterval(name: preset.name, steps: preset.steps) }
                        }
                    } label: {
                        Image(systemName: "play.circle.fill").font(.title)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.indigo)
                    .disabled(vault.data.isBusy)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { vault.deletePreset(preset.id) }
                    Button("Edit") { editingPreset = preset }.tint(.indigo)
                }
            }
            Button {
                editingPreset = MTPreset(name: "", steps: [
                    MTPresetStep(type: .pump, rounds: 3, workMinutes: 10, restMinutes: 2, pressureInHg: vault.data.lastPressure(for: .pump))
                ])
            } label: {
                Label("New preset", systemImage: "plus")
            }
        } header: {
            Text("Presets")
        } footer: {
            Text("Swipe a preset to edit or delete it.")
        }
    }

    private var startSection: some View {
        Section("Start a session") {
            ForEach(MTType.timed) { type in
                Button {
                    requestStart(type)
                } label: {
                    HStack {
                        Label(type.title, systemImage: type.symbol)
                        Spacer()
                        if let detail = setupText(pressure: vault.data.lastPressure(for: type), tension: vault.data.lastTension(for: type)) {
                            Text("last \(detail)").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "play.circle.fill")
                    }
                }
                .disabled(vault.data.isBusy)
            }
            Button {
                addingSession = true
            } label: {
                Label("Add a past session", systemImage: "plus")
            }
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        Section("Recent") {
            let recent = Array(vault.data.sessions.sorted { $0.start > $1.start }.prefix(30))
            if recent.isEmpty {
                Text("No sessions yet").foregroundStyle(.secondary)
            }
            ForEach(recent) { session in
                sessionRow(session)
                    .swipeActions {
                        Button("Delete", role: .destructive) { vault.deleteSession(session.id) }
                    }
            }
        }
    }

    private func sessionRow(_ session: MTSession) -> some View {
        HStack(alignment: .top) {
            Image(systemName: session.type.symbol)
                .foregroundStyle(session.level?.color ?? (session.type == .pac ? Color.yellow : Color.indigo))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.type.title)
                    if let level = session.level {
                        Text(level.title).font(.caption2.bold()).foregroundStyle(level.color)
                    }
                    if !session.warningList.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(sessionDetail(session)).font(.caption).foregroundStyle(.secondary)
                if let notes = session.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(MTStats.formatDuration(session.duration)).monospacedDigit()
        }
    }

    private func sessionDetail(_ session: MTSession) -> String {
        var parts = [session.start.formatted(date: .abbreviated, time: .shortened)]
        if let rounds = session.rounds, rounds > 1 { parts.append("\(rounds) rounds") }
        if let setup = setupText(pressure: session.pressureInHg, tension: session.tensionKg) { parts.append(setup) }
        if !session.warningList.isEmpty { parts.append(session.warningList.map(\.title).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func setupText(pressure: Double?, tension: Double?) -> String? {
        if let pressure { return String(format: "%.1f inHg", pressure) }
        if let tension {
            let unit = vault.data.settings.weightUnit
            return String(format: "%.1f %@", unit.display(tension), unit.rawValue)
        }
        return nil
    }
}

/// Monday–Sunday: green ✓ trained, yellow ✓ trained with PAC, white = not yet, yellow outline = PAC planned.
struct MTWeekRow: View {
    @EnvironmentObject private var vault: MTVault
    @Binding var selectedDay: Date?

    var body: some View {
        let calendar = Calendar.current
        let days = MTStats.mondayWeek(containing: .now)
        let sessions = vault.data.sessions
        let trained = Set(sessions.map { calendar.startOfDay(for: $0.start) })
            .union(vault.data.stretcherStartedAt != nil ? [calendar.startOfDay(for: .now)] : [])
        let pacDays = Set(sessions.filter { $0.type == .pac }.map { calendar.startOfDay(for: $0.start) })
        let planned: Set<Date> = vault.data.settings.dailyRoutineOn ? [] : MTPACSchedule.plannedDays(sessions, through: days.last ?? .now)
        let staminaDays = Set(vault.data.staminaList.map { calendar.startOfDay(for: $0.start) })
        let restDays = Set(vault.data.restDayList.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: .now)
        let letters = ["M", "T", "W", "T", "F", "S", "S"]

        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isPAC = pacDays.contains(day)
                let isTrained = trained.contains(day)
                let isPlanned = planned.contains(day) && !isPAC
                let isToday = day == today
                let isRest = restDays.contains(day) && !isTrained && !isPAC
                let isMissed = day < today && !isTrained && !isPAC && !isRest && !staminaDays.contains(day)
                Button {
                    selectedDay = (selectedDay == day) ? nil : day
                } label: {
                    VStack(spacing: 4) {
                        Text(letters[index])
                            .font(.caption2.bold())
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                        ZStack {
                            Circle()
                                .fill(isPAC ? Color.yellow : (isTrained ? Color.green : (isMissed ? Color.red : (isRest ? Color.gray : Color.white))))
                            Circle()
                                .stroke(isPlanned ? Color.yellow : (isTrained || isPAC || isMissed || isRest ? Color.clear : Color.gray.opacity(0.35)),
                                        lineWidth: isPlanned ? 3 : 1)
                            if isPAC || isTrained {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(isPAC ? Color.black : Color.white)
                            } else if isMissed {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.white)
                            } else if isRest {
                                Image(systemName: "moon.zzz.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(selectedDay == day ? Color.indigo : Color.clear, lineWidth: 2)
                                .padding(-4)
                        )
                        Text("\(calendar.component(.day, from: day))")
                            .font(.caption2)
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(isToday ? Color.indigo : Color.secondary)
                        Circle()
                            .fill(staminaDays.contains(day) ? Color.blue : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - PAC guide (MK18.2, Karl's "The Power of PAC")

struct MTPACGuideView: View {
    var body: some View {
        List {
            Section("What it is") {
                Text("A pump cylinder sits on top of an inflatable clamp (Python or Fenrir) around the base, so you hold vacuum and clamp pressure at the same time — with less clamp force than other clamping.")
            }
            Section {
                row("1. Set up", "Clamp on the base, not inflated. Get semi-erect.")
                row("2. Fill up · 2 min", "Vacuum −7 to −8 inHg (−24 to −27 kPa), clamp off.")
                row("3. Clamp set 1 · 5 min", "Vacuum \(MTPlan.both(8, "−")), clamp \(MTPlan.both(8, "+")). Release when the electric pump stops kicking in.")
                row("4. Fresh blood · 3 min", "Clamp released. RIP up to \(MTPlan.both(12, "−")) or more, dropping near zero.")
                row("5. Clamp set 2 · 5 min", "Vacuum \(MTPlan.both(9, "−")), clamp \(MTPlan.both(10, "+")). Repeat steps 4–5 if you like.")
                row("6. Final set · 10 min", "Vacuum \(MTPlan.both(10, "−")), clamp \(MTPlan.both(12, "+")).")
            } header: {
                Text("The routine · ~30 min under pressure")
            } footer: {
                Text("Start runs steps 2–6 as a timer (25 min). The longer final hold briefly starves the tissue of oxygen (mild hypoxia), which is meant to trigger VEGF, a growth factor that helps blood vessels grow. Stopping at 20–25 min because of skin discomfort is fine.")
            }
            Section("Gear") {
                bullet("Seal: a silicone toe shield as the gasket works better than the Python's standard rubber one.")
                bullet("+12 inHg on the clamp gauge isn't +12 inside the penis — it depends on your size and the clamp's sleeve. Go by feel and dial it in for your own gear.")
            }
            Section("Safety and limits") {
                bullet("Hard on the small blood vessels: expect redness and red dots (petechiae). A lotion with aloe vera and vitamin E helps.")
                bullet("The stretch should feel deep but never painful. Tingling is never a good sign — stop.")
                bullet("For people already comfortable with pumping and clamping. Still the most beginner-friendly clamping: you don't need to stay hard and you use less clamp force.")
                bullet("No more than 3–4 times a week. On PAC days, RIP or milking later in the day. Monday to Friday with weekends off also works.")
                bullet("PAC can boost erection quality. If erections are weak for a few hours afterwards, the session was too intense — dial it back.")
            }
            Section("Tips") {
                bullet("Don't start fully erect — a rock-hard penis doesn't expand well. Start semi-erect and let the vacuum fill you up.")
                bullet("An 850 nm infrared heat pad around the cylinder, or bundled stretches beforehand, makes the tissue more pliable.")
                bullet("Clamp sets don't have to be 5+ minutes: short pulse-clamping works well, and each pulse draws in fresh blood.")
                bullet("Keep the vacuum on while clamping. Using the pump only to fill up misses the point — the vacuum is what lets you use less clamp force and puts less pressure on the nerves at the base.")
            }
        }
        .navigationTitle("PAC")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.subheadline)
        }
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(.subheadline)
    }
}
