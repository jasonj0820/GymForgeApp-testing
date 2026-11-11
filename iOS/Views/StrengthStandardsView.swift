import SwiftUI

/// Your best estimated 1RM on the big lifts versus typical strength levels, as multiples of
/// body weight. Approximate standards for men, for orientation only.
struct StrengthStandardsView: View {
    @EnvironmentObject private var store: PhoneAppStore

    struct Lift: Identifiable {
        let id: String
        let title: String
        let keywords: [String]
        let exclude: [String]
        /// Beginner, novice, intermediate, advanced, elite (× body weight).
        let levels: [Double]
    }

    static let lifts: [Lift] = [
        Lift(id: "bench", title: "Bench press", keywords: ["bench"], exclude: ["incline", "decline", "dumbbell", "db "], levels: [0.5, 0.75, 1.0, 1.5, 2.0]),
        Lift(id: "squat", title: "Squat", keywords: ["squat"], exclude: ["split", "goblet", "hack", "front", "bulgarian"], levels: [0.75, 1.25, 1.5, 2.25, 2.75]),
        Lift(id: "deadlift", title: "Deadlift", keywords: ["deadlift"], exclude: ["romanian", "rdl", "stiff"], levels: [1.0, 1.5, 2.0, 2.5, 3.0]),
        Lift(id: "ohp", title: "Overhead press", keywords: ["overhead press", "military", "ohp", "shoulder press"], exclude: ["dumbbell", "machine", "db "], levels: [0.35, 0.55, 0.75, 1.0, 1.4]),
        Lift(id: "row", title: "Barbell row", keywords: ["row"], exclude: ["cable", "seated", "machine", "dumbbell", "upright", "db "], levels: [0.5, 0.75, 1.0, 1.5, 1.75]),
    ]
    static let levelNames = ["Beginner", "Novice", "Intermediate", "Advanced", "Elite"]

    var body: some View {
        let bodyWeight = store.latestBodyWeightKg
        VStack(alignment: .leading, spacing: 14) {
            if let bodyWeight, bodyWeight > 0 {
                Text("Best estimated 1RM ÷ body weight (\(GFFormat.kg(bodyWeight)) kg)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(Self.lifts) { lift in
                    row(lift, bodyWeight: bodyWeight)
                }
                Text("Approximate standards for men, from common strength tables. Lifts are matched by exercise name; estimated 1RM uses your best set in the last 6 months.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Need your body weight", systemImage: "scalemass",
                                       description: Text("Log your weight on the Body tab so standards can be scaled to you."))
            }
        }
    }

    private func best(for lift: Lift) -> (name: String, e1rm: Double)? {
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .distantPast
        var result: (String, Double)?
        for log in store.workoutLogs where log.startedAt >= cutoff {
            for exercise in log.exercises where !exercise.isCardio {
                let name = exercise.exerciseName.lowercased()
                guard lift.keywords.contains(where: { name.contains($0) }),
                      !lift.exclude.contains(where: { name.contains($0) }) else { continue }
                let value = exercise.estimatedOneRepMaxKg
                if value > (result?.1 ?? 0) { result = (exercise.exerciseName, value) }
            }
        }
        return result.map { (name: $0.0, e1rm: $0.1) }
    }

    @ViewBuilder
    private func row(_ lift: Lift, bodyWeight: Double) -> some View {
        let best = best(for: lift)
        let ratio = (best?.e1rm ?? 0) / bodyWeight
        let levelIndex = lift.levels.lastIndex(where: { ratio >= $0 })
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(lift.title).font(.headline)
                Spacer()
                if let best {
                    Text("\(GFFormat.kg(best.e1rm)) kg · \(String(format: "%.2f", ratio))×")
                        .font(.subheadline.monospacedDigit())
                } else {
                    Text("No data").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            StandardsBar(levels: lift.levels, ratio: best == nil ? nil : ratio)
            if best != nil {
                let next = levelIndex.map { $0 + 1 } ?? 0
                Text(levelText(levelIndex: levelIndex, next: next, lift: lift, bodyWeight: bodyWeight))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func levelText(levelIndex: Int?, next: Int, lift: Lift, bodyWeight: Double) -> String {
        let current = levelIndex.map { Self.levelNames[$0] } ?? "Below beginner"
        guard next < lift.levels.count else { return current + " — top of the table." }
        let target = lift.levels[next] * bodyWeight
        return current + " · \(Self.levelNames[next]) at \(GFFormat.kg((target / 2.5).rounded() * 2.5)) kg"
    }
}

struct StandardsBar: View {
    let levels: [Double]
    let ratio: Double?

    var body: some View {
        GeometryReader { geo in
            let maxValue = (levels.last ?? 1) * 1.1
            let x = { (value: Double) -> CGFloat in CGFloat(min(value / maxValue, 1)) * geo.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 10)
                Capsule()
                    .fill(LinearGradient(colors: [.gray, .blue, .green, .orange, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x(ratio ?? 0), height: 10)
                ForEach(levels.indices, id: \.self) { index in
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1.5, height: 16)
                        .offset(x: x(levels[index]))
                }
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }
}
