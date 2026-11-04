import Foundation

/// One explained observation for the Guide, ranked by how much it matters.
struct Insight: Identifiable {
    enum Level: Int, Comparable {
        case critical, warning, opportunity, good, info
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    enum Action { case redirect(String, Money), organise, subscriptions, afterpay, review, fixPlan }
    var id: String
    var level: Level
    var icon: String
    var title: String
    var detail: String
    var action: Action? = nil
    var actionTitle: String? = nil
    var notify = false // Worth a notification the first time it appears.
}
struct MoneyScore {
    struct Part: Identifiable { var name: String; var points: Int; var max: Int; var note: String; var id: String { name } }
    var total: Int
    var parts: [Part]
    var label: String { total >= 80 ? "Strong" : total >= 60 ? "Good" : total >= 40 ? "Needs attention" : "At risk" }
}
struct MonthReview {
    var month: Date
    var spent: Money
    var previousSpent: Money
    var income: Money
    var changes: [(category: Category, change: Money)]
    var kept: Double? { income > 0 ? Double(income - spent) / Double(income) : nil }
}

extension Engine {
    private var now: Date { Date() }
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }
    /// Start of the budget period `back` periods before the current one.
    func periodStart(back: Int) -> Date {
        let c = Calendar.current
        switch state.period {
        case .month: return c.date(byAdding: .month, value: -back, to: state.periodStart)!
        case .fortnight: return c.date(byAdding: .day, value: -14 * back, to: state.periodStart)!
        case .week: return c.date(byAdding: .day, value: -7 * back, to: state.periodStart)!
        }
    }
    /// Cash that left for spending: purchases net of refunds, plus Afterpay instalments paid.
    func cashSpending(from: Date, to: Date) -> Money {
        state.entries.filter { $0.date >= from && $0.date < to }.reduce(Money(0)) { total, e in
            switch e.kind {
            case .expense, .repayment: return total + e.amount
            case .refund: return total - e.amount
            default: return total
            }
        }
    }
    /// Wages, allowance and confirmed other income received between two dates.
    func incomeReceived(from: Date, to: Date) -> Money {
        state.entries.filter { $0.date >= from && $0.date < to && ($0.kind.income || ($0.kind == .otherIncome && $0.needsReview != true)) }.reduce(Money(0)) { $0 + $1.amount }
    }
    /// Share of income kept (not spent) over recent months, once there are at least four weeks of history.
    var keptRate: (rate: Double, days: Int)? {
        guard let first = state.entries.map(\.date).min() else { return nil }
        let days = min(90, Calendar.current.dateComponents([.day], from: first, to: now).day ?? 0)
        guard days >= 28 else { return nil }
        let from = Calendar.current.startOfDay(for: daysAgo(days)) // Whole days, so the first day's transactions count.
        let income = incomeReceived(from: from, to: now.addingTimeInterval(1))
        guard income > 0 else { return nil }
        return (Double(income - cashSpending(from: from, to: now.addingTimeInterval(1))) / Double(income), days)
    }
    /// Average monthly spend on essentials (fuel, groceries, bills, subscriptions) over the last 90 days.
    var monthlyEssentials: Money {
        let from = daysAgo(90), to = now.addingTimeInterval(1)
        let total = [Category.fuel, .groceries, .bills, .subscriptions].reduce(Money(0)) { sum, c in let u = used(c, from: from, to: to); return sum + u.spent + u.afterpay }
        return total * 30 / 90
    }
    /// The lowest point of the cash forecast, and how far it is above or below your protected savings.
    var forecastLow: (date: Date, balance: Money, free: Money)? {
        // Without expected pay the forecast has no income in it, so it would always look like running out.
        guard state.settings.expectedWages > 0 || state.settings.expectedAllowance > 0 else { return nil }
        return forecast().map { (date: $0.date, balance: $0.balance, free: $0.balance - protected) }.min { $0.free < $1.free }
    }
    /// The last expected date of a regular payment, if it fell 1 to 3 days ago.
    private func recentlyDue(_ date: Date) -> Date? {
        let days = Calendar.current.dateComponents([.day], from: date, to: Calendar.current.startOfDay(for: now)).day ?? 0
        return (1...3).contains(days) ? date : nil
    }

