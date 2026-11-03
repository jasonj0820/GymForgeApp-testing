import HealthKit
import SwiftUI

/// MK11: last night vs your schedule, how consistent you've been, and "Going to sleep / I'm awake"
/// for nights the Watch didn't track (its own sleep tracking always wins).
struct WatchSleepView: View {
    @EnvironmentObject private var store: WatchAppStore
    @State private var nights: [SleepNight] = []
    @State private var sleepingSince: Date? = SleepHealth.manualStart
    private let healthStore = HKHealthStore()

    private var schedule: SleepSchedule { store.profile.sleepSchedule ?? .standard }

    var body: some View {
        let report = SleepAnalysis.report(nights: nights, schedule: schedule)
        List {
            if let last = report.lastNight {
                Section("Last night") {
                    Text(hours(last.night.hoursAsleep)).font(.title3.bold())
                    if let start = last.night.start {
                        Text("Bed \(start.formatted(date: .omitted, time: .shortened)) · \(SleepAnalysis.offText(last.bedMinutesOff))")
                            .font(.caption2)
                    }
                    if let end = last.night.end {
                        Text("Up \(end.formatted(date: .omitted, time: .shortened)) · \(SleepAnalysis.offText(last.wakeMinutesOff))")
                            .font(.caption2)
                    }
                }
            } else {
                Text("No sleep yet. Wear your Watch to bed (Sleep Focus on) or log it below.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let score = report.score {
                Section("Consistency") {
                    Text("\(score)/100").font(.headline)
                    Text("\(report.onScheduleStreak) on-schedule night\(report.onScheduleStreak == 1 ? "" : "s") in a row · \(report.lateNights7) late this week")
                        .font(.caption2)
                }
            }
            Section {
                let weekday = Calendar.current.component(.weekday, from: .now)
                Text("Tonight: bed \(SleepSchedule.format(schedule.bedMinutes(weekday))) · up \(SleepSchedule.format(schedule.wakeMinutes(weekday)))")
                    .font(.caption2)
                if let since = sleepingSince {
                    Button {
                        Task {
                            await SleepHealth.finishManual(store: healthStore)
                            sleepingSince = nil
                            await load()
                        }
                    } label: {
                        Label("I'm awake (since \(since.formatted(date: .omitted, time: .shortened)))", systemImage: "sun.max.fill")
                    }
                    .tint(.yellow)
                } else {
                    Button {
                        SleepHealth.manualStart = .now
                        sleepingSince = SleepHealth.manualStart
                    } label: {
                        Label("Going to sleep", systemImage: "moon.zzz.fill")
                    }
                    .tint(.indigo)
                }
            } footer: {
                Text("Only used when the Watch didn't track that night.")
            }
        }
        .navigationTitle("Sleep")
        .task { await load() }
    }

    private func hours(_ value: Double) -> String {
        "\(Int(value)) h \(Int((value - Double(Int(value))) * 60)) m"
    }

    private func load() async {
        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            try? await healthStore.requestAuthorization(toShare: SleepHealth.shareTypes, read: [type])
        }
        nights = await SleepHealth.nights(days: 21, store: healthStore)
    }
}
