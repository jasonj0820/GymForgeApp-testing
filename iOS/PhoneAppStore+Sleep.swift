import ActivityKit
import Foundation
import UIKit
import UserNotifications

/// MK11: sleep schedule, wind-down Live Activity and reminders.
extension PhoneAppStore {
    var sleepSchedule: SleepSchedule { profile.sleepSchedule ?? .standard }
    var sleepReport: SleepReport { SleepAnalysis.report(nights: healthKit.sleep, schedule: sleepSchedule) }

    func setSleepSchedule(_ schedule: SleepSchedule?) {
        var updated = profile
        updated.sleepSchedule = schedule
        setProfile(updated)   // syncs to the Watch and re-plans Cluck
        refreshSleep()
    }

    /// Re-plans the 15-minute reminders and starts / updates tonight's Live Activity.
    func refreshSleep(now: Date = .now) {
        scheduleWindDownNotifications()
        scheduleWakeChecklist(now: now)
        scheduleBedtimeNags(now: now)
        syncSleepActivity(now: now)
    }

    // MARK: MK11.2 — nag until "I'm going to bed"

    /// Your shortcut that turns on Sleep Focus (Shortcuts app). Empty = don't run one.
    static let focusShortcutKey = "gymforge.sleep.focusShortcut"
    private static let dismissedKey = "gymforge.sleep.dismissedNight"
    private static let startedKey = "gymforge.sleep.windDownStarted"
    /// Evening (start of day, seconds since 1970) → minutes late when you tapped "I'm going to bed".
    private static let bedLogKey = "gymforge.sleep.bedLog"

    // MARK: Dayfold before-bed checklist

