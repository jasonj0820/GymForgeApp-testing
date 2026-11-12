import SwiftUI
import Charts

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M", threeMonths = "3M", sixMonths = "6M", year = "1Y", all = "All"
    var id: String { rawValue }

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .month: return calendar.date(byAdding: .month, value: -1, to: .now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: .now)
        case .sixMonths: return calendar.date(byAdding: .month, value: -6, to: .now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }

    func includes(_ date: Date) -> Bool {
        guard let start = startDate else { return true }
        return date >= start
    }

    var title: String {
        switch self {
        case .month: return "Last month"
        case .threeMonths: return "Last 3 months"
        case .sixMonths: return "Last 6 months"
        case .year: return "Last year"
        case .all: return "All time"
        }
    }
}

// MARK: - Trends

/// MK21.1: one lift's direction over the chosen range — the thing the Progress tab is built around.
struct LiftTrend: Identifiable {
    enum Status { case up, holding, down, new, cardio }
    /// What "stronger" is measured in for this lift.
    enum Unit { case oneRepMax, assistance, reps, minutes }

    let exercise: ExerciseDefinition
    let unit: Unit
    /// One value per session in the range, oldest first (for the little line).
    let points: [Double]
    let latest: ExerciseHistoryPoint?
    /// + = better (for assisted lifts, less help), as a fraction. nil until there are 3 sessions in range.
    let change: Double?
    let status: Status
    var id: String { exercise.historyKey }

    var color: Color {
        switch status {
        case .up: return .green
        case .down: return .orange
        case .holding, .new, .cardio: return .secondary
        }
    }

    var changeText: String {
        guard let change else { return "–" }
        let percent = (change * 100).rounded()
        if abs(percent) < 1 { return "0%" }
        return String(format: "%+.0f%%", percent)
    }

    /// "106 kg × 12 · 6 days ago"
    var subtitle: String {
        guard let latest else { return "" }
        let when = latest.date.formatted(.relative(presentation: .named))
        return LiftTrends.bestText(latest.log, unit: unit) + " · " + when
    }
}

enum LiftTrends {
    static func unit(for exercise: ExerciseDefinition, history: [ExerciseHistoryPoint]) -> LiftTrend.Unit {
        if exercise.isCardio || (history.last?.log.isCardio ?? false) { return .minutes }
        if exercise.isAssisted { return .assistance }
        // Bodyweight lifts with no added load: count reps instead of an estimated max.
        if !history.isEmpty, history.allSatisfy({ $0.log.estimatedOneRepMaxKg <= 0 }) { return .reps }
        return .oneRepMax
    }

    static func score(_ log: ExerciseLog, unit: LiftTrend.Unit) -> Double {
        switch unit {
        case .oneRepMax: return log.estimatedOneRepMaxKg
        case .assistance: return log.leastAssistanceKg ?? 0
        case .reps: return Double(log.sets.map(\.reps).max() ?? 0)
        case .minutes: return log.totalDurationSeconds / 60
        }
    }

    /// The session's best, in words: "106 × 12", "20 kg help", "14 reps", "25 min".
    static func bestText(_ log: ExerciseLog, unit: LiftTrend.Unit) -> String {
        switch unit {
        case .oneRepMax: return log.bestSet.map { "\(GFFormat.kg($0.weightKg)) kg × \($0.reps)" } ?? "–"
        case .assistance: return log.leastAssistanceKg.map { "\(GFFormat.kg($0)) kg help" } ?? "–"
        case .reps: return "\(log.sets.map(\.reps).max() ?? 0) reps"
        case .minutes: return "\(Int((log.totalDurationSeconds / 60).rounded())) min"
        }
    }

    /// Start of the range against now. With 4+ sessions it's the average of the first two against the
    /// last two, so one great or awful day doesn't decide it. Deloads and tagged off-days are left out.
    static func make(_ exercise: ExerciseDefinition, history all: [ExerciseHistoryPoint], range: ChartRange,
                     atypical: Set<UUID>) -> LiftTrend {
        let unit = Self.unit(for: exercise, history: all)
        let inRange = all.filter { range.includes($0.date) }
        let values = inRange.filter { !atypical.contains($0.workoutID) }.map { score($0.log, unit: unit) }.filter { $0 > 0 }
        var change: Double?
        var status: LiftTrend.Status = unit == .minutes ? .cardio : .new
        if unit != .minutes, values.count >= 3 {
            let window = values.count >= 4 ? 2 : 1
            let start = values.prefix(window).reduce(0, +) / Double(window)
            let end = values.suffix(window).reduce(0, +) / Double(window)
            if start > 0 {
                let raw = (end - start) / start
                let better = unit == .assistance ? -raw : raw
                change = better
                status = better >= 0.025 ? .up : (better <= -0.025 ? .down : .holding)
            }
        }
        return LiftTrend(exercise: exercise, unit: unit, points: inRange.map { score($0.log, unit: unit) }.filter { $0 > 0 },
                         latest: all.last, change: change, status: status)
    }

