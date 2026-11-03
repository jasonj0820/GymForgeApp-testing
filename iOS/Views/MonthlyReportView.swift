import SwiftUI
import Charts

struct MonthlyReportView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var month: Date = .now

    var body: some View {
        let report = store.monthlyReport(for: month)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthPicker(report)

                VStack(alignment: .leading, spacing: 8) {
                    Text(report.headline).font(.title3.bold())
                    ForEach(report.highlights, id: \.self) { line in
                        Label(line, systemImage: "sparkle").font(.subheadline)
                    }
                }
                .card()

                statsGrid(report)
                heatmap(report)
                strengthSection(report)
                muscleSection(report)
                bodySection(report)
                milestoneSection(report)
            }
            .padding()
        }
        .navigationTitle("Monthly report")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private func monthPicker(_ report: MonthlyReport) -> some View {
        HStack {
            Button {
                month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
            } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(report.title).font(.title2.bold())
            Spacer()
            Button {
                month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
            } label: { Image(systemName: "chevron.right") }
            .disabled(report.monthEnd > .now)
        }
        .buttonStyle(.bordered)
    }

    private func statsGrid(_ report: MonthlyReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Workouts", "\(report.workouts) / \(report.plannedWorkouts)", sub: "\(GFFormat.percent(report.adherence)) of goal")
            stat("Volume", GFFormat.volume(report.totalVolumeKg), sub: "\(report.totalSets) sets · \(report.totalReps) reps")
            stat("Time trained", GFFormat.minutes(report.totalTime), sub: "avg \(GFFormat.minutes(report.averageDuration))")
            stat("PRs", "\(report.prs.count)", sub: report.activeCalories > 0 ? "\(Int(report.activeCalories)) active kcal" : " ")
            if report.cardioSeconds > 0 {
                stat("Cardio", GFFormat.minutes(report.cardioSeconds), sub: report.cardioKm > 0 ? "\(GFFormat.km(report.cardioKm)) km" : " ")
            }
            if report.deloadSessions > 0 {
                stat("Light sessions", "\(report.deloadSessions)", sub: "deload / low recovery")
            }
        }
    }

    private func stat(_ title: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .card()
    }

    private func heatmap(_ report: MonthlyReport) -> some View {
        let calendar = Calendar.current
        let dayCount = calendar.range(of: .day, in: .month, for: report.monthStart)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: report.monthStart)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Training days").font(.headline)
            LazyVGrid(columns: columns, spacing: 5) {
                // Separate id ranges (headers −107…−101, blanks −100…, days 1…31) so no two cells share an id.
                ForEach(-107 ..< -100, id: \.self) { index in
                    Text(ordered[index + 107]).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(-100 ..< (-100 + offset), id: \.self) { _ in
                    Color.clear.frame(height: 30)
                }
                ForEach(1...dayCount, id: \.self) { day in
                    let count = report.trainingDays[day] ?? 0
                    RoundedRectangle(cornerRadius: 6)
                        .fill(count == 0 ? Color.gray.opacity(0.15) : Color.orange.opacity(count > 1 ? 1 : 0.75))
                        .frame(height: 30)
                        .overlay(
                            Text("\(day)")
                                .font(.caption2)
                                .foregroundStyle(count == 0 ? Color.secondary : Color.white)
                        )
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func strengthSection(_ report: MonthlyReport) -> some View {
        if !report.strengthChanges.isEmpty || !report.prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Strength").font(.headline)
                if let best = report.mostImproved, best.percent > 0.005 {
                    Label("Most improved: \(best.name) +\(GFFormat.percent(best.percent))", systemImage: "arrow.up.right.circle.fill")
                        .foregroundStyle(.green)
                }
                ForEach(report.strengthChanges.prefix(6)) { change in
                    HStack {
                        Text(change.name)
                        Spacer()
                        Text("\(GFFormat.kg(change.before.rounded())) → \(GFFormat.kg(change.after.rounded())) kg")
                            .foregroundStyle(.secondary)
                        Text((change.percent >= 0 ? "+" : "") + GFFormat.percent(change.percent))
                            .bold()
                            .foregroundStyle(change.percent >= 0 ? Color.green : Color.orange)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .font(.subheadline)
                }
                Text("Best estimated 1RM this month vs your best before it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !report.prs.isEmpty {
                    Divider()
                    Text("PRs this month").font(.subheadline.bold())
                    ForEach(report.prs) { pr in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text(pr.exerciseName)
                            Spacer()
                            Text(pr.set.summaryText).foregroundStyle(.secondary)
                            Text(pr.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func muscleSection(_ report: MonthlyReport) -> some View {
        let rows = ExerciseCategory.muscleGroups
            .map { MuscleRow(name: $0.title, sets: report.muscleSets[$0] ?? 0) }
            .filter { $0.sets > 0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sets per muscle group").font(.headline)
                Chart {
                    ForEach(rows) { row in
                        BarMark(x: .value("Sets", row.sets), y: .value("Muscle", row.name))
                            .foregroundStyle(Color.orange.gradient)
                            .annotation(position: .trailing) {
                                Text("\(row.sets)").font(.caption2).foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(height: CGFloat(rows.count) * 30 + 20)
            }
            .card()
        }
    }

    @ViewBuilder
    private func bodySection(_ report: MonthlyReport) -> some View {
        let hasBody = report.bodyWeightEnd != nil || report.bodyFatEnd != nil || report.averageSleep != nil || report.averageHRRecovery != nil
        if hasBody {
            VStack(alignment: .leading, spacing: 8) {
                Text("Body & recovery").font(.headline)
                if let end = report.bodyWeightEnd {
                    trendRow("Body weight", start: report.bodyWeightStart, end: end, unit: "kg")
                }
                if let end = report.bodyFatEnd {
                    trendRow("Body fat", start: report.bodyFatStart, end: end, unit: "%")
                }
                if let sleep = report.averageSleep {
                    LabeledContent("Average sleep", value: String(format: "%.1f h", sleep))
                }
                if let hrr = report.averageHRRecovery {
                    LabeledContent("HR recovery (1 min)") {
                        Text("\(Int(hrr.rounded())) bpm" + (report.previousHRRecovery.map { " (was \(Int($0.rounded())))" } ?? ""))
                    }
                }
            }
            .font(.subheadline)
            .card()
        }
    }

    private func trendRow(_ title: String, start: Double?, end: Double, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let start {
                Text(String(format: "%.1f → %.1f %@", start, end, unit)).foregroundStyle(.secondary)
                Text("\(GFFormat.signed(end - start)) \(unit)").bold()
            } else {
                Text(String(format: "%.1f %@", end, unit)).foregroundStyle(.secondary)
            }
        }
    }

    private func milestoneSection(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Milestones").font(.headline)
            if report.newMilestones.isEmpty {
                Text("No new milestones this month — here's what's next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.newMilestones) { milestone in
                HStack {
                    Image(systemName: milestone.systemImage).foregroundStyle(.orange)
                    Text(milestone.title).bold()
                    Spacer()
                    Text(milestone.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(report.nextMilestones) { next in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Next: \(next.title)").font(.subheadline)
                        Spacer()
                        Text("\(GFFormat.percent(next.fraction))").font(.caption).foregroundStyle(.secondary)
                    }
                    SwiftUI.ProgressView(value: next.fraction)
                }
            }
        }
        .card()
    }
}

struct MuscleRow: Identifiable {
    let name: String
    let sets: Int
    var id: String { name }
}
