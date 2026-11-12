import Foundation
import UIKit
import UserNotifications
import WidgetKit

/// Schedules Sergeant Cluck's 5:10 / 7:00 / 8:30pm nags for the next week, assuming you
/// don't train in the meantime. Logging a workout re-plans everything (and cancels today's).
enum CluckNotifier {
    static let category = "gymforge.cluck"
    static let snoozeAction = "gymforge.cluck.snooze"
    private static let daysAhead = 7
    private static let motivationDays = 4
    static let restNagHours = [10, 12, 14, 16]
    static let recapID = "gymforge.cluck.recap"

    private static var allIDs: [String] {
        let stages = (0..<daysAhead).flatMap { day in (0..<CluckEngine.stages.count).map { "gymforge.cluck.\(day).\($0)" } }
        let rest = (0..<daysAhead).flatMap { day in restNagHours.indices.map { "gymforge.cluck.r.\(day).\($0)" } }
        let motivation = (0..<motivationDays).flatMap { day in (0..<2).map { "gymforge.cluck.m.\(day).\($0)" } }
        return stages + rest + motivation
    }

    static func registerCategory() {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Not today (1 per week)", options: [])
        let cluckCategory = UNNotificationCategory(identifier: category, actions: [snooze], intentIdentifiers: [], options: [])
        // MK14: log protein straight from the nag (runs in the background, app stays closed).
        let protein = UNNotificationCategory(identifier: ProteinNotifier.category,
                                             actions: [UNNotificationAction(identifier: ProteinNotifier.add25, title: "+25 g", options: []),
                                                       UNNotificationAction(identifier: ProteinNotifier.add40, title: "+40 g", options: [])],
                                             intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var set = existing.filter { $0.identifier != Self.category && $0.identifier != ProteinNotifier.category }
            set.insert(cluckCategory)
            set.insert(protein)
            UNUserNotificationCenter.current().setNotificationCategories(set)
        }
    }

    private static func add(_ id: String, _ message: (title: String, body: String), at fire: Date, snooze: Bool,
                            opensReview: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.interruptionLevel = .active
        if snooze { content.categoryIdentifier = category }
        if opensReview { content.userInfo = ["open": "review"] }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    /// Plans the next week of nags, rest-day nags and random motivation, assuming you don't train
    /// in the meantime. Logging (or starting) a workout re-plans everything.
    static func reschedule(_ snapshot: CluckSnapshot, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: allIDs)
        guard snapshot.enabled else { return }
        let cal = Calendar.current

        for day in 0..<daysAhead {
            guard let date = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: now)) else { continue }

            // 5:10 / 7:00 / 8:30pm
            for (index, stage) in CluckEngine.stages.enumerated() {
                guard let fire = cal.date(bySettingHour: stage.hour, minute: stage.minute, second: 0, of: date),
                      fire > now else { continue }
                let state = CluckEngine.evaluate(snapshot, at: fire)
                guard let message = CluckEngine.notification(state, stage: index, at: fire, style: snapshot.coachStyle) else { continue }
                add("gymforge.cluck.\(day).\(index)", message, at: fire, snooze: state.snoozeAvailable)
            }

