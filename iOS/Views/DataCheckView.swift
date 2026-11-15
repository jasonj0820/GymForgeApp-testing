import SwiftUI

/// MK24: looks through your data for things that are probably mistakes — an 800 kg typo, a workout saved
/// twice, a day planned for a routine that no longer exists — and offers a one-tap fix for each.
/// Nothing is changed until you tap a fix.
struct DataCheckView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var confirming: DataIssue?

    var body: some View {
        let issues = DataCheck.run(logs: store.workoutLogs, routines: store.routines, plans: store.extras.dayPlans)
        List {
            if issues.isEmpty {
                ContentUnavailableView("Nothing looks wrong", systemImage: "checkmark.seal",
                                       description: Text("No impossible numbers, duplicate workouts, empty workouts or orphaned plans."))
            }
            ForEach(DataIssue.Kind.allCases, id: \.self) { kind in
                let rows = issues.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title).font(.subheadline.weight(.semibold))
                                Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                if let fix = issue.fixTitle {
                                    Button(fix, role: issue.destructive ? .destructive : nil) {
                                        if issue.destructive { confirming = issue } else { apply(issue) }
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .buttonStyle(.borderless)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(kind.title)
                    } footer: {
                        Text(kind.footer)
                    }
                }
            }
        }
        .navigationTitle("Data check-up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Usage.opened("Data check-up") }
        .confirmationDialog(confirming?.fixTitle ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { issue in
            Button(issue.fixTitle ?? "Fix", role: .destructive) { apply(issue) }
            Button("Cancel", role: .cancel) {}
        } message: { issue in
            Text(issue.title + ". A safety copy of your data is kept each time a new build opens, but this can't be undone from here.")
        }
    }

    private func apply(_ issue: DataIssue) {
        switch issue.fix {
        case .deleteSet(let workoutID, let setID):
            guard var log = store.workoutLogs.first(where: { $0.id == workoutID }) else { return }
            for index in log.exercises.indices { log.exercises[index].sets.removeAll { $0.id == setID } }
            log.exercises.removeAll { $0.sets.isEmpty }
            store.saveCorrectedWorkout(log)
        case .deleteWorkout(let id):
            if let log = store.workoutLogs.first(where: { $0.id == id }) { store.deleteWorkout(log) }
        case .removePlans(let days):
            store.extras.dayPlans.removeAll { days.contains($0.day) }
            store.saveExtras()
        case .none:
            break
        }
    }
}

