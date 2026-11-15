import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Lift goal (72)

/// On a lift's page: set a target weight and see when you'll get there at your current rate.
struct LiftGoalCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    let exercise: ExerciseDefinition
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        if !exercise.isCardio, !exercise.isBodyweight, !exercise.isAssisted {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Goal", systemImage: "flag.checkered").font(.headline)
                    Spacer()
                    Button(store.liftGoal(for: exercise) == nil ? "Set a goal" : "Change") {
                        draft = store.liftGoal(for: exercise).map { GFFormat.kg($0) } ?? ""
                        editing = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
                if let goal = store.liftGoal(for: exercise), let outcome = store.goalOutcome(for: exercise) {
                    Text("\(exercise.formatLoad(goal)) for a working set").font(.title3.bold())
                    Text(LiftGoalText.line(outcome)).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("A target weight, and the date you'd reach it at the rate you're climbing.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .card()
            .alert("Goal for \(exercise.name)", isPresented: $editing) {
                TextField("kg", text: $draft).keyboardType(.decimalPad)
                Button("Save") { store.setLiftGoal(Double(draft.replacingOccurrences(of: ",", with: ".")), for: exercise) }
                if store.liftGoal(for: exercise) != nil {
                    Button("Remove goal", role: .destructive) { store.setLiftGoal(nil, for: exercise) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The heaviest weight you want to lift for a working set.")
            }
        }
    }
}

enum LiftGoalText {
    static func line(_ outcome: GoalProjection.Outcome) -> String {
        switch outcome {
        case .reached(let date):
            return "Done: you first lifted it on \(date.formatted(date: .abbreviated, time: .omitted)). Time for a new one."
        case .onTrack(let date, let perWeek):
            return "≈ \(date.formatted(.dateTime.day().month(.abbreviated).year())) at +\(String(format: "%.1f", perWeek)) kg a week."
        case .flat:
            return "Not climbing over the last 12 weeks, so no date yet. The coach's next-step advice will get it moving."
        case .tooFew:
            return "A date shows after 3 sessions over 2 weeks."
        }
    }
}

/// Coach → every lift with a goal.
struct LiftGoalsSection: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let exercises = store.goalExercises
        if !exercises.isEmpty {
            Section {
                ForEach(exercises, id: \.historyKey) { exercise in
                    NavigationLink {
                        LiftDetailView(exercise: exercise, range: .threeMonths)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(exercise.name) → \(store.liftGoal(for: exercise).map { exercise.formatLoad($0) } ?? "")").font(.headline)
                            if let outcome = store.goalOutcome(for: exercise) {
                                Text(LiftGoalText.line(outcome)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Lift goals")
            } footer: {
                Text("Set one from any lift's page in Progress.")
            }
        }
    }
}

// MARK: - What changed this week and why (73)

struct WeekChangesView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let changes = store.weekChanges
        List {
            Section {
                Label("\(store.thisWeekGoal) session\(store.thisWeekGoal == 1 ? "" : "s") this week", systemImage: "target")
                    .font(.headline)
                let reasons = store.goalReasons
                if reasons.isEmpty {
                    Text("Your usual weekly goal.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(reasons, id: \.self) { Text($0).font(.subheadline) }
                if let label = EffortTarget.blockLabel(profile: store.profile) {
                    Label(label, systemImage: "chart.bar.doc.horizontal").font(.subheadline)
                }
            } header: {
                Text("The plan")
            }
            group("Going up", icon: "arrow.up.circle.fill", color: .green, changes.up,
                  footer: "You hit the top of the rep range on every set last time.")
            group("Same weight, more reps", icon: "equal.circle.fill", color: .blue, changes.hold,
                  footer: "Inside the rep range: add reps before weight.")
            group("Coming down", icon: "arrow.down.circle.fill", color: .orange, changes.down,
                  footer: "Below the rep range last time, so a little lighter to get back in it.")
            if changes.up.isEmpty && changes.hold.isEmpty && changes.down.isEmpty {
                Text("Nothing to show until you've done your routines once.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("This week's changes")
    }

    @ViewBuilder
    private func group(_ title: String, icon: String, color: Color, _ rows: [PhoneAppStore.WeekChange], footer: String) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { change in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(change.exercise).font(.headline)
                            Spacer()
                            Text(change.title).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                        }
                        Text(change.why).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label(title, systemImage: icon).foregroundStyle(color)
            } footer: {
                Text(footer)
            }
        }
    }
}

// MARK: - Accessory rotation (74)

struct AccessoryRotationView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<UUID> = []

    var body: some View {
        let plan = store.accessoryRotationPlan
        List {
            if plan.isEmpty {
                Text("None of your accessories have a swap option yet. Add one from the workout screen (Swap → Add swap option) or the routine editor.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(plan) { swap in
                    Button {
                        if picked.contains(swap.id) { picked.remove(swap.id) } else { picked.insert(swap.id) }
                    } label: {
                        HStack {
                            Image(systemName: picked.contains(swap.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked.contains(swap.id) ? Color.green : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(swap.from) → \(swap.to.name)").font(.headline)
                                Text(swap.routineName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if !plan.isEmpty {
                    Text("A fresh angle on the small muscles each block, while the main lifts stay the same so they keep climbing. Each keeps its own history; the old one stays as a swap option.")
                }
            }
            if !plan.isEmpty {
                Section {
                    Button("Rotate \(picked.count) exercise\(picked.count == 1 ? "" : "s")") {
                        store.rotateAccessories(plan.filter { picked.contains($0.id) })
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                    Button("Keep them this block") {
                        store.markRotationHandled()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Rotate accessories")
        .onAppear { picked = Set(plan.map(\.id)) }
    }
}

// MARK: - Busy weeks (76)

/// Suggests easing the goal when the calendar has exams or deadlines this week; or set it by hand.
struct BusyWeekSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage("busy.dismissedWeek") private var dismissedWeek = 0.0

    var body: some View {
        let start = store.weekStart(of: .now)
        let busy = store.busyWeek(of: .now)
        let heavy = store.heavyEvents(inWeekOf: .now)
        Section {
            if let busy {
                Label("Busy week: goal eased by \(busy.fewer)", systemImage: "briefcase.fill")
                Stepper("Fewer sessions: \(busy.fewer)", value: Binding(
                    get: { busy.fewer },
                    set: { store.setBusyWeek(of: .now, fewer: $0, reason: busy.reason) }
                ), in: 0...3)
            } else if !heavy.isEmpty, dismissedWeek != start.timeIntervalSince1970 {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(heavy.count) big thing\(heavy.count == 1 ? "" : "s") in your calendar this week", systemImage: "calendar.badge.exclamationmark")
                        .font(.headline)
                    Text(heavy.prefix(3).map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Ease the goal by 1") { store.setBusyWeek(of: .now, fewer: 1, reason: heavy.first?.title) }
                            .buttonStyle(.borderedProminent)
                        Button("Not needed") { dismissedWeek = start.timeIntervalSince1970 }
                            .buttonStyle(.bordered)
                    }
                    .font(.subheadline)
                }
            } else {
                Button {
                    store.setBusyWeek(of: .now, fewer: 1, reason: nil)
                } label: {
                    Label("Busy week? Ease the goal by 1", systemImage: "briefcase")
                }
            }
        } header: {
            Text("This week")
        } footer: {
            Text("Exams, deadlines or a heavy work week. The goal, Sergeant Cluck and the weekly review all use the eased goal.")
        }
    }
}

// MARK: - Ask the coach (78)

@MainActor
enum AskCoach {
    /// nil when Apple's on-device model can answer.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return "This needs an iPhone 15 Pro or later."
                case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in the iPhone's Settings to use this."
                case .modelNotReady: return "Apple's model is still downloading. Try again in a while."
                @unknown default: return "Apple's on-device model isn't available right now."
                }
            }
        }
        return "This needs iOS 26."
        #else
        return "This needs iOS 26 on an iPhone 15 Pro or later."
        #endif
    }

    static let instructions = """
    You are the coach inside Splitday, a gym app. Answer the lifter's question in plain English, in 2 to 6 short \
    sentences, using the training summary you're given. Be specific: name lifts, weights and days from the summary. \
    If the summary doesn't contain the answer, say so briefly and give general, safe advice. Never give medical \
    advice; for pain or injury, suggest seeing a physio. Use kilograms.
    """

    static func answer(_ question: String, context: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: "Training summary:\n\(context)\n\nQuestion: \(question)")
                return response.content
            } catch {
                return "The coach couldn't answer that one (\(error.localizedDescription))."
            }
        }
        #endif
        return unavailableReason ?? "Not available."
    }
}

struct AskCoachView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var question = ""
    @State private var answers: [QA] = []
    @State private var thinking = false
    @FocusState private var focused: Bool

    struct QA: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let suggestions = ["Why is my bench stuck?", "Should I train today?", "What should I focus on this week?",
                               "Am I doing enough for my back?"]

    var body: some View {
        List {
            if let reason = AskCoach.unavailableReason {
                Section {
                    Label(reason, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
            }
            Section {
                TextField("Ask about your training…", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(ask)
                Button {
                    ask()
                } label: {
                    if thinking { HStack { SwiftUI.ProgressView(); Text("Thinking…") } } else { Label("Ask", systemImage: "paperplane.fill") }
                }
                .disabled(thinking || question.trimmingCharacters(in: .whitespaces).isEmpty || AskCoach.unavailableReason != nil)
            } footer: {
                Text("Runs on your iPhone with Apple's on-device model. It's given a summary of your last 8 weeks; nothing leaves the phone.")
            }
            if answers.isEmpty {
                Section("Try") {
                    ForEach(suggestions, id: \.self) { text in
                        Button(text) { question = text; ask() }
                            .disabled(AskCoach.unavailableReason != nil)
                    }
                }
            }
            ForEach(answers.reversed()) { qa in
                Section {
                    Text(qa.answer).textSelection(.enabled)
                } header: {
                    Text(qa.question).textCase(nil).font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationTitle("Ask the coach")
    }

    private func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !thinking else { return }
        thinking = true
        focused = false
        let context = store.coachContext
        Task {
            let reply = await AskCoach.answer(text, context: context)
            answers.append(QA(question: text, answer: reply))
            question = ""
            thinking = false
        }
    }
}
