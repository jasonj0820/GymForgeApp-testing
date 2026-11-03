import Foundation
import SwiftUI

// Goals per measurement, comparison with published averages, the fat-pad gap and plateau advice.
// Everything here stays inside More Training (it only *reads* body fat from the gym side).

/// Which published average to compare against.
enum MTReference: String, CaseIterable, Identifiable {
    case herbenick, veale
    var id: String { rawValue }

    var title: String {
        switch self {
        case .herbenick: return "Self-measured, US men (Herbenick 2014)"
        case .veale: return "Measured by clinicians (Veale 2015)"
        }
    }

    var shortTitle: String {
        switch self {
        case .herbenick: return "Herbenick 2014"
        case .veale: return "Veale 2015"
        }
    }

    /// Erect length and girth averages, cm.
    var lengthMean: Double { self == .herbenick ? 14.15 : 13.12 }
    var girthMean: Double { self == .herbenick ? 12.23 : 11.66 }

    /// Spread: Herbenick doesn't publish one, so both use the clinical study's (Veale 2015).
    static let lengthSD = 1.66
    static let girthSD = 1.10
    /// Stretched flaccid length is only in Veale 2015.
    static let stretchedMean = 13.24
    static let stretchedSD = 2.89
    /// No study measures non-bone-pressed length: estimated as the bone-pressed average minus about 1 cm.
    static let fatPadEstimateCM = 1.0
}

struct MTComparison {
    let metric: MTMetric
    let value: Double
    let average: Double
    let percentile: Double
    let source: String
    let isEstimate: Bool

    var percentDifference: Double { (value / average - 1) * 100 }

    /// Neutral, factual wording (the normal range is wide).
    var band: String {
        switch percentile {
        case ..<16: return "below average"
        case ..<84: return "average range"
        case ..<97.5: return "above average"
        default: return "well above average"
        }
    }
}

struct MTGoalProgress {
    let metric: MTMetric
    let start: Double
    let target: Double
    let current: Double
    /// 0…1 of the way from where you started to the goal.
    let fraction: Double
    /// Trend over the last ~4 months, cm per 30 days.
    let perMonth: Double?
    let projected: Date?
}

enum MTGoals {
    static func reference(_ settings: MTSettings) -> MTReference {
        MTReference(rawValue: settings.averageReference ?? "") ?? .herbenick
    }

    /// Average of your readings within 10 days of the latest one (smooths day-to-day noise), cm.
    static func current(_ metric: MTMetric, _ data: MTData) -> (value: Double, date: Date)? {
        let readings = data.measurements.compactMap { m in m.value(metric).map { (date: m.date, value: $0) } }
            .sorted { $0.date < $1.date }
        guard let latest = readings.last else { return nil }
        let recent = readings.filter { latest.date.timeIntervalSince($0.date) < 10 * 86_400 }.map(\.value)
        return (recent.reduce(0, +) / Double(max(recent.count, 1)), latest.date)
    }

    static func percentile(_ value: Double, mean: Double, sd: Double) -> Double {
        let z = (value - mean) / sd
        return 0.5 * (1 + erf(z / 2.0.squareRoot())) * 100
    }

    static func comparison(_ metric: MTMetric, data: MTData) -> MTComparison? {
        guard let current = current(metric, data) else { return nil }
        let ref = reference(data.settings)
        let mean: Double
        let sd: Double
        let source: String
        var estimate = false
        switch metric {
        case .bpel:
            mean = ref.lengthMean; sd = MTReference.lengthSD; source = ref.shortTitle
        case .nbpl:
            mean = ref.lengthMean - MTReference.fatPadEstimateCM; sd = MTReference.lengthSD
            source = "estimate: \(ref.shortTitle) length − ~1 cm"
            estimate = true
        case .mg:
            mean = ref.girthMean; sd = MTReference.girthSD; source = ref.shortTitle
        case .bpfsl:
            mean = MTReference.stretchedMean; sd = MTReference.stretchedSD; source = "Veale 2015 (stretched)"
        case .bg:
            return nil
        }
        return MTComparison(metric: metric, value: current.value, average: mean,
                            percentile: percentile(current.value, mean: mean, sd: sd), source: source, isEstimate: estimate)
    }

