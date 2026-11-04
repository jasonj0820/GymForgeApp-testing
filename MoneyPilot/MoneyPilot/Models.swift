import Foundation

enum AppError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

typealias Money = Int64 // Integer minor units; no floating-point budget arithmetic.
func money(_ value: Money, currency: String = "AUD") -> String {
    (Double(value) / 100).formatted(.currency(code: currency))
}
func cents(_ text: String) -> Money? {
    let clean = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard clean.range(of: #"^\d+(\.\d{0,2})?$"#, options: .regularExpression) != nil,
          let value = Decimal(string: clean), value >= 0,
          value <= 1_000_000_000 else { return nil }
    var raw = value * 100; var rounded = Decimal()
    NSDecimalRound(&rounded, &raw, 0, .plain)
    return NSDecimalNumber(decimal: rounded).int64Value
}
func percentage(_ amount: Money, _ percent: Int) -> Money { amount * Int64(percent) / 100 }

enum Category: String, Codable, CaseIterable, Identifiable {
    case fuel = "Fuel", groceries = "Groceries", takeaway = "Takeaway", shopping = "Shopping", subscriptions = "Subscriptions", bills = "Bills", entertainment = "Entertainment", other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self { case .fuel: return "fuelpump.fill"; case .groceries: return "basket.fill"; case .takeaway: return "fork.knife"; case .shopping: return "bag.fill"; case .subscriptions: return "repeat.circle.fill"; case .bills: return "doc.text.fill"; case .entertainment: return "ticket.fill"; case .other: return "square.grid.2x2.fill" }
    }
    var essential: Bool { [.fuel, .groceries, .bills].contains(self) }
}
extension Category {
    /// MK3: shopping is spare money (your Shopping account), not a budget.
    static let budgeted = allCases.filter { $0 != .shopping }
}
enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case expense = "Expense", wage = "Wages", allowance = "Parents’ allowance", otherIncome = "Other income", refund = "Refund", transfer = "Internal transfer", investment = "To Stake", repayment = "Afterpay repayment"
    case fromStake = "From Stake" // MK2.21: money withdrawn from Stake back to your bank
    var id: String { rawValue }
    var income: Bool { self == .wage || self == .allowance }
    var inflow: Bool { income || self == .refund || self == .otherIncome || self == .fromStake }
}
struct Account: Identifiable, Codable {
    var id = UUID(); var name: String; var openingBalance: Money
    var role: AccountRole? = nil // What this account is for; guessed from its name until you choose
    var effectiveRole: AccountRole? { role ?? AccountRole.guess(name) }
}
enum AccountRole: String, Codable, CaseIterable, Identifiable {
    case everyday = "Everyday", shopping = "Shopping", emergency = "Emergency", savings = "Savings"
    var id: String { rawValue }
    /// Shown in the app. The stored value stays "Shopping" so saved choices still load.
    var title: String { self == .shopping ? "Spare money" : rawValue }
    static func guess(_ name: String) -> AccountRole? {
        let n = name.lowercased()
        if n.contains("emergenc") { return .emergency }
        if n.contains("saving") || n.contains("saver") { return .savings }
        if n.contains("shop") { return .shopping }
        if n.contains("everyday") || n.contains("day to day") || n.contains("transaction") { return .everyday }
        return nil
    }
}
struct Entry: Identifiable, Codable {
    var id = UUID(); var date: Date; var name: String; var amount: Money
    var kind: EntryKind; var category: Category; var accountID: UUID; var destinationID: UUID?
    var externalID: Int? = nil   // PocketSmith transaction ID for imported entries
    var needsReview: Bool? = nil // Imported entry whose type must be confirmed
    var pairedID: Int? = nil     // PocketSmith ID of the other half of an imported transfer
    var historical: Bool? = nil  // Imported as past activity; never applied the income rule
    var installmentID: UUID? = nil // The Afterpay instalment this repayment paid
    var usd: Money? = nil          // MK2.21: USD credited at Stake (To Stake) or taken out of it (From Stake)
    var costAUD: Money? = nil      // MK2.22, From Stake: what the withdrawn money originally cost you in AUD
    var cut: Money? = nil          // MK3, pay: how much savings + investing gave up so the fortnight's budgets were covered
    var usdEstimated: Bool? = nil  // MK3.1: `usd` was estimated from the exchange rate, not typed from Stake
    var hadEffects: Bool { needsReview != true && historical != true }
}
enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case week, fortnight, month
    var id: String { rawValue }
    var title: String { switch self { case .week: return "Weekly"; case .fortnight: return "Fortnightly · from payday"; case .month: return "Monthly · from the 1st" } }
    var perYear: Int64 { switch self { case .week: return 52; case .fortnight: return 26; case .month: return 12 } }
    func end(from start: Date) -> Date {
        switch self {
        case .week: return Calendar.current.date(byAdding: .day, value: 7, to: start)!
        case .fortnight: return Calendar.current.date(byAdding: .day, value: 14, to: start)!
        case .month: return Calendar.current.date(byAdding: .month, value: 1, to: start)!
        }
    }
}
enum Cycle: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly", fortnightly = "Fortnightly", monthly = "Monthly", yearly = "Yearly"
    var id: String { rawValue }
    func next(after date: Date) -> Date {
        let c = Calendar.current
        switch self {
        case .weekly: return c.date(byAdding: .day, value: 7, to: date)!
        case .fortnightly: return c.date(byAdding: .day, value: 14, to: date)!
        case .monthly: return c.date(byAdding: .month, value: 1, to: date)!
        case .yearly: return c.date(byAdding: .year, value: 1, to: date)!
        }
    }
    func monthly(_ amount: Money) -> Money {
        switch self { case .weekly: return amount * 52 / 12; case .fortnightly: return amount * 26 / 12; case .monthly: return amount; case .yearly: return amount / 12 }
    }
}
struct Subscription: Identifiable, Codable {
    var id = UUID(); var name: String; var keyword: String; var amount: Money; var cycle: Cycle; var start: Date
}
struct Budget: Identifiable, Codable {
    var category: Category; var limit: Money; var locked = false
    var id: String { category.rawValue }
}
struct Installment: Identifiable, Codable {
    var id = UUID(); var due: Date; var amount: Money; var paidOn: Date?
}
struct AfterpayPlan: Identifiable, Codable {
    var id = UUID(); var name: String; var category: Category = .shopping; var purchased: Date
    var installments: [Installment]
    var total: Money { installments.reduce(0) { $0 + $1.amount } }
    var outstanding: Money { installments.filter { $0.paidOn == nil }.reduce(0) { $0 + $1.amount } }
}
struct Goal: Identifiable, Codable {
    var id = UUID(); var name: String; var target: Money; var reserved: Money = 0; var weekly: Money
}
struct Holding: Identifiable, Codable {
    var id = UUID(); var symbol: String; var shares: Double; var costUSD: Money; var priceUSD: Money; var updated: Date
    // MK2.20, optional for older files. costUSD is what the shares still held cost, brokerage included.
    var costAUD: Money? = nil      // The same cost at the exchange rate on the day of each buy
    var realisedUSD: Money? = nil  // Profit or loss from shares already sold, after brokerage
    var realisedAUD: Money? = nil
    var soldCostUSD: Money? = nil  // What the sold shares had cost, for the total return %
    var valueUSD: Money { Money((shares * Double(priceUSD)).rounded()) }
    var averagePriceUSD: Money { shares > 0 ? Money((Double(costUSD) / shares).rounded()) : 0 }
    var unrealisedUSD: Money { valueUSD - costUSD }
    var profitUSD: Money { unrealisedUSD + (realisedUSD ?? 0) }
    /// Total return on everything ever put in, sold or not.
    var profitPercent: Double { let invested = costUSD + (soldCostUSD ?? 0); return invested > 0 ? Double(profitUSD) / Double(invested) : 0 }
    func paidAUD(_ rate: Double) -> Money { costAUD ?? Money((Double(costUSD) * rate).rounded()) }
    func profitAUD(_ rate: Double) -> Money { Money((Double(valueUSD) * rate).rounded()) - paidAUD(rate) + (realisedAUD ?? 0) }
}
/// Stake's US share brokerage per trade, the starting value for every buy and sell.
let stakeBrokerageUSD: Money = 300
struct HistoryPoint: Identifiable, Codable {
    var id = UUID(); var date: Date; var assets: Money; var netWorth: Money; var emergency: Money; var investments: Money
}
struct Settings: Codable {
    var futurePercent = 70; var savingsSplit = 60
    var expectedWages: Money = 0; var expectedAllowance: Money = 0
    var nextPayday = Date(); var allowanceDay = 1
    var emergencyMinimum: Money = 500_000
    var audPerUSD = 1.50
    var notifications = false
    var warningPercent = 75
    var rolloverToShopping = true
    var liveActivity: Bool? = nil // Optional so older saved files still load.
    var savingsGrowth: Money? = nil      // Savings must end each month this much above where it started (default $160)
    var savingsWithdrawals: Int? = nil   // Withdrawals allowed from Savings each month (default 1)
    var fxFeePercent: Double? = nil      // MK2.21: Stake's FX fee each way, default 0.55%
    var shoppingLimit: Money? = nil      // MK3: optional cap on spending from the Shopping account
    var shoppingMonthly: Bool? = nil     // MK3: the cap is per month (true) or per fortnight
    var appLock: Bool? = nil // Require Face ID or the passcode to open MoneyPilot
    var autoOrganise: Bool? = nil // nil means on: file new and "Other" transactions automatically after each sync
    var monthlyBudget: Bool? = nil // MK1.7 setting; replaced by budgetPeriod
    var budgetPeriod: String? = nil // "week", "fortnight" or "month"
    var nextAllowance: Date? = nil  // Next expected allowance; its day of the month repeats
    var timeOff: [TimeOff]? = nil   // MK3.6: dates you're not working: no wages, allowance only
}
/// MK3.6: a stretch with no wages (paydays inside it pay nothing); allowance still arrives.
struct TimeOff: Identifiable, Codable { var id = UUID(); var from: Date; var to: Date }
struct FinanceState: Codable {
    var version = 1; var demo = false
    var accounts: [Account] = (1...4).map { Account(name: "Account \($0)", openingBalance: 0) }
    var entries: [Entry] = []; var plans: [AfterpayPlan] = []; var goals: [Goal] = []; var holdings: [Holding] = []
    var budgets = Category.allCases.map { Budget(category: $0, limit: 0) }
    var savings: Money = 0; var emergency: Money = 0; var investmentReserve: Money = 0
    var stakeCashUSD: Money = 0; var shoppingCarry: Money = 0
    var skippedTransfers: [String]? = nil // MK3.5: suggested transfers you chose not to make (or made differently) until next payday
    var stakeCorrectionsUSD: Money? = nil // MK3.1: corrections you made so Stake cash matches the Stake app
    var everydayBuffer: Money? = nil     // MK3: 30% of last period's unspent budget, kept in Everyday
    var stakeBefore: StakeHistory? = nil // MK2.21: money moved to and from Stake before MoneyPilot tracked it
    var periodStart = Calendar.current.startOfDay(for: Date())
    var settings = Settings(); var rules: [String: Category] = [:]
    var history: [HistoryPoint] = []; var notified: [String] = []
    var pocketsmith: PocketSmithLink? = nil // Optional so MK1.1 saved files still load.
    var subscriptions: [Subscription]? = nil
    var groupRules: [String: Category]? = nil // Merchant group (see Engine.groupKey) → category, for similar transactions
    /// Files the chosen transactions from Other into the engine's suggested categories. Returns how many moved.
    @discardableResult mutating func organise(_ ids: Set<UUID>? = nil) -> Int {
        let proposals = Engine(state: self).organiseProposals.filter { ids?.contains($0.id) ?? true }
        for p in proposals {
            guard let i = entries.firstIndex(where: { $0.id == p.id }) else { continue }
            if p.stockDeposit { fileAsStockDeposit(i) } else { entries[i].category = p.category }
        }
        return proposals.count
    }
    /// Turns a bank payment to a broker into a stock deposit. It comes out of money set aside for investing; for Stake,
    /// the USD credited is estimated at today's exchange rate (adjust Stake cash in Settings if it differs).
    /// `usd` is the USD Stake actually credited, when known.
    mutating func fileAsStockDeposit(_ i: Int, usd: Money? = nil) {
        let wasCounted = entries[i].hadEffects
        entries[i].kind = .investment; entries[i].category = .other; entries[i].needsReview = nil
        if let usd, usd > 0 { entries[i].usd = usd }
        else if !Engine.isOtherBroker(entries[i].name) { entries[i].usd = usdBought(aud: entries[i].amount); entries[i].usdEstimated = true }
        guard wasCounted else { return } // History never set money aside, so there is nothing to move.
        investmentReserve = max(0, investmentReserve - entries[i].amount)
        stakeCashUSD += entries[i].usd ?? 0
    }
    /// Turns a stock deposit back into ordinary spending, returning its amount to the money set aside for investing.
    mutating func fileAsSpending(_ i: Int) {
        guard entries[i].kind == .investment else { return }
        if entries[i].hadEffects { reverseEffects(.investment, amount: entries[i].amount, usd: entries[i].usd ?? 0) }
        entries[i].kind = .expense; entries[i].category = .other; entries[i].usd = nil; entries[i].usdEstimated = nil
    }
    /// Records transfers you've just made in your banking app. The bank's own copies are linked to these when they sync.
    /// MK3.5: you made `made` (amounts may differ from the plan). Any suggestion not made exactly as shown stays hidden until next payday.
    mutating func confirmTransfers(planned: [MoneyPlan.Transfer], made: [MoneyPlan.Transfer], nextPay: Date) {
        recordTransfers(made.filter { $0.amount > 0 })
        let changed = planned.filter { p in !made.contains { $0.from == p.from && $0.to == p.to && $0.amount == p.amount } }
        skippedTransfers = (skippedTransfers ?? []).filter { $0.hasSuffix("@\(Int(nextPay.timeIntervalSince1970))") } + changed.map { $0.skipKey(nextPay) }
    }
    mutating func recordTransfers(_ transfers: [MoneyPlan.Transfer]) {
        for t in transfers {
            if let to = t.to {
                entries.append(Entry(date: Date(), name: "Transfer", amount: t.amount, kind: .transfer, category: .other, accountID: t.from, destinationID: to))
            } else {
                entries.append(Entry(date: Date(), name: "Stake deposit", amount: t.amount, kind: .expense, category: .other, accountID: t.from))
                fileAsStockDeposit(entries.count - 1)
            }
        }
    }
    /// On payday, sets aside each goal's per-pay amount (two weeks' worth) from spare cash, in goal order, until each is funded.
    /// Payday: each goal takes its amount, oldest goal first, but together never more than half of this pay's spare money.
    mutating func fundGoals(spare: Money) {
        var cap = spare / 2
        for i in goals.indices where cap > 0 && goals[i].reserved < goals[i].target && goals[i].weekly > 0 {
            let amount = min(goals[i].weekly * 2, goals[i].target - goals[i].reserved, cap)
            goals[i].reserved += amount; cap -= amount
        }
    }
    /// Files every past and future transaction from the same merchant group under `category`.
    mutating func categoriseSimilar(to name: String, as category: Category) {
        let key = Engine.groupKey(name)
        guard !key.isEmpty else { return }
        var rules = groupRules ?? [:]; rules[key] = category; groupRules = rules
        let e = Engine(state: self)
        for i in entries.indices where (entries[i].kind == .expense || entries[i].kind == .refund) && entries[i].needsReview != true && Engine.inGroup(entries[i].name, key) {
            // A more specific rule (exact name or longer group) still wins for its own transactions.
            if let c = e.ruleCategory(entries[i].name) { entries[i].category = c }
        }
    }
    var subs: [Subscription] { get { subscriptions ?? [] } set { subscriptions = newValue } }
    /// Fills in what older saved files lack, such as budgets for categories added later.
    mutating func migrate() {
        for c in Category.allCases where !budgets.contains(where: { $0.category == c }) { budgets.append(Budget(category: c, limit: 0)) }
    }
    var period: BudgetPeriod { settings.budgetPeriod.flatMap(BudgetPeriod.init) ?? (settings.monthlyBudget == true ? .month : .week) }
    var monthly: Bool { period == .month }
    var periodEnd: Date { period.end(from: periodStart) }
    /// The start of the period of kind `p` that contains today: the 1st, the latest payday, or today for weekly budgets.
    func start(of p: BudgetPeriod) -> Date {
        let c = Calendar.current, today = c.startOfDay(for: Date())
        switch p {
        case .month: return c.dateInterval(of: .month, for: today)!.start
        case .week: return today
        case .fortnight:
            var payday = c.startOfDay(for: settings.nextPayday)
            while payday > today { payday = c.date(byAdding: .day, value: -14, to: payday)! }
            while c.date(byAdding: .day, value: 14, to: payday)! <= today { payday = c.date(byAdding: .day, value: 14, to: payday)! }
            return payday
        }
    }
    /// Where the next budget period starts once the current one ends. MK3.6: weekly budgets roll forward in whole weeks
    /// from the old start (they used to never roll on their own), so the week keeps starting on the same day.
    var newPeriodStart: Date {
        guard period == .week else { return start(of: period) }
        let c = Calendar.current, today = c.startOfDay(for: Date())
        var start = c.startOfDay(for: periodStart)
        while c.date(byAdding: .day, value: 7, to: start)! <= today { start = c.date(byAdding: .day, value: 7, to: start)! }
        return start
    }
    /// Switches the budget period, converting every limit through its yearly amount so the plan stays the same size.
    mutating func switchPeriod(to new: BudgetPeriod) {
        let old = period
        guard old != new else { return }
        for i in budgets.indices { budgets[i].limit = budgets[i].limit * old.perYear / new.perYear }
        settings.budgetPeriod = new.rawValue; settings.monthlyBudget = nil
        periodStart = start(of: new)
        notified = []
    }
    /// The next expected allowance on or after today: the date you set, then the same day each month.
    var nextAllowance: Date {
        let c = Calendar.current, today = c.startOfDay(for: Date())
        if let set = settings.nextAllowance.map({ c.startOfDay(for: $0) }), set >= today { return set }
        func payDay(in monthOf: Date) -> Date {
            let month = c.dateInterval(of: .month, for: monthOf)!.start
            return c.date(byAdding: .day, value: min(settings.allowanceDay, c.range(of: .day, in: .month, for: month)!.count) - 1, to: month)!
        }
        let thisMonth = payDay(in: today)
        return thisMonth >= today ? thisMonth : payDay(in: c.date(byAdding: .month, value: 1, to: today)!)
    }
    static func sample() -> FinanceState {
        var s = FinanceState(); s.demo = true
        s.accounts = [Account(name: "Everyday", openingBalance: 185_000), Account(name: "Salary", openingBalance: 60_000), Account(name: "Savings", openingBalance: 820_000), Account(name: "Emergency", openingBalance: 450_000)]
        s.savings = 600_000; s.emergency = 450_000; s.investmentReserve = 80_000; s.shoppingCarry = 20_000
        s.settings.expectedWages = 140_000; s.settings.expectedAllowance = 160_000
        s.settings.nextPayday = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        s.budgets = [.init(category: .fuel, limit: 6_000), .init(category: .groceries, limit: 12_000), .init(category: .takeaway, limit: 4_000), .init(category: .shopping, limit: 8_000), .init(category: .subscriptions, limit: 1_500), .init(category: .bills, limit: 3_000), .init(category: .other, limit: 2_000)]
        s.entries = [Entry(date: Date(), name: "Woolworths", amount: 7_450, kind: .expense, category: .groceries, accountID: s.accounts[0].id), Entry(date: Date(), name: "Lunch", amount: 3_200, kind: .expense, category: .takeaway, accountID: s.accounts[0].id)]
        s.plans = [AfterpayPlan(name: "Sneakers", purchased: Date(), installments: (0..<4).map { Installment(due: Calendar.current.date(byAdding: .day, value: $0 * 14 + 2, to: Date())!, amount: 3_000) })]
        s.goals = [Goal(name: "New watch", target: 50_000, reserved: 10_000, weekly: 5_500)]
        s.holdings = [Holding(symbol: "DEMO ETF", shares: 6, costUSD: 240_000, priceUSD: 45_000, updated: Date())]
        s.stakeCashUSD = 15_000
        return s
    }
}
extension FinanceState {
    // Side effects of a received or paid entry: income reservations, or moving the investment reserve to Stake.
    /// Undoes applyEffects for a removed or changed entry. Stake USD is left alone; it is reconciled in Settings.
    mutating func reverseEffects(_ kind: EntryKind, amount: Money, usd: Money = 0, cut: Money = 0) {
        if kind == .fromStake { stakeCashUSD += usd }
        if kind.income {
            let kept = Engine(state: self).afterCut(amount, cut: cut)
            savings = max(0, savings - kept.savings); investmentReserve = max(0, investmentReserve - kept.investment)
        }
        if kind == .investment { investmentReserve += amount; stakeCashUSD = max(0, stakeCashUSD - usd) } // Its USD leaves Stake cash too.
    }
    mutating func deleteEntry(_ id: UUID) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        guard entries[i].kind != .repayment else { throw AppError.invalid("Afterpay payments belong to their payment schedule and cannot be deleted here.") }
        if entries[i].hadEffects { reverseEffects(entries[i].kind, amount: entries[i].amount, usd: entries[i].usd ?? 0, cut: entries[i].cut ?? 0) }
        entries.remove(at: i)
    }
    mutating func editEntry(_ id: UUID, name: String, amount: Money, date: Date, category: Category) throws {
        guard amount > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalid("Enter a description and an amount greater than zero.") }
        guard date <= Date() else { throw AppError.invalid("The date cannot be in the future.") }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[i]
        guard old.kind != .repayment || old.amount == amount else { throw AppError.invalid("Afterpay payment amounts come from their schedule.") }
        if old.hadEffects && old.amount != amount {
            if old.kind == .investment {
                investmentReserve = max(0, investmentReserve + old.amount - amount)
                if let was = old.usd, old.amount > 0 { // Scale its USD with the new amount.
                    let now = Money((Double(was) * Double(amount) / Double(old.amount)).rounded())
                    stakeCashUSD = max(0, stakeCashUSD + now - was); entries[i].usd = now
                }
            }
            else {
                reverseEffects(old.kind, amount: old.amount, usd: old.usd ?? 0, cut: old.cut ?? 0)
                entries[i].amount = amount // Pay is worked out with the new amount already in the balance.
                let usd = try applyEffects(old.kind, amount: amount, entry: i, newPay: false) // A From Stake amount change re-estimates its USD.
                if old.kind == .fromStake {
                    entries[i].usd = usd
                    if let cost = old.costAUD, let was = old.usd, was > 0 { entries[i].costAUD = Money((Double(cost) * Double(usd) / Double(was)).rounded()) }
                }
            }
        }
        entries[i].name = name; entries[i].amount = amount; entries[i].date = date; entries[i].category = category
    }
    // MARK: Afterpay corrections
    /// The repayment entry for an instalment: linked directly, or for older entries matched by plan name and amount.
    func repaymentIndex(plan: AfterpayPlan, installment: Installment) -> Int? {
        let label = "Afterpay · \(plan.name)"
        return entries.indices.filter { i in
            entries[i].kind == .repayment && (entries[i].installmentID == installment.id || (entries[i].installmentID == nil && entries[i].name == label && entries[i].amount == installment.amount))
        }.min { abs(entries[$0].date.timeIntervalSince(installment.paidOn ?? Date())) < abs(entries[$1].date.timeIntervalSince(installment.paidOn ?? Date())) }
    }
    /// Removes a recorded repayment. A bank payment stays as money that left the account and goes to review.
    private mutating func dropRepayment(_ i: Int) {
        if entries[i].externalID != nil {
            entries[i].kind = .expense; entries[i].needsReview = true; entries[i].installmentID = nil
        } else { entries.remove(at: i) }
    }
    /// Marks a paid instalment as unpaid again, reversing the payment that was logged.
    mutating func undoPayment(planID: UUID, installmentID: UUID) {
        guard let p = plans.firstIndex(where: { $0.id == planID }), let k = plans[p].installments.firstIndex(where: { $0.id == installmentID }), plans[p].installments[k].paidOn != nil else { return }
        if let i = repaymentIndex(plan: plans[p], installment: plans[p].installments[k]) { dropRepayment(i) }
        plans[p].installments[k].paidOn = nil
    }
    /// Saves edited names, dates and amounts. Paid instalments keep their amount, because it matches money already paid.
    mutating func updatePlan(_ plan: AfterpayPlan) throws {
        guard let p = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        guard !plan.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalid("Enter a name for this purchase.") }
        guard !plan.installments.isEmpty, plan.installments.allSatisfy({ $0.amount > 0 }) else { throw AppError.invalid("Every instalment needs an amount greater than zero.") }
        for old in plans[p].installments where old.paidOn != nil {
            guard let new = plan.installments.first(where: { $0.id == old.id }), new.paidOn != nil, new.amount == old.amount else {
                throw AppError.invalid("Undo a payment before changing the amount of, or removing, that instalment.")
            }
        }
        var updated = plan
        updated.installments.sort { $0.due < $1.due }
        // Keep linked repayments readable after a rename.
        for i in entries.indices where entries[i].kind == .repayment && entries[i].category == plans[p].category && entries[i].name == "Afterpay · \(plans[p].name)" {
            entries[i].name = "Afterpay · \(updated.name)"; entries[i].category = updated.category
        }
        plans[p] = updated
    }
    /// Removes a plan entered by mistake, with the payments recorded against it.
    mutating func deletePlan(_ id: UUID) {
        guard let p = plans.firstIndex(where: { $0.id == id }) else { return }
        for part in plans[p].installments where part.paidOn != nil {
            if let i = repaymentIndex(plan: plans[p], installment: part) { dropRepayment(i) }
        }
        plans.remove(at: p)
    }
    /// Returns the USD that moved at Stake (0 for other kinds); without `usd` it's estimated at today's rate less the FX fee.
    /// For pay, `entry` is its index (already in the balance): the savings rule gives way if the fortnight's budgets
    /// wouldn't be covered, the cut is stored on it, and on a new wage the goals are funded from this pay's spare money.
    @discardableResult mutating func applyEffects(_ kind: EntryKind, amount: Money, usd: Money = 0, entry i: Int? = nil, newPay: Bool = true) throws -> Money {
        if kind.income {
            let split = Engine(state: self).paySplit(amount)
            savings += split.savings; investmentReserve += split.investment
            if let i {
                entries[i].cut = split.cut > 0 ? split.cut : nil
                if newPay && kind == .wage { fundGoals(spare: split.spare) }
            }
        }
        if kind == .investment {
            if usd <= 0, let i { entries[i].usdEstimated = true }
            let usd = usd > 0 ? usd : usdBought(aud: amount)
            investmentReserve = max(0, investmentReserve - amount)
            stakeCashUSD += usd
            return usd
        }
        if kind == .fromStake {
            if usd <= 0, let i { entries[i].usdEstimated = true }
            let usd = usd > 0 ? usd : usdSold(aud: amount)
            stakeCashUSD = max(0, stakeCashUSD - usd)
            return usd
        }
        return 0
    }
}

