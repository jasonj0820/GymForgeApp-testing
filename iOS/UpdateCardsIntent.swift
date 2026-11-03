import AppIntents

/// MK12.1: Shortcuts action "Update Splitday cards". Runs in the background (no app switch) and starts,
/// updates or ends Sergeant Cluck's gym card and the bedtime wind-down card, exactly as opening the app would.
/// Use it in a Time of Day automation (e.g. 7:00 am and 10:10 pm) with "Run Immediately".
struct UpdateCardsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update Splitday cards"
    static var description = IntentDescription("Shows or refreshes the gym nag and bedtime wind-down cards on your Lock Screen, without opening Splitday.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = PhoneAppStore.shared
        store.refreshCluck()
        store.refreshSleep()
        ProteinNotifier.reschedule(store: store)   // keeps tomorrow's protein nags topped up
        QuoteNotifier.reschedule()
        store.dayfold?.refresh()
        return .result()   // silent: no pop-up when an automation runs it
    }
}

/// Makes the action show up under GymForge in Shortcuts with no setup.
struct GymForgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UpdateCardsIntent(), phrases: ["Update \(.applicationName) cards"],
                    shortTitle: "Update cards", systemImageName: "rectangle.stack.badge.person.crop")
    }
}