    static func progress(_ metric: MTMetric, data: MTData) -> MTGoalProgress? {
        let key = metric.rawValue
        guard let target = data.settings.goalsCM?[key], let current = current(metric, data) else { return nil }
        let start = data.settings.goalStartCM?[key] ?? data.measurements
            .compactMap { m in m.value(metric).map { (date: m.date, value: $0) } }
            .min { $0.date < $1.date }?.value ?? current.value
        let span = target - start
        let fraction = span > 0 ? min(max((current.value - start) / span, 0), 1) : (current.value >= target ? 1 : 0)
        let window = data.measurements.filter { $0.date >= current.date.addingTimeInterval(-120 * 86_400) }
            .compactMap { m in m.value(metric).map { (date: m.date, value: $0) } }
        let perMonth = MTInsights.trend(window)?.perMonth
        var projected: Date?
        if let perMonth, perMonth > 0.01, current.value < target {
            let months = (target - current.value) / perMonth
            if months < 120 { projected = current.date.addingTimeInterval(months * 30 * 86_400) }
        }
        return MTGoalProgress(metric: metric, start: start, target: target, current: current.value,
                              fraction: fraction, perMonth: perMonth, projected: projected)
    }

    /// BPEL − NBPL over 1 inch: mostly the fat pad, which a cut shrinks.
    static func gapAdvice(_ data: MTData, bodyFatPercent: Double?, unit: MTUnit) -> String? {
        guard let bp = current(.bpel, data)?.value, let nbp = current(.nbpl, data)?.value else { return nil }
        let gap = bp - nbp
        guard gap > 2.54 else { return nil }
        let gapText = unit == .cm ? String(format: "%.1f cm", gap) : String(format: "%.2f in", gap / 2.54)
        var text = "Your BP–NBP gap is \(gapText) — mostly the fat pad over the pubic bone. Losing body fat shrinks it, so more of your length shows."
        if let bodyFatPercent {
            if bodyFatPercent > 15 {
                text += String(format: " Your latest body fat reading is about %.0f%% (Apple Health): a cut toward ~15%% is the most reliable way to reduce the gap.", bodyFatPercent)
            } else {
                text += String(format: " You're already lean (latest reading about %.0f%% body fat), so the remaining gap is mostly skin and tissue over the pubic bone — measure NBP the same way each time.", bodyFatPercent)
            }
        } else {
            text += " Track body fat on the gym side (Apple Health) to see how a cut affects it."
        }
        text += " Rough rule of thumb from forums (not research): about 1 in (2.5 cm) per 15 kg (35 lb) lost."
        return text
    }
}

// MARK: - Goal & comparison views (Measure tab)

struct MTGoalSection: View {
    @EnvironmentObject private var vault: MTVault
    let metric: MTMetric
    @State private var editing = false
    @State private var draft = ""

    private var unit: MTUnit { vault.data.settings.unit }

    private func format(_ cm: Double) -> String {
        String(format: unit == .cm ? "%.1f cm" : "%.2f in", unit.display(cm))
    }