// MARK: Buying and selling shares (MK2.20)
extension FinanceState {
    /// Adds shares to the holding for `symbol` (averaging the cost) or starts one. Brokerage is part of the cost.
    /// `fromCash` pays for it out of the uninvested USD cash at Stake.
    mutating func buy(_ symbol: String, shares: Double, priceUSD: Money, brokerageUSD: Money, fromCash: Bool) throws {
        guard shares > 0, priceUSD > 0, brokerageUSD >= 0 else { throw AppError.invalid("Enter the shares, price and brokerage.") }
        let cost = Money((shares * Double(priceUSD)).rounded()) + brokerageUSD
        if fromCash {
            guard cost <= stakeCashUSD else { throw AppError.invalid("There is not enough recorded USD cash at Stake.") }
            stakeCashUSD -= cost
        }
        let rate = settings.audPerUSD, costAUD = Money((Double(cost) * rate).rounded())
        if let i = holdings.firstIndex(where: { $0.symbol == symbol }) {
            holdings[i].costAUD = holdings[i].paidAUD(rate) + costAUD
            holdings[i].shares += shares; holdings[i].costUSD += cost
            holdings[i].priceUSD = priceUSD; holdings[i].updated = Date()
        } else {
            holdings.append(Holding(symbol: symbol, shares: shares, costUSD: cost, priceUSD: priceUSD, updated: Date(), costAUD: costAUD))
        }
    }
    /// Sells part or all of a holding. The money, less brokerage, stays at Stake as cash.
    /// Profit is measured against the average cost of the shares sold.
    mutating func sell(_ id: UUID, shares: Double, priceUSD: Money, brokerageUSD: Money) throws {
        guard let i = holdings.firstIndex(where: { $0.id == id }) else { return }
        let held = holdings[i].shares
        guard shares > 0, priceUSD > 0, brokerageUSD >= 0 else { throw AppError.invalid("Enter the shares, price and brokerage.") }
        guard shares <= held + 0.000_001 else { throw AppError.invalid("You only hold \(held.formatted()) shares.") }
        let all = shares >= held - 0.000_001, fraction = all ? 1 : shares / held, rate = settings.audPerUSD
        let costPart = all ? holdings[i].costUSD : Money((Double(holdings[i].costUSD) * fraction).rounded())
        let costPartAUD = all ? holdings[i].paidAUD(rate) : Money((Double(holdings[i].paidAUD(rate)) * fraction).rounded())
        let proceeds = Money((shares * Double(priceUSD)).rounded()) - brokerageUSD
        stakeCashUSD += proceeds
        holdings[i].costAUD = holdings[i].paidAUD(rate) - costPartAUD
        holdings[i].realisedUSD = (holdings[i].realisedUSD ?? 0) + proceeds - costPart
        holdings[i].realisedAUD = (holdings[i].realisedAUD ?? 0) + Money((Double(proceeds) * rate).rounded()) - costPartAUD
        holdings[i].soldCostUSD = (holdings[i].soldCostUSD ?? 0) + costPart
        holdings[i].shares = all ? 0 : held - shares
        holdings[i].costUSD -= costPart
        holdings[i].priceUSD = priceUSD; holdings[i].updated = Date()
    }
}

