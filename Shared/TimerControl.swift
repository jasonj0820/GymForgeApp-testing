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

/// Every change to the running timer goes through here, so the app, widget and Live Activity stay in step.
enum TimerControl {
    static let changed = Notification.Name("ductile.timerChanged")

    static func start(_ block: Block) {
        let timer = ActiveTimer(blockID: block.id, ends: Date().addingTimeInterval(Double(block.minutes) * 60))
        save(timer)
        scheduleEndAlert(for: timer, title: block.title)
        _ = try? Activity.request(attributes: BlockActivity(title: block.title),
                                  content: ActivityContent(state: timer, staleDate: nil))
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
            await activity.update(ActivityContent(state: timer, staleDate: nil))
        }
    }

    static func finish() async {
        save(nil)
        cancelEndAlert()
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
        content.body = "Open Ductile and tick it off: full or minimum."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.left()), repeats: false)
        center.add(UNNotificationRequest(identifier: "block-end", content: content, trigger: trigger))
    }

    private static func cancelEndAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["block-end"])
    }
}
