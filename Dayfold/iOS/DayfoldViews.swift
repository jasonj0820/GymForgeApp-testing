import SwiftUI
import UIKit
import UserNotifications

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
        !row.done && row.task.isWeighIn && store.thisWeeksWeighIn == nil
    }
}

// MARK: - Today card

/// MK22: today's routine on the home screen, under the session card — progress, the next three steps
/// (tick them right here), and a way into the full list.
struct HomeRoutineCard: View {
    @EnvironmentObject private var dayfold: DayfoldStore
    @EnvironmentObject private var store: PhoneAppStore
    @Binding var showWeighIn: Bool
    /// MK23: the step just ticked here. It leaves the list straight away, so Undo stays for a few seconds.
    @State private var justTicked: TaskOccurrence?

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
                                if weighIn {
                                    showWeighIn = true
                                } else {
                                    dayfold.setDone(row, done: true)
                                    justTicked = row
                                }
                            }
                        }
                        if open.count > 3 {
                            NavigationLink { RoutineScreen() } label: {
                                Text("\(open.count - 3) more").font(.footnote.weight(.semibold))
                            }
                        }
                    }
                    if let ticked = justTicked {
                        HStack {
                            Text("Ticked \"\(ticked.task.title)\"").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Button("Undo") {
                                // The row as it stands now (ticked), so the right day's tick is removed.
                                if let current = dayfold.todayRows().first(where: { $0.id == ticked.id }) {
                                    dayfold.setDone(current, done: false)
                                }
                                justTicked = nil
                            }
                            .font(.footnote.weight(.semibold))
                        }
                        .task(id: ticked.id) {
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            if !Task.isCancelled { justTicked = nil }
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
    // MK24 (H)
    @State private var historyTask: RoutineTask?
    @State private var focusing = false
    @State private var reordering = false

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
                    // MK24 (119): sick and travel days pause the routine.
                    if dayfold.isPaused(now) {
                        Label("Paused for today's sick or travel day. Nothing will chase you, and streaks don't break; tick anything you still do.",
                              systemImage: "pause.circle.fill")
                            .font(.footnote)
                            .card()
                    }
                    // MK24 (121): one step at a time.
                    if today.contains(where: { !$0.done }) {
                        Button { focusing = true } label: {
                            Label("One step at a time", systemImage: "rectangle.portrait.on.rectangle.portrait")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
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
                    // MK24 (125): monthly and yearly steps coming up.
                    let upcoming = dayfold.snapshot.configuration.tasks
                        .filter { $0.enabled && ($0.routine == .monthly || $0.routine == .yearly) }
                        .compactMap { task in ScheduleEngine.nextDue(task, after: now).map { (task, $0) } }
                        .sorted { $0.1 < $1.1 }
                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Coming up", systemImage: "calendar.badge.clock").font(.headline).foregroundStyle(.purple)
                            ForEach(upcoming.prefix(5), id: \.0.id) { item in
                                HStack {
                                    Text(item.0.title).font(.subheadline)
                                    Spacer()
                                    Text(item.1.formatted(.dateTime.day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .card()
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
                Button { reordering = true } label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
                NavigationLink("Edit") { DayfoldManageView() }
            }
        }
        .sheet(item: $historyTask) { task in
            NavigationStack { StepHistoryView(task: task) }.environmentObject(dayfold)
        }
        .fullScreenCover(isPresented: $focusing) {
            StepFocusView().environmentObject(store).environmentObject(dayfold)
        }
        .sheet(isPresented: $reordering) {
            NavigationStack {
                DayfoldManageView()
                    .environment(\.editMode, .constant(.active))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { reordering = false } } }
            }
            .environmentObject(dayfold)
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
                            note: RoutineOrder.needsWeighIn(row, store: store) ? "Opens the weigh-in" : nil,
                            onSkip: { dayfold.skip(row) }, onHistory: { historyTask = row.task }) { tap(row) }
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
    /// MK24: long-press → skip today / history (only where the screen offers them).
    var onSkip: (() -> Void)? = nil
    var onHistory: (() -> Void)? = nil
    let action: () -> Void
    @ObservedObject private var timers = StepTimers.shared

    var body: some View {
        HStack(spacing: 8) {
            mainButton
            // MK24 (113, 114): the step's timer and link, next to it.
            if !row.done, let minutes = row.task.timerMinutes {
                Button {
                    timers.toggle(row.task, minutes: minutes)
                } label: {
                    if let end = timers.ends[row.task.id], end > .now {
                        Text(timerInterval: Date.now...end, countsDown: true).font(.caption.monospacedDigit().bold()).frame(width: 48)
                    } else {
                        Image(systemName: "timer").font(.body)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Timer, \(minutes) minutes")
            }
            if !row.done, let link = row.task.link, let url = StepLinks.url(link) {
                Button { UIApplication.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Open")
            }
        }
        .contextMenu {
            if let onSkip, !row.done {
                Button { onSkip() } label: { Label("Skip today (keeps the streak)", systemImage: "forward") }
            }
            if let onHistory {
                Button { onHistory() } label: { Label("History and streak", systemImage: "calendar") }
            }
        }
    }

    private var mainButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()   // MK22.1: a tick you can feel
            action()
        } label: {
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
        if row.skipped { return "Skipped today · tap to undo" }
        if row.done, let date = row.completedAt {
            return compact ? nil : "Done \(date.formatted(date: .omitted, time: .shortened)) · tap to undo"
        }
        if !row.retryToday { return "Still pending · retries every \(row.task.retryDays) days" }
        if row.overdue { return "Carried forward · due \(row.due.formatted(date: .abbreviated, time: .omitted))" }
        // "Every day" on a daily step says nothing; weekly, monthly and yearly steps keep their schedule.
        return row.task.routine == .daily ? nil : row.task.scheduleLabel
    }
}

// MARK: - MK24: step timers, links, history, one at a time

/// Running step timers (a notification at the end, in case you've left the app).
@MainActor
final class StepTimers: ObservableObject {
    static let shared = StepTimers()
    @Published private(set) var ends: [UUID: Date] = [:]

    func toggle(_ task: RoutineTask, minutes: Int) {
        let id = "dayfold.timer.\(task.id.uuidString)"
        if let end = ends[task.id], end > .now {
            ends[task.id] = nil
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            return
        }
        let end = Date.now.addingTimeInterval(Double(minutes) * 60)
        ends[task.id] = end
        let content = UNMutableNotificationContent()
        content.title = "\(task.title): time's up"
        content.body = "Tap Done to tick it off."
        content.sound = .default
        content.categoryIdentifier = "dayfold.step"
        content.userInfo = ["taskID": task.id.uuidString, "routine": task.routine.rawValue]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(Double(minutes) * 60, 1), repeats: false)))
    }
}

enum StepLinks {
    /// A web or app link as is; anything else is taken as the name of a Shortcut.
    static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":"), let url = URL(string: trimmed) { return url }
        var parts = URLComponents(string: "shortcuts://run-shortcut")
        parts?.queryItems = [URLQueryItem(name: "name", value: trimmed)]
        return parts?.url
    }
}

