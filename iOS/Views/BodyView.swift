import SwiftUI
import Charts

struct BodyView: View {
    @EnvironmentObject private var store: PhoneAppStore
    /// Touched date on each chart (keyed by chart title); nil when not touching.
    @State private var selections: [String: Date] = [:]
    @State private var range: ChartRange = .threeMonths

    var body: some View {
        let weights = store.healthKit.bodyWeight
        let fats = store.healthKit.bodyFat
        let lean = BodyTrendCalculator.leanMass(weights: weights, fats: fats)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                metricSection(title: "Body weight", suffix: "kg", points: weights)
                metricSection(title: "Body fat", suffix: "%", points: fats)
                metricSection(title: "Lean mass (estimate)", suffix: "kg", points: lean)

                TapeMeasurementsSection()

                Text("Read from Apple Health, so your Xiaomi scale (or any scale) only needs to sync to Health. Trends use a 7-day average so one reading doesn't swing things. Lean mass = weight × (1 − body fat %).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let error = store.healthKit.authorizationError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle("Body")
        .refreshable { await store.healthKit.refreshBodyMetrics() }
        .task {
            if store.healthKit.bodyWeight.isEmpty { await store.healthKit.refreshBodyMetrics() }
        }
    }

    @ViewBuilder
    private func metricSection(title: String, suffix: String, points: [BodyMetricPoint]) -> some View {
        let visible = points.filter { range.includes($0.date) }
        let trend = BodyTrendCalculator.rollingAverage(points).filter { range.includes($0.date) }
        let weekly = BodyTrendCalculator.weeklyChange(points)
        let selected: BodyMetricPoint? = selections[title].flatMap { date in
            visible.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        let selectedTrend: BodyMetricPoint? = selected.flatMap { point in trend.first { $0.date == point.date } }

        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
            if let selected {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(selected.value, specifier: "%.1f") \(suffix)").font(.largeTitle.bold())
                    Text(selected.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                }
            } else if let average = BodyTrendCalculator.recentAverage(points) ?? points.last?.value {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(average, specifier: "%.1f") \(suffix)").font(.largeTitle.bold())
                    Text("7-day avg").foregroundStyle(.secondary)
                }
            }
            if let weekly {
                Text("Trend: \(GFFormat.signed(weekly, decimals: 2)) \(suffix)/week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if visible.isEmpty {
                Text("No Apple Health data in this range.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart {
                    ForEach(visible) { point in
                        PointMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .foregroundStyle(.gray.opacity(0.45))
                            .symbolSize(18)
                    }
                    ForEach(trend) { point in
                        LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .interpolationMethod(.monotone)
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 4,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 2) {
                                    Text("\(selected.value, specifier: "%.1f") \(suffix)")
                                        .font(.headline)
                                    if let selectedTrend {
                                        Text("7-day avg \(selectedTrend.value, specifier: "%.1f")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(selected.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.secondarySystemBackground))
                                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                )
                            }
                        PointMark(x: .value("Date", selected.date), y: .value(title, selected.value))
                            .symbolSize(90)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXSelection(value: Binding(
                    get: { selections[title] },
                    set: { selections[title] = $0 }
                ))
                .frame(height: 220)
                Text("Touch and drag along the graph to see each reading.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
