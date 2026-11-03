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
}

private enum ProgressMetric: String, CaseIterable, Identifiable {
    case weight = "Working weight"
    case reps = "Reps at top weight"
    case bestSet = "Best set volume"
    case totalReps = "Total reps"
    case volume = "Total volume"
    case oneRepMax = "Estimated 1RM"
    case duration = "Duration (min)"
    case distance = "Distance (km)"
    var id: String { rawValue }

    var isCardio: Bool { self == .duration || self == .distance }
    static var strength: [ProgressMetric] { allCases.filter { !$0.isCardio } }
    static var cardio: [ProgressMetric] { [.duration, .distance] }

    var unit: String {
        switch self {
        case .weight, .bestSet, .volume, .oneRepMax: return "kg"
        case .reps, .totalReps: return "reps"
        case .duration: return "min"
        case .distance: return "km"
        }
    }

    func value(_ log: ExerciseLog) -> Double {
        switch self {
        case .weight: return log.isAssisted ? (log.leastAssistanceKg ?? 0) : log.bestWeightKg
        case .reps: return Double(log.repsAtBestWeight)
        case .bestSet: return log.sets.map(\.volumeKg).max() ?? 0
        case .totalReps: return Double(log.totalReps)
        case .volume: return log.volumeKg
        case .oneRepMax: return log.estimatedOneRepMaxKg
        case .duration: return log.totalDurationSeconds / 60
        case .distance: return log.totalDistanceKm
        }
    }
}

private struct ChartMarker: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let isRangeChange: Bool
}