/// MK24 (112): a step's streak and the last two months, day by day.
struct StepHistoryView: View {
    @EnvironmentObject private var dayfold: DayfoldStore
    @Environment(\.dismiss) private var dismiss
    let task: RoutineTask

    var body: some View {
        let streak = dayfold.streak(task)
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let months = [calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth, thisMonth]
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(streak.current)", task.routine == .daily ? "day streak" : "in a row")
                    stat("\(streak.best)", "best")
                }
                ForEach(months, id: \.self) { month in
                    monthGrid(month)
                }
                HStack(spacing: 14) {
                    legend(.green, "Done")
                    legend(.yellow, "Skipped")
                    legend(.gray, "Paused")
                    legend(.red.opacity(0.7), "Missed")
                }
                .font(.caption)
            }
            .padding()
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(.green)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text(text) }
    }

    private func monthGrid(_ month: Date) -> some View {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let due = Set(ScheduleEngine.dueDays(task, from: month, to: calendar.date(byAdding: .month, value: 1, to: month) ?? month).map { calendar.startOfDay(for: $0) })
        return VStack(alignment: .leading, spacing: 6) {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(1...days, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                    let color: Color = {
                        guard due.contains(calendar.startOfDay(for: date)), date <= Date() else { return .clear }
                        switch ScheduleEngine.state(task, due: date, completions: dayfold.snapshot.completions, now: Date(), paused: dayfold.isPaused) {
                        case .done: return .green
                        case .skipped: return .yellow
                        case .paused: return .gray
                        case .missed: return .red.opacity(0.7)
                        case .due: return .blue.opacity(0.4)
                        }
                    }()
                    Text("\(day)")
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(color.opacity(color == .clear ? 0 : 0.35), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(due.contains(calendar.startOfDay(for: date)) ? Color.secondary.opacity(0.3) : .clear))
                }
            }
        }
    }
}

/// MK24 (121): today's open steps one at a time, big, with Done / Skip / Later.
struct StepFocusView: View {
    @EnvironmentObject private var dayfold: DayfoldStore
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var later: [String] = []
    @State private var showWeighIn = false

    var body: some View {
        let open = RoutineOrder.nextUp(dayfold.todayRows(), now: Date())
        let queue = open.filter { !later.contains($0.id) } + open.filter { later.contains($0.id) }
        let total = dayfold.todayRows().count
        VStack(spacing: 24) {
            HStack {
                Text("\(total - open.count) of \(total) done").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }
            }
            Spacer()
            if let row = queue.first {
                VStack(spacing: 14) {
                    Text(row.task.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    if let minutes = row.task.timerMinutes {
                        Button { StepTimers.shared.toggle(row.task, minutes: minutes) } label: {
                            Label("\(minutes) min timer", systemImage: "timer").font(.title3)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let link = row.task.link, let url = StepLinks.url(link) {
                        Button { UIApplication.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.bordered)
                    }
                }
                .id(row.id)
                .transition(.push(from: .trailing))
                Spacer()
                Button {
                    if RoutineOrder.needsWeighIn(row, store: store) { showWeighIn = true } else { dayfold.setDone(row, done: true) }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Done", systemImage: "checkmark").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                HStack {
                    Button("Skip today") { dayfold.skip(row) }.frame(maxWidth: .infinity)
                    Button("Later") { withAnimation { later.append(row.id) } }.frame(maxWidth: .infinity)
                        .disabled(queue.count < 2)
                }
                .buttonStyle(.bordered)
            } else {
                Label("All done", systemImage: "checkmark.seal.fill").font(.largeTitle.bold()).foregroundStyle(.green)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .animation(.snappy, value: queue.first?.id)
        .sheet(isPresented: $showWeighIn) { WeighInSheet().environmentObject(store) }
    }
}
