import Foundation
import UserNotifications

/// Local notifications: falling behind the weekly goal, too many days off, monthly report, rest finished.
@MainActor
enum ReminderScheduler {
    private static let reminderIDs = (0..<7).map { "gymforge.reminder.\($0)" }
    private static let reportID = "gymforge.report"
    private static let restID = "gymforge.rest"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func reschedule(profile: UserProfile, logs: [WorkoutLog], weeklyGoal: Int, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: reminderIDs + [reportID])
        guard profile.reminders else { return }

        let calendar = Calendar.current
        let hour = profile.reminderHour ?? 17
        let minute = profile.reminderMinute ?? 30
        let goal = max(weeklyGoal, 1)
        let lastWorkout = logs.map(\.startedAt).max()

        // Sergeant Cluck handles "you're behind" nags when he's on, so skip these.
        for offset in 0..<(profile.cluckEnabled ? 0 : 7) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > now,
                  let week = calendar.dateInterval(of: .weekOfYear, for: day) else { continue }
            if logs.contains(where: { calendar.isDate($0.startedAt, inSameDayAs: day) }) { continue }

            let done = logs.filter { $0.startedAt >= week.start && $0.startedAt < fire }.count
            let remaining = goal - done
            guard remaining > 0 else { continue }
            let daysLeft = max(1, calendar.dateComponents([.day], from: day, to: week.end).day ?? 1)
            let daysOff = lastWorkout.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: day).day ?? 0 } ?? 99
            guard remaining >= daysLeft || daysOff >= 2 else { continue }

            let content = UNMutableNotificationContent()
            content.title = remaining >= daysLeft ? "\(done)/\(goal) workouts this week" : "\(daysOff) days since your last workout"
            content.body = message(style: profile.coachStyle, done: done, goal: goal, remaining: remaining, daysLeft: daysLeft, daysOff: daysOff)
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: reminderIDs[offset], content: content, trigger: trigger))
        }

        // Monthly report on the 1st at 9:00.
        if let thisMonth = calendar.dateInterval(of: .month, for: now),
           let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: thisMonth.end) {
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL"
            let content = UNMutableNotificationContent()
            content.title = "Your \(formatter.string(from: thisMonth.start)) report is ready"
            content.body = "Workouts, PRs, strength gained and body trends — open the Coach tab."
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: reportID, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    static func message(style: CoachStyle, done: Int, goal: Int, remaining: Int, daysLeft: Int, daysOff: Int) -> String {
        let tight = remaining >= daysLeft
        switch style {
        case .pushMe:
            return tight ? "\(remaining) to go and \(daysLeft) day\(daysLeft == 1 ? "" : "s") left. No excuses — train today." : "\(daysOff) days off. Get back in today."
        case .motivating:
            return tight ? "One workout today keeps your week on track. You've got this!" : "A session today gets your momentum back."
        case .analytical:
            return "Week: \(done)/\(goal) (\(GFFormat.percent(Double(done) / Double(goal)))). \(remaining) needed in \(daysLeft) day\(daysLeft == 1 ? "" : "s")."
        case .supportive:
            return tight ? "Even a short session today counts. Be kind to yourself." : "Whenever you're ready, a light session is a great way back."
        case .heartbreak:
            return tight ? "Don't text her. Train. \(remaining) to go." : "\(daysOff) days off. She's not waiting for you — neither should your goals."
        case .hardTruth:
            return tight ? "\(remaining) sessions, \(daysLeft) day\(daysLeft == 1 ? "" : "s"). Excuses don't build anything. Go." : "\(daysOff) days off. Comfort is winning. Take it back today."
        }
    }

    /// iPhone notification when rest ends (only used when the Watch isn't there to buzz).
    static func scheduleRestEnd(at date: Date, nextExercise: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restID])
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest finished"
        content.body = "Next: \(nextExercise)"
        // Locked iPhone: the chime / ding plays as the notification sound (the spoken part needs GymForge open).
        content.sound = RestSound.mode.fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) } ?? .default
        center.add(UNNotificationRequest(identifier: restID, content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }

    static func cancelRestEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restID])
    }
}