    /// Tomorrow's planned session (Plan week), for "Pack gym bag" and the gym-night nudge.
    func gymSession(afterNightOf bed: Date) -> String? {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: evening(of: bed)),
              let plan = extras.dayPlan(on: tomorrow), plan.kind == .workout else { return nil }
        return plan.routineName ?? "Gym"
    }

    func gymSessionTomorrow(now: Date = .now) -> String? {
        gymSession(afterNightOf: tonightsBedtime(now: now) ?? Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now)
    }

    var windDownStarted: Bool {
        guard let bed = tonightsBedtime() else { return false }
        return (UserDefaults.standard.object(forKey: Self.startedKey) as? Date).map { Calendar.current.isDate($0, inSameDayAs: evening(of: bed)) } ?? false
    }

    /// "Start" on the Live Activity, the wind-down notification, or opening the checklist.
    func startWindDown(now: Date = .now) {
        if let bed = tonightsBedtime(now: now) { UserDefaults.standard.set(evening(of: bed), forKey: Self.startedKey) }
        syncSleepActivity(now: now)
    }

    /// A Dayfold check-off: finishing the before-bed checklist in the wind-down window counts as going to bed.
    func dayfoldChanged(now: Date = .now) {
        let rows = dayfold?.bedtimeRows(now: now) ?? []
        if windDownStarted, inBedtimeWindow(now: now), !rows.isEmpty, rows.allSatisfy(\.done) {
            goingToBed(now: now)
        } else {
            syncSleepActivity(now: now)
        }
        scheduleWakeChecklist(now: now)   // ticking the morning list cancels its follow-up
    }

    // MARK: MK15 — rest days, nightly recap, wake-up checklist

    /// No session planned or logged today (sick/travel days don't count as rest days).
    func isRestDay(now: Date = .now) -> Bool {
        extras.dayPlan(on: now) == nil
            && !workoutLogs.contains { $0.countsAsTraining && Calendar.current.isDate($0.startedAt, inSameDayAs: now) }
    }

    static let recapKey = "gymforge.recap.last"

    func dailyRecap(evening: Date) -> DailyRecap.Recap {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: evening) ?? evening
        let steps = RoutineKind.allCases.flatMap { dayfold?.rows($0, now: noon) ?? [] }.filter { $0.retryToday || $0.done }
        let food = nutritionToday(evening)
        return DailyRecap.make(proteinG: food.proteinG, target: proteinTargetG, creatine: food.creatine,
                               trained: workoutLogs.contains { $0.countsAsTraining && cal.isDate($0.startedAt, inSameDayAs: evening) },
                               stepsDone: steps.filter(\.done).count, stepsTotal: steps.count,
                               gymTomorrow: gymSession(afterNightOf: bedtime(forEvening: evening)))
    }

    private func bedtime(forEvening evening: Date) -> Date {
        (profile.sleepSchedule ?? .standard).bedtime(forNightOf: evening)
    }

    /// Sent as you go to bed; also shown on the wake-up checklist next morning.
    private func sendRecap(evening: Date) {
        let recap = dailyRecap(evening: evening)
        UserDefaults.standard.set(["title": recap.title, "text": recap.text, "date": evening.timeIntervalSince1970], forKey: Self.recapKey)
        let content = UNMutableNotificationContent()
        content.title = recap.title
        content.body = recap.text
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "gymforge.recap", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// Last night's recap, if it was last night.
    var lastRecap: (title: String, text: String)? {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.recapKey),
              let title = saved["title"] as? String, let text = saved["text"] as? String,
              let date = saved["date"] as? Double,
              Date(timeIntervalSince1970: date) > Date.now.addingTimeInterval(-36 * 3600) else { return nil }
        return (title, text)
    }

    private static let wakeIDs = (0...1).flatMap { morning in (0...1).map { "gymforge.wake.\(morning).\($0)" } }

    /// The next two mornings: at wake time, plus one follow-up 45 min later while the list is still open.
    func scheduleWakeChecklist(now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.wakeIDs)
        guard let schedule = profile.sleepSchedule, let dayfold else { return }
        let cal = Calendar.current
        let mornings = (-1...1).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) }
            .map { schedule.wakeTime(forNightOf: $0) }
            .filter { $0.addingTimeInterval(45 * 60) > now }
            .prefix(2)
        for (index, wake) in mornings.enumerated() {
            let open = dayfold.wakeRows(now: wake).filter { !$0.done }
            guard !open.isEmpty else { continue }
            for (step, fire) in [wake, wake.addingTimeInterval(45 * 60)].enumerated() where fire > now {
                let content = UNMutableNotificationContent()
                content.title = step == 0 ? "☀️ Wake-up checklist" : "🪖 Wake-up checklist still open"
                content.body = open.map(\.task.title).joined(separator: "\n")
                content.sound = .default
                content.interruptionLevel = .active
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: "gymforge.wake.\(index).\(step)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    /// Nights in a row you tapped "I'm going to bed" by your bedtime.
    var bedtimeStreak: Int {
        let raw = UserDefaults.standard.dictionary(forKey: Self.bedLogKey) as? [String: Int] ?? [:]
        let log = Dictionary(uniqueKeysWithValues: raw.compactMap { key, late in Double(key).map { (Date(timeIntervalSince1970: $0), late) } })
        return BedtimeNag.streak(log: log, today: evening(of: tonightsBedtime() ?? .now))
    }

    /// The evening (start of day) a bedtime belongs to.
    private func evening(of bed: Date) -> Date { Calendar.current.startOfDay(for: bed.addingTimeInterval(-12 * 3600)) }

    /// Tonight's bedtime — still "tonight" until an hour after it.
    func tonightsBedtime(now: Date = .now) -> Date? {
        profile.sleepSchedule?.nextBedtime(after: now.addingTimeInterval(-BedtimeNag.windowAfter))
    }

    /// True from wind-down (10 min before bed) to an hour after, unless you've tapped "I'm going to bed".
    func inBedtimeWindow(now: Date = .now) -> Bool {
        guard let bed = tonightsBedtime(now: now) else { return false }
        return bed.timeIntervalSince(now) <= BedtimeNag.windowBefore && !isDismissed(bed)
    }

    private func isDismissed(_ bed: Date) -> Bool {
        (UserDefaults.standard.object(forKey: Self.dismissedKey) as? Date).map { Calendar.current.isDate($0, inSameDayAs: evening(of: bed)) } ?? false
    }

    private func nagIDs(_ bed: Date) -> [String] {
        let key = Int(evening(of: bed).timeIntervalSince1970)
        return ([0] + BedtimeNag.offsets).map { "gymforge.sleep.nag.\(key).\($0)" }
    }

    /// One-shot nags for tonight and tomorrow night (one-shots keep us well under iOS's 64 pending notifications).
    private func scheduleBedtimeNags(now: Date) {
        let center = UNUserNotificationCenter.current()
        guard let schedule = profile.sleepSchedule, let tonight = tonightsBedtime(now: now) else {
            center.getPendingNotificationRequests { requests in
                center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("gymforge.sleep.nag.") })
            }
            return
        }
        let nights = [tonight, schedule.nextBedtime(after: tonight.addingTimeInterval(60))]
        center.removePendingNotificationRequests(withIdentifiers: nights.flatMap(nagIDs))
        for bed in nights where !isDismissed(bed) {
            // Gym tomorrow: one extra nag right at bedtime, and every nag says what's at stake.
            let gym = gymSession(afterNightOf: bed)
            for (offset, id) in zip([0] + BedtimeNag.offsets, nagIDs(bed)) {
                let fire = bed.addingTimeInterval(Double(offset) * 60)
                guard fire > now, offset > 0 || gym != nil else { continue }
                let message = offset == 0
                    ? (title: "🪖 LIGHTS OUT", body: "Bedtime. \(gym ?? "Gym") tomorrow — you lift better rested. Bag packed?")
                    : BedtimeNag.message(minutesLate: offset)
                let content = UNMutableNotificationContent()
                content.title = message.title
                content.body = offset > 0 && gym != nil ? message.body + " \(gym!) tomorrow." : message.body
                content.sound = .default
                content.interruptionLevel = .active
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: id, content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    /// "I'm going to bed" (Live Activity button, Today card): the card goes, the nags stop, and your
    /// Sleep Focus shortcut runs. Sleep itself is left to the Apple Watch.
    func goingToBed(now: Date = .now) {
        guard let bed = tonightsBedtime(now: now) else { return }
        if !isDismissed(bed) { sendRecap(evening: evening(of: bed)) }
        UserDefaults.standard.set(evening(of: bed), forKey: Self.dismissedKey)
        var log = UserDefaults.standard.dictionary(forKey: Self.bedLogKey) as? [String: Int] ?? [:]
        log[String(Int(evening(of: bed).timeIntervalSince1970))] = Int(now.timeIntervalSince(bed) / 60)
        UserDefaults.standard.set(log.filter { Double($0.key).map { $0 > now.timeIntervalSince1970 - 90 * 86_400 } ?? false }, forKey: Self.bedLogKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: nagIDs(bed))
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: nagIDs(bed))
        for activity in Activity<SleepActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let name = UserDefaults.standard.string(forKey: Self.focusShortcutKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !name.isEmpty, let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private static let windDownIDs = (1...7).map { "gymforge.sleep.wind.\($0)" }

    /// One weekly reminder per night, at wind-down (10 min before that night's bedtime; iPhone + Watch, with sound).
    /// Tapping it opens the before-bed checklist and starts the wind-down Live Activity.
    private func scheduleWindDownNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.windDownIDs)
        guard let schedule = profile.sleepSchedule else { return }
        for weekday in 1...7 {
            let bed = schedule.bedMinutes(weekday)
            let fire = (bed < 12 * 60 ? bed + 24 * 60 : bed) - Int(BedtimeNag.windowBefore / 60)
            var components = DateComponents()
            components.weekday = (weekday - 1 + fire / (24 * 60)) % 7 + 1
            components.hour = (fire % (24 * 60)) / 60
            components.minute = fire % 60
            let content = UNMutableNotificationContent()
            content.title = "🪖 Wind down"
            content.body = "Lights out at \(SleepSchedule.format(bed)). Tap to start your before-bed checklist."
            content.sound = .default
            content.interruptionLevel = .active
            center.add(UNNotificationRequest(identifier: Self.windDownIDs[weekday - 1], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
    }

    /// MK11.1: the Live Activity only exists in the wind-down window (10 min before bed → an hour after), so the
    /// rest of the day the Lock Screen is about the gym. iOS only lets an app start one while it's open — the
    /// wind-down notification brings you in at the right time.
    func syncSleepActivity(now: Date = .now) {
        let running = Activity<SleepActivityAttributes>.activities
        guard let schedule = profile.sleepSchedule, ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in running { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let calendar = Calendar.current
        // MK13.1: from 2 h before bed (any app open or the Shortcuts automation puts it up early, so it's
        // already there at wind-down) until you tap "I'm going to bed" or an hour past bedtime.
        let bed = schedule.nextBedtime(after: now.addingTimeInterval(-BedtimeNag.windowAfter))
        let evening = calendar.startOfDay(for: bed.addingTimeInterval(-12 * 3600))
        guard bed.timeIntervalSince(now) <= BedtimeNag.cardBefore, !isDismissed(bed) else {
            for activity in running { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        let windDown = bed.addingTimeInterval(-BedtimeNag.windowBefore)
        let checklist = dayfold?.bedtimeRows(now: now) ?? []
        let state = SleepActivityAttributes.ContentState(bedtime: bed, windDown: windDown,
                                                         wake: schedule.wakeTime(forNightOf: evening),
                                                         lateNights: sleepReport.lateNights7,
                                                         started: windDownStarted,
                                                         done: checklist.filter(\.done).count,
                                                         total: checklist.count,
                                                         next: checklist.first { !$0.done }?.task.title,
                                                         gym: gymSession(afterNightOf: bed))
        // Goes stale at bedtime → the card turns into Cluck yelling, with a live "minutes late" counter.
        let content = ActivityContent(state: state, staleDate: now < bed ? bed : nil, relevanceScore: 60)
        if let current = running.first(where: { calendar.isDate($0.attributes.night, inSameDayAs: evening) }) {
            Task { await current.update(content) }
            for other in running where other.id != current.id { Task { await other.end(nil, dismissalPolicy: .immediate) } }
            return
        }
        for activity in running { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        _ = try? Activity.request(attributes: SleepActivityAttributes(night: evening), content: content, pushType: nil)
    }
}