    /// Wages or allowance due today or in the last two days that hasn't been recorded yet, for the payday button.
    var pendingPay: (kind: EntryKind, expected: Money, due: Date)? {
        let c = Calendar.current, today = c.startOfDay(for: now)
        func missing(_ due: Date, _ expected: Money) -> Bool {
            let days = c.dateComponents([.day], from: due, to: today).day ?? -1
            return (0...2).contains(days) && !state.entries.contains { $0.kind.inflow && $0.kind != .refund && $0.kind != .fromStake && $0.date >= c.date(byAdding: .day, value: -1, to: due)! && $0.amount * 2 >= expected }
        }
        if state.settings.expectedWages > 0 {
            let payday = state.paydayCycle(onOrAfter: c.date(byAdding: .day, value: -13, to: today)!) // Latest payday up to today
            if state.paysWages(on: payday), missing(payday, state.settings.expectedWages) { return (.wage, state.settings.expectedWages, payday) }
        }
        if state.settings.expectedAllowance > 0 {
            let month = c.dateInterval(of: .month, for: today)!.start
            let due = c.date(byAdding: .day, value: min(state.settings.allowanceDay, c.range(of: .day, in: .month, for: month)!.count) - 1, to: month)!
            if missing(due, state.settings.expectedAllowance) { return (.allowance, state.settings.expectedAllowance, due) }
        }
        return nil
    }
    // MARK: Insights
    var insights: [Insight] {
        var out: [Insight] = []
        let c = Calendar.current, today = c.startOfDay(for: now), period = periodName

        // Cash runway
        if let low = forecastLow, low.free < 0 {
            if low.balance < 0 {
                out.append(Insight(id: "runway-\(state.periodStart.timeIntervalSince1970)", level: .critical, icon: "exclamationmark.octagon.fill", title: "Cash could run out around \(low.date.formatted(.dateTime.day().month(.abbreviated)))",
                                   detail: "If you spend your full budgets, your bank balance drops to \(money(low.balance)) before more pay arrives. Lower a budget or hold off on big purchases until then.", notify: true))
            } else {
                out.append(Insight(id: "runway-\(state.periodStart.timeIntervalSince1970)", level: .warning, icon: "arrow.down.right.circle.fill", title: "Full budgets would dip into savings",
                                   detail: "Around \(low.date.formatted(.dateTime.day().month(.abbreviated))), spending every budget in full would use \(money(-low.free)) of your protected savings, emergency or investing money.", notify: true))
            }
        }
        if unallocated < 0 {
            out.append(Insight(id: "overallocated", level: .critical, icon: "exclamationmark.triangle.fill", title: "Your plan is bigger than your cash",
                               detail: "Budgets and reservations exceed the cash you have by \(money(-unallocated)). Expected pay isn't cash yet.", action: .fixPlan, actionTitle: "Fix it for me"))
        }
        // Spare money: the shopping limit and goal money.
        if let limit = state.settings.shoppingLimit, limit > 0 {
            let spent = shoppingSpent, key = shoppingLimitStart.timeIntervalSince1970
            if spent > limit {
                out.append(Insight(id: "shop-over-\(key)", level: .critical, icon: "bag.fill", title: "Shopping account is \(money(spent - limit)) over its limit",
                                   detail: "\(money(spent)) spent of \(money(limit)) this \(shoppingLimitName).", notify: true))
            } else if spent * 100 >= limit * 80 {
                out.append(Insight(id: "shop-80-\(key)", level: .warning, icon: "bag.fill", title: "Shopping: \(money(limit - spent)) left this \(shoppingLimitName)",
                                   detail: "\(money(spent)) of your \(money(limit)) shopping limit used.", notify: true))
            }
        }
        if goalMoneyUsed > 0 {
            out.append(Insight(id: "goal-money-\(state.periodStart.timeIntervalSince1970)", level: .warning, icon: "target", title: "You've spent \(money(goalMoneyUsed)) of goal savings",
                               detail: "Your Shopping account holds less than your goals have set aside. Top it up, or release some from a goal.", notify: true))
        }

        // Budget pace
        for line in lines where line.limit > 0 {
            if line.used > line.limit {
                out.append(Insight(id: "over-\(state.periodStart.timeIntervalSince1970)-\(line.id)", level: .warning, icon: line.category.icon, title: "\(line.category.rawValue) is \(money(line.used - line.limit)) over budget",
                                   detail: "\(money(line.used)) of \(money(line.limit)) this \(period). Anything more comes out of other budgets' cash."))
            } else if !Engine.fixed.contains(line.category), elapsedFraction >= 0.2, elapsedFraction < 1 {
                // MK3.6: only real spending is projected forward; Afterpay instalments are fixed amounts, not a pace.
                let projected = Money(Double(line.spent) / elapsedFraction) + line.committed + line.goalReserved
                if projected > line.limit + max(line.limit / 10, 1_000) {
                    out.append(Insight(id: "pace-\(state.periodStart.timeIntervalSince1970)-\(line.id)", level: .warning, icon: "hare.fill", title: "\(line.category.rawValue): on pace for \(money(projected)) this \(period)",
                                       detail: "Your budget is \(money(line.limit)). Keep to \(money(max(0, line.remaining) / Money(daysLeft))) a day for the next \(daysLeft) day\(daysLeft == 1 ? "" : "s") to finish on budget.", notify: true))
                }
            }
        }

        // Compared with your usual (last complete period vs the three before it)
        if let first = state.entries.map(\.date).min(), first <= periodStart(back: 4) {
            let last = Dictionary(uniqueKeysWithValues: spending(state.period, start: periodStart(back: 1)).map { ($0.category, $0.amount) })
            var usual: [Category: Money] = [:]
            for k in 2...4 { for item in spending(state.period, start: periodStart(back: k)) { usual[item.category, default: 0] += item.amount } }
            let changes: [(Category, Money, Money)] = Category.allCases.map { cat -> (Category, Money, Money) in
                let recent: Money = last[cat] ?? 0, typical: Money = (usual[cat] ?? 0) / 3
                return (cat, recent, typical)
            }.filter { $0.2 >= 2_000 }
            if let up = changes.filter({ $0.1 - $0.2 >= 2_000 && ($0.1 - $0.2) * 10 >= $0.2 * 3 }).max(by: { $0.1 - $0.2 < $1.1 - $1.2 }) {
                let extra = up.1 - up.2
                out.append(Insight(id: "usual-up-\(up.0.rawValue)", level: .opportunity, icon: "chart.line.uptrend.xyaxis", title: "\(up.0.rawValue) was \(money(extra)) above your usual",
                                   detail: "Last \(period): \(money(up.1)), against a usual \(money(up.2)). Back at your usual level, that's \(money(extra * state.period.perYear)) a year you could keep."))
            }
            if let down = changes.filter({ $0.2 - $0.1 >= 2_000 && ($0.2 - $0.1) * 10 >= $0.2 * 2 }).max(by: { $0.2 - $0.1 < $1.2 - $1.1 }) {
                out.append(Insight(id: "usual-down-\(down.0.rawValue)", level: .good, icon: "hand.thumbsup.fill", title: "\(down.0.rawValue) down \(money(down.2 - down.1)) on usual",
                                   detail: "Last \(period): \(money(down.1)), against a usual \(money(down.2)). Keep it up and that's \(money((down.2 - down.1) * state.period.perYear)) a year."))
            }
        }

        // Savings rate
        if let kept = keptRate {
            let target = Double(state.settings.futurePercent) / 100
            let pct = Int((kept.rate * 100).rounded())
            if kept.rate + 0.1 < target {
                out.append(Insight(id: "kept", level: .opportunity, icon: "percent", title: "You've kept \(max(0, pct))% of your income",
                                   detail: "Over the last \(kept.days) days, against your \(state.settings.futurePercent)% savings and investing target. The categories above your usual are the quickest place to close the gap."))
            } else {
                out.append(Insight(id: "kept", level: .good, icon: "percent", title: "You've kept \(pct)% of your income",
                                   detail: "Over the last \(kept.days) days, on track with your \(state.settings.futurePercent)% target."))
            }
        }

        // Emergency fund
        let essentials = monthlyEssentials
        if state.emergency < state.settings.emergencyMinimum {
            let short = state.settings.emergencyMinimum - state.emergency, move = min(short, max(0, unallocated))
            out.append(Insight(id: "emergency", level: .warning, icon: "cross.case.fill", title: "Emergency fund is \(money(short)) below your minimum",
                               detail: essentials > 0 ? "It covers \(String(format: "%.1f", Double(state.emergency) / Double(essentials))) months of essentials (fuel, groceries, bills and subscriptions)." : "Top it up before adding to shopping or goals.",
                               action: move > 0 ? .redirect("emergency", move) : nil, actionTitle: move > 0 ? "Move \(money(move)) to emergency" : nil))
        } else if essentials > 0 {
            let months = Double(state.emergency) / Double(essentials)
            out.append(Insight(id: "emergency-months", level: months >= 3 ? .good : .info, icon: "cross.case.fill", title: "Emergency fund covers \(String(format: "%.1f", months)) months",
                               detail: months >= 3 ? "Of your essentials, at about \(money(essentials)) a month. Three months is a common goal, and you're there." : "Of your essentials, at about \(money(essentials)) a month. Three months would be \(money(essentials * 3 - state.emergency)) more."))
        }

        // Afterpay load
        let owed = afterpayDebt
        if owed > 0 {
            let unpaid = state.plans.flatMap(\.installments).filter { $0.paidOn == nil }
            let soon = unpaid.filter { $0.due < c.date(byAdding: .day, value: 14, to: today)! }.reduce(Money(0)) { $0 + $1.amount }
            let monthly = expectedIncome(per: .month).total
            let heavy = state.plans.filter { $0.outstanding > 0 }.count >= 3 || (monthly > 0 && owed * 4 > monthly)
            let share = monthly > 0 ? " That's \(Int(Double(owed) / Double(monthly) * 100))% of a month's income." : ""
            out.append(Insight(id: "afterpay", level: heavy ? .warning : .info, icon: "calendar.badge.clock", title: "\(money(owed)) still owed to Afterpay",
                               detail: "\(money(soon)) is due in the next two weeks, and everything is paid off by \((unpaid.map(\.due).max() ?? today).formatted(.dateTime.day().month(.abbreviated))).\(share)\(heavy ? " Holding off on new plans until then keeps more of each pay free." : "")",
                               action: .afterpay, actionTitle: "Open Afterpay"))
        }

        // Subscriptions
        for sub in state.subs {
            let charges = state.entries.filter { $0.kind == .expense && $0.name.lowercased().contains(sub.keyword.lowercased()) }.sorted { $0.date < $1.date }
            guard charges.count >= 2, let latest = charges.last else { continue }
            let previous = charges[charges.count - 2].amount, rise = latest.amount - previous
            if rise >= 50 && rise * 100 >= previous * 3 {
                out.append(Insight(id: "price-\(sub.id)-\(latest.amount)", level: .warning, icon: "arrow.up.circle.fill", title: "\(sub.name) went up \(money(rise))",
                                   detail: "From \(money(previous)) to \(money(latest.amount)), about \(money(sub.cycle.monthly(rise) * 12)) more a year. Worth checking it's still worth it.", action: .subscriptions, actionTitle: "Subscriptions", notify: true))
            }
        }
        let found = detectedSubscriptions()
        if !found.isEmpty {
            out.append(Insight(id: "found-subs", level: .opportunity, icon: "repeat.circle.fill", title: "\(found.count) charge\(found.count == 1 ? " looks" : "s look") like subscriptions",
                               detail: "\(found.prefix(3).map(\.name).joined(separator: ", ")). Tracking them shows their real yearly cost and the next charge date.", action: .subscriptions, actionTitle: "Review"))
        }

        // Possible double charges in the last 30 days
        let recent = state.entries.filter { $0.kind == .expense && $0.amount >= 2_000 && $0.date >= daysAgo(30) }.sorted { $0.date < $1.date }
        var flagged = 0
        for (i, a) in recent.enumerated() where flagged < 3 {
            if let b = recent[(i + 1)...].first(where: { $0.amount == a.amount && Engine.groupKey($0.name) == Engine.groupKey(a.name) && $0.date.timeIntervalSince(a.date) <= 36 * 3_600 }) {
                flagged += 1
                out.append(Insight(id: "dup-\(a.id)-\(b.id)", level: .warning, icon: "doc.on.doc.fill", title: "Possible double charge: \(a.name)",
                                   detail: "\(money(a.amount)) twice, on \(a.date.formatted(.dateTime.day().month(.abbreviated))) and \(b.date.formatted(.dateTime.day().month(.abbreviated))). If you only bought once, ask the merchant or your bank for a refund.", notify: true))
            }
        }

        // Unusually large purchases this week
        for e in state.entries where e.kind == .expense && e.amount >= 10_000 && e.date >= daysAgo(7) {
            let peers = state.entries.filter { $0.kind == .expense && $0.category == e.category && $0.id != e.id && $0.date >= daysAgo(90) }.map(\.amount).sorted()
            guard peers.count >= 5 else { continue }
            let median = peers[peers.count / 2]
            if median > 0 && e.amount >= median * 3 {
                out.append(Insight(id: "big-\(e.id)", level: .info, icon: "exclamationmark.circle", title: "Bigger than usual: \(e.name)",
                                   detail: "\(money(e.amount)), about \(e.amount / median)× your typical \(e.category.rawValue.lowercased()) purchase of \(money(median))."))
            }
        }

        // Pay that hasn't arrived
        if state.pocketsmith != nil {
            if state.settings.expectedWages > 0 {
                let payday = state.paydayCycle(onOrAfter: c.date(byAdding: .day, value: -13, to: today)!)
                if state.paysWages(on: payday), let due = recentlyDue(payday), !state.entries.contains(where: { $0.kind.inflow && $0.kind != .refund && $0.kind != .fromStake && $0.date >= c.date(byAdding: .day, value: -1, to: due)! && $0.amount * 2 >= state.settings.expectedWages }) {
                    out.append(Insight(id: "pay-\(due.timeIntervalSince1970)", level: .warning, icon: "clock.badge.exclamationmark", title: "Wages due \(due.formatted(.dateTime.weekday(.wide))) haven't arrived",
                                       detail: "Expected about \(money(state.settings.expectedWages)). Banks can take a day; if it's still missing, check with your employer. Budgets only count pay once it lands.", notify: true))
                }
            }
            if state.settings.expectedAllowance > 0 {
                let thisMonth = c.dateInterval(of: .month, for: today)!.start
                let due = c.date(byAdding: .day, value: min(state.settings.allowanceDay, c.range(of: .day, in: .month, for: thisMonth)!.count) - 1, to: thisMonth)!
                if let due = recentlyDue(due), !state.entries.contains(where: { $0.kind.inflow && $0.kind != .refund && $0.kind != .fromStake && $0.date >= c.date(byAdding: .day, value: -1, to: due)! && $0.amount * 2 >= state.settings.expectedAllowance }) {
                    out.append(Insight(id: "allowance-\(due.timeIntervalSince1970)", level: .info, icon: "clock", title: "Allowance due \(due.formatted(.dateTime.weekday(.wide))) hasn't shown up",
                                       detail: "Expected about \(money(state.settings.expectedAllowance)). It may just be late, or arriving as a deposit to review in Activity."))
                }
            }
        }

        // Time off coming up or under way (MK3.6)
        if state.settings.expectedWages > 0, let off = state.timeOff(before: c.date(byAdding: .day, value: 42, to: today)!).first {
            let range = "\(off.from.formatted(.dateTime.day().month(.abbreviated)))–\(off.to.formatted(.dateTime.day().month(.abbreviated)))"
            let next = nextPayDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            out.append(Insight(id: "time-off-\(off.id)", level: .info, icon: "beach.umbrella", title: c.startOfDay(for: off.from) <= today ? "Not working until \(off.to.formatted(.dateTime.day().month(.abbreviated)))" : "No wages \(range)",
                               detail: "Allowance only until your next pay on \(next). Everyday is planned to last until then, and a pay before it gives up savings and investing first if it has to."))
        }
        // Savings account conditions
        if let plan = moneyPlan, let rule = plan.savingsRule, let account = state.accounts.first(where: { $0.effectiveRole == .savings }) {
            let now = accountBalance(account.id), gap = rule.required - now
            let end = c.date(byAdding: .day, value: -1, to: rule.monthEnd)!.formatted(.dateTime.day().month(.abbreviated))
            if gap > 0 {
                out.append(Insight(id: "savings-growth-\(rule.monthEnd.timeIntervalSince1970)", level: .warning, icon: "banknote", title: "Savings needs \(money(gap)) more by \(end)",
                                   detail: "It started the month at \(money(rule.monthStart)) and must finish at least \(money(rule.required - rule.monthStart)) higher, at \(money(rule.required)). Move money in, not out.", notify: true))
            } else {
                out.append(Insight(id: "savings-growth", level: .good, icon: "banknote", title: "Savings is on track this month",
                                   detail: "\(money(now)), at least \(money(rule.required - rule.monthStart)) above where it started the month."))
            }
            if !rule.canWithdraw {
                out.append(Insight(id: "savings-withdrawal-\(rule.monthEnd.timeIntervalSince1970)", level: .warning, icon: "hand.raised.fill", title: "No more Savings withdrawals this month",
                                   detail: "You've made \(rule.withdrawals) of the \(rule.allowed) allowed. MoneyPilot won't suggest taking from Savings again until \(rule.monthEnd.formatted(.dateTime.day().month(.abbreviated))).", notify: true))
            }
        }
        // Housekeeping
        let toSort = organiseProposals.count
        if toSort > 0 {
            out.append(Insight(id: "organise", level: .opportunity, icon: "wand.and.stars", title: "\(toSort) transaction\(toSort == 1 ? "" : "s") can be sorted",
                               detail: "They're in Other or look like stock deposits. Sorting them makes budgets and charts accurate.", action: .organise, actionTitle: "Sort now"))
        }
        let reviews = state.entries.filter { $0.needsReview == true }.count
        if reviews > 0 {
            out.append(Insight(id: "reviews", level: .info, icon: "questionmark.circle", title: "\(reviews) bank transaction\(reviews == 1 ? " needs" : "s need") a quick review",
                               detail: "Find them at the top of Activity. Until then, deposits aren't counted as income."))
        }

        // Investing and spare cash
        if state.investmentReserve >= 10_000 {
            out.append(Insight(id: "invest-ready", level: .opportunity, icon: "chart.line.uptrend.xyaxis", title: "\(money(state.investmentReserve)) is ready to invest",
                               detail: "Set aside by your income rule. Deposit it to Stake when you're ready; MoneyPilot records it as a stock deposit automatically."))
        }
        if state.stakeCashUSD >= 5_000 {
            out.append(Insight(id: "stake-cash", level: .info, icon: "dollarsign.circle", title: "\(money(state.stakeCashUSD, currency: "USD")) uninvested at Stake",
                               detail: "Cash at Stake doesn't grow until it's invested."))
        }
        if unallocated > 0 {
            let (target, label) = state.emergency < state.settings.emergencyMinimum ? ("emergency", "emergency fund") : ("savings", "savings")
            out.append(Insight(id: "surplus", level: .opportunity, icon: "sparkles", title: "Give \(money(unallocated)) a job",
                               detail: "Cash left after savings, debts, goals and every budget. Parking it in \(label) keeps it from being spent by accident.", action: .redirect(target, unallocated), actionTitle: "Move to \(label)"))
        }

        // Goals
        for goal in state.goals where goal.reserved < goal.target && goal.weekly > 0 {
            let left = goal.target - goal.reserved
            if shoppingAvailable >= left {
                out.append(Insight(id: "goal-ready-\(goal.id)", level: .good, icon: "gift.fill", title: "You could fund \(goal.name) today",
                                   detail: "\(money(left)) to go, and \(money(shoppingAvailable)) is free for shopping. Reserve it from the goal card in Budgets."))
            } else {
                let weeks = Int((Double(left) / Double(goal.weekly)).rounded(.up))
                out.append(Insight(id: "goal-\(goal.id)", level: .info, icon: "gift", title: "\(goal.name): \(money(left)) to go",
                                   detail: "About \(weeks) week\(weeks == 1 ? "" : "s") at \(money(goal.weekly)) a week, around \(c.date(byAdding: .day, value: weeks * 7, to: today)!.formatted(.dateTime.day().month(.abbreviated)))."))
            }
        }
        return out.sorted { $0.level < $1.level }
    }

