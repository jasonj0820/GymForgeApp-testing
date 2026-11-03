import SwiftUI
import Charts

struct TapePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Tape measurements (cm) with a chart per site.
struct TapeMeasurementsSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var adding = false
    @State private var site: TapeSite = .arm

    var body: some View {
        let entries = store.extras.tape
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tape measurements").font(.headline)
                Spacer()
                Button {
                    adding = true
                } label: {
                    Label("Measure", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            if entries.isEmpty {
                Text("Measure every 2–4 weeks, same time of day, relaxed (arm flexed). Waist at the navel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Site", selection: $site) {
                    ForEach(TapeSite.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                let points = entries.compactMap { entry in entry.value(site).map { TapePoint(date: entry.date, value: $0) } }
                if points.isEmpty {
                    Text("No \(site.title.lowercased()) measurements yet.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("cm", point.value))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.date), y: .value("cm", point.value))
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 160)
                    if let first = points.first, let last = points.last, points.count > 1 {
                        let change = last.value - first.value
                        Text("\(GFFormat.signed(change)) cm since \(first.date.formatted(date: .abbreviated, time: .omitted)) · now \(GFFormat.kg(last.value)) cm")
                            .font(.footnote)
                            .foregroundStyle(change >= 0 ? (site == .waist ? Color.orange : Color.green) : (site == .waist ? Color.green : Color.orange))
                    }
                }
                if let latest = entries.last {
                    let parts = TapeSite.allCases.compactMap { s in latest.value(s).map { "\(s.title) \(GFFormat.kg($0))" } }
                    Text("Latest (\(latest.date.formatted(date: .abbreviated, time: .omitted))): " + parts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $adding) {
            TapeEntrySheet(previous: entries.last) { store.addTape($0) }
        }
    }
}

struct TapeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let previous: TapeEntry?
    let onSave: (TapeEntry) -> Void
    @State private var date = Date()
    @State private var texts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Section {
                    ForEach(TapeSite.allCases) { site in
                        HStack {
                            Text(site.title)
                            Spacer()
                            TextField(previous?.value(site).map { GFFormat.kg($0) } ?? "cm", text: Binding(
                                get: { texts[site.rawValue] ?? "" },
                                set: { texts[site.rawValue] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            Text("cm").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Leave any blank. Grey numbers are last time.")
                }
            }
            .navigationTitle("Tape measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var values: [String: Double] = [:]
                        for (key, text) in texts {
                            if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 { values[key] = value }
                        }
                        if !values.isEmpty { onSave(TapeEntry(date: date, values: values)) }
                        dismiss()
                    }
                }
            }
        }
    }
}