struct DataIssue: Identifiable, Equatable {
    enum Kind: CaseIterable {
        case typo, duplicate, empty, orphan, lookalike
        var title: String {
            switch self {
            case .typo: return "Numbers that look like typos"
            case .duplicate: return "Workouts saved twice"
            case .empty: return "Empty workouts"
            case .orphan: return "Plans for routines that are gone"
            case .lookalike: return "Exercises that may be the same"
            }
        }
        var footer: String {
            switch self {
            case .typo: return "A set far above everything else you've lifted on that exercise skews your charts, records and the coach's next weight."
            case .duplicate: return "Same routine, started within two minutes, with the same sets."
            case .empty: return "Saved with no sets in them."
            case .orphan: return "Days in Plan week that point at a deleted routine."
            case .lookalike: return "Names that differ only in spelling don't share history, so progress is split between them. Rename one in its routine to join them."
            }
        }
    }
    enum Fix: Equatable {
        case deleteSet(workoutID: UUID, setID: UUID)
        case deleteWorkout(UUID)
        case removePlans([Date])
        case none
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let fix: Fix
    var fixTitle: String? {
        switch fix {
        case .deleteSet: return "Delete this set"
        case .deleteWorkout: return kind == .duplicate ? "Delete the second copy" : "Delete this workout"
        case .removePlans: return "Clear these days"
        case .none: return nil
        }
    }
    var destructive: Bool { fix != .none }
}

enum DataCheck {
    static func run(logs: [WorkoutLog], routines: [WorkoutRoutine], plans: [DayPlan], now: Date = .now) -> [DataIssue] {
        var issues: [DataIssue] = []
        let date = { (d: Date) in d.formatted(date: .abbreviated, time: .omitted) }

        // Typos: a set more than 2.5× the exercise's usual top weight (or over 500 kg), or 100+ reps.
        var tops: [String: [Double]] = [:]
        for log in logs { for exercise in log.exercises where !exercise.isCardio && exercise.bestWeightKg > 0 {
            tops[ExerciseLog.key(for: exercise.exerciseName), default: []].append(exercise.bestWeightKg)
        } }
        let usual = tops.mapValues { values -> Double in
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        for log in logs {
            for exercise in log.exercises where !exercise.isCardio {
                let normal = usual[ExerciseLog.key(for: exercise.exerciseName)] ?? 0
                for set in exercise.sets {
                    let tooHeavy = set.weightKg > 500 || (normal > 0 && set.weightKg > normal * 2.5 && set.weightKg - normal > 20)
                    let tooMany = set.reps >= 100
                    guard tooHeavy || tooMany else { continue }
                    issues.append(DataIssue(
                        id: "typo-\(set.id)", kind: .typo,
                        title: "\(exercise.exerciseName): \(GFFormat.kg(set.weightKg)) kg × \(set.reps)",
                        detail: date(log.startedAt) + (normal > 0 ? " · you usually top out around \(GFFormat.kg(normal)) kg" : ""),
                        fix: .deleteSet(workoutID: log.id, setID: set.id)))
                }
            }
        }

        // Saved twice.
        let sorted = logs.sorted { $0.startedAt < $1.startedAt }
        for (a, b) in zip(sorted, sorted.dropFirst())
        where a.routineID == b.routineID && b.startedAt.timeIntervalSince(a.startedAt) < 120
            && a.exercises.flatMap(\.sets).map { "\($0.weightKg)x\($0.reps)" } == b.exercises.flatMap(\.sets).map { "\($0.weightKg)x\($0.reps)" } {
            issues.append(DataIssue(id: "dup-\(b.id)", kind: .duplicate, title: "\(b.routineName), \(date(b.startedAt))",
                                    detail: "\(b.exercises.reduce(0) { $0 + $1.sets.count }) sets, saved twice", fix: .deleteWorkout(b.id)))
        }

        // Empty.
        for log in logs where log.exercises.allSatisfy({ $0.sets.isEmpty }) && log.routineID != CardioIDs.run && log.routineID != CardioIDs.basketball {
            issues.append(DataIssue(id: "empty-\(log.id)", kind: .empty, title: "\(log.routineName), \(date(log.startedAt))",
                                    detail: "No sets logged", fix: .deleteWorkout(log.id)))
        }

        // Plans pointing at a deleted routine.
        let ids = Set(routines.map(\.id)).union([CardioIDs.run, CardioIDs.basketball, FixedSplit.microChestID])
        let orphans = plans.filter { $0.kind == .workout && $0.routineID.map { !ids.contains($0) } == true && $0.day >= Calendar.current.startOfDay(for: now) }
        if !orphans.isEmpty {
            issues.append(DataIssue(id: "orphans", kind: .orphan,
                                    title: "\(orphans.count) planned day\(orphans.count == 1 ? "" : "s")",
                                    detail: orphans.map { "\(date($0.day)): \($0.routineName ?? "a deleted routine")" }.joined(separator: " · "),
                                    fix: .removePlans(orphans.map(\.day))))
        }

        // Look-alike names: the same letters once spaces, punctuation and a trailing "s" are ignored.
        func loose(_ name: String) -> String {
            var letters = name.lowercased().filter { $0.isLetter || $0.isNumber }
            if letters.hasSuffix("s") { letters.removeLast() }
            return letters
        }
        var names = Set(routines.flatMap { $0.exercises.map(\.exercise.name) })
        for log in logs { for exercise in log.exercises { names.insert(exercise.exerciseName) } }
        let groups = Dictionary(grouping: names, by: loose).values
            .filter { Set($0.map { ExerciseLog.key(for: $0) }).count > 1 }
        for group in groups {
            let list = group.sorted()
            issues.append(DataIssue(id: "alike-\(list.joined())", kind: .lookalike, title: list.joined(separator: " / "),
                                    detail: "Counted as \(list.count) separate exercises", fix: .none))
        }
        return issues
    }
}