    /// Sessions that set a new best (estimated 1RM above every earlier session).
    static func recordSessions(_ history: [ExerciseHistoryPoint]) -> Set<UUID> {
        var best = 0.0
        var result = Set<UUID>()
        for (index, point) in history.enumerated() {
            let value = point.log.estimatedOneRepMaxKg
            if value > best + 0.001 {
                if index > 0 { result.insert(point.workoutID) }
                best = value
            }
        }
        return result
    }
}

/// MK22.1: every exercise's history from one pass over the log. The Progress tab needs all of them at
/// once (and again on every keystroke in the search box); asking the store per exercise re-read the whole
/// log each time, which got slow with a long history.
struct LiftHistoryIndex {
    private typealias Entry = (point: ExerciseHistoryPoint, order: Int)
    private var byID: [UUID: [Entry]] = [:]
    private var byKey: [String: [Entry]] = [:]

    init(_ logs: [WorkoutLog]) {
        for workout in logs {
            var seenIDs = Set<UUID>()
            var seenKeys = Set<String>()
            for (order, log) in workout.exercises.enumerated() {
                let entry: Entry = (ExerciseHistoryPoint(workoutID: workout.id, date: workout.startedAt, log: log), order)
                if seenIDs.insert(log.exerciseID).inserted { byID[log.exerciseID, default: []].append(entry) }
                let key = ExerciseLog.key(for: log.exerciseName)
                if seenKeys.insert(key).inserted { byKey[key, default: []].append(entry) }
            }
        }
    }

    /// Same answer as `store.history(for:)`: per workout, the first log that matches the exercise by ID
    /// or by name, oldest first.
    func history(for exercise: ExerciseDefinition) -> [ExerciseHistoryPoint] {
        var first: [UUID: Entry] = [:]
        for entry in (byID[exercise.id] ?? []) + (byKey[exercise.historyKey] ?? []) {
            if let existing = first[entry.point.workoutID], existing.order <= entry.order { continue }
            first[entry.point.workoutID] = entry
        }
        return first.values.map { $0.point }.sorted { $0.date < $1.date }
    }
}

/// The little trend line on each row.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    /// Assisted lifts: less help is better, so the line is flipped to make "up" mean progress.
    var invert = false

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let low = values.min(), let high = values.max() {
                let span = high - low
                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        var level = span > 0.0001 ? CGFloat((value - low) / span) : 0.5
                        if invert { level = 1 - level }
                        let point = CGPoint(x: x, y: geo.size.height * (1 - level))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 54, height: 22)
    }
}

// MARK: - Progress tab