// MARK: Money to and from Stake (MK2.21)
/// Totals from Stake's own statements for transfers made before MoneyPilot tracked them.
struct StakeHistory: Codable { var sentAUD: Money = 0; var usdIn: Money = 0; var backAUD: Money = 0; var usdOut: Money = 0 }
extension FinanceState {
    /// Stake's FX fee as a fraction, charged on AUD → USD deposits and USD → AUD withdrawals.
    var fxFee: Double { (settings.fxFeePercent ?? 0.55) / 100 }
    /// USD Stake credits for an AUD deposit, after the FX fee.
    func usdBought(aud: Money) -> Money { settings.audPerUSD > 0 ? Money((Double(aud) * (1 - fxFee) / settings.audPerUSD).rounded()) : 0 }
    /// USD taken out of Stake for the AUD that reached your bank, after the FX fee.
    func usdSold(aud: Money) -> Money { settings.audPerUSD > 0 && fxFee < 1 ? Money((Double(aud) / (1 - fxFee) / settings.audPerUSD).rounded()) : 0 }
    /// What a withdrawal of `usd` originally cost you, from Stake cash alone (share prices never affect it):
    /// the AUD still invested, less what the shares you hold cost, shared across the cash. Call before the withdrawal is applied.
    func withdrawalCost(usd: Money) -> Money {
        let rate = settings.audPerUSD
        let cashCost = max(0, Engine(state: self).stakeMoney.basisAUD - holdings.reduce(0) { $0 + $1.paidAUD(rate) })
        guard stakeCashUSD > 0 else { return cashCost }
        return Money((Double(cashCost) * Double(min(usd, stakeCashUSD)) / Double(stakeCashUSD)).rounded())
    }
    /// AUD that reaches your bank when you withdraw `usd`, after the FX fee.
    func audBack(usd: Money) -> Money { Money((Double(usd) * settings.audPerUSD * (1 - fxFee)).rounded()) }
}

