import ActivityKit
import Foundation

/// Starts, updates and ends Sergeant Cluck's Live Activity (Lock Screen + Dynamic Island).
/// iOS only lets an app start one while it's open, so this runs whenever GymForge refreshes.
@MainActor
enum CluckActivityManager {
    static let enabledKey = "cluck.liveActivity"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Shown on days you haven't trained yet and still owe sessions, from now until 9pm.
    static func sync(_ snapshot: CluckSnapshot, workoutActive: Bool, now: Date = .now) {
        let cal = Calendar.current
        let current = CluckEngine.evaluate(snapshot, at: now)
        let cutoff = cal.date(bySettingHour: CluckEngine.cutoffHour, minute: CluckEngine.cutoffMinute, second: 0, of: now) ?? now
        let endOfNags = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now) ?? now
        // The More Training timer card takes his place while it runs.
        let trainingTimer = Activity<MTTimerAttributes>.activities.contains { [.active, .stale].contains($0.activityState) }
        let shouldShow = isEnabled && snapshot.enabled && !workoutActive && !trainingTimer && now < endOfNags
            && !current.trainedToday && current.remaining > 0 && !current.snoozedToday
            && [.watching, .annoyed, .furious, .doomed, .suspicious].contains(current.mood)
        guard shouldShow, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endAll()
            return
        }

        // The mood he'll have once 5:10 passes (if it hasn't already).
        let later = CluckEngine.evaluate(snapshot, at: max(now, cutoff.addingTimeInterval(60)))
        let state = CluckActivityAttributes.ContentState(
            mood: current.mood.rawValue,
            moodAfterCutoff: later.mood.rawValue,
            line: CluckEngine.line(current, at: now),
            lineAfterCutoff: CluckEngine.line(later, at: now),
            remaining: current.remaining,
            daysLeft: current.daysLeft,
            spare: current.spare,
            cutoff: cutoff
        )
        let content = ActivityContent(state: state, staleDate: now < cutoff ? cutoff : nil, relevanceScore: 50)
        let today = cal.startOfDay(for: now)

        let running = Activity<CluckActivityAttributes>.activities
        if let activity = running.first(where: { cal.isDate($0.attributes.day, inSameDayAs: today) }) {
            Task { await activity.update(content) }
            for other in running where other.id != activity.id {
                Task { await other.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        endAll()
        do {
            _ = try Activity.request(attributes: CluckActivityAttributes(day: today), content: content, pushType: nil)
        } catch {
            print("Cluck Live Activity failed: \(error)")
        }
    }

    static func endAll() {
        for activity in Activity<CluckActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
