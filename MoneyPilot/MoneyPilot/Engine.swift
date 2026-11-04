import Foundation

struct BudgetLine: Identifiable {
    var category: Category; var limit: Money; var spent: Money; var committed: Money; var goalReserved: Money
    var id: String { category.id }
    var used: Money { spent + committed + goalReserved }
    var remaining: Money { limit - used }
    var ratio: Double { limit > 0 ? Double(used) / Double(limit) : (used > 0 ? 1 : 0) }
}
struct Suggestion: Identifiable {
    var id: String; var title: String; var detail: String; var action: String? = nil
}
/// Works out every figure from your data. MK4.1: one Engine per version of your data, and it remembers each answer,
/// so a screen asking for the same number many times (or one figure needing another) only works it out once.
/// It used to recalculate everything from every transaction on each request, which made the app lag.
final class Engine {
    let state: FinanceState
    let made = Date() // Answers depend on today's date too, so the Store replaces an Engine after a minute.
    var version = 0   // Which version of the Store's data this Engine was made from
    private var memo: [String: Any] = [:]
    init(state: FinanceState) { self.state = state }
    /// The remembered answer for `key`, worked out on first use.
    func cached<T>(_ key: String, _ make: () -> T) -> T {
        if let stored = memo[key], let hit = stored as? T { return hit } // Unwrap first: an optional answer must not read as a hit.
        let value = make(); memo[key] = value; return value
    }
    func inPeriod(_ date: Date) -> Bool { date >= state.periodStart && date < state.periodEnd }
    func accountBalance(_ id: UUID, before date: Date = .distantFuture) -> Money {
        cached("balance-\(id)-\(date.timeIntervalSince1970)") { balance(id, before: date) }
    }
    private func balance(_ id: UUID, before date: Date) -> Money {
        let opening = state.accounts.first { $0.id == id }?.openingBalance ?? 0
        return state.entries.filter { $0.date < date }.reduce(opening) { total, e in
            var delta: Money = 0
            if e.accountID == id { delta = e.kind.inflow ? e.amount : -e.amount }
            if e.kind == .transfer && e.destinationID == id { delta += e.amount }
            return total + delta
        } + (date == .distantFuture ? pending(id) : 0)
    }
    /// PocketSmith's pending total for an account: already spent at the bank, not posted yet.
    func pending(_ id: UUID) -> Money {
        guard let link = state.pocketsmith else { return 0 }
        return link.accountMap.filter { $0.value == id }.reduce(0) { $0 + (link.pending?[$1.key] ?? 0) }
    }
    var bankCash: Money { cached("bankCash") { state.accounts.reduce(0) { $0 + accountBalance($1.id) } } }
    var afterpayDebt: Money { state.plans.reduce(0) { $0 + $1.outstanding } }
    var goalReserves: Money { state.goals.reduce(0) { $0 + $1.reserved } }
    var protected: Money { state.savings + state.emergency + state.investmentReserve }
    /// MK3.3: only Afterpay due before your next payday comes out of today's cash; later instalments come out of later pays.
    var unreservedCash: Money { bankCash - protected - afterpayDueBeforePay - goalReserves }
    /// The next payday after today that actually pays. MK3.6: paydays inside time off are skipped.
    var nextPayDate: Date { cached("nextPayDate") { payDate() } }
    private func payDate() -> Date {
        let c = Calendar.current, today = c.startOfDay(for: Date())
        guard state.settings.expectedWages > 0 else { return state.periodEnd }
        return state.payingPayday(onOrAfter: c.date(byAdding: .day, value: 1, to: today)!)
    }
    var afterpayDueBeforePay: Money { cached("afterpayDueBeforePay") { afterpayDue(before: nextPayDate) } }
    private func afterpayDue(before end: Date) -> Money {
        return state.plans.flatMap(\.installments).filter { $0.paidOn == nil && $0.due < end }.reduce(0) { $0 + $1.amount }
    }
    /// Why cash and budgets don't line up: every amount taken off your bank cash, in order (MK3.3).
    var cashBreakdown: [(label: String, amount: Money)] {
        [("Cash in all your accounts", bankCash), ("Savings set aside", -state.savings), ("Emergency fund", -state.emergency),
         ("Waiting to go to Stake", -state.investmentReserve), ("Afterpay due before payday", -afterpayDueBeforePay),
         ("Saved for goals", -goalReserves), ("Budgets left this \(periodName)", -lines.reduce(0) { $0 + max(0, $1.remaining) })]
    }
    /// Spending in a category between two dates, net of refunds, plus Afterpay instalments due then.
    /// Each instalment counts in the period it falls due, so a purchase is spread over the coming weeks or months.
    func used(_ category: Category, from: Date, to: Date) -> (spent: Money, afterpay: Money) {
        let spent = state.entries.filter { $0.date >= from && $0.date < to && $0.category == category }.reduce(Money(0)) {
            if $1.kind == .expense { return $0 + $1.amount }
            if $1.kind == .refund { return $0 - $1.amount }
            return $0
        }
        let afterpay = state.plans.filter { $0.category == category }.flatMap(\.installments).filter { $0.due >= from && $0.due < to }.reduce(Money(0)) { $0 + $1.amount }
        return (spent, afterpay)
    }
    /// Start of the current week or month for spending charts: your budget week when budgets are weekly, otherwise the calendar week or month.
    func chartStart(_ period: BudgetPeriod, back: Int = 0) -> Date {
        let c = Calendar.current
        switch period {
        case .month: return c.date(byAdding: .month, value: -back, to: c.dateInterval(of: .month, for: Date())!.start)!
        case .fortnight: return c.date(byAdding: .day, value: -14 * back, to: state.start(of: .fortnight))!
        case .week:
            let current = state.period == .week ? state.periodStart : c.dateInterval(of: .weekOfYear, for: Date())!.start
            return c.date(byAdding: .day, value: -7 * back, to: current)!
        }
    }
    /// What was spent in each category over a period, largest first. Only purchases count (net of refunds, with Afterpay
    /// instalments due then); transfers between your accounts, Stake deposits and income are left out.
    func spending(_ period: BudgetPeriod, start: Date) -> [(category: Category, amount: Money)] {
        let end = period.end(from: start)
        return Category.allCases.map { c -> (category: Category, amount: Money) in
            let u = used(c, from: start, to: end); return (c, u.spent + u.afterpay)
        }.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }
    func baseLimit(_ category: Category) -> Money { category == .shopping ? 0 : state.budgets.first { $0.category == category }?.limit ?? 0 }
    func line(_ category: Category) -> BudgetLine { cached("line-\(category)") { makeLine(category) } }
    private func makeLine(_ category: Category) -> BudgetLine {
        let u = used(category, from: state.periodStart, to: state.periodEnd)
        return BudgetLine(category: category, limit: baseLimit(category), spent: u.spent, committed: u.afterpay, goalReserved: 0)
    }
    /// Budget against actual spending for any past or current month or week, using today's budgets scaled to that length.
    func review(_ period: BudgetPeriod, start: Date) -> [BudgetLine] {
        let end = period.end(from: start)
        return Category.budgeted.map { c in
            let base = baseLimit(c)
            let limit = base * state.period.perYear / period.perYear
            let u = used(c, from: start, to: end)
            return BudgetLine(category: c, limit: limit, spent: u.spent, committed: u.afterpay, goalReserved: 0)
        }
    }
    var lines: [BudgetLine] { cached("lines") { Category.budgeted.map(line) } }
    // Debt and goal reserves were already deducted in unreservedCash.
    var unallocated: Money { cached("unallocated") { unreservedCash - lines.reduce(0) { $0 + max(0, $1.remaining) } } }
    func spendable(_ category: Category) -> Money {
        let otherEnvelopes = lines.filter { $0.category != category }.reduce(Money(0)) { $0 + max(0, $1.remaining) }
        return max(0, min(line(category).remaining, unreservedCash - otherEnvelopes))
    }
    var shoppingAvailable: Money { spareMoney?.comfortable ?? 0 }
    var investmentUSD: Money { state.holdings.reduce(0) { $0 + $1.valueUSD } }
    /// Money sent to Stake and brought back (AUD cents), split into what's still invested and what's been banked.
    struct StakeMoney {
        var sentAUD: Money = 0, backAUD: Money = 0, feesAUD: Money = 0, worthAUD: Money = 0
        var basisAUD: Money = 0  // What the money still at Stake cost you
        var insideAUD: Money = 0 // Gain or loss on money still at Stake: prices, currency and fees, not yet banked
        var bankedAUD: Money = 0 // Actual profit or loss on money withdrawn to your bank
        var withdrawnCostAUD: Money = 0
    }
    /// Every stock deposit counts as money sent to Stake unless it clearly went to another broker (MK3.4):
    /// Apple Pay deposits don't always say "Stake" in the bank description.
    var stakeDeposits: [Entry] { state.entries.filter { $0.kind == .investment && ($0.usd != nil || !Engine.isOtherBroker($0.name)) } }
    var stakeWithdrawals: [Entry] { state.entries.filter { $0.kind == .fromStake } }
    var stakeMoney: StakeMoney { cached("stakeMoney") { makeStakeMoney() } }
    private func makeStakeMoney() -> StakeMoney {
        let before = state.stakeBefore ?? StakeHistory(), fee = state.fxFee
        // shortcut: withdrawals before MoneyPilot are assumed to have broken even; enter them as "Before MoneyPilot" totals.
        var m = StakeMoney(sentAUD: before.sentAUD, backAUD: before.backAUD, withdrawnCostAUD: before.backAUD)
        for d in stakeDeposits { m.sentAUD += d.amount }
        for w in stakeWithdrawals { m.backAUD += w.amount; m.withdrawnCostAUD += w.costAUD ?? w.amount; m.bankedAUD += w.amount - (w.costAUD ?? w.amount) }
        m.feesAUD = Money((Double(m.sentAUD) * fee).rounded()) + (fee < 1 ? Money((Double(m.backAUD) * fee / (1 - fee)).rounded()) : 0)
        m.worthAUD = aud(investmentUSD + state.stakeCashUSD)
        m.basisAUD = max(0, m.sentAUD - m.withdrawnCostAUD)
        m.insideAUD = m.worthAUD - m.basisAUD
        return m
    }
    /// Everything made or lost on shares, sold and still held, after brokerage.
    var portfolioProfitUSD: Money { state.holdings.reduce(0) { $0 + $1.profitUSD } }
    var portfolioProfitAUD: Money { state.holdings.reduce(0) { $0 + $1.profitAUD(state.settings.audPerUSD) } }
    func aud(_ usd: Money) -> Money { Money((Double(usd) * state.settings.audPerUSD).rounded()) }
    var investmentsAUD: Money { aud(investmentUSD) }
    var assets: Money { bankCash + aud(investmentUSD + state.stakeCashUSD) }
    var netWorth: Money { assets - afterpayDebt }
    var income: Money { state.entries.filter { inPeriod($0.date) && $0.kind.income }.reduce(0) { $0 + $1.amount } }
    var contributions: Money { state.entries.filter { inPeriod($0.date) && $0.kind == .investment }.reduce(0) { $0 + $1.amount } }
    func allocation(_ amount: Money) -> (savings: Money, investment: Money, spending: Money) {
        let future = percentage(amount, state.settings.futurePercent)
        let savings = percentage(future, state.settings.savingsSplit)
        return (savings, future - savings, amount - future)
    }
    var periodName: String { state.period.rawValue }
    /// Expected wages and allowance for one budget period; together they are your income for planning.
    func expectedIncome(per p: BudgetPeriod) -> (wages: Money, allowance: Money, total: Money) {
        let w = state.settings.expectedWages * 26, a = state.settings.expectedAllowance * 12
        return (w / p.perYear, a / p.perYear, (w + a) / p.perYear)
    }
    var expectedPeriodWages: Money { expectedIncome(per: state.period).wages }
    var expectedPeriodAllowance: Money { expectedIncome(per: state.period).allowance }
    var expectedPeriodIncome: Money { expectedIncome(per: state.period).total }
    var expectedWeeklyIncome: Money { state.settings.expectedWages / 2 + state.settings.expectedAllowance * 12 / 52 }
    func suggestedBudgets() -> [Budget] {
        let pool = allocation(expectedPeriodIncome).spending
        let locked = state.budgets.filter { $0.locked && $0.category != .shopping }.reduce(Money(0)) { $0 + $1.limit }
        let available = max(0, pool - locked)
        let weights: [Category: Int64] = [.fuel: 18, .groceries: 36, .takeaway: 10, .subscriptions: 4, .bills: 12, .entertainment: 6, .other: 4]
        // Recent actual expense history informs weights once at least four weeks exist.
        let historyStart = Calendar.current.date(byAdding: .day, value: -56, to: state.periodStart)!
        let old = state.entries.filter { $0.date >= historyStart && $0.date < state.periodStart && $0.kind == .expense }
        let enoughHistory = old.contains { $0.date < Calendar.current.date(byAdding: .day, value: -28, to: state.periodStart)! }
        let unlocked = state.budgets.filter { !$0.locked && $0.category != .shopping } // MK3.6: shopping no longer takes a share
        func weight(_ c: Category) -> Int64 {
            if enoughHistory { return max(1, old.filter { $0.category == c }.reduce(0) { $0 + $1.amount }) }
            return weights[c] ?? 1
        }
        let total = unlocked.reduce(Int64(0)) { $0 + weight($1.category) }
        var result = state.budgets
        var allocated: Money = 0
        for i in result.indices where !result[i].locked && result[i].category != .shopping {
            result[i].limit = total > 0 ? available * weight(result[i].category) / total : 0
            allocated += result[i].limit
        }
        if let i = result.lastIndex(where: { !$0.locked && $0.category != .shopping }) { result[i].limit += available - allocated }
        return result
    }
    var suggestions: [Suggestion] {
        var result: [Suggestion] = []
        if state.emergency < state.settings.emergencyMinimum {
            result.append(.init(id: "emergency", title: "Emergency fund needs attention", detail: "You are \(money(state.settings.emergencyMinimum - state.emergency)) below your chosen minimum. You can redirect unallocated cash without touching existing goals.", action: "emergency"))
        }
        if unallocated < 0 {
            result.append(.init(id: "overallocated", title: "Your plan exceeds available cash", detail: "Budgets and reservations exceed cash by \(money(-unallocated)). Reduce a budget or release a reservation; expected income is not cash yet."))
        }
        for line in lines where line.ratio >= Double(state.settings.warningPercent) / 100 {
            result.append(.init(id: "budget-\(line.id)", title: "\(line.category.rawValue): \(Int(line.ratio * 100))% allocated or used", detail: "\(money(line.spent)) paid this period, \(money(line.committed)) Afterpay due this period, \(money(line.goalReserved)) in purchase goals. You can spend \(money(spendable(line.category))) more within this plan."))
        }
        if unallocated > 0 {
            result.append(.init(id: "surplus", title: "Give \(money(unallocated)) a purpose", detail: "This is cash left after protected funds, debt, goals and category budgets. Consider savings, your investment reserve or extra shopping money.", action: "surplus"))
        }
        result.append(.init(id: "rule", title: "Your income rule", detail: "For every $1,000 received: \(money(allocation(100_000).savings)) to savings, \(money(allocation(100_000).investment)) reserved for investing and \(money(allocation(100_000).spending)) for spending. Reservations do not transfer money."))
        return result
    }
    /// Words banks add around merchant names, ignored when grouping similar transactions.
    static let noise: Set<String> = ["visa", "purchase", "eftpos", "debit", "credit", "card", "direct", "payment", "pos", "the", "and", "pty", "ltd", "aus", "www", "com", "net", "tap", "int", "transaction", "fee", "paypal", "zlr", "smp", "ezi", "lsp", "sumup", "square", "tyro", "osko", "transfer", "bpay", "nsw", "qld", "vic", "brisbane", "sydney", "melbourne", "aud", "usd"]
    /// The merchant part of a bank description: its first two meaningful words, e.g. "VISA PURCHASE TRANSLINK GO CARD 1234" → "translink go".
    static func groupKey(_ name: String) -> String {
        name.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 && !noise.contains($0) }.prefix(2).joined(separator: " ")
    }
    /// Whether a transaction belongs to a group: same merchant, possibly with a longer description ("translink" covers "translink go").
    static func inGroup(_ name: String, _ key: String) -> Bool {
        let own = groupKey(name)
        return !key.isEmpty && (own == key || own.hasPrefix(key + " "))
    }
    /// Your own category choice for a merchant: an exact-name rule first, then the most specific group rule.
    func ruleCategory(_ merchant: String) -> Category? {
        if let rule = state.rules[merchant.lowercased().trimmingCharacters(in: .whitespaces)] { return rule }
        return (state.groupRules ?? [:]).filter { Engine.inGroup(merchant, $0.key) }.max { $0.key.count < $1.key.count }?.value
    }
    // MARK: Auto-organise
    /// The category most of your other transactions from the same merchant are filed under, ignoring Other.
    func learnedCategory(_ name: String, excluding id: UUID? = nil) -> Category? {
        let key = Engine.groupKey(name)
        guard !key.isEmpty else { return nil }
        var votes = merchantVotes[key] ?? [:]
        if let id, let own = entryByID[id], own.category != .other, own.kind == .expense || own.kind == .refund, Engine.groupKey(own.name) == key {
            votes[own.category, default: 0] -= 1 // Leave the transaction being sorted out of its own vote.
        }
        return votes.filter { $0.value > 0 }.max { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) }?.key
    }
    /// MK4.1: for each merchant, how many of your purchases and refunds are filed under each category (Other left out),
    /// counted once instead of re-reading every transaction for each one being sorted.
    private var merchantVotes: [String: [Category: Int]] {
        cached("merchantVotes") {
            var votes: [String: [Category: Int]] = [:]
            for e in state.entries where (e.kind == .expense || e.kind == .refund) && e.category != .other {
                let key = Engine.groupKey(e.name)
                if !key.isEmpty { votes[key, default: [:]][e.category, default: 0] += 1 }
            }
            return votes
        }
    }
    private var entryByID: [UUID: Entry] { cached("entryByID") { Dictionary(state.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) } }
    /// Best category for a transaction and why: your rules, then how you filed this merchant before, then known merchants, then PocketSmith's category.
    func autoCategory(_ name: String, hint: String? = nil, excluding id: UUID? = nil) -> (category: Category, reason: String) {
        if let rule = ruleCategory(name) { return (rule, "Your rule for this merchant") }
        if let learned = learnedCategory(name, excluding: id) { return (learned, "Like your other \(Engine.groupKey(name).capitalized) transactions") }
        let known = categorise(name)
        if known != .other { return (known, "Recognised merchant") }
        if let hint, case let fromHint = categorise(hint), fromHint != .other { return (fromHint, "PocketSmith category “\(hint)”") }
        return (.other, "")
    }
    /// Share-trading platforms whose deposits are investing, not spending.
    static let brokers = ["stake", "commsec", "superhero", "pearler", "selfwealth", "cmc markets", "nabtrade", "moomoo", "webull", "etoro", "interactive brokers", "ibkr", "raiz", "spaceship", "vanguard", "stockspot", "sharesies", "tiger brokers", "openmarkets"]
    static func isStockDeposit(_ name: String) -> Bool { let n = name.lowercased(); return brokers.contains { n.contains($0) } }
    static func isOtherBroker(_ name: String) -> Bool { let n = name.lowercased(); return !n.contains("stake") && brokers.contains { n.contains($0) } }
    struct Proposal: Identifiable { var id: UUID; var name: String; var amount: Money; var date: Date; var category: Category; var reason: String; var stockDeposit = false }
    /// Spending still in Other that the engine can now file, and payments to brokers that should be stock deposits.
    var organiseProposals: [Proposal] { cached("organiseProposals") { makeProposals() } }
    private func makeProposals() -> [Proposal] {
        state.entries.filter { $0.kind == .expense && Engine.isStockDeposit($0.name) }.map {
            Proposal(id: $0.id, name: $0.name, amount: $0.amount, date: $0.date, category: .other, reason: "Payment to a share-trading platform", stockDeposit: true)
        } + state.entries.filter { ($0.kind == .expense || $0.kind == .refund) && $0.category == .other && $0.needsReview != true && !Engine.isStockDeposit($0.name) }.compactMap { e in
            let guess = autoCategory(e.name, excluding: e.id)
            return guess.category == .other ? nil : Proposal(id: e.id, name: e.name, amount: e.amount, date: e.date, category: guess.category, reason: guess.reason)
        }.sorted { $0.date > $1.date }
    }
    /// Transactions that a correction to `name` would also change.
    func similar(to name: String) -> [Entry] {
        let key = Engine.groupKey(name)
        return state.entries.filter { ($0.kind == .expense || $0.kind == .refund) && $0.needsReview != true && Engine.inGroup($0.name, key) }
    }
    func categorise(_ merchant: String) -> Category {
        let text = merchant.lowercased().trimmingCharacters(in: .whitespaces)
        if let rule = ruleCategory(merchant) { return rule }
        // Subscriptions first so "apple.com/bill" and "amazon prime" are not read as shopping.
        let keywords: [(Category, [String])] = [(.subscriptions, ["netflix", "spotify", "disney", "stan.com", "binge", "kayo", "youtube", "apple.com", "icloud", "amazon prime", "prime video", "openai", "chatgpt", "anthropic", "claude.ai", "adobe", "microsoft", "xbox", "playstation", "nintendo", "audible", "patreon", "subscription"]), (.fuel, ["ampol", "shell", "bp ", "petrol", "fuel", "7-eleven"]), (.groceries, ["woolworths", "coles", "aldi", "iga ", "groceries", "supermarket"]), (.takeaway, ["ubereats", "uber eats", "doordash", "menulog", "gyg", "mcdonald", "kfc", "hungry jack", "cafe", "coffee", "restaurant", "eating out", "dining", "takeaway"]), (.bills, ["agl", "origin", "telstra", "optus", "vodafone", "rent", "utilities", "insurance", "phone", "internet"]), (.shopping, ["amazon", "kmart", "big w", "target", "jb hi", "apple store", "uniqlo", "shopping", "clothing"]), (.entertainment, ["event cinemas", "hoyts", "reading cinema", "dendy", "palace cinema", "cinema", "movies", "ticketek", "ticketmaster", "moshtix", "oztix", "eventbrite", "timezone", "strike bowling", "bowling", "holey moley", "archie brothers", "lasertag", "escape room", "karaoke", "concert", "theatre", "dreamworld", "movie world", "sea world", "wet n wild", "steam", "entertainment", "recreation"])]
        return keywords.first { $0.1.contains(where: text.contains) }?.0 ?? .other
    }
    /// Linked accounts whose balance differs from PocketSmith's latest figure.
    /// MK3.7: the balance an account has once matched to PocketSmith: its figure less pending transactions.
    func matched(_ drift: (pocketsmithID: String, account: Account, theirs: Money)) -> Money { drift.theirs + pending(drift.account.id) }
    /// `theirs` is PocketSmith's own figure, which leaves out pending transactions; compare with `matched(_:)`.
    var drifted: [(pocketsmithID: String, account: Account, theirs: Money)] { cached("drifted") { findDrift() } }
    private func findDrift() -> [(pocketsmithID: String, account: Account, theirs: Money)] {
        guard let link = state.pocketsmith else { return [] }
        return link.accountMap.compactMap { id, mine in
            guard let account = state.accounts.first(where: { $0.id == mine }), let theirs = link.balances[id], theirs + pending(mine) != accountBalance(mine) else { return nil }
            return (id, account, theirs)
        }
    }
    // MARK: Week at a glance
    var daysLeft: Int { max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: state.periodEnd).day ?? 1) }
    static let fixed: Set<Category> = [.bills, .subscriptions]
    /// Money left this week for everyday categories, limited by free cash after fixed costs still to come.
    var weekLeft: Money {
        let flexible = lines.filter { !Engine.fixed.contains($0.category) }.reduce(Money(0)) { $0 + max(0, $1.remaining) }
        let fixedLeft = lines.filter { Engine.fixed.contains($0.category) }.reduce(Money(0)) { $0 + max(0, $1.remaining) }
        return max(0, min(flexible, unreservedCash - fixedLeft))
    }
    /// MK3.2: takeaway budget left this period, never more than the cash you actually have.
    var takeawayLeft: Money { spendable(.takeaway) }
    var weekUsed: Double {
        let limit = lines.reduce(Money(0)) { $0 + $1.limit }
        return limit > 0 ? Double(lines.reduce(Money(0)) { $0 + $1.used }) / Double(limit) : 0
    }
    var elapsedFraction: Double { min(1, max(0, Date().timeIntervalSince(state.periodStart) / state.periodEnd.timeIntervalSince(state.periodStart))) }
    /// Positive means spending faster than an even pace through the week.
    func pace(_ line: BudgetLine) -> Money { line.used - Money((Double(line.limit) * elapsedFraction).rounded()) }
    var weekPace: Money { lines.filter { !Engine.fixed.contains($0.category) }.reduce(Money(0)) { $0 + pace($1) } }
    struct Upcoming: Identifiable { var id: String; var date: Date; var name: String; var amount: Money; var icon: String; var income = false }
    /// Subscriptions, Afterpay instalments and expected pay in the next few days.
    func upcoming(days: Int = 7) -> [Upcoming] {
        let c = Calendar.current; let today = c.startOfDay(for: Date())
        let end = c.date(byAdding: .day, value: days, to: today)!
        var items = state.subs.map { Upcoming(id: "sub-\($0.id)", date: nextCharge($0), name: $0.name, amount: $0.amount, icon: Category.subscriptions.icon) }
        items += state.plans.flatMap { p in p.installments.filter { $0.paidOn == nil }.map { Upcoming(id: "ap-\($0.id)", date: $0.due, name: "Afterpay · \(p.name)", amount: $0.amount, icon: "calendar.badge.clock") } }
        if state.settings.expectedWages > 0 {
            items.append(Upcoming(id: "pay", date: state.payingPayday(onOrAfter: today), name: "Payday", amount: state.settings.expectedWages, icon: "arrow.down.left", income: true))
        }
        if state.settings.expectedAllowance > 0 {
            items.append(Upcoming(id: "allowance", date: state.nextAllowance, name: "Parents’ allowance", amount: state.settings.expectedAllowance, icon: "arrow.down.left", income: true))
        }
        return items.filter { $0.date >= today && $0.date < end }.sorted { $0.date < $1.date }
    }
    // MARK: Subscriptions
    var monthlySubscriptions: Money { state.subs.reduce(0) { $0 + $1.cycle.monthly($1.amount) } }
    func lastCharge(_ sub: Subscription) -> Date? {
        state.entries.filter { $0.kind == .expense && $0.name.lowercased().contains(sub.keyword.lowercased()) }.map(\.date).max()
    }
    func nextCharge(_ sub: Subscription) -> Date {
        var date = lastCharge(sub).map(sub.cycle.next) ?? sub.start
        let today = Calendar.current.startOfDay(for: Date())
        while date < today { date = sub.cycle.next(after: date) }
        return date
    }
    /// Merchant name reduced to its first words without numbers, so "NETFLIX.COM 1234" and "Netflix.com" group together.
    static func merchantKey(_ name: String) -> String {
        let letters = name.lowercased().map { $0.isLetter || $0 == "." ? $0 : " " }
        return String(letters).split(separator: " ").prefix(2).joined(separator: " ")
    }
    /// Charges that repeat at a steady interval and similar amount, not yet tracked.
    func detectedSubscriptions() -> [Subscription] { cached("detectedSubscriptions") { findSubscriptions() } }
    private func findSubscriptions() -> [Subscription] {
        let tracked = state.subs.map { $0.keyword.lowercased() }
        let since = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        let groups = Dictionary(grouping: state.entries.filter { $0.kind == .expense && $0.date >= since }) { Engine.merchantKey($0.name) }
        var found: [Subscription] = []
        for (key, charges) in groups where !key.isEmpty && !tracked.contains(where: { key.contains($0) || $0.contains(key) }) {
            let sorted = charges.sorted { $0.date < $1.date }
            guard let last = sorted.last else { continue }
            let amounts = sorted.map(\.amount).sorted(); let typical = amounts[amounts.count / 2]
            // Single charge in the Subscriptions category: assume monthly.
            if sorted.count == 1 {
                if last.category == .subscriptions { found.append(Subscription(name: last.name, keyword: key, amount: last.amount, cycle: .monthly, start: last.date)) }
                continue
            }
            guard sorted.allSatisfy({ abs($0.amount - typical) * 100 <= typical * 15 }) else { continue }
            let gaps = zip(sorted, sorted.dropFirst()).map { Calendar.current.dateComponents([.day], from: $0.0.date, to: $0.1.date).day ?? 0 }
            let ranges: [(Cycle, ClosedRange<Int>)] = [(.weekly, 6...8), (.fortnightly, 13...15), (.monthly, 27...32), (.yearly, 355...375)]
            guard let cycle = ranges.first(where: { r in gaps.allSatisfy { r.1.contains($0) } })?.0 else { continue }
            // Two shop visits a week apart are common; weekly or fortnightly needs three charges unless already marked a subscription.
            if sorted.count < 3 && (cycle == .weekly || cycle == .fortnightly) && last.category != .subscriptions { continue }
            found.append(Subscription(name: last.name, keyword: key, amount: typical, cycle: cycle, start: last.date))
        }
        return found.sorted { $0.cycle.monthly($0.amount) > $1.cycle.monthly($1.amount) }
    }
    // Forecast is explicitly hypothetical: regular spending + unpaid instalments + scheduled income.
    func forecast(days: Int = 35) -> [(date: Date, balance: Money)] { cached("forecast-\(days)") { makeForecast(days) } }
    private func makeForecast(_ days: Int) -> [(date: Date, balance: Money)] {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: days + 1, to: today)!
        // Instalments for budgeted categories are part of those budgets; they're applied on their own dates instead.
        // MK3.6: shopping isn't a budget, so its old limit no longer counts as spending, and its Afterpay isn't taken off.
        let scheduledInBudgets = state.plans.filter { Category.budgeted.contains($0.category) }.flatMap(\.installments)
            .filter { $0.paidOn == nil && $0.due >= today && $0.due < end }.reduce(Money(0)) { $0 + $1.amount }
        let dailySpend = max(0, Category.budgeted.reduce(Money(0)) { $0 + baseLimit($1) } * state.period.perYear / 365 - scheduledInBudgets / Int64(max(1, days)))
        var balance = bankCash; var points: [(Date, Money)] = []
        for day in 0...days {
            let date = calendar.date(byAdding: .day, value: day, to: today)!
            if day > 0 { balance -= dailySpend }
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: state.settings.nextPayday), to: date).day ?? -1
            if offset >= 0 && offset % 14 == 0 && state.paysWages(on: date) { balance += state.settings.expectedWages }
            let range = calendar.range(of: .day, in: .month, for: date)!
            if calendar.component(.day, from: date) == min(state.settings.allowanceDay, range.count) { balance += state.settings.expectedAllowance }
            balance -= state.plans.flatMap(\.installments).filter { $0.paidOn == nil && calendar.isDate($0.due, inSameDayAs: date) }.reduce(0) { $0 + $1.amount }
            points.append((date, balance))
        }
        return points
    }
}
