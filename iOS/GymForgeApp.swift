import SwiftUI

@main
struct GymForgeApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var appDelegate
    // Shared so the background Shortcuts action (UpdateCardsIntent) uses the same stores.
    @StateObject private var store = PhoneAppStore.shared
    @StateObject private var dayfold = PhoneAppStore.shared.dayfold!
    @Environment(\.scenePhase) private var scenePhase
    /// The first launch runs its own sequence below; only later returns to the app re-check.
    @State private var launched = false
    /// Splitday (MK12+): one app, two halves. "gym" = GymForge, "dayfold" = Dayfold routines.
    @AppStorage("app.mode") private var mode = "gym"
    @State private var showWindDown = false
    @State private var showWakeUp = false
    @State private var showWeighIn = false

    init() {
        // MK20.6: the More Training widget's buttons run here (LiveActivityIntent → app process).
        MTWidgetControl.handler = { MTLiveTimer.handleWidget($0) }
        SharedGroup.migrateIfNeeded()   // MK20.7: sideloaded installs get a renamed App Group
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if mode == "dayfold" {
                    DayfoldRootView().tint(DayfoldPalette.accent).preferredColorScheme(.dark)
                        .transition(.push(from: .trailing))
                } else {
                    RootTabView()
                        .transition(.push(from: .leading))
                }
            }
            .animation(.smooth(duration: 0.45), value: mode)   // MK19: slide between the two halves
            .environmentObject(store)
            .environmentObject(dayfold)
            .sheet(isPresented: $showWindDown) {
                WindDownView().environmentObject(store).environmentObject(dayfold)
            }
            .sheet(isPresented: $showWakeUp) {
                WakeUpView().environmentObject(store).environmentObject(dayfold)
            }
            .sheet(isPresented: $showWeighIn) {
                WeighInSheet().environmentObject(store)
            }
            .task {
                // One permission prompt at a time: Health first, then notifications,
                // then (re)plan every notification now that they're allowed.
                await store.requestHealthAccess()
                await store.appBecameActive()
                dayfoldBecameActive()
                launched = true
                if let pending = AppLink.pending { open(pending) }
            }
            .onOpenURL(perform: open)
            .onReceive(NotificationCenter.default.publisher(for: .appLink)) { note in
                if launched, let url = note.object as? URL { open(url) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, launched {
                Task {
                    await store.appBecameActive()
                    dayfoldBecameActive()
                }
            }
        }
    }

    private func dayfoldBecameActive() {
        dayfold.autoTickWeighIn(weightDates: store.healthKit.bodyWeight.map(\.date))
        dayfold.refresh()
        dayfold.notifications.refreshPermission()
    }

    /// gymforge://bedtime · winddown · gym · weighin · dayfold[/daily|weekly|monthly|yearly]
    private func open(_ url: URL) {
        AppLink.pending = nil
        guard url.scheme == "gymforge" else { return }
        switch url.host {
        case "bedtime":   // MK11.2: "I'm going to bed" on the bedtime Live Activity.
            store.goingToBed()
        case "wakeup":
            showWakeUp = true
        case "winddown":
            store.startWindDown()
            showWindDown = true
        case "gym":
            mode = "gym"
        case "weighin":   // MK20.2: the Sunday 9am reminder.
            mode = "gym"
            showWeighIn = true
        case "mt":   // MK17: the More Training timer card. Still unlocked mid-timer; otherwise asks first.
            let wasDayfold = mode == "dayfold"
            mode = "gym"
            // Give GymForge's Today screen a moment to appear if we were in Dayfold.
            DispatchQueue.main.asyncAfter(deadline: .now() + (wasDayfold ? 0.6 : 0)) {
                NotificationCenter.default.post(name: .openMoreTraining, object: nil)
            }
        case "dayfold":
            mode = "dayfold"
            let routine = url.lastPathComponent
            if RoutineKind(rawValue: routine) != nil {
                NotificationCenter.default.post(name: .dayfoldOpenRoutine, object: routine)
            }
        default:
            break
        }
    }
}
