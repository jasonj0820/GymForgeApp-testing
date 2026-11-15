import AudioToolbox
import Charts
import SwiftUI

// MARK: - MK24 (I): basketball hub

struct BasketballHubView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var loggingDrill = false
    @State private var addingJump = false
    @State private var editingGame: GameStats?

    var body: some View {
        let hoops = store.extras.hoops
        List {
            Section {
                NavigationLink { ShotChartView(sessionID: nil) } label: {
                    Label("Shot chart", systemImage: "circle.dotted.and.circle")
                }
                NavigationLink { DrillTimerView() } label: {
                    Label("Drill interval timer", systemImage: "timer")
                }
            }
            Section {
                ForEach(hoops.drills) { drill in
                    let logs = hoops.drillLogs.filter { $0.drillID == drill.id }.sorted { $0.date < $1.date }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(drill.name)
                            if let last = logs.last {
                                Text("Last: \(last.makes)/\(last.attempts) (\(Int(last.percent))%)" + (logs.count >= 2 ? " · best \(Int(logs.map(\.percent).max() ?? 0))%" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if logs.count >= 2 {
                            Chart(logs.suffix(10)) { LineMark(x: .value("Date", $0.date), y: .value("%", $0.percent)) }
                                .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: 0...100)
                                .frame(width: 60, height: 26)
                        }
                    }
                }
                Button { loggingDrill = true } label: { Label("Log a drill", systemImage: "plus") }
            } header: {
                Text("Drills")
            }
            Section {
                if hoops.jumps.count >= 2 {
                    Chart(hoops.jumps) { jump in
                        LineMark(x: .value("Date", jump.date), y: .value("cm", jump.cm), series: .value("Kind", jump.running ? "Running" : "Standing"))
                            .foregroundStyle(by: .value("Kind", jump.running ? "Running" : "Standing"))
                        PointMark(x: .value("Date", jump.date), y: .value("cm", jump.cm))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 150)
                }
                ForEach(hoops.jumps.suffix(5).reversed()) { jump in
                    HStack {
                        Text(jump.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(GFNumber.text(jump.cm)) cm" + (jump.running ? " (running)" : ""))
                    }
                    .font(.subheadline)
                    .swipeActions { Button("Delete", role: .destructive) { store.deleteJump(jump.id) } }
                }
                Button { addingJump = true } label: { Label("Log a jump", systemImage: "arrow.up.to.line") }
            } header: {
                Text("Vertical jump")
            } footer: {
                Text("Jump-and-reach against a wall: standing reach to the highest mark. Best of three.")
            }
            Section {
                if let avg = GameAverages.make(hoops.games) {
                    Text(String(format: "%.1f pts · %.1f reb · %.1f ast", avg.points, avg.rebounds, avg.assists)
                         + (avg.fgPercent.map { String(format: " · FG %.0f%%", $0) } ?? "")
                         + (avg.threePercent.map { String(format: " · 3P %.0f%%", $0) } ?? ""))
                        .font(.subheadline.weight(.semibold))
                    Text("Over \(avg.games) game\(avg.games == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(hoops.games) { game in
                    Button { editingGame = game } label: {
                        HStack {
                            Text(game.date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(game.points) pts · \(game.rebounds) reb · \(game.assists) ast").foregroundStyle(.primary)
                        }
                        .font(.subheadline)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { store.deleteGame(game.id) } }
                }
                Button { editingGame = GameStats() } label: { Label("Add game stats", systemImage: "plus") }
            } header: {
                Text("Games")
            }
        }
        .navigationTitle("Basketball")
        .sheet(isPresented: $loggingDrill) { DrillLogSheet().environmentObject(store) }
        .sheet(isPresented: $addingJump) { JumpSheet().environmentObject(store) }
        .sheet(item: $editingGame) { game in GameStatsEditor(game: game).environmentObject(store) }
    }
}

// MARK: Shot chart (137)

struct ShotChartView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let sessionID: UUID?
    @State private var making = true
    @State private var range = 0   // 0 = this session / today, 1 = 30 days, 2 = all

    private var shown: [Shot] {
        let all = store.extras.hoops.shots
        switch range {
        case 0:
            if let sessionID { return all.filter { $0.sessionID == sessionID } }
            return all.filter { Calendar.current.isDateInToday($0.date) }
        case 1: return all.filter { $0.date > Date.now.addingTimeInterval(-30 * 86_400) }
        default: return all
        }
    }

    var body: some View {
        let shots = shown
        ScrollView {
            VStack(spacing: 14) {
                Picker("Shots", selection: $range) {
                    Text(sessionID == nil ? "Today" : "This session").tag(0)
                    Text("30 days").tag(1)
                    Text("All").tag(2)
                }
                .pickerStyle(.segmented)
                CourtView(shots: shots) { x, y in
                    store.addShot(Shot(sessionID: sessionID, x: x, y: y, made: making))
                    if making { Haptics.success() } else { Haptics.tap() }
                }
                .aspectRatio(CourtZone.width / CourtZone.halfLength, contentMode: .fit)
                HStack {
                    Picker("Tap logs a", selection: $making) {
                        Text("Make").tag(true)
                        Text("Miss").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Button { store.undoShot() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(store.extras.hoops.shots.isEmpty)
                }
                let made = shots.filter(\.made).count
                Text(shots.isEmpty ? "Tap the court where you shot from." : "\(made) of \(shots.count) (\(Int(Double(made) / Double(shots.count) * 100))%)")
                    .font(.headline)
                VStack(spacing: 6) {
                    ForEach(ShotStats.byZone(shots), id: \.zone) { zone in
                        HStack {
                            Text(zone.zone.title)
                            Spacer()
                            Text(zone.attempts == 0 ? "–" : "\(zone.made)/\(zone.attempts) · \(Int(Double(zone.made) / Double(zone.attempts) * 100))%")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .card()
            }
            .padding()
        }
        .navigationTitle("Shot chart")
    }
}

/// A FIBA half court, baseline at the top. Tap to place a shot.
struct CourtView: View {
    let shots: [Shot]
    let onTap: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / CourtZone.width
            func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x + CourtZone.width / 2) * scale, y: y * scale) }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12))
                Path { p in
                    // Key, free-throw circle, 3-point line, hoop.
                    p.addRect(CGRect(x: point(-2.45, 0).x, y: 0, width: 4.9 * scale, height: 5.8 * scale))
                    p.addEllipse(in: CGRect(x: point(-1.8, 0).x, y: (5.8 - 1.8) * scale, width: 3.6 * scale, height: 3.6 * scale))
                    p.move(to: point(-6.6, 0)); p.addLine(to: point(-6.6, 2.99))
                    p.move(to: point(6.6, 0)); p.addLine(to: point(6.6, 2.99))
                    let corner = acos(6.6 / 6.75)
                    p.addArc(center: point(0, CourtZone.hoopY), radius: 6.75 * scale,
                             startAngle: .radians(corner), endAngle: .radians(.pi - corner), clockwise: false)
                    p.addEllipse(in: CGRect(x: point(-0.225, 0).x, y: (CourtZone.hoopY - 0.225) * scale, width: 0.45 * scale, height: 0.45 * scale))
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                }
                .stroke(Color.orange.opacity(0.7), lineWidth: 1.5)
                ForEach(shots) { shot in
                    Image(systemName: shot.made ? "circle.fill" : "xmark")
                        .font(.system(size: shot.made ? 10 : 11, weight: .bold))
                        .foregroundStyle(shot.made ? Color.green : Color.red)
                        .position(point(shot.x, shot.y))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let x = location.x / scale - CourtZone.width / 2
                let y = location.y / scale
                guard y >= 0, y <= CourtZone.halfLength else { return }
                onTap(x, y)
            }
        }
    }
}

