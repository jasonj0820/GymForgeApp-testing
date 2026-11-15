import Charts
import SwiftUI

// MARK: - Pinned lifts (80)

/// History keys of pinned lifts, one per line in @AppStorage.
enum PinnedLifts {
    static let key = "progress.pinned"
    static func keys(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
    static func toggled(_ key: String, in raw: String) -> String {
        var all = keys(raw)
        if all.contains(key) { all.remove(key) } else { all.insert(key) }
        return all.sorted().joined(separator: "\n")
    }
}

// MARK: - Sets per muscle over months (82)

struct MuscleTrendView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var muscle: ExerciseCategory = .chest

    private struct Week: Identifiable {
        let id: Date
        let sets: Double
    }

    var body: some View {
        let weeks = weeks(for: muscle)
        let range = WeeklyReviewBuilder.targetRange(muscle)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Muscle", selection: $muscle) {
                    ForEach(ExerciseCategory.muscleGroups, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Chart {
                    if let first = weeks.first?.id, let last = weeks.last?.id {
                        RectangleMark(xStart: .value("From", first), xEnd: .value("To", last.addingTimeInterval(7 * 86_400)),
                                      yStart: .value("Low", range.low), yEnd: .value("High", range.high))
                            .foregroundStyle(.green.opacity(0.12))
                    }
                    ForEach(weeks) { week in
                        BarMark(x: .value("Week", week.id, unit: .weekOfYear), y: .value("Sets", week.sets))
                            .foregroundStyle(week.sets < range.low ? Color.orange : (week.sets > range.high ? Color.red : Color.green))
                    }
                }
                .frame(height: 240)
                let trained = weeks.filter { $0.sets > 0 }
                let average = trained.isEmpty ? 0 : trained.map(\.sets).reduce(0, +) / Double(trained.count)
                Text("Weekly hard sets for \(muscle.title.lowercased()), last 26 weeks. The green band is \(Int(range.low))–\(Int(range.high)) sets, a good range for growth. Average in weeks you trained: \(String(format: "%.1f", average)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Sets per muscle")
    }

    private func weeks(for muscle: ExerciseCategory) -> [Week] {
        let cal = Calendar.current
        let lookup = store.categoryLookup
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<26).reversed().compactMap { back -> Week? in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let value = WeeklyReviewBuilder.muscles(logs: store.workoutLogs, from: start, to: end, lookup: lookup)
                .first { $0.id == muscle }?.effective ?? 0
            return Week(id: start, sets: value)
        }
    }
}

// MARK: - Compare two periods (83)