// MARK: Fix it for me (MK3)
extension FinanceState {
    /// Applies a plan from Engine.fixPlan: match drifted balances, release goal money, then lower budgets.
    mutating func apply(_ plan: Engine.FixPlan) {
        for fix in plan.balances { matchBalances([fix.pocketsmithID: fix.theirs]) }
        if let to = plan.savingsTo { savings = to }
        if let to = plan.emergencyTo { emergency = to }
        var release = plan.releaseGoals
        for i in goals.indices.reversed() where release > 0 { // Newest goal gives way first.
            let take = min(release, goals[i].reserved); goals[i].reserved -= take; release -= take
        }
        for cut in plan.cuts { if let i = budgets.firstIndex(where: { $0.category == cut.category }) { budgets[i].limit = max(0, budgets[i].limit - cut.amount) } }
    }
}

// MARK: Checking Stake cash against your history (MK3.1)
extension FinanceState {
    /// Sets Stake cash to what the Stake app shows. The difference is kept as a correction, so your history adds up to it.
    mutating func correctStakeCash(to usd: Money) {
        let history = Engine(state: self).stakeCheck.history
        stakeCorrectionsUSD = (stakeCorrectionsUSD ?? 0) + usd - history
        stakeCashUSD = usd
    }
    /// Replaces an estimated USD amount on a deposit or withdrawal with the real one from Stake.
    mutating func setStakeUSD(_ id: UUID, usd: Money) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }), [.investment, .fromStake].contains(entries[i].kind) else { return }
        guard usd > 0 else { throw AppError.invalid("Enter the USD amount from Stake.") }
        let e = entries[i]
        let was = e.usd ?? (e.kind == .fromStake ? usdSold(aud: e.amount) : e.name.lowercased().contains("stake") ? usdBought(aud: e.amount) : 0)
        if e.hadEffects { stakeCashUSD = max(0, stakeCashUSD + (e.kind == .investment ? usd - was : was - usd)) }
        if e.kind == .fromStake, let cost = e.costAUD, was > 0 { entries[i].costAUD = Money((Double(cost) * Double(usd) / Double(was)).rounded()) }
        entries[i].usd = usd; entries[i].usdEstimated = nil
    }
}
extension Engine {
    /// Stake cash rebuilt from your history, to compare with what MoneyPilot shows and what the Stake app shows.
    struct StakeCheck {
        var before: Money = 0, deposits: Money = 0, withdrawals: Money = 0, bought: Money = 0, sold: Money = 0, corrections: Money = 0
        var history: Money { before + deposits - withdrawals - bought + sold + corrections }
        var estimated: [Entry] = []      // Deposits and withdrawals whose USD is a guess
        var notAdded: Money = 0          // Imported past deposits that never added USD to Stake cash
    }
    var stakeCheck: StakeCheck {
        var c = StakeCheck()
        let b = state.stakeBefore ?? StakeHistory()
        c.before = b.usdIn - b.usdOut
        for d in stakeDeposits {
            let usd = d.usd ?? state.usdBought(aud: d.amount)
            c.deposits += usd
            if !d.hadEffects { c.notAdded += usd }
        }
        for w in stakeWithdrawals { c.withdrawals += w.usd ?? state.usdSold(aud: w.amount) }
        for h in state.holdings {
            c.bought += h.costUSD + (h.soldCostUSD ?? 0)
            c.sold += (h.soldCostUSD ?? 0) + (h.realisedUSD ?? 0)
        }
        c.corrections = state.stakeCorrectionsUSD ?? 0
        c.estimated = (stakeDeposits + stakeWithdrawals).filter { $0.usd == nil || $0.usdEstimated == true }.sorted { $0.date > $1.date }
        return c
    }
}

