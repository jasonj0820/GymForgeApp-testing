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

                SundayWeighInCard()

                metricSection(title: "Body weight", suffix: "kg", points: weights)
                metricSection(title: "Body fat", suffix: "%", points: fats)
                metricSection(title: "Lean mass (estimate)", suffix: "kg", points: lean)

                TapeMeasurementsSection()

                Text("Read from Apple Health (your Xiaomi scale, or any scale, only needs to sync to Health) plus the weigh-ins you type in. Trends use a 7-day average so one reading doesn't swing things. Lean mass = weight × (1 − body fat %).")
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
                Text("No readings in this range.")
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

// MARK: - Sunday weigh-in (MK20.2)

/// Body tab card: this week's weigh-in, the 9am Sunday reminder switch, and your recent typed-in entries.
struct SundayWeighInCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var editing: WeighIn?
    @State private var adding = false
    @State private var remind = WeighInReminder.enabled

    var body: some View {
        let thisWeek = store.thisWeeksWeighIn
        let recent = Array(store.extras.weighIns.suffix(6).reversed())
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Sunday weigh-in", systemImage: "scalemass.fill").font(.headline)
                Spacer()
                Button {
                    if let thisWeek { editing = thisWeek } else { adding = true }
                } label: {
                    Label(thisWeek == nil ? "Log" : "Edit", systemImage: thisWeek == nil ? "plus" : "pencil")
                }
                .buttonStyle(.borderedProminent)
            }
            if let thisWeek {
                Text("This week: " + WeighInSheet.summary(thisWeek) + " · " + thisWeek.date.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(Calendar.current.component(.weekday, from: .now) == 1
                     ? "It's Sunday — log your weight and body fat."
                     : "Not logged since Sunday. You can still add it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Toggle("Remind me Sundays at 9:00am", isOn: $remind)
                .font(.subheadline)
                .onChange(of: remind) { _, on in
                    WeighInReminder.enabled = on
                    WeighInReminder.reschedule(weighIns: store.extras.weighIns)
                }
            if !recent.isEmpty {
                Divider()
                ForEach(recent) { entry in
                    HStack {
                        Text(entry.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(WeighInSheet.summary(entry))
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = entry }
                    .contextMenu {
                        Button { editing = entry } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { store.deleteWeighIn(entry.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Text("Tap to edit, long-press to delete.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
        .sheet(isPresented: $adding) { WeighInSheet().environmentObject(store) }
        .sheet(item: $editing) { WeighInSheet(existing: $0).environmentObject(store) }
    }
}

/// Type in weight (kg) and body fat (%). Opens from the Sunday 9am reminder and the Body tab.
struct WeighInSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    var existing: WeighIn?
    @State private var date = Date()
    @State private var weightText = ""
    @State private var fatText = ""

    static func summary(_ entry: WeighIn) -> String {
        [entry.weightKg.map { "\(GFFormat.kg($0)) kg" }, entry.bodyFatPercent.map { String(format: "%.1f%% fat", $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
    private var weight: Double? { Self.number(weightText).flatMap { (20...400).contains($0) ? $0 : nil } }
    private var fat: Double? { Self.number(fatText).flatMap { (2...70).contains($0) ? $0 : nil } }
    private var canSave: Bool {
        (weight != nil || fat != nil)
            && (weightText.isEmpty || weight != nil) && (fatText.isEmpty || fat != nil)
    }

    var body: some View {
        let lastWeight = store.healthKit.bodyWeight.last?.value
        let lastFat = store.healthKit.bodyFat.last?.value
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField(lastWeight.map { GFFormat.kg($0) } ?? "kg", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Body fat")
                        Spacer()
                        TextField(lastFat.map { String(format: "%.1f", $0) } ?? "%", text: $fatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("%").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Grey numbers are your latest reading. Leave one blank if you only have the other. Same conditions each Sunday (morning, after the bathroom, before eating) keeps the trend honest.")
                }
                if existing != nil {
                    Section {
                        Button("Delete weigh-in", role: .destructive) {
                            if let existing { store.deleteWeighIn(existing.id) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Sunday weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Saved at the time you pick (now, or 9am on a past day) so charts place it sensibly.
                        let cal = Calendar.current
                        let when = cal.isDateInToday(date) ? Date() : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date)
                        store.saveWeighIn(WeighIn(id: existing?.id ?? UUID(), date: when, weightKg: weight, bodyFatPercent: fat))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // Editing, or reopening today's: start from what's saved.
                let current = existing ?? store.extras.weighIn(on: .now)
                if let current {
                    date = current.date
                    weightText = current.weightKg.map { GFFormat.kg($0) } ?? ""
                    fatText = current.bodyFatPercent.map { String(format: "%.1f", $0) } ?? ""
                }
            }
        }
    }
}