/// MK21.1: Progress, rebuilt around one question — are my lifts going up?
/// A summary for the range, every lift grouped by direction (tap one for its chart), recent records,
/// sets per muscle, and links to strength standards, the year view and workout history.
/// Named ExerciseProgressView so it doesn't shadow SwiftUI.ProgressView.
struct ExerciseProgressView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var range: ChartRange = .threeMonths
    @State private var search = ""

    private struct Record: Identifiable {
        let id: UUID
        let date: Date
        let name: String
        let text: String
    }

    var body: some View {
        let atypical = Set(store.workoutLogs.filter(\.isAtypical).map(\.id))
        let index = LiftHistoryIndex(store.workoutLogs)
        let trends = store.progressExercises
            .map { LiftTrends.make($0, history: index.history(for: $0), range: range, atypical: atypical) }
            .filter { $0.latest != nil }
        let query = search.trimmingCharacters(in: .whitespaces)
        let shown = query.isEmpty ? trends : trends.filter { $0.exercise.name.localizedCaseInsensitiveContains(query) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if trends.isEmpty {
                    ContentUnavailableView("Nothing to chart yet", systemImage: "chart.xyaxis.line",
                                           description: Text("Finish a workout and your lifts show up here."))
                } else {
                    if query.isEmpty { summary(trends) }
                    lifts(shown)
                    if query.isEmpty {
                        records
                        MuscleVolumeSection()
                        more
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Progress")
        .searchable(text: $search, prompt: "Find an exercise")
    }

    // MARK: Summary

    private func summary(_ trends: [LiftTrend]) -> some View {
        let up = trends.filter { $0.status == .up }.count
        let holding = trends.filter { $0.status == .holding }.count
        let down = trends.filter { $0.status == .down }.count
        let judged = up + holding + down
        let sessions = store.workoutLogs.filter { $0.countsAsTraining && range.includes($0.startedAt) }.count
        let recordCount = allRecords.count
        let top = trends.filter { $0.status == .up }.max { ($0.change ?? 0) < ($1.change ?? 0) }
        let headline = judged == 0
            ? "Not enough sessions in this range yet"
            : "\(up) of \(judged) lift\(judged == 1 ? "" : "s") \(up == 1 ? "is" : "are") going up"
        var facts = ["\(sessions) session\(sessions == 1 ? "" : "s")", "\(recordCount) record\(recordCount == 1 ? "" : "s")"]
        if let top { facts.append("biggest gain: \(top.exercise.name) \(top.changeText)") }
        return VStack(alignment: .leading, spacing: 12) {
            Text(range.title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(headline).font(.title2.bold())
            HStack(spacing: 8) {
                tile("Going up", up, "arrow.up.right", .green)
                tile("Holding", holding, "arrow.right", .gray)
                tile("Slipping", down, "arrow.down.right", .orange)
            }
            Text(facts.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if judged == 0 {
                Text("A lift needs 3 sessions in the range before it's called up, holding or slipping. Try a longer range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func tile(_ title: String, _ count: Int, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text("\(count)").font(.title.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Lifts

    @ViewBuilder
    private func lifts(_ trends: [LiftTrend]) -> some View {
        let up = trends.filter { $0.status == .up }.sorted { ($0.change ?? 0) > ($1.change ?? 0) }
        let down = trends.filter { $0.status == .down }.sorted { ($0.change ?? 0) < ($1.change ?? 0) }
        let holding = trends.filter { $0.status == .holding }.sorted { $0.exercise.name < $1.exercise.name }
        let fresh = trends.filter { $0.status == .new }
            .sorted { ($0.latest?.date ?? .distantPast) > ($1.latest?.date ?? .distantPast) }
        let cardio = trends.filter { $0.status == .cardio }.sorted { $0.exercise.name < $1.exercise.name }
        if trends.isEmpty {
            Text("No exercise matches that.").foregroundStyle(.secondary)
        }
        group("Going up", "arrow.up.right", .green, up)
        group("Slipping", "arrow.down.right", .orange, down)
        group("Holding", "arrow.right", .gray, holding)
        group("Too few sessions in this range", "hourglass", .gray, fresh)
        group("Cardio", "figure.run", .gray, cardio)
    }

    @ViewBuilder
    private func group(_ title: String, _ icon: String, _ color: Color, _ rows: [LiftTrend]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(color)
                    Spacer()
                    Text("\(rows.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                ForEach(rows) { trend in
                    Divider()
                    row(trend)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func row(_ trend: LiftTrend) -> some View {
        NavigationLink {
            LiftDetailView(exercise: trend.exercise, range: range)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trend.exercise.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(trend.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Sparkline(values: trend.points, color: trend.color, invert: trend.unit == .assistance)
                Text(trend.changeText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(trend.color)
                    .frame(width: 50, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Records

    /// Every session in the range that set a record on a lift, newest first (one line per lift per session).
    private var allRecords: [Record] {
        var rows: [Record] = []
        for workout in store.workoutLogs where range.includes(workout.startedAt) {
            for exercise in workout.exercises where exercise.hasPR {
                let best = exercise.sets.filter { $0.isPR == true }.max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }
                guard let best else { continue }
                rows.append(Record(id: best.id, date: workout.startedAt, name: exercise.exerciseName, text: exercise.summary(best)))
            }
        }
        return rows.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var records: some View {
        let rows = allRecords
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Records", systemImage: "trophy.fill").font(.headline)
                    Spacer()
                    Text("\(rows.count) in this range").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows.prefix(6)) { record in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(record.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(record.text).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }

    // MARK: More

    private var more: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ScrollView { StrengthStandardsView().padding() }.navigationTitle("Strength standards")
            } label: {
                moreRow("figure.strengthtraining.traditional", "Strength standards", "Your big lifts against body weight")
            }
            Divider()
            NavigationLink {
                ScrollView { YearHeatmapView().padding() }.navigationTitle("Year in training")
            } label: {
                moreRow("calendar", "Year in training", "Every session, day by day")
            }
            Divider()
            NavigationLink {
                HistoryView()
            } label: {
                moreRow("clock.arrow.circlepath", "Workout history", "Every workout you've logged")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func moreRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - One lift

/// What the chart can show for a lift.
private enum LiftMetric: String, CaseIterable, Identifiable {
    case strength = "Strength", topWeight = "Top weight", volume = "Volume"
    case assistance = "Help", bestReps = "Best set", totalReps = "Total reps"
    case minutes = "Minutes", distance = "Distance"
    var id: String { rawValue }

    static func options(for unit: LiftTrend.Unit) -> [LiftMetric] {
        switch unit {
        case .oneRepMax: return [.strength, .topWeight, .volume]
        case .assistance: return [.assistance, .totalReps]
        case .reps: return [.bestReps, .totalReps]
        case .minutes: return [.minutes, .distance]
        }
    }

    func value(_ log: ExerciseLog) -> Double {
        switch self {
        case .strength: return log.estimatedOneRepMaxKg
        case .topWeight: return log.bestWeightKg
        case .volume: return log.volumeKg
        case .assistance: return log.leastAssistanceKg ?? 0
        case .bestReps: return Double(log.sets.map(\.reps).max() ?? 0)
        case .totalReps: return Double(log.totalReps)
        case .minutes: return log.totalDurationSeconds / 60
        case .distance: return log.totalDistanceKm
        }
    }

    var caption: String {
        switch self {
        case .strength: return "Estimated one-rep max in kg, worked out from your best set each session."
        case .topWeight: return "The heaviest weight you used each session, in kg."
        case .volume: return "Weight × reps added up over the whole session, in kg."
        case .assistance: return "Least help used each session, in kg. Lower is stronger."
        case .bestReps: return "Most reps in one set each session."
        case .totalReps: return "All reps added up each session."
        case .minutes: return "Minutes each session."
        case .distance: return "Kilometres each session."
        }
    }
}

/// MK21.1: one lift — best ever, latest and the change, one chart, the coach's next step, recent sessions.
struct LiftDetailView: View {
    @EnvironmentObject private var store: PhoneAppStore
    let exercise: ExerciseDefinition
    @State private var range: ChartRange
    @State private var metric: LiftMetric?

    init(exercise: ExerciseDefinition, range: ChartRange) {
        self.exercise = exercise
        _range = State(initialValue: range)
    }

    var body: some View {
        let all = store.history(for: exercise)
        let unit = LiftTrends.unit(for: exercise, history: all)
        let options = LiftMetric.options(for: unit)
        let shown = metric.flatMap { options.contains($0) ? $0 : nil } ?? options[0]
        let atypical = Set(store.workoutLogs.filter(\.isAtypical).map(\.id))
        let trend = LiftTrends.make(exercise, history: all, range: range, atypical: atypical)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tiles(all, unit: unit, trend: trend)
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Show", selection: Binding(get: { shown }, set: { metric = $0 })) {
                    ForEach(options) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                chart(all.filter { range.includes($0.date) }, metric: shown,
                      records: records(all, unit: unit))
                nextStep
                recent(all)
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Sessions that get a diamond: a set flagged as a record when it was logged, or a new best estimated max.
    private func records(_ all: [ExerciseHistoryPoint], unit: LiftTrend.Unit) -> Set<UUID> {
        guard unit != .minutes else { return [] }
        var result = Set(all.filter { $0.log.hasPR }.map(\.workoutID))
        if unit == .oneRepMax { result.formUnion(LiftTrends.recordSessions(all)) }
        return result
    }

    private func tiles(_ all: [ExerciseHistoryPoint], unit: LiftTrend.Unit, trend: LiftTrend) -> some View {
        let scored = all.filter { LiftTrends.score($0.log, unit: unit) > 0 }
            .sorted { LiftTrends.score($0.log, unit: unit) < LiftTrends.score($1.log, unit: unit) }
        // Assisted: the best session is the one with the least help.
        let best: ExerciseHistoryPoint? = unit == .assistance ? scored.first : scored.last
        let latest = all.last
        return HStack(spacing: 8) {
            stat("Best ever", best.map { LiftTrends.bestText($0.log, unit: unit) } ?? "–",
                 best.map { $0.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) } ?? "")
            stat("Latest", latest.map { LiftTrends.bestText($0.log, unit: unit) } ?? "–",
                 latest.map { $0.date.formatted(.relative(presentation: .named)) } ?? "")
            stat("Change", trend.changeText, trend.change == nil ? "needs 3 sessions" : range.title.lowercased(), color: trend.color)
        }
    }

    private func stat(_ title: String, _ value: String, _ detail: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func chart(_ history: [ExerciseHistoryPoint], metric: LiftMetric, records: Set<UUID>) -> some View {
        let points = history.filter { metric.value($0.log) > 0 }
        VStack(alignment: .leading, spacing: 10) {
            if points.count < 2 {
                ContentUnavailableView(points.isEmpty ? "No sessions in this range" : "One session in this range",
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Pick a longer range, or log \(exercise.name) again and the line appears."))
                    .frame(height: 200)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                            .symbolSize(28)
                    }
                    ForEach(points.filter { records.contains($0.workoutID) }) { point in
                        PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                            .symbol(.diamond)
                            .symbolSize(110)
                            .foregroundStyle(.orange)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 240)
            }
            Text(metric.caption + (records.isEmpty ? "" : " Orange diamonds are records."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var nextStep: some View {
        let previous = store.previousLog(for: exercise)
        let recommendation = ProgressionEngine.recommendation(for: exercise, previous: previous)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Next session", systemImage: "arrow.forward.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            Text(recommendation.title).font(.headline)
            Text(recommendation.message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func recent(_ all: [ExerciseHistoryPoint]) -> some View {
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent sessions").font(.headline)
                ForEach(Array(all.suffix(8).reversed())) { point in
                    HStack(alignment: .top) {
                        Text(point.date.formatted(.dateTime.day().month(.abbreviated)))
                            .frame(width: 60, alignment: .leading)
                        Text(point.log.sets.map(\.summaryText).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// Weekly hard sets per muscle group: this week vs your 4-week average.
struct MuscleVolumeSection: View {
    @EnvironmentObject private var store: PhoneAppStore

    private struct Bar: Identifiable {
        let muscle: String
        let period: String
        let sets: Double
        var id: String { muscle + period }
    }

    var body: some View {
        let lookup = store.categoryLookup
        let now = Date()
        let lastWeek = MuscleVolume.sets(logs: store.workoutLogs, from: now.addingTimeInterval(-7 * 86_400), to: now, categoryLookup: lookup)
        let average = MuscleVolume.weeklyAverage(logs: store.workoutLogs, weeks: 4, now: now, categoryLookup: lookup)
        let muscles = ExerciseCategory.muscleGroups.filter { (lastWeek[$0] ?? 0) > 0 || (average[$0] ?? 0) > 0 }
        let bars = muscles.flatMap { muscle in
            [Bar(muscle: muscle.title, period: "Last 7 days", sets: Double(lastWeek[muscle] ?? 0)),
             Bar(muscle: muscle.title, period: "4-week avg", sets: average[muscle] ?? 0)]
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Sets per muscle group").font(.headline)
            if bars.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "square.stack.3d.up", description: Text("Log a workout to see weekly volume per muscle."))
            } else {
                Chart {
                    RuleMark(x: .value("Low", 10))
                        .foregroundStyle(Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    RuleMark(x: .value("High", 20))
                        .foregroundStyle(Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    ForEach(bars) { bar in
                        BarMark(x: .value("Sets", bar.sets), y: .value("Muscle", bar.muscle))
                            .foregroundStyle(by: .value("Period", bar.period))
                            .position(by: .value("Period", bar.period))
                    }
                }
                .chartForegroundStyleScale(["Last 7 days": Color.orange, "4-week avg": Color.gray.opacity(0.6)])
                .frame(height: CGFloat(muscles.count) * 44 + 40)

                Text("Dashed lines: 10–20 hard sets per muscle per week, a common range for muscle growth. Categories come from each exercise's setting in your routines.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(muscles) { muscle in
                    let value = average[muscle] ?? 0
                    if value < 6 {
                        Label("\(muscle.title) is averaging \(Int(value.rounded())) sets/week", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .card()
    }
}
