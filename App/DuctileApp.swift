import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@main
struct DuctileApp: App {
    @StateObject private var model = Model()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            CalendarView()
                .environmentObject(model)
                .onOpenURL { model.handle($0) }
        }
        .onChange(of: phase) { _, new in
            if new == .active { model.refresh() }
        }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var blocks: [Block] {
        didSet {
            guard blocks != oldValue else { return }
            Store.blocks = blocks
            WidgetCenter.shared.reloadAllTimelines()
            Reminders.reschedule()
        }
    }
    /// Mirror of Store.active; changed only through TimerControl (also used by the Live Activity's buttons).
    @Published private(set) var active: ActiveTimer?
    @Published var remind = Store.remind {
        didSet { Store.remind = remind; Reminders.reschedule() }
    }
    /// Off = blocks are just a timer; the two Focus Shortcuts are never run.
    @Published var useFocus = Store.useFocus {
        didSet { Store.useFocus = useFocus }
    }

    init() {
        Store.migrateIfNeeded()
        blocks = Store.blocks
        active = Store.active
        NotificationCenter.default.addObserver(forName: TimerControl.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        WidgetCenter.shared.reloadAllTimelines()
        Reminders.reschedule()
    }

    /// The Live Activity's buttons change the store behind the app's back; pick that up.
    func refresh() {
        active = Store.active
        let stored = Store.blocks
        if stored != blocks { blocks = stored }
    }

    /// ductile://start?id=… comes from tapping a block on the widget.
    func handle(_ url: URL) {
        guard url.host == "start",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:)),
              let block = blocks.first(where: { $0.id == id }), block.outcome == nil
        else { return }
        start(block)
    }

    func start(_ block: Block) {
        guard active == nil else { return }
        TimerControl.start(block)
        // The Shortcut turns Focus on *until* the end time, so it switches off by itself even if Ductile is closed.
        if useFocus { UIApplication.shared.open(Links.runShortcut(Links.focusOn, text: String(block.focus))) }
    }

    func togglePause() { Task { await TimerControl.togglePause() } }

    /// nil = stopped without doing it.
    func finish(_ outcome: Block.Outcome?) {
        guard let timer = active else { return }
        TimerControl.complete(outcome)
        Task { await TimerControl.endActivities() }
        if useFocus, timer.isPaused || Date() < timer.ends { // ended early, so Focus may still be on
            UIApplication.shared.open(Links.runShortcut(Links.focusOff))
        }
    }

    /// Tick a block off (or clear the tick with nil) without running its timer.
    func mark(_ block: Block, _ outcome: Block.Outcome?) {
        guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[i].outcome = outcome
        if outcome == nil { blocks[i].focusedMinutes = nil }
    }

    func save(_ block: Block) {
        if let i = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[i] = block
        } else {
            blocks.append(block)
        }
    }

    func delete(_ block: Block) {
        if active?.blockID == block.id { finish(nil) }
        blocks.removeAll { $0.id == block.id }
    }

    func copy(_ block: Block, byDays days: Int) {
        blocks.append(block.copied(byDays: days))
    }

    /// Everything planned on `source`, laid onto `day` at the same times.
    func copyDay(from source: Date, to day: Date) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: source), to: calendar.startOfDay(for: day)).day ?? 0
        blocks.append(contentsOf: dayBlocks(blocks, on: source).map { $0.copied(byDays: days) })
    }
}
