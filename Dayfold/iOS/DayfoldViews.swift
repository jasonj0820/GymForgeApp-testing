import SwiftUI

/// MK22: routine colours follow the system. The fixed dark palette went with the separate Dayfold half.
enum DayfoldPalette {
    static let accent = Color.orange
    static let lavender = Color.indigo
    static func color(_ kind: RoutineKind) -> Color {
        switch kind {
        case .daily: .green
        case .weekly: .teal
        case .monthly: .indigo
        case .yearly: .orange
        }
    }
}

extension DayfoldStore {
    /// Everything on today's list: due now, or already ticked. Steps waiting for a later retry are left out.
    func todayRows(now: Date = Date()) -> [TaskOccurrence] {
        RoutineKind.allCases.flatMap { rows($0, now: now) }.filter { $0.retryToday || $0.done }
    }
}

enum RoutineOrder {
    /// A step flagged for both ends of the day sits with wake-up until mid-afternoon, then with before bed.
    static func isWake(_ row: TaskOccurrence, hour: Int) -> Bool {
        row.task.wake && !(row.task.bedtime && hour >= 15)
    }

    /// What's still open, most relevant first: wake-up steps in the morning, before-bed steps in the evening.
    static func nextUp(_ rows: [TaskOccurrence], now: Date) -> [TaskOccurrence] {
        let hour = Calendar.current.component(.hour, from: now)
        func rank(_ row: TaskOccurrence) -> Int {
            if isWake(row, hour: hour) { return hour < 12 ? 0 : 2 }
            if row.task.bedtime { return hour >= 18 ? 0 : 3 }
            return 1
        }
        return rows.filter { !$0.done }.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// A weigh-in step opens the weigh-in sheet until this week's weight is logged; saving it ticks the step.
    @MainActor static func needsWeighIn(_ row: TaskOccurrence, store: PhoneAppStore) -> Bool {
        !row.done && row.task.title.localizedCaseInsensitiveContains("weigh") && store.thisWeeksWeighIn == nil
    }
}

// MARK: - Today card

/// MK22: today's routine on the home screen, under the session card — progress, the next three steps
/// (tick them right here), and a way into the full list.
struct HomeRoutineCard: View {
    @EnvironmentObject private var dayfold: DayfoldStore
    @EnvironmentObject private var store: PhoneAppStore
    @Binding var showWeighIn: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let rows = dayfold.todayRows(now: context.date)
            let open = RoutineOrder.nextUp(rows, now: context.date)
            let done = rows.count - open.count
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { RoutineScreen() } label: {
                    HStack {
                        Label("Routine", systemImage: "checklist").font(.headline)
                        Spacer()
                        Text(rows.isEmpty ? "Set up" : "\(done) of \(rows.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if rows.isEmpty {
                    Text("Nothing on today's list. Add the daily, weekly, monthly or yearly steps you want to keep up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: Double(done), total: Double(rows.count))
                        .tint(.green)
                        .accessibilityLabel("Routine progress")
                    if open.isEmpty {
                        Label("All done for today", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        ForEach(open.prefix(3)) { row in
                            let weighIn = RoutineOrder.needsWeighIn(row, store: store)
                            TaskRow(row: row, color: .green, compact: true, note: weighIn ? "Opens the weigh-in" : nil) {
                                if weighIn { showWeighIn = true } else { dayfold.setDone(row, done: true) }
                            }
                        }
                        if open.count > 3 {
                            NavigationLink { RoutineScreen() } label: {
                                Text("\(open.count - 3) more").font(.footnote.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .card()
        }
    }
}

// MARK: - Routine screen

/// MK22: the whole routine in one list, in the order the day runs — wake-up, during the day, before bed.
/// Replaces Dayfold's separate home, its four frequency pages and its own tab bar.
struct RoutineScreen: View {
    @EnvironmentObject private var dayfold: DayfoldStore
    @EnvironmentObject private var store: PhoneAppStore
    @State private var showWeighIn = false
    @State private var showWakeUp = false
    @State private var showWindDown = false
    @State private var showLater = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let hour = Calendar.current.component(.hour, from: now)
            let all = RoutineKind.allCases.flatMap { dayfold.rows($0, now: now) }
            let today = all.filter { $0.retryToday || $0.done }
            let later = all.filter { !$0.retryToday && !$0.done }
            let done = today.filter(\.done).count
            let wake = today.filter { RoutineOrder.isWake($0, hour: hour) }
            let bed = today.filter { $0.task.bedtime && !RoutineOrder.isWake($0, hour: hour) }
            let day = today.filter { !$0.task.wake && !$0.task.bedtime }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if all.isEmpty {
                        ContentUnavailableView("No steps yet", systemImage: "checklist",
                                               description: Text("Tap Edit to add the things you want to keep up: daily, weekly, monthly or yearly."))
                    } else {
                        header(done: done, total: today.count, now: now)
                    }
                    section("Wake-up", icon: "sun.horizon.fill", color: .orange, rows: wake, open: "Checklist") { showWakeUp = true }
                    section("Today", icon: "sun.max.fill", color: .green, rows: day)
                    section("Before bed", icon: "moon.stars.fill", color: .indigo, rows: bed, open: "Start wind-down") {
                        store.startWindDown()
                        showWindDown = true
                    }
                    if !later.isEmpty {
                        DisclosureGroup("Waiting for the next reminder · \(later.count)", isExpanded: $showLater) {
                            VStack(spacing: 8) {
                                ForEach(later) { row in
                                    TaskRow(row: row, color: DayfoldPalette.color(row.task.routine)) { tap(row) }
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                        .tint(.secondary)
                    }
                    if !dayfold.snapshot.configuration.routines.contains(where: \.remindersEnabled) {
                        NavigationLink { DayfoldSettingsView() } label: {
                            Label("Reminders are off, so nothing will chase you. Turn them on.", systemImage: "bell.slash")
                                .font(.footnote)
                                .multilineTextAlignment(.leading)
                        }
                        .tint(.orange)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Routine")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { DayfoldSettingsView() } label: { Label("Reminders", systemImage: "bell") }
                NavigationLink("Edit") { DayfoldManageView() }
            }
        }
        .sheet(isPresented: $showWeighIn) { WeighInSheet().environmentObject(store) }
        .sheet(isPresented: $showWakeUp) { WakeUpView().environmentObject(store).environmentObject(dayfold) }
        .sheet(isPresented: $showWindDown) { WindDownView().environmentObject(store).environmentObject(dayfold) }
    }

    private func header(done: Int, total: Int, now: Date) -> some View {
        let left = total - done
        return VStack(alignment: .leading, spacing: 8) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(total == 0 ? "Nothing due today" : (left == 0 ? "All done" : "\(left) left today"))
                .font(.title2.bold())
            if total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .tint(.green)
                    .accessibilityLabel("Routine progress")
                Text("\(done) of \(total) done")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func section(_ title: String, icon: String, color: Color, rows: [TaskOccurrence],
                         open: String? = nil, onOpen: @escaping () -> Void = {}) -> some View {
        if !rows.isEmpty {
            let sorted = rows.filter { !$0.done } + rows.filter(\.done)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
                    Text("\(rows.filter(\.done).count) of \(rows.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let open {
                        Button(open, action: onOpen).font(.subheadline.weight(.semibold))
                    }
                }
                ForEach(sorted) { row in
                    TaskRow(row: row, color: color,
                            note: RoutineOrder.needsWeighIn(row, store: store) ? "Opens the weigh-in" : nil) { tap(row) }
                }
            }
        }
    }

    private func tap(_ row: TaskOccurrence) {
        if RoutineOrder.needsWeighIn(row, store: store) {
            showWeighIn = true
        } else {
            dayfold.setDone(row, done: !row.done)
        }
    }
}

struct TaskRow: View {
    let row: TaskOccurrence
    let color: Color
    /// Inside another card (the home screen): no background of its own, tighter.
    var compact = false
    /// Replaces the schedule line, e.g. "Opens the weigh-in".
    var note: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 10 : 14) {
                Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                    .font(compact ? Font.title3 : Font.title2)
                    .foregroundStyle(row.done ? color : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.task.title)
                        .font(compact ? Font.subheadline : Font.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .strikethrough(row.done)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 0 : 14)
            .padding(.vertical, compact ? 3 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if !compact { RoundedRectangle(cornerRadius: 16).fill(.thinMaterial) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.task.title), \(row.done ? "completed, tap to undo" : "tap to complete")")
    }

    private var subtitle: String? {
        if let note { return note }
        if row.done, let date = row.completedAt {
            return compact ? nil : "Done \(date.formatted(date: .omitted, time: .shortened)) · tap to undo"
        }
        if !row.retryToday { return "Still pending · retries every \(row.task.retryDays) days" }
        if row.overdue { return "Carried forward · due \(row.due.formatted(date: .abbreviated, time: .omitted))" }
        // "Every day" on a daily step says nothing; weekly, monthly and yearly steps keep their schedule.
        return row.task.routine == .daily ? nil : row.task.scheduleLabel
    }
}