            // Rest day: every two hours from 10am too (next 3 days, to stay under iOS's 64-notification limit).
            for (index, hour) in restNagHours.enumerated() where day < 3 {
                guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: date), fire > now else { continue }
                let state = CluckEngine.evaluate(snapshot, at: fire)
                guard state.restDay, state.mood.nags else { continue }
                add("gymforge.cluck.r.\(day).\(index)", CluckEngine.restDayNag(state, index: index, at: fire), at: fire, snooze: false)
            }

            // MK19: the twice-daily motivation messages are gone (their IDs stay in allIDs so old ones get cancelled).
        }
    }

    /// Sunday 7:30pm recap of this week (re-planned whenever a workout is logged).
    static func scheduleRecap(enabled: Bool, sessions: Int, goal: Int, prs: Int, liftsUp: Int, restDays: Int,
                              style: String, strongerLifts: [String] = [], leanChange: Double? = nil, phase: String = "",
                              now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [recapID])
        guard enabled else { return }
        let cal = Calendar.current
        var parts = DateComponents()
        parts.weekday = 1   // Sunday
        parts.hour = 19
        parts.minute = 30
        guard let fire = cal.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) else { return }
        var message = CluckEngine.recap(sessions: sessions, goal: goal, prs: prs, liftsUp: liftsUp,
                                        restDays: restDays, style: style)
        if let celebration = CluckEngine.celebration(strongerLifts: strongerLifts, leanChange: leanChange, phase: phase) {
            message = ("🪖🎉 " + message.title.replacingOccurrences(of: "🪖 ", with: ""), celebration + " " + message.body)
        }
        message.body += " Tap for your weekly review."
        add(recapID, message, at: fire, snooze: false, opensReview: true)
    }

    static let reviewID = "gymforge.review"

    /// Sunday 7:30pm "your weekly review is ready" — only when Sergeant Cluck is off
    /// (otherwise his recap carries the link).
    static func scheduleReviewReminder(standalone: Bool, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reviewID])
        guard standalone else { return }
        var parts = DateComponents()
        parts.weekday = 1
        parts.hour = 19
        parts.minute = 30
        guard let fire = Calendar.current.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) else { return }
        add(reviewID, ("Weekly review", "Your week in sets, priorities and coaching follow-ups is ready."),
            at: fire, snooze: false, opensReview: true)
    }

    /// "Not today" from a notification (works with the app closed).
    static func handleSnooze() {
        let used = CluckStore.snoozeToday()
        if let snapshot = CluckStore.load() { reschedule(snapshot) }
        WidgetCenter.shared.reloadTimelines(ofKind: CluckStore.widgetKind)

        let content = UNMutableNotificationContent()
        content.title = "🪖 Sergeant Cluck"
        content.body = used
            ? ["Fine. Take your day. I'll remember this.",
               "Snoozed. I'm writing this down. In pen.",
               "Enjoy the couch. I'll be here. Judging."].randomElement()!
            : "You already used this week's snooze. Nice try. Gym."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "gymforge.cluck.reply", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}

/// Handles notification actions and decides what shows while the app is open.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set when the weekly-review notification was tapped before the UI was ready.
    static var pendingReview = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        CluckNotifier.registerCategory()
        return true
    }

    /// MK22.1: portrait everywhere, except the screens that ask for more (the More Training timers).
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    /// Home Screen long-press actions arrive through the scene delegate.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { AppLink.open(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let grams = ProteinNotifier.grams(for: response.actionIdentifier) {
            Task { @MainActor in
                PhoneAppStore.shared.addProtein(grams)
                completionHandler()
            }
            return
        }
        if response.actionIdentifier == CluckNotifier.snoozeAction {
            CluckNotifier.handleSnooze()
            NotificationCenter.default.post(name: .cluckChanged, object: nil)
        } else if let routine = response.notification.request.content.userInfo["routine"] as? String {
            AppLink.open(URL(string: "gymforge://dayfold/\(routine)")!)
        } else if response.notification.request.identifier.hasPrefix("gymforge.wake") {
            AppLink.open(URL(string: "gymforge://wakeup")!)
        } else if response.notification.request.identifier.hasPrefix("gymforge.sleep.wind") {
            AppLink.open(URL(string: "gymforge://winddown")!)
        } else if response.notification.request.content.userInfo["open"] as? String == "weighin" {
            AppLink.open(URL(string: "gymforge://weighin")!)
        } else if response.notification.request.content.userInfo["open"] as? String == "review" {
            PhoneAppDelegate.pendingReview = true
            NotificationCenter.default.post(name: .openWeeklyReview, object: nil)
        }
        completionHandler()
    }

    /// While the app is open: banners for reminders and Sergeant Cluck; timers stay in-app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        // The rest timer already buzzes inside the app. Private timers only buzz on their own screens
        // (and not while locked), so they still sound here — no banner, so nothing shows on screen.
        if id.hasPrefix("gymforge.rest") {
            completionHandler([])
        } else if id.hasPrefix("gymforge.mt") {
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }
}

