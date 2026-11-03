import SwiftUI

/// Plan the week day by day: a workout, rest, sick or travel. Sick and travel days take a session off
/// the week's goal and stand Sergeant Cluck down; travel days offer a no-equipment hotel workout.
struct WeekPlanView: View {
    @EnvironmentObject private var store: PhoneAppStore
    /// 0 = this week, 1 = next week.
    @State private var weekOffset: Int

    init(nextWeek: Bool = false) {
        _weekOffset = State(initialValue: nextWeek ? 1 : 0)
    }
    @State private var confirmClear = false
    @State private var showAutoPlan = false

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Monday, like the Today row
        cal.timeZone = .current
        return cal
    }

    private var days: [Date] {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        let offset = (cal.component(.weekday, from: today) + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -offset + weekOffset * 7, to: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        let excused = days.filter { store.extras.isExcused($0) }.count
        List {
            Section {
                Picker("Week", selection: $weekOffset) {
                    Text("This week").tag(0)
                    Text("Next week").tag(1)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Weekly goal \(store.weeklyGoal)" + (excused > 0 ? " − \(excused) sick/travel = \(max(store.weeklyGoal - excused, 0)) sessions" : " sessions") + ".")
            }

            Section {
                ForEach(days, id: \.self) { day in
                    dayRow(day)
                }
            } footer: {
                Text("Planned workouts show up first on Today. Runs and basketball are optional extras (only weight training counts toward the goal). Sergeant Cluck is chill on rest days you plan ahead (the day before or earlier) and stands down on sick and travel days. A rest day declared on the day still gets you nagged.")
            }

            Section {
                Button {
                    showAutoPlan = true
                } label: {
                    Label("Auto-plan the open days", systemImage: "wand.and.stars")
                }
                Button {
                    store.copyPreviousWeek(into: days)
                } label: {
                    Label("Copy the week before", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("Only fills days that are still open, from today on.")
            }

            Section {
                NavigationLink {
                    GiveMeABreakView()
                } label: {
                    Label(store.activeBreak == nil ? "Give me a break" : "On a break — details", systemImage: "pause.circle")
                }
            } footer: {
                Text("For genuinely busy stretches (2+ assignments due, a work crunch, a move). Hard to switch on, on purpose.")
            }

            Section {
                Button("Clear this week's plan", role: .destructive) { confirmClear = true }
                NavigationLink {
                    WeeklyReviewView()
                } label: {
                    Label("Weekly review", systemImage: "chart.bar.doc.horizontal")
                }
            }
        }
        .navigationTitle("Plan week")
        .sheet(isPresented: $showAutoPlan) {
            NavigationStack { AutoPlanSheet(days: days) }
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Clear the plan for this week?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                if let first = days.first { store.clearWeekPlan(containing: first) }
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let choice = store.dayChoice(on: day)
        let done = store.workoutLogs.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                    .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : .primary)
                Text(day.formatted(.dateTime.day().month()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !done.isEmpty {
                Label(done.map(\.routineName).joined(separator: ", "), systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Menu {
                Button { store.setDay(day, to: .unplanned) } label: { Label("Nothing planned", systemImage: "circle") }
                Section("Workout") {
                    ForEach(store.routines.filter { !$0.exercises.isEmpty }) { routine in
                        Button(routine.name) { store.setDay(day, to: .routine(routine.id)) }
                    }
                }
                Section("Cardio") {
                    Button { store.setDay(day, to: .run) } label: { Label("Run", systemImage: "figure.run") }
                    Button { store.setDay(day, to: .basketball) } label: { Label("Basketball", systemImage: "basketball") }
                }
                Button { store.setDay(day, to: .rest) } label: { Label("Rest day", systemImage: "moon.zzz") }
                Button { store.setDay(day, to: .ill) } label: { Label("Sick", systemImage: "cross.case") }
                Button { store.setDay(day, to: .travel) } label: { Label("Travel", systemImage: "airplane") }
            } label: {
                choiceLabel(choice)
            }
        }
    }

    private func choiceLabel(_ choice: PhoneAppStore.DayChoice) -> some View {
        let text: String
        let symbol: String
        let color: Color
        switch choice {
        case .unplanned:
            text = "Plan"; symbol = "plus.circle"; color = .secondary
        case .rest:
            text = "Rest"; symbol = "moon.zzz.fill"; color = .indigo
        case .ill:
            text = "Sick"; symbol = "cross.case.fill"; color = .red
        case .travel:
            text = "Travel"; symbol = "airplane"; color = .teal
        case .run:
            text = "Run"; symbol = "figure.run"; color = .green
        case .basketball:
            text = "Basketball"; symbol = "basketball"; color = .orange
        case .routine(let id):
            text = store.routines.first { $0.id == id }?.name ?? "Workout"; symbol = "dumbbell.fill"; color = .orange
        }
        return Label(text, systemImage: symbol)
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Today's plan on the Today screen (planned workout, sick or travel day).
struct TodayPlanCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        switch store.todayPlanKind {
        case .travel?:
            VStack(alignment: .leading, spacing: 8) {
                Label("Travel day", systemImage: "airplane").font(.headline).foregroundStyle(.teal)
                Text("No gym? Try a 20-minute hotel workout: push-ups, squats, pike push-ups, lunges, glute bridges and a plank. It doesn't count against your week either way.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await store.startTravelWorkout() }
                } label: {
                    Label("Start hotel workout", systemImage: "figure.strengthtraining.functional")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(store.activeWorkout != nil)
                planLink
            }
            .card()
        case .ill?:
            VStack(alignment: .leading, spacing: 6) {
                Label("Sick day", systemImage: "cross.case.fill").font(.headline).foregroundStyle(.red)
                Text("Rest up. This week's goal is lowered and Sergeant Cluck is standing down.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                planLink
            }
            .card()
        case .workout?:
            if let cardio = plannedCardioToday {
                HStack {
                    Label("Planned today: \(cardio == .run ? "Run" : "Basketball")", systemImage: cardio == .run ? "figure.run" : "basketball")
                        .font(.subheadline.bold())
                    Spacer()
                    planLink
                }
                .card()
            } else if let routine = store.plannedRoutineToday {
                HStack {
                    Label("Planned today: \(routine.name)", systemImage: "calendar.badge.clock")
                        .font(.subheadline.bold())
                    Spacer()
                    planLink
                }
                .card()
            } else {
                planLink.card()
            }
        case nil:
            if store.extras.isPlannedRestDay(.now) && !store.workoutLogs.contains(where: { Calendar.current.isDateInToday($0.startedAt) }) {
                HStack {
                    Label("Planned rest day — Sergeant Cluck is off duty", systemImage: "moon.zzz.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.indigo)
                    Spacer()
                    planLink
                }
                .card()
            } else if store.weekNeedsPlan {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Plan your week", systemImage: "calendar").font(.headline)
                    Text("Pick your training and rest days — planned rest days keep Sergeant Cluck calm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    planLink
                }
                .card()
            } else {
                planLink.card()
            }
        }
    }

    /// A run / basketball planned for today and not done yet.
    private var plannedCardioToday: ActivityKind? {
        guard let id = store.extras.dayPlan(on: .now)?.routineID else { return nil }
        let kind: ActivityKind? = id == CardioIDs.run ? .run : (id == CardioIDs.basketball ? .basketball : nil)
        guard let kind, !store.workoutLogs.contains(where: { $0.routineID == id && Calendar.current.isDateInToday($0.startedAt) }) else { return nil }
        return kind
    }

    private var planLink: some View {
        NavigationLink {
            WeekPlanView()
        } label: {
            Label("Plan week", systemImage: "calendar")
                .font(.subheadline)
        }
    }
}

/// Pick your training days; routines go on them in order, rest on the others.
struct AutoPlanSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let days: [Date]
    @State private var weekdays: Set<Int> = []
    @State private var restOthers = true

    var body: some View {
        Form {
            Section {
                ForEach(days, id: \.self) { day in
                    let weekday = Calendar.current.component(.weekday, from: day)
                    Toggle(day.formatted(.dateTime.weekday(.wide)), isOn: Binding(
                        get: { weekdays.contains(weekday) },
                        set: { on in if on { weekdays.insert(weekday) } else { weekdays.remove(weekday) } }))
                }
            } header: {
                Text("Training days")
            } footer: {
                Text("\(weekdays.count) day\(weekdays.count == 1 ? "" : "s") · weekly goal \(store.weeklyGoal). Pre-selected from the days you usually train.")
            }
            Section {
                Toggle("Plan the other days as rest", isOn: $restOthers)
            } footer: {
                Text("Rest days planned ahead keep Sergeant Cluck calm on the day.")
            }
            Section {
                Button {
                    store.autoPlan(days: days, trainingWeekdays: weekdays, restOthers: restOthers)
                    dismiss()
                } label: {
                    Label("Fill the week", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(weekdays.isEmpty && !restOthers)
            }
        }
        .navigationTitle("Auto-plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if weekdays.isEmpty { weekdays = store.usualTrainingWeekdays() } }
    }
}