    // MARK: Score
    var score: MoneyScore {
        var parts: [MoneyScore.Part] = []
        let limit = lines.reduce(Money(0)) { $0 + $1.limit }
        if limit > 0 {
            let over = lines.reduce(Money(0)) { $0 + max(0, $1.used - $1.limit) }
            parts.append(.init(name: "Budgets", points: Int((25 * max(0, 1 - Double(over) / Double(limit) * 2)).rounded()), max: 25, note: over == 0 ? "Everything within budget" : "\(money(over)) over across categories"))
        }
        if let kept = keptRate {
            let target = max(0.01, Double(state.settings.futurePercent) / 100)
            parts.append(.init(name: "Saving", points: Int((25 * min(1, max(0, kept.rate / target))).rounded()), max: 25, note: "Kept \(Int((kept.rate * 100).rounded()))% of income (target \(state.settings.futurePercent)%)"))
        }
        if state.settings.emergencyMinimum > 0 {
            parts.append(.init(name: "Emergency fund", points: Int((20 * min(1, Double(state.emergency) / Double(state.settings.emergencyMinimum))).rounded()), max: 20, note: "\(money(state.emergency)) of \(money(state.settings.emergencyMinimum))"))
        }
        let monthly = expectedIncome(per: .month).total, owed = afterpayDebt
        parts.append(.init(name: "Afterpay", points: owed == 0 ? 15 : monthly > 0 ? Int((15 * max(0, 1 - Double(owed) * 2 / Double(monthly))).rounded()) : 7, max: 15, note: owed == 0 ? "Nothing owed" : "\(money(owed)) owed"))
        if let low = forecastLow {
            parts.append(.init(name: "Cash runway", points: low.free >= 0 ? 15 : low.balance >= 0 ? 7 : 0, max: 15, note: low.free >= 0 ? "Budgets fit your cash for 5 weeks" : low.balance >= 0 ? "Full budgets would touch savings" : "Cash could run out"))
        }
        let got = parts.reduce(0) { $0 + $1.points }, possible = parts.reduce(0) { $0 + $1.max }
        return MoneyScore(total: possible > 0 ? Int((Double(got) / Double(possible) * 100).rounded()) : 0, parts: parts)
    }