/// MK14: protein nags for today and tomorrow (6 fixed IDs), rebuilt whenever you log protein or open the app.
enum ProteinNotifier {
    static let category = "gymforge.protein"
    static let add25 = "gymforge.protein.add25"
    static let add40 = "gymforge.protein.add40"
    private static let ids = (0...1).flatMap { day in ProteinNag.checkpoints.indices.map { "gymforge.protein.nag.\(day).\($0)" } }

    static func grams(for action: String) -> Double? {
        [add25: 25, add40: 40][action]
    }

    @MainActor
    static func reschedule(store: PhoneAppStore, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)   // stale once you've logged more
        guard let target = store.proteinTargetG, target > 0 else { return }
        let cal = Calendar.current
        for day in 0...1 {
            guard let date = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: now)) else { continue }
            let eaten = day == 0 ? store.nutritionToday(now).proteinG : 0
            for checkpoint in ProteinNag.behind(eaten: eaten, target: target) {
                guard let fire = cal.date(bySettingHour: checkpoint.hour, minute: checkpoint.minute, second: 0, of: date), fire > now,
                      let index = ProteinNag.checkpoints.firstIndex(of: checkpoint) else { continue }
                let message = ProteinNag.message(eaten: eaten, target: target, at: checkpoint)
                let content = UNMutableNotificationContent()
                content.title = message.title
                content.body = message.body
                content.sound = .default
                content.interruptionLevel = .active
                content.categoryIdentifier = category
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: "gymforge.protein.nag.\(day).\(index)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

/// MK16: quotes at 8:00, 13:00 and 18:00 for today and tomorrow (6 fixed IDs), silent.
enum QuoteNotifier {
    private static let ids = (0...1).flatMap { day in QuotePicker.slotHours.indices.map { "gymforge.quote.\(day).\($0)" } }

    static func reschedule(now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        WidgetCenter.shared.reloadTimelines(ofKind: QuoteSettings.widgetKind)
        guard QuoteSettings.notify else { return }
        let cal = Calendar.current
        for day in 0...1 {
            guard let date = cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: now)) else { continue }
            for (index, hour) in QuotePicker.slotHours.enumerated() {
                guard let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: date), fire > now else { continue }
                let quote = QuoteSettings.current(at: fire)
                let content = UNMutableNotificationContent()
                content.title = quote.topic.title
                content.body = quote.text + (quote.author.map { "\n— \($0)" } ?? "")
                content.interruptionLevel = .passive   // no sound; sits on the Lock Screen
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                center.add(UNNotificationRequest(identifier: "gymforge.quote.\(day).\(index)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }
}

/// MK22.1: the app is portrait. A screen that also works on its side (the More Training timers) asks for
/// landscape while it's showing; when the last one goes, the app turns upright again.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait
    private static var askers: Set<String> = []

    @MainActor
    static func allowLandscape(_ allowed: Bool, for screen: String) {
        if allowed { askers.insert(screen) } else { askers.remove(screen) }
        apply()
    }

    /// Leaving More Training: nothing may stay sideways.
    @MainActor
    static func reset() {
        askers = []
        apply()
    }

    @MainActor
    private static func apply() {
        let wanted: UIInterfaceOrientationMask = askers.isEmpty ? .portrait : .allButUpsideDown
        guard wanted != mask else { return }
        mask = wanted
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                // Whatever is on top decides the orientation, so tell the whole presentation chain.
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            if wanted == .portrait {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
    }
}

/// Long-press menu on the app icon: GymForge / Dayfold / Wind down.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        AppLink.open(shortcutItem)
        completionHandler(true)
    }
}

/// gymforge:// links from quick actions and notification taps, held until the UI is listening (cold launch).
enum AppLink {
    static var pending: URL?
    static func open(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: .appLink, object: url)
    }
    static func open(_ item: UIApplicationShortcutItem) {
        if let url = URL(string: item.type) { open(url) }
    }
}

extension Notification.Name {
    static let appLink = Notification.Name("gymforge.appLink")
    static let openMoreTraining = Notification.Name("gymforge.openMoreTraining")
    static let cluckChanged = Notification.Name("gymforge.cluckChanged")
    static let openWeeklyReview = Notification.Name("gymforge.openWeeklyReview")
}