// MARK: Drills (138)

struct DrillLogSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var drillID: UUID?
    @State private var makes = 7
    @State private var attempts = 10
    @State private var newDrill = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Drill", selection: $drillID) {
                    ForEach(store.extras.hoops.drills) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Stepper("Makes: \(makes)", value: $makes, in: 0...max(attempts, 0))
                Stepper("Attempts: \(attempts)", value: $attempts, in: 1...500)
                Section("New drill") {
                    HStack {
                        TextField("Name", text: $newDrill)
                        Button("Add") { store.addDrill(named: newDrill); newDrill = ""; drillID = store.extras.hoops.drills.last?.id }
                            .disabled(newDrill.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Log a drill")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let drillID { store.logDrill(DrillLog(drillID: drillID, makes: min(makes, attempts), attempts: attempts)) }
                        dismiss()
                    }
                    .disabled(drillID == nil)
                }
            }
            .onAppear { drillID = drillID ?? store.extras.hoops.drills.first?.id }
            .onChange(of: attempts) { _, value in makes = min(makes, value) }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: Interval timer (139)

struct DrillTimerView: View {
    @AppStorage("drill.work") private var work = 30
    @AppStorage("drill.rest") private var rest = 30
    @AppStorage("drill.rounds") private var rounds = 10
    @State private var startedAt: Date?
    @State private var lastPhase = ""

