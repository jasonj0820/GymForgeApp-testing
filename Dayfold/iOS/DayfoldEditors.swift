import SwiftUI
import UIKit

struct DayfoldManageView: View {
    @EnvironmentObject var store: DayfoldStore
    @State private var editingTask: RoutineTask?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Build routines that fit your life. Drag to reorder, tap to edit, or add a new step.")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                ForEach(RoutineKind.allCases) { kind in
                    Section {
                        let tasks = store.snapshot.configuration.tasks.filter { $0.routine == kind }.sorted { $0.order < $1.order }
                        ForEach(tasks) { task in
                            Button { editingTask = task } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title).foregroundStyle(.primary)
                                        Text(task.enabled ? task.scheduleLabel + (task.wake ? " · Wake-up" : "") + (task.bedtime ? " · Before bed" : "") : "Paused")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 3)
                            }
                        }
                        .onMove { store.reorder(kind, from: $0, to: $1) }
                        .onDelete { offsets in
                            for offset in offsets { store.deleteTask(tasks[offset].id) }
                        }
                        Button {
                            editingTask = RoutineTask(title: "", routine: kind,
                                weekdays: kind == .weekly ? [Calendar.current.component(.weekday, from: Date())] : Set(1...7),
                                order: (tasks.map(\.order).max() ?? -1) + 1)
                        } label: { Label("Add a step", systemImage: "plus") }
                    } header: { Label(kind.title, systemImage: kind.symbol) }
                }
            }.scrollContentBackground(.hidden).background(DayfoldPalette.background)
                .navigationTitle("Your routines")
                .toolbar { EditButton() }
                .sheet(item: $editingTask) { task in TaskEditor(task: task) }
        }
    }
}

struct TaskEditor: View {
    @EnvironmentObject var store: DayfoldStore
    @Environment(\.dismiss) private var dismiss
    @State var task: RoutineTask
    @State private var confirmDelete = false
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var body: some View {
        NavigationStack {
            Form {
                Section("The step") {
                    TextField("Task name", text: $task.title)
                    Picker("Repeats", selection: $task.routine) {
                        ForEach(RoutineKind.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Active", isOn: $task.enabled)
                    Toggle("Wake-up", isOn: $task.wake)
                    Toggle("Before bed", isOn: $task.bedtime)
                }
                switch task.routine {
                case .daily:
                    EmptyView()
                case .weekly:
                    Section {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(weekdays[day - 1], isOn: Binding(get: { task.weekdays.contains(day) }, set: { enabled in
                                if enabled { task.weekdays.insert(day) } else { task.weekdays.remove(day) }
                            }))
                        }
                    } header: { Text("Days of the week") } footer: { Text("Completing late never shifts these days.") }
                case .monthly, .yearly:
                    Section {
                        if task.routine == .yearly {
                            Picker("Month", selection: $task.month) {
                                ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) }
                            }
                        }
                        Stepper("Day \(task.monthDay)", value: $task.monthDay, in: 1...31)
                    } header: { Text("Due on") } footer: { Text("Shorter months use their last day. Completing late never shifts the date.") }
                }
                if task.routine != .daily {
                    Section {
                        Stepper(task.retryDays == 1 ? "Remind every day" : "Remind every \(task.retryDays) days", value: $task.retryDays, in: 1...14)
                    } header: { Text("If unfinished") } footer: { Text("Stays on your home screen and resurfaces at this interval from its due date until done. No duplicate copies.") }
                }
                if store.snapshot.configuration.tasks.contains(where: { $0.id == task.id }) {
                    Section { Button("Delete task", role: .destructive) { confirmDelete = true } }
                }
            }.onChange(of: task.routine) { _, kind in
                if kind == .weekly && task.weekdays.count == 7 { task.weekdays = [Calendar.current.component(.weekday, from: Date())] }
            }
            .navigationTitle(task.title.isEmpty ? "New step" : "Edit step")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            // Moving between routines places the item at the end of its destination.
                            if let old = store.snapshot.configuration.tasks.first(where: { $0.id == task.id }), old.routine != task.routine {
                                task.order = (store.snapshot.configuration.tasks.filter { $0.routine == task.routine }.map(\.order).max() ?? -1) + 1
                            }
                            store.saveTask(task); dismiss()
                        }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (task.routine == .weekly && task.weekdays.isEmpty))
                    }
                }
                .confirmationDialog("Delete this task and remove it from your routine?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete task", role: .destructive) { store.deleteTask(task.id); dismiss() }
                }
        }
    }
}

