import ActivityKit
import AppIntents
import Foundation
import UserNotifications
import WidgetKit

/// The Live Activity: block title, plus the timer state that changes on pause/resume.
struct BlockActivity: ActivityAttributes {
    typealias ContentState = ActiveTimer
    var title: String
}

/// The pause/resume button on the Live Activity. Runs in the app's process, in the background.
struct PauseResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume block"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await TimerControl.togglePause()
        return .result()
    }
}

/// MK2: "Full" / "Minimum" on the Live Activity once time is up, so a block can be ticked off from the
/// Lock Screen without opening the app.
struct TickOffIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Tick off block"
    static var openAppWhenRun = false

    @Parameter(title: "Full version")
    var full: Bool

    init() {}
    init(full: Bool) { self.full = full }

    func perform() async throws -> some IntentResult {
        TimerControl.complete(full ? .full : .minimum)
        await TimerControl.endActivities()
        return .result()
    }
}

/// Every change to the running timer goes through here, so the app, widget and Live Activity stay in step.
enum TimerControl {
    static let changed = Notification.Name("ductile.timerChanged")

    static func start(_ block: Block) {
        let timer = ActiveTimer(blockID: block.id, ends: Date().addingTimeInterval(Double(block.focus) * 60))
        save(timer)
        scheduleEndAlert(for: timer, title: block.title)
        Reminders.reschedule()   // the running block doesn't need "start now"
        // Going stale at the end is what redraws the card with its Full / Minimum buttons.
        _ = try? Activity.request(attributes: BlockActivity(title: block.title),
                                  content: ActivityContent(state: timer, staleDate: timer.ends))
    }

    static func togglePause() async {
        guard let timer = Store.active?.toggled() else { return }
        save(timer)
        if timer.isPaused {
            cancelEndAlert()
        } else {
            let title = Store.blocks.first { $0.id == timer.blockID }?.title ?? "Block"
            scheduleEndAlert(for: timer, title: title)
        }
        for activity in Activity<BlockActivity>.activities {
            await activity.update(ActivityContent(state: timer, staleDate: timer.isPaused ? nil : timer.ends))
        }
    }

    /// Ends the timer and, with an outcome, ticks its block off with the time the timer really ran.
    /// nil = stopped without doing it. Follow with `endActivities()`.
    static func complete(_ outcome: Block.Outcome?) {
        guard let timer = Store.active else { return }
        if let outcome {
            var blocks = Store.blocks
            if let i = blocks.firstIndex(where: { $0.id == timer.blockID }) {
                blocks[i].outcome = outcome
                blocks[i].focusedMinutes = max(0, Int((Double(blocks[i].focus) * 60 - timer.left()) / 60))
                Store.blocks = blocks
            }
        }
        cancelEndAlert()
        save(nil)
        Reminders.reschedule()
    }

    static func endActivities() async {
        for activity in Activity<BlockActivity>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func save(_ timer: ActiveTimer?) {
        Store.active = timer
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    private static func scheduleEndAlert(for timer: ActiveTimer, title: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "\(title) is done"
        content.body = "Tick it off: full or minimum. Both count."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.left()), repeats: false)
        center.add(UNNotificationRequest(identifier: "block-end", content: content, trigger: trigger))
    }

    private static func cancelEndAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["block-end"])
    }
}

/// MK2: a nudge when each block's window opens and at its "start by" time.
enum Reminders {
    /// Replaces every planned reminder with what the calendar says now. Cheap; called on every change.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        let planned = Store.remind ? reminders(for: Store.blocks, now: Date(), skipping: Store.active?.blockID) : []
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("remind-") })
            guard !planned.isEmpty else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                for reminder in planned {
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = reminder.body
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
                    center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                }
            }
        }
    }
}