    var body: some View {
        let plan = IntervalPlan(workSeconds: work, restSeconds: rest, rounds: rounds)
        VStack(spacing: 20) {
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 0.25)) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    if let phase = plan.phase(at: elapsed) {
                        VStack(spacing: 8) {
                            Text(phase.working ? "WORK" : "REST").font(.title.bold()).foregroundStyle(phase.working ? .green : .cyan)
                            Text("\(Int(phase.left.rounded(.up)))").font(.system(size: 120, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("Round \(phase.round) of \(plan.rounds)").font(.title3).foregroundStyle(.secondary)
                        }
                        .onChange(of: "\(phase.round)\(phase.working)") { _, key in cue(key, working: phase.working) }
                    } else {
                        Label("Done", systemImage: "checkmark.seal.fill").font(.largeTitle.bold()).foregroundStyle(.green)
                            .onAppear { cue("done", working: false) }
                    }
                }
                Button("Stop") { self.startedAt = nil }.buttonStyle(.bordered).controlSize(.large)
            } else {
                Form {
                    Stepper("Work: \(work) s", value: $work, in: 5...300, step: 5)
                    Stepper("Rest: \(rest) s", value: $rest, in: 0...300, step: 5)
                    Stepper("Rounds: \(rounds)", value: $rounds, in: 1...50)
                    Text("Total \(GFFormat.duration(Double(plan.totalSeconds)))").foregroundStyle(.secondary)
                }
                Button {
                    lastPhase = ""
                    startedAt = .now
                    cue("1true", working: true)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
        }
        .navigationTitle("Drill timer")
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func cue(_ key: String, working: Bool) {
        guard key != lastPhase else { return }
        lastPhase = key
        AudioServicesPlaySystemSound(working ? 1057 : 1052)
        if working { Haptics.heavy() } else { Haptics.success() }
    }
}

// MARK: Vertical jump (140) and game stats (141)

struct JumpSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var cm = ""
    @State private var running = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Jump (cm)", text: $cm).keyboardType(.decimalPad)
                Toggle("Running start", isOn: $running)
            }
            .navigationTitle("Vertical jump")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(cm.replacingOccurrences(of: ",", with: ".")), value > 0 { store.addJump(JumpEntry(cm: value, running: running)) }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct GameStatsEditor: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State var game: GameStats

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $game.date, displayedComponents: .date)
                Section("Box score") {
                    Stepper("Points: \(game.points)", value: $game.points, in: 0...200)
                    Stepper("Rebounds: \(game.rebounds)", value: $game.rebounds, in: 0...100)
                    Stepper("Assists: \(game.assists)", value: $game.assists, in: 0...100)
                    Stepper("Steals: \(game.steals)", value: $game.steals, in: 0...50)
                    Stepper("Blocks: \(game.blocks)", value: $game.blocks, in: 0...50)
                    Stepper("Turnovers: \(game.turnovers)", value: $game.turnovers, in: 0...50)
                }
                Section {
                    Stepper("FG: \(game.fgMade)/\(game.fgAttempts)", onIncrement: { game.fgMade += 1; game.fgAttempts += 1 },
                            onDecrement: { game.fgAttempts += 1 })
                    Stepper("3PT: \(game.threeMade)/\(game.threeAttempts)", onIncrement: {
                        game.threeMade += 1; game.threeAttempts += 1; game.fgMade += 1; game.fgAttempts += 1
                    }, onDecrement: { game.threeAttempts += 1; game.fgAttempts += 1 })
                    Stepper("FT: \(game.ftMade)/\(game.ftAttempts)", onIncrement: { game.ftMade += 1; game.ftAttempts += 1 },
                            onDecrement: { game.ftAttempts += 1 })
                    if game.pointsFromShots != game.points {
                        Button("Set points to \(game.pointsFromShots) from the shots") { game.points = game.pointsFromShots }
                    }
                    Button("Clear shots", role: .destructive) {
                        game.fgMade = 0; game.fgAttempts = 0; game.threeMade = 0; game.threeAttempts = 0; game.ftMade = 0; game.ftAttempts = 0
                    }
                } header: {
                    Text("Shooting")
                } footer: {
                    Text("+ is a make, − is a miss. 3s count toward field goals too.")
                }
            }
            .navigationTitle("Game stats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.saveGame(game); dismiss() } }
            }
        }
    }
}