    // MARK: Month in review
    /// The last complete calendar month compared with the one before, once that month has activity.
    var lastMonthReview: MonthReview? {
        let start = chartStart(.month, back: 1), end = BudgetPeriod.month.end(from: start)
        guard state.entries.contains(where: { $0.date >= start && $0.date < end }) else { return nil }
        let now = Dictionary(uniqueKeysWithValues: spending(.month, start: start).map { ($0.category, $0.amount) })
        let before = Dictionary(uniqueKeysWithValues: spending(.month, start: chartStart(.month, back: 2)).map { ($0.category, $0.amount) })
        let changes = Category.allCases.map { (category: $0, change: (now[$0] ?? 0) - (before[$0] ?? 0)) }.filter { abs($0.change) >= 2_000 }.sorted { abs($0.change) > abs($1.change) }
        return MonthReview(month: start, spent: now.values.reduce(0, +), previousSpent: before.values.reduce(0, +), income: incomeReceived(from: start, to: end), changes: Array(changes.prefix(3)))
    }
    /// Average monthly spend in a category over the last three complete months.
    func usualMonthly(_ category: Category) -> Money {
        (1...3).reduce(Money(0)) { sum, k in sum + (spending(.month, start: chartStart(.month, back: k)).first { $0.category == category }?.amount ?? 0) } / 3
    }
}

