import SwiftUI
import WatchKit

@main
struct GymForgeWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WatchAppStore.shared
    @StateObject private var dayfold = DayfoldStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(store.workoutManager)
                .environmentObject(dayfold)
        }
    }
}