struct ComparePeriodsView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var choice: Choice = .fourWeeks

    enum Choice: String, CaseIterable, Identifiable {
        case fourWeeks = "4 weeks", month = "Month", threeMonths = "3 months", block = "Block"
        var id: String { rawValue }
    }

    var body: some View {
        let periods = periods(choice)
        List {
            Picker("Compare", selection: $choice) {
                ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            if let periods {
                let before = PeriodStats.make(store.workoutLogs, from: periods.0.start, to: periods.0.end)
                let now = PeriodStats.make(store.workoutLogs, from: periods.1.start, to: periods.1.end)
                let labels = periods.2
                Section {
                    row("Sessions", before.sessions, now.sessions)
                    row("Per week", before.perWeek, now.perWeek, digits: 1)
                    row("Sets", before.sets, now.sets)
                    row("Volume (t)", before.volumeKg / 1000, now.volumeKg / 1000, digits: 1)
                    row("Records", before.prs, now.prs)
                } header: {
                    HStack { Text(labels.0); Spacer(); Text("→ \(labels.1)") }
                }
                let lifts = PeriodStats.liftChanges(before, now)
                if !lifts.isEmpty {
                    Section("Heaviest set, lifts done in both") {
                        ForEach(lifts, id: \.key) { lift in
                            HStack {
                                Text(name(for: lift.key)).lineLimit(1)
                                Spacer()
                                Text("\(GFFormat.kg(lift.from)) → \(GFFormat.kg(lift.to)) kg")
                                    .monospacedDigit()
                                    .foregroundStyle(lift.to > lift.from ? Color.green : (lift.to < lift.from ? Color.orange : Color.secondary))
                            }
                            .font(.subheadline)
                        }
                    }
                }
            } else {
                Text("Set up a training program (Coach → Training block) to compare blocks.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Compare")
    }

    private func name(for key: String) -> String {
        store.progressExercises.first { $0.historyKey == key }?.name ?? key.capitalized
    }

    private func row(_ title: String, _ a: Int, _ b: Int) -> some View {
        row(title, Double(a), Double(b), digits: 0)
    }

    private func row(_ title: String, _ a: Double, _ b: Double, digits: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%.\(digits)f", a)).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            Text(String(format: "%.\(digits)f", b)).bold().monospacedDigit()
                .foregroundStyle(b > a ? Color.green : (b < a ? Color.orange : Color.primary))
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// (earlier, later, labels). The later one ends now (or at the block's end).
    private func periods(_ choice: Choice) -> (DateInterval, DateInterval, (String, String))? {
        let cal = Calendar.current
        let now = Date.now
        func back(_ c: Calendar.Component, _ n: Int, from d: Date) -> Date { cal.date(byAdding: c, value: -n, to: d) ?? d }
        switch choice {
        case .fourWeeks:
            let mid = back(.day, 28, from: now)
            return (DateInterval(start: back(.day, 28, from: mid), end: mid), DateInterval(start: mid, end: now), ("4 weeks before", "last 4 weeks"))
        case .month:
            guard let this = cal.dateInterval(of: .month, for: now) else { return nil }
            let last = DateInterval(start: back(.month, 1, from: this.start), end: this.start)
            return (last, DateInterval(start: this.start, end: now),
                    (last.start.formatted(.dateTime.month(.wide)), this.start.formatted(.dateTime.month(.wide)) + " so far"))
        case .threeMonths:
            let mid = back(.month, 3, from: now)
            return (DateInterval(start: back(.month, 3, from: mid), end: mid), DateInterval(start: mid, end: now), ("3 months before", "last 3 months"))
        case .block:
            guard let program = store.profile.program, let position = program.position(at: now) else { return nil }
            let length = Double(max(position.block.weeks, 1)) * 7 * 86_400
            let start = position.blockEnds.addingTimeInterval(-length)
            guard let previous = program.position(at: start.addingTimeInterval(-86_400)) else { return nil }
            let prevLength = Double(max(previous.block.weeks, 1)) * 7 * 86_400
            let prevStart = previous.blockEnds.addingTimeInterval(-prevLength)
            return (DateInterval(start: prevStart, end: previous.blockEnds), DateInterval(start: start, end: min(now, position.blockEnds)),
                    (previous.block.phase.title + " block", position.block.phase.title + " block"))
        }
    }
}

// MARK: - Year in review (90)

struct YearInReviewView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var year = Calendar.current.component(.year, from: .now)

    var body: some View {
        let review = YearReview.make(store.workoutLogs, year: year, weekGoal: max(1, store.weeklyGoal - 1))
        ScrollView {
            VStack(spacing: 16) {
                Stepper("\(String(year))", value: $year, in: 2015...Calendar.current.component(.year, from: .now))
                    .font(.headline)
                YearReviewCard(review: review)
                if review.sessions > 0 {
                    ShareLink(item: YearReviewCard.image(review), preview: SharePreview("My \(String(year)) in training", image: YearReviewCard.image(review))) {
                        Label("Share as a picture", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Year in review")
    }
}

struct YearReviewCard: View {
    let review: YearReview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(String(review.year)) in training").font(.title.bold())
            if review.sessions == 0 {
                Text("No sessions logged this year.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        stat("\(review.sessions)", "sessions")
                        stat(String(format: "%.0f", review.hours), "hours")
                    }
                    GridRow {
                        stat("\(review.sets)", "sets")
                        stat(String(format: "%.0f t", review.volumeKg / 1000), "lifted")
                    }
                    GridRow {
                        stat("\(review.prs)", "records")
                        stat("\(review.longestStreakWeeks) wk", "longest streak")
                    }
                }
                if !review.mostImproved.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Most improved").font(.headline)
                        ForEach(review.mostImproved, id: \.name) { lift in
                            Text("\(lift.name): \(GFFormat.kg(lift.from)) → \(GFFormat.kg(lift.to)) kg").font(.subheadline)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let routine = review.favouriteRoutine { Text("Most done: \(routine)").font(.subheadline) }
                    if let month = review.busiestMonth {
                        Text("Busiest month: \(Calendar.current.monthSymbols[month - 1])").font(.subheadline)
                    }
                    Text("Best week: \(review.bestWeek) sessions").font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            Text("Splitday").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(.tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The card as a picture, for sharing.
    @MainActor
    static func image(_ review: YearReview) -> Image {
        let renderer = ImageRenderer(content: YearReviewCard(review: review).frame(width: 360).padding(12)
            .background(Color(.systemBackground)))
        renderer.scale = 3
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "photo")
    }
}