// MARK: Paydays and time off (MK3.6)
extension FinanceState {
    /// Whether wages arrive on `day`: false inside any time off you've entered.
    func paysWages(on day: Date) -> Bool {
        let c = Calendar.current, d = c.startOfDay(for: day)
        return !(settings.timeOff ?? []).contains { c.startOfDay(for: $0.from) <= d && d <= c.startOfDay(for: $0.to) }
    }
    /// The fortnightly payday on or after `day`, whether or not it pays.
    func paydayCycle(onOrAfter day: Date) -> Date {
        let c = Calendar.current, d = c.startOfDay(for: day)
        var pay = c.startOfDay(for: settings.nextPayday)
        while pay > d { pay = c.date(byAdding: .day, value: -14, to: pay)! }
        while pay < d { pay = c.date(byAdding: .day, value: 14, to: pay)! }
        return pay
    }
    /// The first payday on or after `day` that actually pays, skipping time off (looks up to two years ahead).
    func payingPayday(onOrAfter day: Date) -> Date {
        var pay = paydayCycle(onOrAfter: day)
        for _ in 0..<52 where !paysWages(on: pay) { pay = Calendar.current.date(byAdding: .day, value: 14, to: pay)! }
        return pay
    }
    /// Time off that overlaps the days from today up to `end`.
    func timeOff(before end: Date) -> [TimeOff] {
        let today = Calendar.current.startOfDay(for: Date())
        return (settings.timeOff ?? []).filter { $0.to >= today && $0.from < end }.sorted { $0.from < $1.from }
    }
}

