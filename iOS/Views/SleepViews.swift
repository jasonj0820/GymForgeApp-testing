import SwiftUI

/// MK11: Today → Sleep: last night vs your schedule, consistency, and "Going to sleep / I'm awake".
struct SleepCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var sleepingSince: Date? = SleepHealth.manualStart

    var body: some View {
        let report = store.sleepReport
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sleep", systemImage: "bed.double.fill").font(.headline)
                Spacer()
                NavigationLink {
                    SleepScheduleView()
                } label: {
                    Text(store.profile.sleepSchedule == nil ? "Set schedule" : "Schedule").font(.subheadline)
                }
            }
            if let last = report.lastNight {
                Text(String(format: "%d h %02d m", Int(last.night.hoursAsleep), Int(last.night.hoursAsleep.truncatingRemainder(dividingBy: 1) * 60)))
                    .font(.title3.bold())
                if let start = last.night.start, let end = last.night.end {
                    Text("Bed \(start.formatted(date: .omitted, time: .shortened)) (\(SleepAnalysis.offText(last.bedMinutesOff))) · up \(end.formatted(date: .omitted, time: .shortened)) (\(SleepAnalysis.offText(last.wakeMinutesOff)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let score = report.score, store.profile.sleepSchedule != nil {
                HStack {
                    Text("Consistency \(score)/100").font(.subheadline.bold())
                    Spacer()
                    Text("\(report.onScheduleStreak) on time in a row · \(report.lateNights7) late this week")
                        .font(.caption)
                        .foregroundStyle(report.lateNights7 >= 3 ? .orange : .secondary)
                }
            }
            if store.inBedtimeWindow() {
                // MK11.2: same as the Live Activity button.
                Button {
                    store.goingToBed()
                } label: {
                    Label("I'm going to bed", systemImage: "bed.double.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            if let since = sleepingSince {
                Button {
                    Task {
                        await store.healthKit.finishManualSleep()
                        sleepingSince = nil
                    }
                } label: {
                    Label("I'm awake (asleep since \(since.formatted(date: .omitted, time: .shortened)))", systemImage: "sun.max.fill")
                }
                .buttonStyle(.bordered)
                .tint(.yellow)
            } else {
                Button {
                    store.healthKit.startManualSleep()
                    sleepingSince = SleepHealth.manualStart
                } label: {
                    Label("Going to sleep", systemImage: "moon.zzz.fill")
                }
                .buttonStyle(.bordered)
                .tint(.indigo)
            }
        }
        .card()
    }
}

/// A bedtime and wake time for each night of the week.
struct SleepScheduleView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var schedule = SleepSchedule.standard
    @AppStorage(PhoneAppStore.focusShortcutKey) private var focusShortcut = ""

    /// Monday first, like the week row.
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                ForEach(order, id: \.self) { weekday in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Calendar.current.weekdaySymbols[weekday - 1] + " night").font(.subheadline.bold())
                        HStack {
                            DatePicker("Bed", selection: binding(\.bedtime, weekday, fallback: 23 * 60), displayedComponents: .hourAndMinute)
                            DatePicker("Up", selection: binding(\.wake, weekday, fallback: 7 * 60), displayedComponents: .hourAndMinute)
                        }
                        .font(.subheadline)
                    }
                }
            } footer: {
                Text("Each night is the evening it starts: \"Friday night\" = bed Friday, up Saturday. 10 minutes before bed you get a wind-down notification (iPhone and Watch). Tap it and your Dayfold before-bed checklist opens, with the wind-down card on the Lock Screen until you go to bed. The rest of the day it stays about the gym.")
            }
            Section {
                TextField("Shortcut name, e.g. GymForge Sleep", text: $focusShortcut)
                    .autocorrectionDisabled()
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
            } header: {
                Text("Sleep Focus")
            } footer: {
                Text("After bedtime Sergeant Cluck nags you (every 10 min, then every 5 after 30 min late, for an hour) until you tap \"I'm going to bed\" — on the Lock Screen card or here. To turn on Sleep Focus at the same time: in Shortcuts tap +, add \"Set Focus\" → Sleep → Turn On, name it (e.g. GymForge Sleep) and type that name above. Leave it empty to skip. Your Apple Watch tracks the sleep itself.")
            }
            Section {
                Button("Save") { store.setSleepSchedule(schedule) }
                    .bold()
                if store.profile.sleepSchedule != nil {
                    Button("Turn off sleep schedule", role: .destructive) { store.setSleepSchedule(nil) }
                }
            }
        }
        .navigationTitle("Sleep schedule")
        .onAppear { schedule = store.profile.sleepSchedule ?? .standard }
    }

    private func binding(_ keyPath: WritableKeyPath<SleepSchedule, [Int: Int]>, _ weekday: Int, fallback: Int) -> Binding<Date> {
        Binding(
            get: {
                let minutes = schedule[keyPath: keyPath][weekday] ?? fallback
                return Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(minutes) * 60)
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule[keyPath: keyPath][weekday] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