// MARK: - Sleep debt and consistency (128)

struct SleepDebtCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let nights = store.sleepNightsAll
        let need = store.sleepNeed
        let debt = SleepMath.debt(nights, need: need)
        let spread = SleepMath.bedtimeSpread(nights)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sleep debt", systemImage: "bed.double.circle").font(.headline)
                Spacer()
                NavigationLink("Calendar") { SleepCalendarView() }.font(.subheadline)
            }
            if debt.nights == 0 {
                Text("No nights recorded in the last two weeks. Health, the Shortcuts bridge or the morning check-in fill this in.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(debt.hours < 0.5 ? "None: you're getting the \(GFNumber.text((need * 10).rounded() / 10)) h your schedule allows."
                     : String(format: "%.1f h short over %d nights", debt.hours, debt.nights))
                    .font(.title3.bold())
                    .foregroundStyle(debt.hours >= 5 ? Color.orange : Color.primary)
                if debt.hours >= 2 {
                    Text("Pay it back gradually: 30–60 minutes earlier to bed for a few nights beats one long lie-in.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let spread {
                Text("Bedtime varies by about ±\(Int(spread)) min" + (spread > 45 ? ". Steadier bedtimes help more than the odd early night." : "."))
                    .font(.subheadline)
                    .foregroundStyle(spread > 45 ? Color.orange : Color.secondary)
            }
        }
        .card()
    }
}

struct SleepCalendarView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let calendar = Calendar.current
        let nights = store.sleepNightsAll
        let need = store.sleepNeed
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let months = (0..<3).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(months, id: \.self) { month in
                    let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
                    let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
                    VStack(alignment: .leading, spacing: 6) {
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                            ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 34) }
                            ForEach(1...days, id: \.self) { day in
                                let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                                let night = nights.first { calendar.isDate($0.date, inSameDayAs: date) }
                                VStack(spacing: 0) {
                                    Text("\(day)").font(.caption2).foregroundStyle(.secondary)
                                    Text(night.map { String(format: "%.1f", $0.hoursAsleep) } ?? "").font(.caption2.bold().monospacedDigit())
                                }
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(color(night?.hoursAsleep, need: need), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                Text("Each day shows the night before it. Green: your full \(GFNumber.text((need * 10).rounded() / 10)) h; yellow: within an hour; orange: short.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Sleep calendar")
    }

    private func color(_ hours: Double?, need: Double) -> Color {
        guard let hours else { return Color.gray.opacity(0.08) }
        if hours >= need - 0.25 { return .green.opacity(0.35) }
        if hours >= need - 1 { return .yellow.opacity(0.35) }
        return .orange.opacity(0.4)
    }
}