// MARK: Moving money between accounts
struct MoneyPlan {
    struct Transfer: Identifiable { var from: UUID; var to: UUID?; var amount: Money; var id: String { "\(from)-\(to?.uuidString ?? "stake")-\(amount)" } // to == nil means Stake
        func skipKey(_ nextPay: Date) -> String { "\(from)-\(to?.uuidString ?? "stake")@\(Int(nextPay.timeIntervalSince1970))" }
    }
    struct Need: Identifiable { var name: String; var amount: Money; var id: String { name } }
    var nextPay: Date
    var needs: [Need]               // What Everyday must cover until next pay
    var targets: [UUID: Money]      // What each account should hold
    var transfers: [Transfer]
    var shortfall: Money            // Essentials your free cash can't cover
    var savingsRule: SavingsRule?   // Your savings account's monthly conditions, when you have one
}
struct SavingsRule {
    var monthStart: Money, required: Money, monthEnd: Date
    var withdrawals: Int, allowed: Int
    var canWithdraw: Bool { withdrawals < allowed }
}
extension Engine {
    /// Everyday pays all your spending (every budget, subscriptions and Afterpay) until next pay; Emergency and Savings hold
    /// their reservations; money set aside for investing goes to Stake; the spare-money (Shopping) account keeps whatever is left.
    var moneyPlan: MoneyPlan? {
        let c = Calendar.current, today = c.startOfDay(for: Date())
        var byRole: [AccountRole: Account] = [:]
        for a in state.accounts { if let r = a.effectiveRole, byRole[r] == nil { byRole[r] = a } }
        guard let everyday = byRole[.everyday] ?? byRole[.shopping] else { return nil }
        let shopping = byRole[.shopping] ?? everyday
        let emergency = byRole[.emergency] ?? byRole[.savings] ?? shopping
        let savings = byRole[.savings] ?? byRole[.emergency] ?? shopping
        let planned = Set([everyday.id, shopping.id, emergency.id, savings.id])

        let nextPay = nextPayDate
        let needs = self.needs(until: nextPay)
        let need = max(0, needs.reduce(Money(0)) { $0 + $1.amount })

        // Savings account conditions: end the month at least $160 above its start, with at most one withdrawal.
        var rule: SavingsRule?
        if let account = byRole[.savings] {
            let month = c.dateInterval(of: .month, for: today)!
            let used = state.entries.filter { $0.accountID == account.id && $0.date >= month.start && !$0.kind.inflow && $0.kind != .refund }.count
            let start = accountBalance(account.id, before: month.start)
            rule = SavingsRule(monthStart: start, required: start + (state.settings.savingsGrowth ?? 16_000), monthEnd: month.end, withdrawals: used, allowed: state.settings.savingsWithdrawals ?? 1)
        }
        let savingsTarget = max(state.savings, rule?.required ?? 0)
        let total = planned.reduce(Money(0)) { $0 + accountBalance($1) }
        let stake = state.investmentReserve
        let free = total - state.emergency - savingsTarget - stake
        var targets: [UUID: Money] = Dictionary(uniqueKeysWithValues: planned.map { ($0, 0) })
        targets[emergency.id, default: 0] += state.emergency
        targets[savings.id, default: 0] += savingsTarget
        let everydayTarget = max(0, min(need, free))
        targets[everyday.id, default: 0] += everydayTarget
        targets[shopping.id, default: 0] += max(0, free - everydayTarget)

        // Fill accounts in priority order, taking from Shopping first and Savings last. Amounts are whole dollars; under $5 is ignored.
        var surplus = [shopping, everyday, emergency, savings].map(\.id).reduce(into: [(UUID, Money)]()) { list, id in
            if !list.contains(where: { $0.0 == id }) { list.append((id, max(0, accountBalance(id) - targets[id]!))) }
        }
        var deficits: [(UUID?, Money)] = []
        for id in [everyday, emergency, savings].map(\.id) where !deficits.contains(where: { $0.0 == id }) { deficits.append((id, max(0, targets[id]! - accountBalance(id)))) }
        deficits.append((nil, stake))
        if !deficits.contains(where: { $0.0 == shopping.id }) { deficits.append((shopping.id, max(0, targets[shopping.id]! - accountBalance(shopping.id)))) }
        var transfers: [MoneyPlan.Transfer] = []
        var savingsWithdrawalsLeft = rule.map { max(0, $0.allowed - $0.withdrawals) } ?? Int.max
        for (to, wanted) in deficits {
            var left = wanted
            for i in surplus.indices where left > 0 && surplus[i].0 != to && surplus[i].1 > 0 {
                if surplus[i].0 == byRole[.savings]?.id {
                    // Investing money never goes through Savings, and each withdrawal from it is limited.
                    if to == nil || savingsWithdrawalsLeft == 0 { continue }
                    savingsWithdrawalsLeft -= 1
                }
                let move = min(left, surplus[i].1)
                surplus[i].1 -= move; left -= move
                let rounded = (move + 50) / 100 * 100
                if rounded >= 500 {
                    if let k = transfers.firstIndex(where: { $0.from == surplus[i].0 && $0.to == to }) { transfers[k].amount += rounded }
                    else { transfers.append(.init(from: surplus[i].0, to: to, amount: rounded)) }
                }
            }
        }
        let skipped = Set(state.skippedTransfers ?? [])
        transfers.removeAll { skipped.contains($0.skipKey(nextPay)) }
        return MoneyPlan(nextPay: nextPay, needs: needs, targets: targets, transfers: transfers, shortfall: max(0, need - max(0, free)), savingsRule: rule)
    }
}

