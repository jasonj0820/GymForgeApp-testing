import SwiftUI
import UserNotifications
import BackgroundTasks

let backgroundCheckID = "MoneyPilot.check" // Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
/// Asks iOS to run a PocketSmith check in a few hours. iOS decides the exact time based on how you use the app.
func scheduleBackgroundCheck() {
    let request = BGAppRefreshTaskRequest(identifier: backgroundCheckID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // Hourly is the soonest we ask for; iOS may run it later.
    try? BGTaskScheduler.shared.submit(request) // Not available in the simulator; harmless failure there.
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound, .list]) }
}
@main @MainActor struct MoneyPilotApp: App {
    @StateObject private var store = Store()
    private let delegate = NotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = delegate }
    var body: some Scene {
        let model = store
        WindowGroup { RootView().environmentObject(model).tint(.mint).preferredColorScheme(.dark) }
            .backgroundTask(.appRefresh(backgroundCheckID)) {
                scheduleBackgroundCheck()
                await model.backgroundCheck()
            }
    }
}