/// Named ExerciseProgressView so it doesn't shadow SwiftUI.ProgressView.
struct ExerciseProgressView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var selectedKey: String?
    @State private var metric: ProgressMetric = .oneRepMax
    @State private var range: ChartRange = .threeMonths
    @State private var mode: Mode = .exercises

    private enum Mode: String, CaseIterable, Identifiable {
        case exercises = "Exercises", muscles = "Muscles", standards = "Standards", year = "Year"
        var id: String { rawValue }
    }

    var body: some View {
        let exercises = store.progressExercises
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .muscles {
                    MuscleVolumeSection()
                } else if mode == .standards {
                    StrengthStandardsView()
                } else if mode == .year {
                    YearHeatmapView()
                } else if exercises.isEmpty {
                    ContentUnavailableView("No exercises yet", systemImage: "chart.xyaxis.line", description: Text("Create a routine first."))
                } else {
                    Picker("Exercise", selection: Binding(
                        get: { selectedKey ?? exercises.first?.historyKey ?? "" },
                        set: { selectedKey = $0 }
                    )) {
                        ForEach(exercises) { exercise in
                            Text(exercise.name).tag(exercise.historyKey)
                        }
                    }
                    .pickerStyle(.menu)

                    let key = selectedKey ?? exercises.first?.historyKey ?? ""
                    let selected = exercises.first(where: { $0.historyKey == key })
                    let isCardio = selected?.isCardio ?? false
                    Picker("Metric", selection: Binding(
                        get: { effectiveMetric(isCardio: isCardio) },
                        set: { metric = $0 }
                    )) {
                        ForEach(isCardio ? ProgressMetric.cardio : ProgressMetric.strength) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)

                    Picker("Range", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let exercise = selected {
                        exerciseSection(exercise)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Progress")
    }

    private func effectiveMetric(isCardio: Bool) -> ProgressMetric {
        if isCardio { return metric.isCardio ? metric : .duration }
        return metric.isCardio ? .oneRepMax : metric
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: ExerciseDefinition) -> some View {
        // Assisted: 1RM doesn't apply — show the assistance used (lower = stronger).
        let metric = exercise.isAssisted && effectiveMetric(isCardio: false) == .oneRepMax ? .weight : effectiveMetric(isCardio: exercise.isCardio)
        let allHistory = store.history(for: exercise)
        let history = allHistory.filter { range.includes($0.date) }
        let prs = personalRecords(allHistory).filter { range.includes($0.date) }
        let markers = changeMarkers(allHistory).filter { range.includes($0.date) }

        if history.isEmpty {
            ContentUnavailableView("No data in this range", systemImage: "figure.strengthtraining.traditional", description: Text("Complete \(exercise.name) and your graph will appear here."))
        } else {
            Chart {
                ForEach(history) { point in
                    LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                }
                ForEach(prs) { point in
                    PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, metric.value(point.log)))
                        .symbol(.diamond)
                        .symbolSize(110)
                        .foregroundStyle(.orange)
                }
                ForEach(markers) { marker in
                    RuleMark(x: .value("Date", marker.date))
                        .foregroundStyle(marker.isRangeChange ? Color.purple.opacity(0.5) : Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(marker.label).font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 260)

            HStack(spacing: 14) {
                Label("PR", systemImage: "diamond.fill").foregroundStyle(.orange)
                Label(exercise.isAssisted ? "Less assistance" : "Weight increase", systemImage: "line.diagonal").foregroundStyle(.green)
                Label("Rep-range change", systemImage: "line.diagonal").foregroundStyle(.purple)
            }
            .font(.caption2)

            if exercise.isAssisted,
               let best = allHistory.filter({ $0.log.leastAssistanceKg != nil })
                .min(by: { ($0.log.leastAssistanceKg ?? 0) < ($1.log.leastAssistanceKg ?? 0) }),
               let kg = best.log.leastAssistanceKg {
                let reps = best.log.sets.filter { $0.reps > 0 && abs($0.weightKg - kg) < 0.001 }.map(\.reps).max() ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal best").font(.headline)
                    Text("Least assistance: \(GFFormat.kg(kg)) kg × \(reps) on \(best.date.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
                .card()
            } else if !exercise.isCardio,
               let best = allHistory.max(by: { $0.log.estimatedOneRepMaxKg < $1.log.estimatedOneRepMaxKg }),
               let bestSet = best.log.bestSet {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal best").font(.headline)
                    Text("\(GFFormat.kg(bestSet.weightKg)) kg × \(bestSet.reps) on \(best.date.formatted(date: .abbreviated, time: .omitted)) · est. 1RM \(GFFormat.kg(best.log.estimatedOneRepMaxKg.rounded())) kg")
                        .foregroundStyle(.secondary)
                }
                .card()
            }
        }

        let recommendation = ProgressionEngine.recommendation(for: exercise, previous: allHistory.last?.log)
        VStack(alignment: .leading, spacing: 6) {
            Text(recommendation.title).font(.headline)
            Text(recommendation.message).foregroundStyle(.secondary)
        }
        .card()

        if !allHistory.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent sessions").font(.headline)
                ForEach(Array(allHistory.suffix(6).reversed())) { point in
                    HStack(alignment: .top) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .frame(width: 90, alignment: .leading)
                        Text(point.log.sets.map(\.summaryText).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .card()
        }
    }

    /// Sessions where estimated 1RM beat every earlier session (assisted: least assistance ever).
    private func personalRecords(_ history: [ExerciseHistoryPoint]) -> [ExerciseHistoryPoint] {
        if history.first?.log.isAssisted == true {
            var least = Double.infinity
            var result: [ExerciseHistoryPoint] = []
            for (index, point) in history.enumerated() {
                guard let value = point.log.leastAssistanceKg else { continue }
                if value < least - 0.001 {
                    if index > 0 && least < .infinity { result.append(point) }
                    least = value
                }
            }
            return result
        }
        var best = 0.0
        var result: [ExerciseHistoryPoint] = []
        for (index, point) in history.enumerated() {
            let value = point.log.estimatedOneRepMaxKg
            if value > best + 0.001 {
                if index > 0 { result.append(point) }
                best = value
            }
        }
        return result
    }

    private func changeMarkers(_ history: [ExerciseHistoryPoint]) -> [ChartMarker] {
        var markers: [ChartMarker] = []
        for (previous, current) in zip(history, history.dropFirst()) {
            if current.log.isAssisted {
                // Assisted: progress is LESS help.
                if let now = current.log.leastAssistanceKg, let before = previous.log.leastAssistanceKg, now < before - 0.001 {
                    markers.append(ChartMarker(date: current.date, label: "\(GFFormat.kg(now))", isRangeChange: false))
                }
            } else if current.log.bestWeightKg > previous.log.bestWeightKg + 0.001 {
                markers.append(ChartMarker(date: current.date, label: "\(GFFormat.kg(current.log.bestWeightKg))", isRangeChange: false))
            }
            if current.log.repMinAtTime != previous.log.repMinAtTime || current.log.repMaxAtTime != previous.log.repMaxAtTime {
                markers.append(ChartMarker(date: current.date, label: "\(current.log.repMinAtTime)–\(current.log.repMaxAtTime)", isRangeChange: true))
            }
        }
        return markers
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
