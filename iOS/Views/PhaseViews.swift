import SwiftUI

// MARK: - Plateau pop-up (shown every time you open a routine with stalled lifts)

struct PlateauSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let routineName: String
    let plateaus: [PhaseCoach.Plateau]
    let deload: PhaseCoach.Warning?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        CluckView(mood: plateaus.contains { $0.kind == .strengthDrop } ? .annoyed : .watching)
                            .frame(width: 56, height: 56)
                        Text(summary)
                            .font(.subheadline)
                    }
                    if let deload {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(deload.title, systemImage: "battery.25")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(deload.message).font(.subheadline)
                            Button("Start a deload week") {
                                store.startDeloadWeek()
                                store.acceptSuggestion("Take a deload week. " + deload.message, exercise: nil)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                        .card()
                    }
                    ForEach(plateaus) { plateau in
                        PlateauCard(plateau: plateau)
                    }
                }
                .padding()
            }
            .navigationTitle(routineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: String {
        let stalled = plateaus.filter { $0.kind == .stalled }.count
        let dropping = plateaus.filter { $0.kind == .strengthDrop }.count
        var parts: [String] = []
        if stalled > 0 { parts.append("\(stalled) exercise\(stalled == 1 ? " has" : "s have") stalled") }
        if dropping > 0 { parts.append("\(dropping) \(dropping == 1 ? "is" : "are") losing strength on your cut") }
        return parts.joined(separator: " and ") + ". Here's what I'd change, recruit."
    }
}

struct PlateauCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    let plateau: PhaseCoach.Plateau
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: plateau.kind == .stalled ? "arrow.right.circle.fill" : "arrow.down.right.circle.fill")
                    .foregroundStyle(plateau.kind == .stalled ? Color.orange : Color.red)
                Text(plateau.exercise.name).font(.headline)
            }
            Text(plateau.headline).font(.subheadline.bold()).foregroundStyle(.secondary)
            ForEach(Array((compact ? Array(plateau.advice.prefix(1)) : plateau.advice).enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").bold()
                    Text(tip).font(.subheadline)
                    Spacer(minLength: 4)
                    AcceptTipButton(text: tip, exercise: plateau.exercise)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Mid-workout version, shown under the exercise name.
struct WorkoutPlateauBanner: View {
    let plateau: PhaseCoach.Plateau
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Label(plateau.headline, systemImage: plateau.kind == .stalled ? "chart.line.flattrend.xyaxis" : "arrow.down.right")
                        .font(.footnote.bold())
                        .foregroundStyle(plateau.kind == .stalled ? Color.orange : Color.red)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption)
                }
            }
            .buttonStyle(.borderless)
            ForEach(Array((expanded ? plateau.advice : Array(plateau.advice.prefix(1))).enumerated()), id: \.offset) { _, tip in
                Text("• " + tip).font(.footnote)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
    }
}

// MARK: - Today card

