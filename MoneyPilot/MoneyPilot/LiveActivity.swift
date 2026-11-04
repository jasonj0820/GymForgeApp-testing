import ActivityKit
import Foundation
import UIKit
import WidgetKit

extension WidgetSnapshot {
    init(_ e: Engine) {
        let limit = e.state.settings.shoppingLimit ?? 0 // MK3: spare money and its optional limit, not a shopping budget
        self.init(shoppingLeft: e.shoppingAvailable, shoppingLimit: limit, shoppingUsed: limit > 0 ? Double(e.shoppingSpent) / Double(limit) : 0, takeawayLeft: e.takeawayLeft, daysLeft: e.daysLeft, updated: Date(), period: e.periodName)
    }
    /// Saves the latest figures for the widget and asks iOS to redraw it.
    static func publish(_ e: Engine) {
        WidgetSnapshot(e).save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Starts, refreshes and ends the Lock Screen / Dynamic Island view.
@MainActor enum LiveMoney {
    static func content(_ e: Engine) -> ActivityContent<MoneyActivityAttributes.ContentState> {
        let next = e.upcoming(days: 14).first { !$0.income }
        var state = MoneyActivityAttributes.ContentState(spare: e.shoppingAvailable, weekLeft: e.weekLeft, weekUsed: e.weekUsed, daysLeft: e.daysLeft, nextName: next?.name, nextAmount: next?.amount, nextDate: next?.date, period: e.periodName)
        state.takeawayLeft = e.takeawayLeft
        if let due = e.pendingPay { state.payKind = due.kind == .wage ? "Payday" : "Allowance day" }
        else if let pay = recentPay(e) {
            let kept = e.afterCut(pay.amount, cut: pay.cut ?? 0)
            state.payKind = pay.kind == .wage ? "Pay received" : "Allowance received"
            state.payAmount = pay.amount; state.paySavings = kept.savings; state.payInvest = kept.investment; state.paySpend = pay.amount - kept.savings - kept.investment
        }
        return ActivityContent(state: state, staleDate: e.state.periodEnd)
    }
    static func recentPay(_ e: Engine) -> Entry? {
        e.state.entries.filter { $0.kind.income && $0.hadEffects && $0.date >= Date().addingTimeInterval(-86_400) }.max { $0.date < $1.date }
    }
    /// On payday (or the day pay is entered) the Lock Screen shows the pay prompt or split even if the everyday view is off.
    static func wanted(_ e: Engine) -> Bool { e.state.settings.liveActivity == true || e.pendingPay != nil || recentPay(e) != nil }
    /// iOS only lets an app start a Live Activity while it is open.
    static func start(_ e: Engine) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, Activity<MoneyActivityAttributes>.activities.allSatisfy({ $0.activityState != .active }) else { return }
        _ = try? Activity.request(attributes: MoneyActivityAttributes(), content: content(e))
    }
    static func update(_ e: Engine) async {
        for activity in Activity<MoneyActivityAttributes>.activities where activity.activityState == .active {
            var latest = content(e).state
            latest.transfers = activity.content.state.transfers; latest.step = activity.content.state.step // Keep transfers in progress.
            latest.status = activity.content.state.status
            await activity.update(ActivityContent(state: latest, staleDate: latest.status == nil ? e.state.periodEnd : statusExpiry))
        }
    }
    /// "Transfer now": shows the transfers on the Dynamic Island and Lock Screen and copies the first amount.
    /// Returns false when Live Activities are turned off for MoneyPilot.
    @discardableResult static func showTransfers(_ steps: [MoneyActivityAttributes.TransferStep], _ e: Engine) async -> Bool {
        guard let first = steps.first, ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        UIPasteboard.general.string = pasteAmount(first.amount)
        var state = content(e).state
        state.transfers = steps; state.step = 0
        let latest = ActivityContent(state: state, staleDate: nil)
        if let running = Activity<MoneyActivityAttributes>.activities.first(where: { $0.activityState == .active }) { await running.update(latest) }
        else { _ = try? Activity.request(attributes: MoneyActivityAttributes(), content: latest) }
        return true
    }
    /// A sign-in status goes stale after this, so it can never stay stuck if iOS pauses MoneyPilot mid-way.
    static var statusExpiry: Date { Date().addingTimeInterval(120) }
    /// Shows what the PocketSmith sign-in is doing. nil goes back to the usual view, or ends it if nothing else needs it.
    static func status(_ text: String?, _ e: Engine) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let running = Activity<MoneyActivityAttributes>.activities.first { $0.activityState == .active }
        var state = content(e).state
        state.transfers = running?.content.state.transfers; state.step = running?.content.state.step
        state.status = text
        let latest = ActivityContent(state: state, staleDate: text == nil ? e.state.periodEnd : statusExpiry)
        if let running {
            if text == nil && state.transfers == nil && !wanted(e) { await running.end(nil, dismissalPolicy: .immediate) } else { await running.update(latest) }
        } else if text != nil { _ = try? Activity.request(attributes: MoneyActivityAttributes(), content: latest) }
    }
    static func end() async {
        for activity in Activity<MoneyActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