struct DayfoldSettingsView: View {
    @EnvironmentObject var store: DayfoldStore
    var body: some View {
        NavigationStack {
            List {
                Section("Reminders") {
                    ForEach(RoutineKind.allCases) { kind in
                        NavigationLink { ReminderEditor(settings: store.settings(kind)) } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                    }
                    NotificationStatus(notifications: store.notifications)
                }
                Section("Apple Watch") {
                    Label(store.syncStatus, systemImage: "applewatch")
                    Button("Sync now") { store.refresh() }
                    Text("Dayfold is in the GymForge Watch app. Check-offs work offline and sync over GymForge's connection. Edit routines on your iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Motivation") {
                    NavigationLink { MotivationSettingsView() } label: { Label("Quotes & widget", systemImage: "quote.opening") }
                }
                Section("Before bed") {
                    Text("Steps marked \"Before bed\" make up the wind-down checklist on GymForge's bedtime card, plus \"Pack gym bag\" when a session is planned tomorrow. Set bedtime and your Sleep Focus shortcut in GymForge → Today → Sleep.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Your routine rules") {
                    Label("Home shows everything due today", systemImage: "house")
                    Label("Weigh-ins tick themselves when Apple Health gets a new weight", systemImage: "scalemass")
                    Label("One reminder per frequency, only when something's due", systemImage: "bell")
                    Label("Late completion keeps the original schedule", systemImage: "calendar")
                    Label("Day 31 falls on the last day of shorter months", systemImage: "calendar.badge.clock")
                }
                Section {
                    Text("Dayfold · part of Splitday\nStored on your devices. No account, ads or analytics.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").scrollContentBackground(.hidden).background(DayfoldPalette.background)
        }
    }
}

struct NotificationStatus: View {
    @ObservedObject var notifications: DayfoldNotifications
    @EnvironmentObject var store: DayfoldStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(notifications.permission).font(.subheadline)
            Button("Enable notifications") {
                Task { await notifications.requestPermission(); store.refresh() }
            }
            Button("Open iPhone notification settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }.font(.footnote)
            if let problem = notifications.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            Text("Up to 10 upcoming reminders are prepared (iOS shares a limit of 64 with GymForge's own) and renewed whenever you open the app. Focus and notification settings control delivery to your watch.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}

struct ReminderEditor: View {
    @EnvironmentObject var store: DayfoldStore
    @Environment(\.dismiss) private var dismiss
    @State var settings: RoutineSettings
    private func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
    }
    private func minutes(_ date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
    }
    var body: some View {
        Form {
            Section {
                Toggle("Scheduled reminder", isOn: $settings.remindersEnabled)
                DatePicker("Default time", selection: Binding(get: { date(settings.hour * 60 + settings.minute) }, set: {
                    let value = minutes($0); settings.hour = value / 60; settings.minute = value % 60
                }), displayedComponents: .hourAndMinute)
            } footer: { Text("Fires only on days something in this list is due. Finishing early cancels the reminder once the phone has your completion.") }
            Section {
                ForEach(1...7, id: \.self) { day in
                    VStack {
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { settings.weekdayMinutes[day] != nil }, set: { enabled in
                            if enabled { settings.weekdayMinutes[day] = settings.hour * 60 + settings.minute }
                            else { settings.weekdayMinutes.removeValue(forKey: day) }
                        }))
                        if settings.weekdayMinutes[day] != nil {
                            DatePicker("Time", selection: Binding(get: { date(settings.weekdayMinutes[day] ?? 420) }, set: {
                                settings.weekdayMinutes[day] = minutes($0)
                            }), displayedComponents: .hourAndMinute)
                        }
                    }
                }
            } header: { Text("Different times by day") } footer: { Text("Enable a day to override the default time. Days without overrides use the default. Reminders only occur when a task is due or due for a retry.") }
        }.navigationTitle("\(settings.kind.title) reminders").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveSettings(settings)
                        if settings.remindersEnabled {
                            Task { await store.notifications.requestPermission(); store.refresh() }
                        }
                        dismiss()
                    }
                }
            }
    }
}

/// MK16 + MK19.3: topics, tone and the three daily quote notifications. The widget follows the same settings.
struct MotivationSettingsView: View {
    @State private var topics = QuoteSettings.topics
    @State private var tough = QuoteSettings.tough
    @State private var notify = QuoteSettings.notify
    @State private var offset = QuoteSettings.offset

    var body: some View {
        Form {
            Section {
                let quote = QuotePicker.quote(slot: QuotePicker.widgetSlot(at: .now), offset: offset, topics: topics, tough: tough)
                VStack(alignment: .leading, spacing: 6) {
                    Text(quote.text).font(.system(.title3, design: .serif))
                    if let author = quote.author { Text("— \(author)").font(.caption).foregroundStyle(.secondary) }
                }.padding(.vertical, 6)
                Button {
                    offset += 1
                    QuoteSettings.offset = offset
                    QuoteNotifier.reschedule()
                } label: {
                    Label("Next quote", systemImage: "arrow.clockwise")
                }
            } header: { Text("Showing now") }
            Section {
                ForEach(QuoteTopic.allCases) { topic in
                    Toggle(topic.title, isOn: Binding(get: { topics.contains(topic) }, set: { on in
                        if on { topics.insert(topic) } else if topics.count > 1 { topics.remove(topic) }
                    }))
                }
            } header: { Text("Topics") } footer: { Text("At least one stays on. Quotes take turns between your topics.") }
            Section {
                Picker("Tone", selection: $tough) {
                    Text("Calm").tag(false)
                    Text("Tough (Sergeant Cluck)").tag(true)
                }
                Toggle("3 a day · 8:00, 13:00, 18:00", isOn: $notify)
            } footer: { Text("Quote notifications are silent. Add the widget: long-press the Home Screen → + → Splitday → Motivation. ↻ on the widget shows the next quote.") }
        }
        .navigationTitle("Motivation")
        .onChange(of: topics) { _, value in QuoteSettings.topics = value; QuoteNotifier.reschedule() }
        .onChange(of: tough) { _, value in QuoteSettings.tough = value; QuoteNotifier.reschedule() }
        .onChange(of: notify) { _, value in QuoteSettings.notify = value; QuoteNotifier.reschedule() }
    }
}
