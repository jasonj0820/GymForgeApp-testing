import ActivityKit
import AppIntents
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What the Lock Screen and Dynamic Island show. Shared by the app and the MoneyPilotLive extension. Amounts are AUD cents.
struct MoneyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var spare: Int64 // MK3.2: spare money (comfortable to spend) replaces "safe to spend today"
        var weekLeft: Int64
        var weekUsed: Double // Share of this week's budgets used or reserved
        var daysLeft: Int
        var nextName: String?
        var nextAmount: Int64?
        var nextDate: Date?
        var period: String? = nil // "week" or "month"
        // Payday: payKind is set on pay day; payAmount stays nil until you enter what arrived, then the split shows.
        var payKind: String? = nil
        var payAmount: Int64? = nil
        var paySavings: Int64? = nil
        var payInvest: Int64? = nil
        var paySpend: Int64? = nil
        // "Transfer now": the transfers to make in your bank app, shown one at a time.
        var transfers: [TransferStep]? = nil
        var step: Int? = nil
        // MK2.15: what the PocketSmith sign-in is doing, e.g. "Logging in to PocketSmith…". Shown instead of everything else while set.
        var status: String? = nil
        var takeawayLeft: Int64 = 0
    }
    struct TransferStep: Codable, Hashable { var from: String; var to: String; var amount: Int64 }
}
func wholeDollars(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "AUD").precision(.fractionLength(0))) }

/// Must match the App Groups entry in both targets' entitlements. If Xcode says it is taken, change it in all three places.
let appGroupID = "group.com.jasonchang.MoneyPilot"
/// The few numbers the Home Screen widget shows, saved by the app after every change. Amounts are AUD cents.
struct WidgetSnapshot: Codable {
    var shoppingLeft: Int64
    var shoppingLimit: Int64
    var shoppingUsed: Double
    var takeawayLeft: Int64
    var daysLeft: Int
    var updated: Date
    var period: String? = nil
    static let preview = WidgetSnapshot(shoppingLeft: 8_450, shoppingLimit: 15_000, shoppingUsed: 0.44, takeawayLeft: 3_200, daysLeft: 4, updated: Date())
    static func load() -> WidgetSnapshot? {
        UserDefaults(suiteName: appGroupID)?.data(forKey: "widget-snapshot").flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
    }
    func save() { UserDefaults(suiteName: appGroupID)?.set(try? JSONEncoder().encode(self), forKey: "widget-snapshot") }
}

/// Plain amount for pasting into a banking app, e.g. "350.00".
func pasteAmount(_ cents: Int64) -> String { String(format: "%.2f", Double(cents) / 100) }
/// The "Done" button on the Lock Screen and Dynamic Island: moves to the next transfer and copies its amount.
struct NextTransferIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next transfer"
    func perform() async throws -> some IntentResult {
        for activity in Activity<MoneyActivityAttributes>.activities {
            var state = activity.content.state
            guard let steps = state.transfers else { continue }
            let next = (state.step ?? 0) + 1
            if next < steps.count {
                state.step = next
                #if canImport(UIKit)
                UIPasteboard.general.string = pasteAmount(steps[next].amount)
                #endif
            } else { state.transfers = nil; state.step = nil } // All done: back to the everyday view.
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        return .result()
    }
}
