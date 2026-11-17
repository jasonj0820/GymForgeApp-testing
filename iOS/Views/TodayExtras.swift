import SwiftUI

// MARK: - + menu (MK24, 44)

enum QuickAdd: String, Identifiable {
    case protein, calories, note
    var id: String { rawValue }
}

/// The + in Today's toolbar: protein, calories, weight or a note in two taps.
struct QuickAddMenu: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Binding var sheet: QuickAdd?
    @Binding var showWeighIn: Bool

    var body: some View {
        Menu {
            Button { sheet = .protein } label: { Label("Protein", systemImage: "fork.knife") }
            Button { sheet = .calories } label: { Label("Calories", systemImage: "flame") }
            Button { showWeighIn = true } label: { Label("Weight", systemImage: "scalemass") }
            Button { sheet = .note } label: { Label("Note", systemImage: "note.text") }
            Divider()
            // MK24 (110): tonight's a big one.
            Button { store.toggleBigNight() } label: {
                Label(store.isBigNight(store.bigNightTonightDate) ? "Not a big night after all" : "Big night out tonight", systemImage: "party.popper")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .accessibilityLabel("Add protein, calories, weight or a note")
    }
}

struct QuickAddSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let kind: QuickAdd
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if kind == .note {
                    Section {
                        TextField("How training felt, a niggle, what you ate…", text: $text, axis: .vertical)
                            .lineLimit(4...10)
                            .focused($focused)
                    } footer: {
                        Text("Notes stay on today and show on the Today screen.")
                    }
                } else {
                    let today = store.extras.nutrition(on: .now)
                    Section {
                        TextField(kind == .protein ? "Grams" : "kcal", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($focused)
                            .font(.title2.monospacedDigit())
                        HStack {
                            ForEach(chips, id: \.self) { value in
                                Button("+\(Int(value))") { add(value) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } footer: {
                        if kind == .protein {
                            Text("So far today: \(Int(today?.proteinG ?? 0)) g" + (store.proteinTargetG.map { " of \(Int($0)) g" } ?? ""))
                        } else {
                            Text("So far today: \(Int(today?.calories ?? 0)) kcal")
                        }
                    }
                }
            }
            .navigationTitle(kind == .protein ? "Add protein" : (kind == .calories ? "Add calories" : "Note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(kind == .note ? "Save" : "Add") {
                        if kind == .note { store.addDayNote(text); Haptics.success(); dismiss() }
                        else if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 { add(value) }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var chips: [Double] { kind == .protein ? [20, 30, 40, 50] : [200, 400, 600, 800] }

    private func add(_ value: Double) {
        if kind == .protein { store.addProtein(value) } else { store.addCalories(value) }
        Haptics.success()
        dismiss()
    }
}

/// Today's notes, if any. Long-press one to delete it.
struct DayNotesCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        let notes = store.todaysNotes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text").font(.headline)
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline) {
                        Text(note.text).font(.subheadline)
                        Spacer()
                        Text(note.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button(role: .destructive) { store.deleteDayNote(note.id) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .card()
        }
    }
}

// MARK: - Timeline of the day (46)

/// Your calendar, the gym and bedtime in one list. Only once you've turned the calendar on.
struct DayTimelineCard: View {
    @EnvironmentObject private var store: PhoneAppStore

    private struct Row: Identifiable {
        let id: String
        let time: Date
        let end: Date?
        let title: String
        let icon: String
        let tint: Color
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let items = rows(now: context.date)
            if DayAgenda.enabled, !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your day", systemImage: "calendar.day.timeline.left").font(.headline)
                    ForEach(items) { row in
                        let past = (row.end ?? row.time) < context.date
                        HStack(spacing: 10) {
                            Text(row.time.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 74, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Image(systemName: row.icon).foregroundStyle(row.tint).frame(width: 20)
                            Text(row.title).font(.subheadline.weight(row.icon == "dumbbell.fill" ? .semibold : .regular))
                            Spacer()
                        }
                        .opacity(past ? 0.45 : 1)
                    }
                }
                .card()
            }
        }
    }

    private func rows(now: Date) -> [Row] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        var rows = DayAgenda.events(on: now).filter { !$0.allDay }.map {
            Row(id: $0.id, time: $0.start, end: $0.end, title: $0.title, icon: "calendar", tint: .blue)
        }
        let trained = store.workoutLogs.contains { $0.countsAsTraining && cal.isDateInToday($0.startedAt) }
        if !trained, let session = store.plannedSessionName(on: now),
           let minutes = store.usualStartMinutes(weekday: cal.component(.weekday, from: now)),
           let start = cal.date(byAdding: .minute, value: minutes, to: day) {
            rows.append(Row(id: "gym", time: start, end: start.addingTimeInterval(3600), title: "\(session) (your usual time)",
                            icon: "dumbbell.fill", tint: .green))
        }
        if let bed = store.tonightsBedtime(now: now), cal.isDate(bed.addingTimeInterval(-6 * 3600), inSameDayAs: now) {
            rows.append(Row(id: "bed", time: bed, end: nil, title: "Bed", icon: "moon.stars.fill", tint: .indigo))
        }
        return rows.sorted { $0.time < $1.time }
    }
}

// MARK: - Sunday reset (48)

/// Sunday's jobs in one place: weigh in, look back at the week, plan the next one, meal prep.
struct SundayResetView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @EnvironmentObject private var dayfold: DayfoldStore
    @State private var showWeighIn = false

    nonisolated static let reviewOpenedKey = "review.lastOpened"

    struct Step: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let done: Bool
    }

    @MainActor
    static func steps(store: PhoneAppStore, dayfold: DayfoldStore?, now: Date = .now) -> [Step] {
        let cal = Calendar.current
        var steps: [Step] = []
        let weighIn = store.extras.weighIn(on: now)
        steps.append(Step(id: "weigh", title: "Weigh in", detail: weighIn?.weightKg.map { "\(String(format: "%.1f", $0)) kg" } ?? "First thing, before food",
                          icon: "scalemass", done: weighIn != nil))
        let reviewed = (UserDefaults.standard.object(forKey: reviewOpenedKey) as? Date).map { cal.isDate($0, inSameDayAs: now) } ?? false
        steps.append(Step(id: "review", title: "Look back at the week", detail: "Sessions, PRs and what to change",
                          icon: "calendar.badge.checkmark", done: reviewed))
        let nextWeek = (1...7).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
        let planned = nextWeek.contains { store.extras.dayPlan(on: $0) != nil || store.extras.isRestDay($0) }
        // MK24.2: with the fixed split on, the split already sets the days (Today stopped asking in MK21), so
        // this one is done unless you want to mark sick, travel or rest days.
        let bySplit = !planned && store.fixedSplitOn
        steps.append(Step(id: "plan", title: "Plan next week",
                          detail: planned ? "Planned" : (bySplit ? "Your fixed split sets the days" : "Which days you'll train"),
                          icon: "calendar", done: planned || bySplit))
        if let prep = dayfold?.rows(.weekly, now: now).first(where: { $0.task.id == RoutineTask.mealPrepID }) {
            steps.append(Step(id: "prep", title: "Meal prep", detail: prep.task.title, icon: "takeoutbag.and.cup.and.straw", done: prep.done))
        }
        return steps
    }

    var body: some View {
        let steps = Self.steps(store: store, dayfold: dayfold)
        List {
            Section {
                ForEach(steps) { step in
                    row(step)
                }
            } footer: {
                Text("\(steps.filter(\.done).count) of \(steps.count) done. Each step ticks itself when you do it.")
            }
        }
        .navigationTitle("Sunday reset")
        .sheet(isPresented: $showWeighIn) { WeighInSheet().environmentObject(store) }
    }

    @ViewBuilder
    private func row(_ step: Step) -> some View {
        let label = HStack(spacing: 12) {
            Image(systemName: step.done ? "checkmark.circle.fill" : step.icon)
                .font(.title3)
                .foregroundStyle(step.done ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.headline).strikethrough(step.done, color: .secondary)
                Text(step.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        switch step.id {
        case "plan":
            NavigationLink { WeekPlanView(nextWeek: true) } label: { label }
        case "weigh":
            Button { showWeighIn = true } label: { label }.buttonStyle(.plain)
        case "review":
            Button { store.showWeeklyReview = true } label: { label }.buttonStyle(.plain)
        default:
            Button {
                if let prep = dayfold.rows(.weekly).first(where: { $0.task.id == RoutineTask.mealPrepID }) {
                    dayfold.setDone(prep, done: !prep.done)
                    Haptics.tap()
                }
            } label: { label }.buttonStyle(.plain)
        }
    }
}

/// On Sundays until it's all done.
struct SundayResetCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @EnvironmentObject private var dayfold: DayfoldStore

    var body: some View {
        if Calendar.current.component(.weekday, from: .now) == 1 {
            let steps = SundayResetView.steps(store: store, dayfold: dayfold)
            let done = steps.filter(\.done).count
            if done < steps.count {
                NavigationLink { SundayResetView() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Sunday reset", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                            Spacer()
                            Text("\(done) of \(steps.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        ProgressView(value: Double(done), total: Double(steps.count)).tint(.green)
                        Text(steps.filter { !$0.done }.map(\.title).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Settings → Sounds and reminders → Your day

struct YourDaySettingsSection: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage(DailyNudges.briefOnKey) private var briefOn = true
    @AppStorage(DailyNudges.briefMinutesKey) private var briefMinutes = 7 * 60
    @AppStorage(DailyNudges.gymOnKey) private var gymOn = true
    @AppStorage(DailyNudges.travelKey) private var travel = 20
    @AppStorage(DayAgenda.enabledKey) private var calendarOn = false
    @State private var calendarDenied = false

    var body: some View {
        Section {
            Toggle("Morning brief", isOn: $briefOn)
            if briefOn {
                DatePicker("At", selection: Binding(
                    get: { Calendar.current.date(byAdding: .minute, value: briefMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now },
                    set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); briefMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0) }
                ), displayedComponents: .hourAndMinute)
                let preview = DailyNudges.briefLines(store: store, on: .now)
                Text("\(preview.title) — \(preview.body)").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Leave for the gym", isOn: $gymOn)
            if gymOn {
                Stepper("Travel time: \(travel) min", value: $travel, in: 0...90, step: 5)
                let weekday = Calendar.current.component(.weekday, from: .now)
                if let usual = store.usualStartMinutes(weekday: weekday) {
                    Text("You usually start around \((Calendar.current.date(byAdding: .minute, value: usual, to: Calendar.current.startOfDay(for: .now)) ?? .now).formatted(date: .omitted, time: .shortened)) on \(Date.now.formatted(.dateTime.weekday(.wide)))s.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Starts once there are a few weeks of sessions to learn your usual time from.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Show my calendar on Today", isOn: Binding(
                get: { calendarOn && DayAgenda.hasAccess },
                set: { on in
                    if on {
                        Task {
                            let granted = await DayAgenda.requestAccess()
                            calendarOn = granted
                            calendarDenied = !granted
                        }
                    } else {
                        calendarOn = false
                    }
                }
            ))
            if calendarDenied {
                Text("Calendar access is off for Splitday. Turn it on in the iPhone's Settings → Apps → Splitday → Calendars.")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Your day")
        } footer: {
            Text("The brief sums up today: your session, protein target, routine steps and bedtime. The gym nudge comes at your usual start time minus travel, only on days with a session still to do, and not if your calendar has something on then.")
        }
        .onChange(of: briefOn) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: briefMinutes) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: gymOn) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: travel) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: calendarOn) { _, _ in DailyNudges.reschedule(store: store) }
    }
}