struct PhaseCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let coach = store.phaseCoach
        let record = store.currentPhaseRecord
        let alert = coach.muscleWarning ?? coach.deloadSuggestion ?? coach.miniCutPrompt
        NavigationLink {
            PhaseView()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record?.title ?? store.nutritionPhase.title).font(.headline)
                    if let record {
                        Text("· week \(weekNumber(record))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.tertiary)
                }
                if coach.miniCutDone {
                    Label("Mini-cut finished — back to bulking?", systemImage: "flag.checkered").font(.subheadline).foregroundStyle(.green)
                } else if let alert {
                    Label(alert.title, systemImage: alert.severe ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(alert.severe ? Color.red : Color.orange)
                } else {
                    let rate = coach.rate
                    Label(rate.title, systemImage: rate.level == .good ? "checkmark.circle.fill" : "scalemass")
                        .font(.subheadline)
                        .foregroundStyle(rate.level == .good ? Color.green : (rate.level == .needData ? Color.secondary : Color.orange))
                }
                let stalled = coach.allPlateaus.count
                if stalled > 0 {
                    Text("\(stalled) lift\(stalled == 1 ? "" : "s") need attention").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    private func weekNumber(_ record: PhaseRecord) -> Int {
        max(Int(Date().timeIntervalSince(record.start) / (7 * 86_400)) + 1, 1)
    }
}

// MARK: - Phase screen

struct PhaseView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let coach = store.phaseCoach
        let record = store.currentPhaseRecord
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(record)
                alerts(coach)
                rateCard(coach)
                trendsCard(coach)
                plateauSection(coach)
                weakPointSection(coach)
                reportSection(coach)
            }
            .padding()
        }
        .navigationTitle("Phase")
        .refreshable { await store.appBecameActive() }
    }

    private func header(_ record: PhaseRecord?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record?.title ?? store.nutritionPhase.title).font(.title2.bold())
                    if let record {
                        Text("Since \(record.start.formatted(date: .abbreviated, time: .omitted))" +
                             (record.plannedEnd.map { " · ends \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    ForEach(NutritionPhase.allCases) { phase in
                        Button(phase.title) { store.setPhase(phase) }
                    }
                } label: {
                    Label("Change", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
            }
            Text(phaseGoal).font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }

    private var phaseGoal: String {
        switch store.nutritionPhase {
        case .bulking: return "Goal: gain 0.25–0.5% body weight a week and keep lifts climbing. Protein 1.6 g/kg."
        case .recomp: return "Goal: stable weight, more muscle, less fat. Protein 2.2 g/kg."
        case .cutting: return "Goal: lose 0.5–1% a week while keeping every bit of muscle and strength. Protein 2.2 g/kg."
        }
    }

    @ViewBuilder
    private func alerts(_ coach: PhaseCoach) -> some View {
        if coach.miniCutDone {
            alertCard(title: "Mini-cut done", message: "5 weeks are up. Head back into your bulk — leaner this time.",
                      color: .green, button: "Back to bulking") { store.endMiniCut() }
        }
        if let warning = coach.muscleWarning {
            alertCard(title: warning.title, message: warning.message, color: .red, button: nil) {}
        }
        if let deload = coach.deloadSuggestion {
            alertCard(title: deload.title, message: deload.message, color: .orange, button: "Start a deload week") { store.startDeloadWeek() }
        }
        if let miniCut = coach.miniCutPrompt {
            alertCard(title: miniCut.title, message: miniCut.message, color: .purple, button: "Start a 5-week mini-cut") { store.startMiniCut() }
        }
    }

    private func alertCard(title: String, message: String, color: Color, button: String?, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(color)
            Text(message).font(.subheadline)
            if let button {
                Button(button, action: action).buttonStyle(.borderedProminent).tint(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func rateCard(_ coach: PhaseCoach) -> some View {
        let rate = coach.rate
        return VStack(alignment: .leading, spacing: 6) {
            Text(store.nutritionPhase == .bulking ? "Bulk rate" : (store.nutritionPhase == .cutting ? "Cut rate" : "Weight trend"))
                .font(.caption.bold()).foregroundStyle(.secondary)
            Label(rate.title, systemImage: rate.level == .good ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(rate.level == .good ? Color.green : (rate.level == .needData ? Color.secondary : Color.orange))
            Text(rate.message).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func trendsCard(_ coach: PhaseCoach) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 4 weeks vs the 4 before").font(.caption.bold()).foregroundStyle(.secondary)
            HStack {
                stat("Muscle (lean)", coach.leanChange.map { String(format: "%+.1f kg", $0) } ?? "—",
                     color: (coach.leanChange ?? 0) >= 0 ? .green : .orange)
                stat("Strength", coach.strengthChange.map { String(format: "%+.1f%%", $0) } ?? "—",
                     color: (coach.strengthChange ?? 0) >= 0 ? .green : .orange)
                stat("Body fat", coach.fatAverage28.map { String(format: "%.1f%%", $0) } ?? "—", color: .primary)
            }
            Text("Lean mass = weight × (1 − body fat %) from Apple Health. Smart-scale body fat is noisy, so only 4-week averages are compared, and muscle-loss warnings also need strength to drop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func stat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func plateauSection(_ coach: PhaseCoach) -> some View {
        let plateaus = coach.allPlateaus
        Text(store.nutritionPhase == .cutting ? "Strength check" : "Plateaus").font(.title3.bold())
        if plateaus.isEmpty {
            Text(store.nutritionPhase == .cutting ? "No lift has dropped more than 5% — muscle is being held. 👍" : "Nothing stalled. Keep stacking reps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(plateaus) { PlateauCard(plateau: $0) }
        }
    }

    @ViewBuilder
    private func weakPointSection(_ coach: PhaseCoach) -> some View {
        let points = coach.weakPoints
        Text("Weak points").font(.title3.bold())
        if points.isEmpty {
            Text("No muscle group is falling behind (needs a few weeks of training data).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 6) {
                    Label(point.message, systemImage: "scope")
                        .font(.subheadline)
                    HStack {
                        Spacer()
                        AcceptMuscleTipButton(muscle: point.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    @ViewBuilder
    private func reportSection(_ coach: PhaseCoach) -> some View {
        Text("Report cards").font(.title3.bold())
        ForEach(store.extras.phases.reversed()) { record in
            let report = coach.report(for: record)
            NavigationLink {
                ReportCardView(report: report)
            } label: {
                HStack {
                    Text(report.grade)
                        .font(.title.bold())
                        .frame(width: 44)
                        .foregroundStyle(gradeColor(report.grade))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title + (record.end == nil ? " (so far)" : "")).font(.headline)
                        Text("\(record.start.formatted(date: .abbreviated, time: .omitted)) – \((record.end ?? .now).formatted(date: .abbreviated, time: .omitted)) · \(report.weeks) wk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }
}

func gradeColor(_ grade: String) -> Color {
    switch grade {
    case "A": return .green
    case "B": return .teal
    case "C": return .yellow
    case "D": return .orange
    default: return .red
    }
}

struct ReportCardView: View {
    let report: PhaseCoach.ReportCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(gradeColor(report.grade).opacity(0.18))
                        Text(report.grade).font(.system(size: 44, weight: .heavy)).foregroundStyle(gradeColor(report.grade))
                    }
                    .frame(width: 86, height: 86)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.record.title).font(.title2.bold())
                        Text("\(report.weeks) weeks · \(report.sessions) sessions · \(GFFormat.percent(report.adherence)) adherence")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    CluckView(mood: ["A", "B"].contains(report.grade) ? .celebrating : (report.grade == "C" ? .chill : .doomed))
                        .frame(width: 48, height: 48)
                    Text(report.verdict).font(.subheadline.italic())
                }
                .card()

                HStack {
                    tile("Weight", report.weightChange.map { String(format: "%+.1f kg", $0) })
                    tile("Lean", report.leanChange.map { String(format: "%+.1f kg", $0) })
                    tile("Body fat", report.fatChange.map { String(format: "%+.1f pts", $0) })
                    tile("Strength", report.averageStrength.map { String(format: "%+.1f%%", $0) })
                }
                .card()

                if !report.lifts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estimated 1RM, first 3 weeks → last 3 weeks").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(report.lifts.prefix(12)) { lift in
                            HStack {
                                Text(lift.id).lineLimit(1)
                                Spacer()
                                Text("\(GFFormat.kg(lift.start)) → \(GFFormat.kg(lift.end)) kg")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%+.0f%%", lift.percent))
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(lift.percent >= 0 ? Color.green : Color.red)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                    }
                    .card()
                } else {
                    Text("Lift changes appear once the phase is 4+ weeks long.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Report card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, _ value: String?) -> some View {
        VStack(spacing: 2) {
            Text(value ?? "—").font(.subheadline.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "I'll do this": remembers a coaching tip so the weekly review can check you did it and whether it worked.
struct AcceptTipButton: View {
    @EnvironmentObject private var store: PhoneAppStore
    let text: String
    let exercise: ExerciseDefinition?

    var body: some View {
        let accepted = store.isAccepted(text, exerciseKey: exercise?.historyKey)
        Button {
            store.acceptSuggestion(text, exercise: exercise)
        } label: {
            Label(accepted ? "Accepted" : "I'll do this", systemImage: accepted ? "checkmark.circle.fill" : "plus.circle")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(accepted ? .green : .accentColor)
        .disabled(accepted)
    }
}

/// "I'll do this" for a weak muscle: followed up by its weekly sets in the review.
struct AcceptMuscleTipButton: View {
    @EnvironmentObject private var store: PhoneAppStore
    let muscle: ExerciseCategory

    var body: some View {
        let accepted = store.isAccepted("\(muscle.title): add 2–3 sets a week", exerciseKey: "muscle:\(muscle.rawValue)")
        Button {
            store.acceptMuscleTip(muscle)
        } label: {
            Label(accepted ? "Accepted" : "I'll do this", systemImage: accepted ? "checkmark.circle.fill" : "plus.circle")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(accepted ? .green : .accentColor)
        .disabled(accepted)
    }
}