// MARK: Afterpay plans (MK3.6: moved here from Store so they can be tested)
extension FinanceState {
    /// Four fortnightly instalments. `alreadyPaid` instalments were paid before tracking (already in your balances).
    /// Afterpay bank payments that arrived before the plan existed are linked to it straight away.
    mutating func addPlan(name: String, total: Money, firstDue: Date, category: Category, alreadyPaid: Int = 0) throws {
        guard total >= 4, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalid("Enter the purchase name and total.") }
        let c = Calendar.current, base = total / 4
        let installments = (0..<4).map { i in
            Installment(due: c.date(byAdding: .day, value: i * 14, to: firstDue)!, amount: base + (i == 3 ? total % 4 : 0), paidOn: i < alreadyPaid ? c.date(byAdding: .day, value: i * 14, to: firstDue)! : nil)
        }
        // The first Afterpay instalment is paid at purchase, so a past first due date means an earlier purchase.
        plans.append(AfterpayPlan(name: name, category: category, purchased: min(firstDue, Date()), installments: installments))
        linkAfterpayPayments()
    }
    /// The unpaid instalment an Afterpay bank payment of `amount` on `date` most likely paid: closest amount (within $1,
    /// for rounding), then the one due nearest the payment date.
    func instalmentFor(amount: Money, date: Date) -> (plan: Int, installment: Int)? {
        plans.indices.flatMap { p in plans[p].installments.indices.map { (plan: p, installment: $0) } }
            .filter { plans[$0.plan].installments[$0.installment].paidOn == nil && abs(plans[$0.plan].installments[$0.installment].amount - amount) <= 100 }
            .min {
                let a = plans[$0.plan].installments[$0.installment], b = plans[$1.plan].installments[$1.installment]
                return (abs(a.amount - amount), abs(a.due.timeIntervalSince(date))) < (abs(b.amount - amount), abs(b.due.timeIntervalSince(date)))
            }
    }
    /// Links an Afterpay bank payment to an instalment: it becomes a repayment, so it isn't counted as spending as well.
    mutating func linkAfterpay(entryID: UUID, plan p: Int, installment k: Int) {
        guard let i = entries.firstIndex(where: { $0.id == entryID }), plans.indices.contains(p), plans[p].installments.indices.contains(k) else { return }
        plans[p].installments[k].paidOn = entries[i].date
        entries[i].kind = .repayment; entries[i].category = plans[p].category; entries[i].needsReview = nil
        entries[i].name = "Afterpay · \(plans[p].name)"; entries[i].installmentID = plans[p].installments[k].id
    }
    /// Afterpay payments from your bank that aren't linked to any instalment yet (for example because they synced before
    /// you added the plan) are matched to unpaid instalments of the same amount, paid within a week of their due date.
    mutating func linkAfterpayPayments() {
        for e in entries where e.kind == .expense && e.installmentID == nil && e.name.lowercased().contains("afterpay") {
            guard let m = instalmentFor(amount: e.amount, date: e.date),
                  abs(plans[m.plan].installments[m.installment].due.timeIntervalSince(e.date)) <= 7 * 86_400 else { continue }
            linkAfterpay(entryID: e.id, plan: m.plan, installment: m.installment)
        }
    }
}