    var body: some View {
        Section {
            if let progress = MTGoals.progress(metric, data: vault.data) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Goal \(format(progress.target))").font(.headline)
                        Spacer()
                        Text("\(Int((progress.fraction * 100).rounded()))%").font(.headline.monospacedDigit())
                    }
                    SwiftUI.ProgressView(value: progress.fraction)
                        .tint(progress.fraction >= 1 ? .green : .indigo)
                    Text("Started \(format(progress.start)) · now \(format(progress.current)) (recent average)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if progress.fraction >= 1 {
                        Label("Goal reached. Set a new one, or switch to maintaining.", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else if let date = progress.projected, let rate = progress.perMonth {
                        Text("At +\(format(rate))/month you'd reach it around \(date.formatted(.dateTime.month(.wide).year())).")
                            .font(.footnote)
                    } else {
                        Text("No upward trend yet — keep measuring the same way; a projection appears once the trend line rises.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button(vault.data.settings.goalsCM?[metric.rawValue] == nil ? "Set a \(metric.title) goal" : "Change goal") {
                draft = vault.data.settings.goalsCM?[metric.rawValue].map { String(format: unit == .cm ? "%.1f" : "%.2f", unit.display($0)) } ?? ""
                editing = true
            }
            if vault.data.settings.goalsCM?[metric.rawValue] != nil {
                Button("Remove goal", role: .destructive) { setGoal(nil) }
            }
        } header: {
            Text("\(metric.title) goal")
        }
        .alert("\(metric.title) goal (\(unit.label))", isPresented: $editing) {
            TextField(unit == .cm ? "e.g. 17.8" : "e.g. 7.0", text: $draft)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let value = Double(draft.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    setGoal(unit.toCM(value))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Progress is measured from your current recent average.")
        }
    }

    private func setGoal(_ cm: Double?) {
        var settings = vault.data.settings
        var goals = settings.goalsCM ?? [:]
        var starts = settings.goalStartCM ?? [:]
        var dates = settings.goalStartDates ?? [:]
        let key = metric.rawValue
        if let cm {
            goals[key] = cm
            starts[key] = MTGoals.current(metric, vault.data)?.value
            dates[key] = .now
        } else {
            goals[key] = nil
            starts[key] = nil
            dates[key] = nil
        }
        settings.goalsCM = goals.isEmpty ? nil : goals
        settings.goalStartCM = starts.isEmpty ? nil : starts
        settings.goalStartDates = dates.isEmpty ? nil : dates
        vault.updateSettings(settings)
    }
}

struct MTComparisonSection: View {
    @EnvironmentObject private var vault: MTVault
    let metric: MTMetric

    /// "1st" … "99th" (clamped: a percentile is never 0 or 100).
    private func ordinal(_ value: Double) -> String {
        let n = min(max(Int(value.rounded()), 1), 99)
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var unit: MTUnit { vault.data.settings.unit }

    private func format(_ cm: Double) -> String {
        String(format: unit == .cm ? "%.1f cm" : "%.2f in", unit.display(cm))
    }

    var body: some View {
        Section {
            if let comparison = MTGoals.comparison(metric, data: vault.data) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%+.0f%%", comparison.percentDifference))
                            .font(.title2.bold())
                        Text(comparison.percentDifference >= 0 ? "over the average" : "under the average")
                            .font(.subheadline)
                        Spacer()
                        Text("~\(ordinal(comparison.percentile)) percentile")
                            .font(.subheadline.bold())
                    }
                    Text("Yours \(format(comparison.value)) · average \(format(comparison.average)) — \(comparison.band).")
                        .font(.subheadline)
                    Text("Source: \(comparison.source)." + (comparison.isEstimate ? " NBP isn't measured in any study, so this average is an estimate." : "")
                         + " Percentile uses the clinical study's spread.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if metric == .bg {
                Text("No published average for base girth.").foregroundStyle(.secondary)
            } else {
                Text("Add a \(metric.title) measurement to compare.").foregroundStyle(.secondary)
            }
            Picker("Compare with", selection: Binding(
                get: { MTGoals.reference(vault.data.settings) },
                set: { value in
                    var settings = vault.data.settings
                    settings.averageReference = value.rawValue
                    vault.updateSettings(settings)
                }
            )) {
                ForEach(MTReference.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Compared with the average")
        }
    }
}

// MARK: - "Preferred size" reference (MK10.1)

/// The average of what women said they prefer (Prause 2015, 3D models) and what sells
/// (Amazon US top 10 / top 50 / realistic dildos, May 2020). Length = insertable length, closest to NBP.
enum MTPreferredSize {
    struct Source: Identifiable {
        let name: String
        let lengthIn: Double
        let girthIn: Double
        var id: String { name }
    }

    static let sources: [Source] = [
        Source(name: "Women's preference, long-term partner (Prause 2015)", lengthIn: 6.3, girthIn: 4.8),
        Source(name: "Women's preference, one-time partner (Prause 2015)", lengthIn: 6.4, girthIn: 5.0),
        Source(name: "Amazon US top 10 dildos (2020)", lengthIn: 6.23, girthIn: 5.15),
        Source(name: "Amazon US top 50 dildos (2020)", lengthIn: 6.54, girthIn: 5.37),
        Source(name: "Realistic dildos in the top 50 (2020)", lengthIn: 6.16, girthIn: 4.89)
    ]

    /// ≈ 16.1 cm (6.33 in).
    static var lengthCM: Double { sources.map(\.lengthIn).reduce(0, +) / Double(sources.count) * 2.54 }
    /// ≈ 12.8 cm (5.04 in).
    static var girthCM: Double { sources.map(\.girthIn).reduce(0, +) / Double(sources.count) * 2.54 }

    static func comment(metric: MTMetric, value: Double, target: Double) -> String {
        let ratio = value / target
        let what = metric == .nbpl ? "length" : "girth"
        switch ratio {
        case ..<0.9: return "Below the preferred \(what) — a realistic goal is the gap shown."
        case ..<0.97: return "Close to the preferred \(what)."
        case ..<1.05: return "Right on the preferred \(what)."
        case ..<1.12: return "Above the preferred \(what) — more isn't needed here."
        default: return "Well above the preferred \(what). Past this point bigger isn't preferred; focus on keeping EQ high."
        }
    }
}

struct MTPreferredSizeSection: View {
    @EnvironmentObject private var vault: MTVault
    @State private var showSources = false

    private var unit: MTUnit { vault.data.settings.unit }

    private func format(_ cm: Double) -> String {
        String(format: unit == .cm ? "%.1f cm" : "%.2f in", unit.display(cm))
    }

    private func signed(_ cm: Double) -> String {
        String(format: unit == .cm ? "%+.1f cm" : "%+.2f in", unit.display(cm))
    }

    var body: some View {
        Section {
            ForEach([MTMetric.nbpl, .mg, .bg]) { metric in
                let target = metric == .nbpl ? MTPreferredSize.lengthCM : MTPreferredSize.girthCM
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metric.title).font(.headline)
                        Text(metric.detail).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("target \(format(target))").font(.caption).foregroundStyle(.secondary)
                    }
                    if let current = MTGoals.current(metric, vault.data) {
                        SwiftUI.ProgressView(value: min(current.value / target, 1.2), total: 1.2)
                            .tint(current.value >= target * 0.97 ? .green : .indigo)
                        Text("Yours \(format(current.value)) · \(signed(current.value - target)) (\(String(format: "%+.0f%%", (current.value / target - 1) * 100)))")
                            .font(.subheadline.monospacedDigit())
                        Text(MTPreferredSize.comment(metric: metric, value: current.value, target: target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Add a \(metric.title) measurement to compare.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            DisclosureGroup("Where these numbers come from", isExpanded: $showSources) {
                ForEach(MTPreferredSize.sources) { source in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.name).font(.caption)
                        Text(String(format: "%.2f in × %.2f in girth", source.lengthIn, source.girthIn))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Length on toys is insertable length (base excluded), so it compares with NBP. Toy rankings are from one 2020 Amazon US snapshot compiled on a forum; no Australian size data was found. Both girths are compared with the same girth figure.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } header: {
            Text("Preferred size")
        } footer: {
            Text("Average of what women chose in a 3D-model study and what sells best: about \(format(MTPreferredSize.lengthCM)) long × \(format(MTPreferredSize.girthCM)) girth.")
        }
    }
}
