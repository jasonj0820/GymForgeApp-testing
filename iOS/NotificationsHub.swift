@preconcurrency import UserNotifications
import SwiftUI

// MARK: - MK24 (147): one budget for every notification, with priorities (iOS keeps only 64)

@MainActor
enum NotificationBudget {
    static let limit = 60   // a little under iOS's 64, for the rest timer and one-offs

    /// Higher keeps. Prefixes are the identifiers each scheduler uses.
    static func priority(_ id: String) -> Int {
        let table: [(String, Int)] = [
            ("gymforge.rest", 100), ("gymforge.preview", 100), ("gymforge.sleep", 90), ("gymforge.wake", 90), ("gymforge.bed", 90),
            ("dayfold.timer", 85), ("dayfold.step", 80), ("dayfold.home", 80), ("gymforge.weighin", 75), ("dayfold.", 70),
            ("gymnudge.", 65), ("brief.", 60), ("gymforge.protein", 50), ("gymforge.review", 50), ("gymforge.recap", 45),
            ("gymforge.cluck.m", 15), ("gymforge.cluck", 40), ("health.import", 35), ("gymforge.quote", 10),
        ]
        return table.first { id.hasPrefix($0.0) }?.1 ?? 30
    }

    private static var pendingRun: Task<Void, Never>?

    /// After the schedulers have had a moment to add theirs.
    static func enforceSoon() {
        guard !Demo.isOn else { return }
        pendingRun?.cancel()
        pendingRun = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await enforce()
        }
    }

    static func fireDate(_ request: UNNotificationRequest) -> Date? {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
    }

    static func enforce() async {
        let center = UNUserNotificationCenter.current()
        var pending = await center.pendingNotificationRequests()
        // Quiet hours and the at-work window: low-priority ones are dropped, the rest wait until it's over.
        let windows = QuietHours.windows
        var removed: [String] = []
        if !windows.isEmpty {
            for request in pending {
                let p = priority(request.identifier)
                guard p < 80, let fire = fireDate(request), QuietHours.isQuiet(fire, windows: windows) else { continue }
                if p >= 45, let content = request.content.mutableCopy() as? UNMutableNotificationContent {
                    let moved = QuietWindow.firstFree(after: fire, windows: windows)
                    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: moved)
                    try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content,
                                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
                } else {
                    removed.append(request.identifier)
                }
            }
            center.removePendingNotificationRequests(withIdentifiers: removed)
            pending = await center.pendingNotificationRequests()
        }
        // Over the limit: keep the most important, soonest first.
        guard pending.count > limit else { return }
        let ranked = pending.sorted {
            let a = priority($0.identifier), b = priority($1.identifier)
            if a != b { return a > b }
            return (fireDate($0) ?? .distantFuture) < (fireDate($1) ?? .distantFuture)
        }
        center.removePendingNotificationRequests(withIdentifiers: ranked.dropFirst(limit).map(\.identifier))
    }
}

/// MK24 (145): quiet hours, and an at-work / in-class window (fixed times, or your calendar).
@MainActor
enum QuietHours {
    static let quietKey = "quiet.night", workKey = "quiet.work", calendarKey = "quiet.calendar"

    static func load(_ key: String) -> QuietWindow? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(QuietWindow.self, from: data)
    }

    static func save(_ window: QuietWindow?, _ key: String) {
        UserDefaults.standard.set(window.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
        NotificationBudget.enforceSoon()
    }

    static var windows: [QuietWindow] { [load(quietKey), load(workKey)].compactMap { $0 } }

    static var useCalendar: Bool {
        get { UserDefaults.standard.bool(forKey: calendarKey) }
        set { UserDefaults.standard.set(newValue, forKey: calendarKey) }
    }

    static let busyWords = ["work", "shift", "class", "lecture", "tutorial", "lab", "seminar", "meeting", "exam"]

    static func isQuiet(_ date: Date, windows: [QuietWindow]) -> Bool {
        if windows.contains(where: { $0.contains(date) }) { return true }
        guard useCalendar else { return false }
        return DayAgenda.events(on: date).contains { event in
            !event.allDay && event.start <= date && event.end > date
                && event.title.lowercased().split { !$0.isLetter }.contains { busyWords.contains(String($0)) }
        }
    }
}

// MARK: - MK24 (143, 144): every notification on one page