// MARK: Spare money and goals
struct SpareMoney {
    var account: Account
    var income: Money, future: Money, spending: Money, bills: Money // One fortnightly pay, and where it goes
    var perPay: Money          // What should land in spare money each pay
    var comfortable: Money     // Spare money you can spend now without touching goals or anything else
    var reserved: Money        // Already set aside for goals
}
extension Engine {
    var spareMoney: SpareMoney? {
        guard let account = state.accounts.first(where: { $0.effectiveRole == .shopping }) else { return nil }
        let income = expectedIncome(per: .fortnight).total
        let split = allocation(income)
        let spending = Category.budgeted.filter { $0 != .subscriptions }.reduce(Money(0)) { $0 + baseLimit($1) * state.period.perYear / 26 } * 105 / 100
        let today = Calendar.current.startOfDay(for: Date()), fortnight = Calendar.current.date(byAdding: .day, value: 14, to: today)!
        let subs = state.subs.isEmpty ? baseLimit(.subscriptions) * state.period.perYear / 26 : monthlySubscriptions * 12 / 26
        let afterpay = state.plans.filter { !Category.budgeted.contains($0.category) }.flatMap(\.installments) // Others sit inside their budget.
            .filter { $0.paidOn == nil && $0.due < fortnight }.reduce(Money(0)) { $0 + $1.amount }
        // After the planned transfers, spare money holds what's left over; goal money in it isn't for spending.
        let holds = moneyPlan?.targets[account.id] ?? accountBalance(account.id)
        return SpareMoney(account: account, income: income, future: split.savings + split.investment, spending: spending, bills: subs + afterpay,
                          perPay: max(0, income - split.savings - split.investment - spending - subs - afterpay),
                          comfortable: max(0, min(holds - goalReserves, shoppingLimitLeft ?? .max)), reserved: goalReserves)
    }
    // MARK: Payday (MK3)
    struct PaySplit { var savings: Money; var investment: Money; var cut: Money; var spare: Money }
    /// How a pay is split. Your budgets come first: if the 30% you keep plus your free cash can't cover everything until
    /// your next pay (what's left of each budget, subscriptions and Afterpay due; MK3.6: across time off too, less the
    /// allowance due meanwhile), savings and investing give up just the shortfall, 60/40. `spare` is what's left of the
    /// pay for spare money once those are covered with the 5% cushion. `alreadyIn`: the pay is already in your balances.
    func paySplit(_ amount: Money, alreadyIn: Bool = true) -> PaySplit {
        let full = allocation(amount), future = full.savings + full.investment, end = nextPayDate
        let bare = max(0, needs(until: end, cushion: false, buffer: false).reduce(Money(0)) { $0 + $1.amount })
        let held = max(0, needs(until: end, buffer: false).reduce(Money(0)) { $0 + $1.amount })
        let cash = bankCash - protected - goalReserves + (alreadyIn ? 0 : amount) - future
        let cut = min(future, max(0, bare - cash))
        let kept = afterCut(amount, cut: cut)
        return PaySplit(savings: kept.savings, investment: kept.investment, cut: cut, spare: max(0, full.spending + cut - held))
    }
    /// MK3.6: what Everyday has to cover from today until `end`, one line each:
    /// - each budget: only what's left of it this period (money already spent isn't asked for again), then full budgets
    ///   for any days after the period ends, less the Afterpay instalments that will sit inside them;
    /// - subscriptions due (every charge, so a long stretch counts monthly ones more than once);
    /// - unpaid Afterpay due, listed once here (a budget's own instalments are already out of what's left of it);
    /// - the buffer kept from last period; and, when time off falls before then, the allowance due meanwhile (negative).
    /// `cushion` adds 5% to budgets in case one runs over.
    func needs(until end: Date, cushion: Bool = true, buffer: Bool = true) -> [MoneyPlan.Need] {
        let c = Calendar.current, today = c.startOfDay(for: Date())
        func days(_ a: Date, _ b: Date) -> Int64 { Int64(max(0, c.dateComponents([.day], from: a, to: b).day ?? 0)) }
        let live = state.periodStart <= today && state.periodEnd > today
        let after = live ? state.periodEnd : today
        func full(_ cat: Category, _ d: Int64) -> Money {
            switch state.period {
            case .week: return baseLimit(cat) * d / 7
            case .fortnight: return baseLimit(cat) * d / 14
            case .month: return baseLimit(cat) * 12 * d / 365
            }
        }
        func share(_ cat: Category) -> Money {
            var total: Money = 0
            if live { total += max(0, line(cat).remaining) * days(today, min(end, state.periodEnd)) / max(1, days(today, state.periodEnd)) }
            if end > after {
                let inside = state.plans.filter { $0.category == cat }.flatMap(\.installments).filter { $0.due >= after && $0.due < end }.reduce(Money(0)) { $0 + $1.amount }
                total += max(0, full(cat, days(after, end)) - inside)
            }
            return total
        }
        var list = Category.budgeted.filter { $0 != .subscriptions }.map { MoneyPlan.Need(name: $0.rawValue, amount: share($0) * (cushion ? 105 : 100) / 100) }
        if buffer { list.append(.init(name: "Buffer from last period", amount: state.everydayBuffer ?? 0)) }
        var subs: Money = 0
        if state.subs.isEmpty { subs = share(.subscriptions) } else {
            for sub in state.subs {
                var d = nextCharge(sub)
                while d < end { if d >= today { subs += sub.amount }; d = sub.cycle.next(after: d) }
            }
        }
        list.append(.init(name: "Subscriptions", amount: subs))
        list.append(.init(name: "Afterpay", amount: state.plans.flatMap(\.installments).filter { $0.paidOn == nil && $0.due < end }.reduce(Money(0)) { $0 + $1.amount }))
        // Allowance only counts towards a stretch that includes time off; a normal fortnight is planned from pay alone.
        if state.settings.expectedAllowance > 0, !state.timeOff(before: end).isEmpty {
            let month = c.dateInterval(of: .month, for: today)!.start
            let dates = (0..<24).compactMap { k -> Date? in
                let m = c.date(byAdding: .month, value: k, to: month)!
                let d = c.date(byAdding: .day, value: min(state.settings.allowanceDay, c.range(of: .day, in: .month, for: m)!.count) - 1, to: m)!
                return d > today && d < end ? d : nil
            }
            list.append(.init(name: "Allowance before then", amount: -state.settings.expectedAllowance * Money(dates.count)))
        }
        return list.filter { $0.amount != 0 }
    }
    /// Savings and investing for a pay once `cut` is taken off, keeping their split.
    func afterCut(_ amount: Money, cut: Money) -> (savings: Money, investment: Money) {
        let full = allocation(amount), future = full.savings + full.investment
        let fromSavings = future > 0 ? Money((Double(min(cut, future)) * Double(full.savings) / Double(future)).rounded()) : 0
        return (full.savings - fromSavings, full.investment - (min(cut, future) - fromSavings))
    }
    // MARK: Shopping limit (MK3)
    var shoppingAccount: Account? { state.accounts.first { $0.effectiveRole == .shopping } }
    var shoppingLimitStart: Date { state.settings.shoppingMonthly == true ? state.start(of: .month) : state.start(of: .fortnight) }
    var shoppingLimitName: String { state.settings.shoppingMonthly == true ? "month" : "fortnight" }
    /// Purchases paid from the Shopping account since the limit period began, less refunds to it.
    var shoppingSpent: Money {
        guard let id = shoppingAccount?.id else { return 0 }
        return state.entries.filter { $0.accountID == id && $0.date >= shoppingLimitStart }.reduce(Money(0)) {
            $1.kind == .expense ? $0 + $1.amount : $1.kind == .refund ? $0 - $1.amount : $0
        }
    }
    var shoppingLimitLeft: Money? { state.settings.shoppingLimit.flatMap { $0 > 0 ? max(0, $0 - shoppingSpent) : nil } }
    /// Goal money already spent: the Shopping account holds less than your goals have set aside.
    var goalMoneyUsed: Money { shoppingAccount.map { max(0, goalReserves - accountBalance($0.id)) } ?? 0 }
    // MARK: Fix it for me (MK3)
    struct FixPlan {
        var balances: [(pocketsmithID: String, account: Account, theirs: Money)] = []
        var savingsTo: Money? = nil   // Savings set aside is more than your Savings account holds: match it
        var emergencyTo: Money? = nil // Same for the emergency fund
        var releaseGoals: Money = 0
        var cuts: [(category: Category, amount: Money)] = []
        var stillShort: Money = 0
    }
    /// When budgets and reservations add up to more than your cash: correct balances, release goal money, then lower
    /// budgets evenly (takeaway, entertainment and other first; groceries and fuel last). Bills, subscriptions, savings,
    /// emergency and investing are never touched.
    var fixPlan: FixPlan? {
        guard unallocated < 0 else { return nil }
        var plan = FixPlan(), over = -unallocated
        plan.balances = drifted
        over -= plan.balances.reduce(Money(0)) { $0 + matched($1) - accountBalance($1.account.id) }
        // Savings set aside only ever grows with each pay; if your Savings account didn't, the difference isn't real money.
        let savingsAccount = state.accounts.first { $0.effectiveRole == .savings }, emergencyAccount = state.accounts.first { $0.effectiveRole == .emergency }
        if let a = savingsAccount, a.id != emergencyAccount?.id {
            let held = max(0, accountBalance(a.id)); if state.savings > held { plan.savingsTo = held; over -= state.savings - held }
        }
        if let a = emergencyAccount, a.id != savingsAccount?.id {
            let held = max(0, accountBalance(a.id)); if state.emergency > held { plan.emergencyTo = held; over -= state.emergency - held }
        }
        plan.releaseGoals = max(0, min(over, goalReserves)); over -= plan.releaseGoals
        for tier in [[Category.takeaway, .entertainment, .other], [.groceries, .fuel]] where over > 0 {
            let room = tier.map { ($0, max(0, line($0).remaining)) }.filter { $0.1 > 0 }
            let total = room.reduce(Money(0)) { $0 + $1.1 }
            guard total > 0 else { continue }
            let take = min(over, total)
            var left = take
            for (k, (category, r)) in room.enumerated() {
                let amount = k == room.count - 1 ? left : min(left, Money((Double(take) * Double(r) / Double(total)).rounded()))
                if amount > 0 { plan.cuts.append((category, amount)); left -= amount }
            }
            over -= take
        }
        plan.stillShort = max(0, over)
        return plan
    }
}
