import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

@main
struct DuctileApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup {
            CalendarView()
                .environmentObject(model)
                .onOpenURL { model.handle($0) }
        }
    }
}

@MainActor
final class Model: ObservableObject {
    @Published var blocks = Store.blocks {
        didSet { Store.blocks = blocks; WidgetCenter.shared.reloadAllTimelines() }
    }
    /// Mirror of Store.active; changed only through TimerControl (also used by the Live Activity's pause button).
    @Published private(set) var active = Store.active

    init() {
        NotificationCenter.default.addObserver(forName: TimerControl.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.active = Store.active }
        }
    }

    /// ductile://start?id=… comes from tapping a block on the widget.
    func handle(_ url: URL) {
        guard url.host == "start",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:)),
              let block = blocks.first(where: { $0.id == id })
        else { return }
        start(block)
    }

    func start(_ block: Block) {
        guard active == nil else { return }
        TimerControl.start(block)
        // The Shortcut turns Focus on *until* the end time, so it switches off by itself even if Ductile is closed.
        UIApplication.shared.open(Links.runShortcut(Links.focusOn, text: String(block.focus)))
    }

    func togglePause() { Task { await TimerControl.togglePause() } }

    /// nil = stopped without doing it.
    func finish(_ outcome: Block.Outcome?) {
        guard let timer = active else { return }
        if let outcome, let i = blocks.firstIndex(where: { $0.id == timer.blockID }) {
            blocks[i].outcome = outcome
        }
        Task { await TimerControl.finish() }
        if timer.isPaused || Date() < timer.ends { // ended early, so Focus may still be on
            UIApplication.shared.open(Links.runShortcut(Links.focusOff))
        }
    }
}