struct NotificationsHubView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var pending: [UNNotificationRequest] = []
    @State private var quiet = QuietHours.load(QuietHours.quietKey)
    @State private var work = QuietHours.load(QuietHours.workKey)
    @State private var useCalendar = QuietHours.useCalendar
    @AppStorage(DailyNudges.briefOnKey) private var briefOn = true
    @AppStorage(DailyNudges.gymOnKey) private var gymOn = true
    @AppStorage("protein.nags") private var proteinOn = true
    @State private var quotesOn = QuoteSettings.notify
    @State private var weighInOn = WeighInReminder.enabled
    @State private var tick = 0

    var body: some View {
        Form {
            Section {
                LabeledContent("Planned now", value: "\(pending.count) of iOS's 64")
                ForEach(groups, id: \.0) { group in
                    LabeledContent(group.0, value: "\(group.1)").font(.subheadline)
                }
            } footer: {
                Text("When there are too many, the least important (quotes first, then Sergeant Cluck's motivation) are dropped so the ones that matter always fit.")
            }

            Section {
                row("Workout reminders", isOn: Binding(get: { store.profile.reminders }, set: { v in Task { await store.setReminders(enabled: v) } }),
                    preview: ("Time to train", "You're one session behind this week."))
                row("Morning brief", isOn: $briefOn, preview: DailyNudges.briefLines(store: store, on: .now))
                row("Leave for the gym", isOn: $gymOn, preview: ("Time to head to the gym", "Push today. You usually start around 5:40 pm. Bag packed?"))
                NavigationLink("Brief time, travel time and calendar") { Form { YourDaySettingsSection() }.navigationTitle("Your day") }
            } header: {
                Text("Training")
            }

            Section {
                row("Weigh-in", isOn: Binding(get: { weighInOn }, set: { weighInOn = $0; WeighInReminder.enabled = $0
                    WeighInReminder.reschedule(weighIns: store.extras.weighIns) }), preview: ("Weigh-in", "Log your weight and body fat for the week."))
                timeRow(NotificationTimes.weighIn) { WeighInReminder.reschedule(weighIns: store.extras.weighIns) }
            } header: {
                Text("Weigh-in")
            }

            Section {
                row("Protein nags", isOn: $proteinOn, preview: ("Protein check", "60 g to go by dinner."))
                ForEach(NotificationTimes.protein) { slot in timeRow(slot) { ProteinNotifier.reschedule(store: store) } }
            } header: {
                Text("Protein")
            } footer: {
                Text("A nag only comes if you're behind at that time; log protein and they reschedule. The + buttons on it log straight away.")
            }

            Section {
                Toggle("Sergeant Cluck", isOn: store.profileBinding(\.cluckEnabled))
                ForEach(NotificationTimes.cluck) { slot in timeRow(slot) { store.rescheduleReminders() } }
                Button("Preview") { preview("🪖 Sergeant Cluck", "Still no session today. The bar isn't going to lift itself.") }
            } header: {
                Text("Sergeant Cluck")
            } footer: {
                Text("Nudges on days you're behind your weekly goal, in order through the evening.")
            }

            Section {
                row("Quotes", isOn: Binding(get: { quotesOn }, set: { quotesOn = $0; QuoteSettings.notify = $0; QuoteNotifier.reschedule() }),
                    preview: ("Discipline", "Motivation gets you started; habit keeps you going."))
                ForEach(NotificationTimes.quotes) { slot in timeRow(slot) { QuoteNotifier.reschedule() } }
            } header: {
                Text("Quotes")
            }

            Section {
                NavigationLink("Routine reminders and follow-ups") { DayfoldSettingsView() }
                NavigationLink("Bedtime and wake-up (sleep schedule)") { RecoveryView() }
            } header: {
                Text("Routine and sleep")
            } footer: {
                Text("Steps can also have their own time or a \"when I get home\" reminder (Routine → Edit → a step → Extras).")
            }

            Section {
                windowRows("Quiet hours", $quiet, key: QuietHours.quietKey, defaultWindow: QuietWindow(start: 22 * 60 + 30, end: 6 * 60 + 30))
            } footer: {
                Text("Nothing but timers, bedtime and steps you set yourself. Quotes and motivation are skipped; the rest wait until it's over.")
            }
            Section {
                windowRows("At work or in class", $work, key: QuietHours.workKey,
                           defaultWindow: QuietWindow(start: 9 * 60, end: 17 * 60, weekdays: [2, 3, 4, 5, 6]))
                Toggle("Also when my calendar says work, class or a lecture", isOn: Binding(get: { useCalendar }, set: {
                    useCalendar = $0
                    QuietHours.useCalendar = $0
                    NotificationBudget.enforceSoon()
                }))
                .disabled(!DayAgenda.enabled)
            } footer: {
                Text(DayAgenda.enabled ? "The calendar check uses events named work, shift, class, lecture, tutorial, lab or meeting."
                     : "Turn on \"Show my calendar on Today\" (Your day) to use your calendar here too.")
            }

            Section {
                Button("Reset all times to the defaults") {
                    NotificationTimes.reset(NotificationTimes.cluck + NotificationTimes.quotes + NotificationTimes.protein + [NotificationTimes.weighIn])
                    tick += 1
                    Task { await store.appBecameActive() }
                }
            }
        }
        .navigationTitle("Notifications")
        .task(id: tick) { await refresh() }
        .onChange(of: briefOn) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: gymOn) { _, _ in DailyNudges.reschedule(store: store) }
        .onChange(of: proteinOn) { _, _ in ProteinNotifier.reschedule(store: store) }
    }

    private var groups: [(String, Int)] {
        let names: [(String, String)] = [("dayfold.", "Routine"), ("gymforge.cluck", "Sergeant Cluck"), ("gymforge.protein", "Protein"),
                                         ("gymforge.quote", "Quotes"), ("brief.", "Morning brief"), ("gymnudge.", "Leave for the gym"),
                                         ("gymforge.weighin", "Weigh-in"), ("gymforge.sleep", "Bedtime"), ("gymforge.wake", "Wake-up")]
        var counts: [String: Int] = [:]
        for request in pending {
            let name = names.first { request.identifier.hasPrefix($0.0) }?.1 ?? "Other"
            counts[name, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func refresh() async {
        try? await Task.sleep(nanoseconds: 600_000_000)
        pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    private func row(_ title: String, isOn: Binding<Bool>, preview sample: (title: String, body: String)) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
            Button { preview(sample.title, sample.body) } label: { Image(systemName: "eye") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview \(title)")
        }
    }

    private func timeRow(_ slot: NotificationTimes.Slot, changed: @escaping () -> Void) -> some View {
        DatePicker(slot.title, selection: Binding(
            get: { Calendar.current.date(byAdding: .minute, value: NotificationTimes.minutes(slot), to: Calendar.current.startOfDay(for: .now)) ?? .now },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                NotificationTimes.set(slot, (c.hour ?? 0) * 60 + (c.minute ?? 0))
                changed()
                tick += 1
            }
        ), displayedComponents: .hourAndMinute)
        .font(.subheadline)
        .id("\(slot.key)-\(tick)")
    }

    @ViewBuilder
    private func windowRows(_ title: String, _ window: Binding<QuietWindow?>, key: String, defaultWindow: QuietWindow) -> some View {
        Toggle(title, isOn: Binding(get: { window.wrappedValue != nil }, set: { on in
            window.wrappedValue = on ? defaultWindow : nil
            QuietHours.save(window.wrappedValue, key)
        }))
        if let current = window.wrappedValue {
            DatePicker("From", selection: minutesBinding(current.start) { var w = current; w.start = $0; window.wrappedValue = w; QuietHours.save(w, key) },
                       displayedComponents: .hourAndMinute)
            DatePicker("Until", selection: minutesBinding(current.end) { var w = current; w.end = $0; window.wrappedValue = w; QuietHours.save(w, key) },
                       displayedComponents: .hourAndMinute)
            if current.weekdays.count < 7 || key == QuietHours.workKey {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in
                        let on = current.weekdays.contains(day)
                        Button(String(Calendar.current.veryShortWeekdaySymbols[day - 1])) {
                            var w = current
                            if on { w.weekdays.remove(day) } else { w.weekdays.insert(day) }
                            window.wrappedValue = w
                            QuietHours.save(w, key)
                        }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .gray)
                    }
                }
            }
        }
    }

    private func minutesBinding(_ minutes: Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(get: { Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); set((c.hour ?? 0) * 60 + (c.minute ?? 0)) })
    }

    private func preview(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "gymforge.preview.\(UUID().uuidString)", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        Haptics.tap()
    }
}
