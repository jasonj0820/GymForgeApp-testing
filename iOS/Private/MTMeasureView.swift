import SwiftUI
import Charts

struct MTMeasureView: View {
    @EnvironmentObject private var vault: MTVault
    @State private var metric: MTMetric = .bpel
    @State private var adding = false
    @State private var expansionTrack: MTProgression.Track = .girth

    private var unit: MTUnit { vault.data.settings.unit }

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    var body: some View {
        let points: [Point] = vault.data.measurements.compactMap { m in
            m.value(metric).map { Point(id: m.id, date: m.date, value: unit.display($0)) }
        }

        List {
            // MK24.1: your short-term goal first.
            MTShortGoalSection()
            // MK10.1: first thing on the Measure tab.
            MTPreferredSizeSection()

            Section {
                Picker("Units", selection: Binding(
                    get: { vault.data.settings.unit },
                    set: { value in
                        var settings = vault.data.settings
                        settings.unit = value
                        vault.updateSettings(settings)
                    }
                )) {
                    ForEach(MTUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Measurement", selection: $metric) {
                    ForEach(MTMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(metric.detail).font(.caption).foregroundStyle(.secondary)

                if points.isEmpty {
                    Text("No \(metric.title) measurements yet.").foregroundStyle(.secondary)
                } else {
                    let trend = MTInsights.trend(points.map { (date: $0.date, value: $0.value) })
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value),
                                     series: .value("Series", "Measured"))
                            PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                        }
                        if let trend {
                            LineMark(x: .value("Date", trend.start.date), y: .value(metric.title, trend.start.value),
                                     series: .value("Series", "Trend"))
                                .foregroundStyle(Color.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            LineMark(x: .value("Date", trend.end.date), y: .value(metric.title, trend.end.value),
                                     series: .value("Series", "Trend"))
                                .foregroundStyle(Color.orange)
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    if let trend {
                        Label("Trend: \(trend.perMonth >= 0 ? "+" : "")\(format(trend.perMonth)) per month", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.footnote.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text("Trend line appears after 3 measurements spanning 2+ weeks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let first = points.first, let last = points.last {
                        HStack {
                            stat("Latest", format(last.value))
                            stat("Start", format(first.value))
                            stat("Change", (last.value - first.value >= 0 ? "+" : "") + format(last.value - first.value))
                        }
                    }
                }
            }

            // MK24.3: the after-session readings, as graphs.
            expansionSection

            MTGoalSection(metric: metric)
            MTComparisonSection(metric: metric)

            if metric == .bpel || metric == .nbpl,
               let gap = MTGoals.gapAdvice(vault.data, bodyFatPercent: MTVault.gymBodyFatPercent, unit: unit) {
                Section {
                    Label(gap, systemImage: "arrow.down.forward.and.arrow.up.backward")
                        .font(.subheadline)
                } header: {
                    Text("BP vs NBP")
                }
            }

            // Length plateaus (the tips are about length devices); girth and NBP views show the BPFSL check.
            if let stall = MTInsights.stall(metric == .bpel ? .bpel : .bpfsl, vault.data) {
                MTStallSection(stall: stall, unit: unit)
            }

            gainsSection

            Section {
                Button {
                    adding = true
                } label: {
                    Label("Add measurement", systemImage: "plus")
                }
                if vault.data.settings.reminderWeeks > 0 {
                    Label("Reminder every \(vault.data.settings.reminderWeeks) weeks", systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(vault.data.measurements.sorted { $0.date > $1.date }) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                        Text(summary(m)).font(.caption).foregroundStyle(.secondary)
                        if let notes = m.notes, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { vault.deleteMeasurement(m.id) }
                    }
                }
            } header: {
                Text("History")
            }
        }
        .navigationTitle("Measure")
        .sheet(isPresented: $adding) {
            NavigationStack { MTAddMeasurementView() }
                .environmentObject(vault)
        }
    }

    /// MK24.3: expansion straight after each session over time, girth (Pump / PAC) or stretch (extender), with the
    /// range you're aiming for shaded.
    @ViewBuilder
    private var expansionSection: some View {
        let tracks = MTProgression.Track.allCases.filter { !MTProgression.expansionSeries(vault.data, track: $0).isEmpty }
        if let fallback = tracks.first {
            let track = tracks.contains(expansionTrack) ? expansionTrack : fallback
            let series = MTProgression.expansionSeries(vault.data, track: track)
            let band = track.band
            let firstDate = series.first?.date ?? .now
            let lastDate = max(series.last?.date ?? .now, firstDate.addingTimeInterval(86_400))
            let trend = MTInsights.trend(series.map { (date: $0.date, value: $0.percent) })
            let inBand = series.filter { band.contains($0.percent) }.count
            Section {
                if tracks.count > 1 {
                    Picker("Expansion", selection: $expansionTrack) {
                        ForEach(tracks, id: \.self) { Text($0 == .girth ? "Girth" : "Stretch").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Chart {
                    RectangleMark(xStart: .value("From", firstDate), xEnd: .value("To", lastDate),
                                  yStart: .value("Low", band.lowerBound), yEnd: .value("High", band.upperBound))
                        .foregroundStyle(Color.green.opacity(0.15))
                    ForEach(series) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Expansion", point.percent),
                                 series: .value("Series", "Expansion"))
                        PointMark(x: .value("Date", point.date), y: .value("Expansion", point.percent))
                            .foregroundStyle(band.contains(point.percent) ? Color.green : Color.orange)
                    }
                    if let trend {
                        LineMark(x: .value("Date", trend.start.date), y: .value("Expansion", trend.start.value),
                                 series: .value("Series", "Trend"))
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        LineMark(x: .value("Date", trend.end.date), y: .value("Expansion", trend.end.value),
                                 series: .value("Series", "Trend"))
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .chartYAxisLabel("%")
                .frame(height: 200)
                HStack {
                    stat("Latest", series.last.map { String(format: "%.1f%%", $0.percent) } ?? "–")
                    stat("Last 2 weeks", MTProgression.averageExpansion(series).map { String(format: "%.1f%%", $0) } ?? "–")
                    stat("In range", "\(inBand) of \(series.count)")
                }
                if let trend {
                    Label(String(format: "Trend: %@%.1f%% per month", trend.perMonth >= 0 ? "+" : "", trend.perMonth),
                          systemImage: "chart.line.uptrend.xyaxis")
                        .font(.footnote.bold())
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Expansion after sessions")
            } footer: {
                Text(String(format: "Shaded: %.0f–%.0f%%, the range to aim for. ", band.lowerBound, band.upperBound)
                     + (track == .girth ? "Girth straight after Pump or PAC" : "Stretched length right after the extender")
                     + ", from the before and after numbers you type when a session ends.")
            }
        }
    }

    private struct MonthBar: Identifiable {
        let month: Date
        let value: Double
        var id: Date { month }
    }

    /// Hours trained per month next to how much the selected measurement changed that month.
    @ViewBuilder
    private var gainsSection: some View {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        let months: [Date] = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
        let measurements = vault.data.measurements.sorted { $0.date < $1.date }
        let hours: [MonthBar] = months.map { start in
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let total = vault.data.sessions.filter { $0.start >= start && $0.start < end }.reduce(0) { $0 + $1.duration }
            return MonthBar(month: start, value: total / 3600)
        }
        let changes: [MonthBar] = months.compactMap { start in
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            guard let atEnd = measurements.last(where: { $0.date < end && $0.value(metric) != nil })?.value(metric),
                  let atStart = measurements.last(where: { $0.date < start && $0.value(metric) != nil })?.value(metric),
                  measurements.contains(where: { $0.date >= start && $0.date < end && $0.value(metric) != nil }) else { return nil }
            return MonthBar(month: start, value: unit.display(atEnd - atStart))
        }

        if hours.contains(where: { $0.value > 0 }) {
            Section {
                Text("Hours trained per month").font(.subheadline.bold())
                Chart(hours) { bar in
                    BarMark(x: .value("Month", bar.month, unit: .month), y: .value("Hours", bar.value))
                        .foregroundStyle(Color.indigo.gradient)
                }
                .frame(height: 140)
                Text("\(metric.title) change per month (\(unit.label))").font(.subheadline.bold())
                if changes.isEmpty {
                    Text("Needs measurements in at least two different months.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(changes) { bar in
                        BarMark(x: .value("Month", bar.month, unit: .month), y: .value("Change", bar.value))
                            .foregroundStyle(bar.value >= 0 ? Color.green : Color.red)
                    }
                    .chartXScale(domain: (months.first ?? .now)...(calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? .now))
                    .frame(height: 140)
                }
            } header: {
                Text("Gains vs training")
            } footer: {
                Text("Measure under the same conditions each time — single readings are noisy, so look at the trend over months.")
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func format(_ value: Double) -> String {
        String(format: unit == .cm ? "%.1f cm" : "%.2f in", value)
    }

    private func summary(_ m: MTMeasurement) -> String {
        MTMetric.allCases.compactMap { metric in
            m.value(metric).map { "\(metric.title) \(format(unit.display($0)))" }
        }.joined(separator: " · ")
    }
}

struct MTAddMeasurementView: View {
    /// "16.1 16.3 16.2" (or "16,1 / 16,3") → their average; one number → itself.
    static func average(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".")
            .split(whereSeparator: { $0 == " " || $0 == "/" || $0 == ";" })
            .compactMap { Double($0) }
            .filter { $0 > 0 }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0, +) / Double(parts.count)
    }

    @EnvironmentObject private var vault: MTVault
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var values: [MTMetric: String] = [:]
    @State private var notes = ""

    private var unit: MTUnit { vault.data.settings.unit }

    var body: some View {
        Form {
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            Section {
                ForEach(MTMetric.allCases) { metric in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(metric.title)
                            Text(metric.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("–", text: Binding(
                            get: { values[metric] ?? "" },
                            set: { values[metric] = $0 }
                        ))
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                        Text(unit.label).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Fill in any you measured — the rest can stay empty. For accuracy, measure 3 times and type them with spaces (e.g. 16.1 16.3 16.2): the average is saved.")
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
            // MK24.3: every measurement counts (the 3-days-off rule and its "won't count" warning are gone).
            Section("Measure the same way every time") {
                Label("Same time of day, so readings line up", systemImage: "clock")
                Label("Same erection level — as full as you can, standing (a ring keeps it consistent)", systemImage: "figure.stand")
                Label("Every measurement counts toward the chart, the trend and the progress check", systemImage: "calendar")
                Label("Same tool: rigid ruler for length, soft tape for girth", systemImage: "ruler")
                Label("BP: pressed firmly to the bone · NBP: touching skin only", systemImage: "arrow.down.to.line")
            }
            .font(.caption)
        }
        .navigationTitle("New measurement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var measurement = MTMeasurement(date: date, notes: notes.isEmpty ? nil : notes)
                    for metric in MTMetric.allCases {
                        if let text = values[metric], let number = Self.average(text), number > 0 {
                            measurement.set(metric, unit.toCM(number))
                        }
                    }
                    vault.addMeasurement(measurement)
                    dismiss()
                }
                .disabled(!values.values.contains { Self.average($0) != nil })
            }
        }
    }
}

/// Shown when BPFSL hasn't moved for about a month.
struct MTStallSection: View {
    let stall: MTInsights.StallAdvice
    let unit: MTUnit

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("No \(stall.metric.title) gain in \(stall.days) days", systemImage: stall.blockedBySafety ? "exclamationmark.octagon.fill" : "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(stall.blockedBySafety ? .red : .orange)
                Text(stall.blockedBySafety
                     ? "Safety first — no changes to the routine right now:"
                     : "Time to change the routine. Work down this list, one step at a time, re-measuring after 4–6 weeks:")
                    .font(.subheadline)
                ForEach(stall.tips, id: \.self) { tip in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.orange).font(.caption)
                        Text(tip).font(.subheadline)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Plateau")
        }
    }
}
