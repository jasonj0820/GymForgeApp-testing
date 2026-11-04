import XCTest
@testable import MoneyPilot

final class EngineTests: XCTestCase {
    func base() -> FinanceState {
        var s = FinanceState()
        s.accounts = [Account(name: "Cash", openingBalance: 100_000), Account(name: "Savings", openingBalance: 0)]
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .entertainment ? 30_000 : 0) }
        return s
    }
    func testIncomeRuleConservesEveryCent() {
        let e = Engine(state: base())
        for amount: Money in [1, 99, 100, 10_001, 100_000] {
            let a = e.allocation(amount)
            XCTAssertEqual(a.savings + a.investment + a.spending, amount)
        }
        let a = e.allocation(100_000)
        XCTAssertEqual(a.savings, 42_000); XCTAssertEqual(a.investment, 28_000); XCTAssertEqual(a.spending, 30_000)
    }
    func testOwnAccountTransferCannotCreateIncomeOrAssets() {
        var s = base()
        s.entries.append(Entry(date: Date(), name: "Move", amount: 25_000, kind: .transfer, category: .other, accountID: s.accounts[0].id, destinationID: s.accounts[1].id))
        let e = Engine(state: s)
        XCTAssertEqual(e.bankCash, 100_000); XCTAssertEqual(e.income, 0)
        XCTAssertEqual(e.accountBalance(s.accounts[0].id), 75_000)
        XCTAssertEqual(e.accountBalance(s.accounts[1].id), 25_000)
    }
    func testAfterpayPaymentDoesNotChargeBudgetTwice() {
        var s = base()
        s.plans = [AfterpayPlan(name: "Watch", category: .entertainment, purchased: Date(), installments: (0..<4).map { _ in Installment(due: Date(), amount: 3_000) })]
        let before = Engine(state: s)
        XCTAssertEqual(before.line(.entertainment).remaining, 18_000)
        s.plans[0].installments[0].paidOn = Date()
        s.entries.append(Entry(date: Date(), name: "Repayment", amount: 3_000, kind: .repayment, category: .entertainment, accountID: s.accounts[0].id))
        let after = Engine(state: s)
        XCTAssertEqual(after.line(.entertainment).remaining, before.line(.entertainment).remaining)
        XCTAssertEqual(after.netWorth, before.netWorth)
        XCTAssertEqual(after.unreservedCash, before.unreservedCash)
    }
    func testEmergencyAndSavingsAreNotExtraAssets() {
        var s = base(); s.savings = 40_000; s.emergency = 30_000
        let e = Engine(state: s)
        XCTAssertEqual(e.assets, 100_000); XCTAssertEqual(e.unreservedCash, 30_000)
    }
    func testGoalMoneyComesOffCashOnce() {
        var s = base(); s.goals = [Goal(name: "Watch", target: 20_000, reserved: 10_000, weekly: 2_000)]
        let e = Engine(state: s)
        XCTAssertEqual(e.spendable(.entertainment), 30_000); XCTAssertEqual(e.unallocated, 100_000 - 10_000 - 30_000)
    }
    func testInsufficientCashCapsAvailableShopping() {
        var s = base(); s.savings = 95_000
        XCTAssertEqual(Engine(state: s).spendable(.entertainment), 5_000)
        XCTAssertEqual(Engine(state: s).unallocated, -25_000)
    }
    func testExpectedIncomeDoesNotBecomeCash() {
        var s = base(); s.settings.expectedWages = 900_000; s.settings.expectedAllowance = 700_000
        XCTAssertEqual(Engine(state: s).bankCash, 100_000)
        XCTAssertEqual(Engine(state: s).spendable(.entertainment), 30_000)
    }
    func testInvestmentTransferPreservesAssetsAtMatchingFX() {
        var s = base(); s.settings.audPerUSD = 1.5
        let before = Engine(state: s).assets
        s.entries.append(Entry(date: Date(), name: "Stake", amount: 15_000, kind: .investment, category: .other, accountID: s.accounts[0].id))
        s.stakeCashUSD += 10_000
        XCTAssertEqual(Engine(state: s).assets, before)
        XCTAssertEqual(Engine(state: s).line(.other).spent, 0)
    }
    func testRefundRestoresCategoryHeadroom() {
        var s = base()
        s.entries.append(Entry(date: Date(), name: "Refund", amount: 2_000, kind: .refund, category: .entertainment, accountID: s.accounts[0].id))
        XCTAssertEqual(Engine(state: s).spendable(.entertainment), 32_000)
        XCTAssertEqual(Engine(state: s).bankCash, 102_000)
    }
    func testLockedBudgetIsPreservedAndRecommendationsConservePool() {
        var s = base(); s.settings.expectedWages = 100_000
        s.budgets[0].limit = 1_234; s.budgets[0].locked = true
        let e = Engine(state: s); let result = e.suggestedBudgets()
        XCTAssertEqual(result[0].limit, 1_234)
        XCTAssertEqual(result.reduce(Money(0)) { $0 + $1.limit }, e.allocation(e.expectedWeeklyIncome).spending)
    }
    func testMerchantCorrectionOverridesHeuristic() {
        var s = base(); s.rules["coles"] = .shopping
        XCTAssertEqual(Engine(state: s).categorise("COLES"), .shopping)
        XCTAssertEqual(Engine(state: s).categorise("Unrecognised place"), .other)
    }
    func testStrictAmountParsing() {
        XCTAssertEqual(cents("1,234.56"), 123456)
        XCTAssertNil(cents("12oops")); XCTAssertNil(cents("-20")); XCTAssertNil(cents("1.234"))
    }
    func testJSONRoundTripPreservesReservationsAndIdentity() throws {
        let s = FinanceState.sample()
        let decoded = try JSONDecoder().decode(FinanceState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.accounts[0].id, s.accounts[0].id)
        XCTAssertEqual(Engine(state: decoded).netWorth, Engine(state: s).netWorth)
        XCTAssertEqual(Engine(state: decoded).spendable(.entertainment), Engine(state: s).spendable(.entertainment))
    }
    func testPastAfterpayInstalmentsDoNotUseThisWeeksBudget() {
        var s = base()
        let lastWeek = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        s.plans = [AfterpayPlan(name: "Shoes", category: .entertainment, purchased: lastWeek, installments: (0..<4).map { i in Installment(due: lastWeek, amount: 3_000, paidOn: i == 0 ? lastWeek : nil) })]
        let e = Engine(state: s)
        XCTAssertEqual(e.line(.entertainment).committed, 0)
        XCTAssertEqual(e.unreservedCash, 100_000 - 9_000) // Unpaid instalments still reserve cash.
    }
    func linked() -> FinanceState {
        var s = base()
        s.pocketsmith = PocketSmithLink(accountMap: ["11": s.accounts[0].id, "22": s.accounts[1].id], wageKeyword: "acme")
        return s
    }
    func tx(_ id: Int, _ payee: String, _ amount: Double, _ account: Int, status: String = "posted") -> PSTransaction {
        PSTransaction(id: id, payee: payee, originalPayee: nil, date: PocketSmithClient.day.string(from: Date()), amount: amount, type: amount < 0 ? "debit" : "credit", status: status, transactionAccount: .init(id: account))
    }
    func testPocketSmithImportPairsTransfersAppliesIncomeAndSkipsDuplicates() {
        var s = linked()
        let batch = [tx(1, "Transfer out", -100, 11), tx(2, "Transfer in", 100, 22), tx(3, "ACME PTY LTD PAY", 1_000, 11), tx(4, "Woolworths", -50, 11), tx(5, "Pending", -9, 11, status: "pending"), tx(6, "Jake", 20, 22)]
        XCTAssertEqual(s.importPocketSmith(batch), 4)
        XCTAssertEqual(s.importPocketSmith(batch), 0) // A second sync of the same data adds nothing.
        let e = Engine(state: s)
        XCTAssertEqual(s.entries.filter { $0.kind == .transfer }.count, 1)
        XCTAssertEqual(e.accountBalance(s.accounts[0].id), 100_000 - 10_000 + 100_000 - 5_000 - 900) // The pending $9 counts already.
        XCTAssertEqual(e.accountBalance(s.accounts[1].id), 10_000 + 2_000)
        XCTAssertEqual(e.income, 100_000); XCTAssertEqual(s.savings, 42_000); XCTAssertEqual(s.investmentReserve, 28_000)
        XCTAssertEqual(e.line(.groceries).spent, 5_000)
        XCTAssertEqual(s.entries.filter { $0.needsReview == true }.map(\.name), ["Jake"])
    }
    func testPocketSmithAfterpayDebitClearsInstalmentWithoutBudgetCharge() {
        var s = linked()
        s.plans = [AfterpayPlan(name: "Watch", category: .entertainment, purchased: Date(), installments: (0..<4).map { _ in Installment(due: Date(), amount: 3_000) })]
        let before = Engine(state: s).line(.entertainment).remaining
        XCTAssertEqual(s.importPocketSmith([tx(9, "AFTERPAY AU", -30, 11)]), 1)
        XCTAssertEqual(s.plans[0].outstanding, 9_000)
        XCTAssertEqual(s.entries.first?.kind, .repayment)
        XCTAssertEqual(Engine(state: s).line(.entertainment).remaining, before)
        XCTAssertEqual(Engine(state: s).bankCash, 97_000)
    }
    func testMK11SavedFileStillLoads() throws {
        // MK1.1 files have no PocketSmith link or import fields.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FinanceState.sample())) as! [String: Any]
        json["pocketsmith"] = nil
        let decoded = try JSONDecoder().decode(FinanceState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.pocketsmith); XCTAssertEqual(decoded.entries.count, 2); XCTAssertNil(decoded.entries[0].externalID)
    }
    func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Date())! }
    func testHistoryImportRecordsWithoutReservationsOrReviews() {
        var s = linked()
        let n = s.importPocketSmith([tx(1, "ACME PAYROLL", 800, 11), tx(2, "Mum", 50, 11), tx(3, "Stake deposit", -200, 11)], historical: true)
        XCTAssertEqual(n, 3)
        XCTAssertEqual(s.savings, 0); XCTAssertEqual(s.investmentReserve, 0)
        XCTAssertEqual(s.entries.map(\.kind), [.wage, .otherIncome, .investment])
        XCTAssertFalse(s.entries.contains { $0.needsReview == true })
        s.matchBalances(["11": 123_456])
        XCTAssertEqual(Engine(state: s).accountBalance(s.accounts[0].id), 123_456)
    }
    func testOtherHalfOfRecordedTransferIsNotDuplicated() {
        var s = linked()
        s.entries = [Entry(date: Date(), name: "Move", amount: 5_000, kind: .transfer, category: .other, accountID: s.accounts[0].id, destinationID: s.accounts[1].id, externalID: 1)]
        XCTAssertEqual(s.importPocketSmith([tx(2, "Move", 50, 22)]), 0)
        XCTAssertEqual(s.entries.count, 1); XCTAssertEqual(s.entries[0].pairedID, 2)
    }
    func testCategoriesUseSubscriptionsAndPocketSmithHints() {
        var s = linked()
        XCTAssertEqual(Engine(state: s).categorise("AMAZON PRIME AU"), .subscriptions)
        XCTAssertEqual(Engine(state: s).categorise("Amazon AU Marketplace"), .shopping)
        var hinted = tx(1, "Smith Family Pty", -12, 11); hinted.category = .init(title: "Eating Out")
        _ = s.importPocketSmith([hinted])
        XCTAssertEqual(s.entries.first?.category, .takeaway)
    }
    func testRecurringChargesAreDetectedAsSubscriptions() {
        var s = base(); let a = s.accounts[0].id
        for i in 0..<3 { s.entries.append(Entry(date: day(-60 + i * 30), name: "NETFLIX.COM \(i)", amount: 1_899, kind: .expense, category: .subscriptions, accountID: a)) }
        for i in 0..<2 { s.entries.append(Entry(date: day(-14 + i * 7), name: "Woolworths 123", amount: 8_000, kind: .expense, category: .groceries, accountID: a)) }
        let found = Engine(state: s).detectedSubscriptions()
        XCTAssertEqual(found.map(\.keyword), ["netflix.com"]); XCTAssertEqual(found.first?.cycle, .monthly)
        s.subs = found
        XCTAssertTrue(Engine(state: s).detectedSubscriptions().isEmpty) // Tracked ones are not suggested again.
        XCTAssertEqual(Engine(state: s).monthlySubscriptions, 1_899)
        XCTAssertGreaterThanOrEqual(Engine(state: s).nextCharge(found[0]), Calendar.current.startOfDay(for: Date()))
    }
    func testOlderFilesGainBudgetsForNewCategories() {
        var s = base(); s.budgets.removeAll { $0.category == .subscriptions }
        s.migrate()
        XCTAssertEqual(s.budgets.count, Category.allCases.count)
    }
    func testSafeToSpendUsesFreeCashAfterFixedCosts() {
        var s = base()
        XCTAssertEqual(Engine(state: s).daysLeft, 7)
        XCTAssertEqual(Engine(state: s).weekLeft, 30_000); XCTAssertEqual(Engine(state: s).takeawayLeft, 0) // No takeaway budget in this setup.
        s.budgets[s.budgets.firstIndex { $0.category == .subscriptions }!].limit = 5_000
        s.savings = 70_000 // Only $300 free; $50 of it is still due for subscriptions.
        XCTAssertEqual(Engine(state: s).weekLeft, 25_000)
        s.periodStart = Date().addingTimeInterval(-3.5 * 86_400)
        s.entries.append(Entry(date: Date(), name: "Shoes", amount: 20_000, kind: .expense, category: .entertainment, accountID: s.accounts[0].id))
        let e = Engine(state: s)
        XCTAssertLessThan(abs(e.pace(e.line(.entertainment)) - 5_000), 10) // Half the week gone, $200 of $300 used.
    }
    func testUpcomingListsSubscriptionsAfterpayAndPaydayInOrder() {
        var s = base(); s.settings.expectedWages = 100_000; s.settings.nextPayday = day(-9) // Fortnightly, so next is in 5 days.
        s.subs = [Subscription(name: "Spotify", keyword: "spotify", amount: 1_399, cycle: .monthly, start: day(2))]
        s.plans = [AfterpayPlan(name: "Shoes", purchased: day(-11), installments: [Installment(due: day(3), amount: 2_500), Installment(due: day(17), amount: 2_500)])]
        let names = Engine(state: s).upcoming().map(\.name)
        XCTAssertEqual(names, ["Spotify", "Afterpay · Shoes", "Payday"])
    }
    func testEditAndDeleteUndoIncomeRuleOnlyWhereItWasApplied() throws {
        var s = base(); let a = s.accounts[0].id
        let wage = Entry(date: Date(), name: "Pay", amount: 100_000, kind: .wage, category: .other, accountID: a)
        s.entries.append(wage); try s.applyEffects(.wage, amount: 100_000)
        try s.editEntry(wage.id, name: "Pay", amount: 50_000, date: Date(), category: .other)
        XCTAssertEqual(s.savings, 21_000); XCTAssertEqual(s.investmentReserve, 14_000)
        try s.deleteEntry(wage.id)
        XCTAssertEqual(s.savings, 0); XCTAssertEqual(s.investmentReserve, 0)
        s.savings = 5_000
        let old = Entry(date: Date(), name: "Old pay", amount: 80_000, kind: .wage, category: .other, accountID: a, historical: true)
        s.entries.append(old); try s.deleteEntry(old.id)
        XCTAssertEqual(s.savings, 5_000) // History never added to savings, so deleting it takes nothing away.
        let stake = Entry(date: Date(), name: "Stake", amount: 10_000, kind: .investment, category: .other, accountID: a)
        s.entries.append(stake); try s.deleteEntry(stake.id)
        XCTAssertEqual(s.investmentReserve, 10_000)
        let repay = Entry(date: Date(), name: "Afterpay", amount: 3_000, kind: .repayment, category: .shopping, accountID: a)
        s.entries.append(repay)
        XCTAssertThrowsError(try s.deleteEntry(repay.id))
    }
    func plan(_ s: inout FinanceState) -> AfterpayPlan {
        let p = AfterpayPlan(name: "Watch", purchased: Date(), installments: (0..<4).map { Installment(due: day($0 * 14), amount: 3_000) })
        s.plans = [p]; return p
    }
    func testUndoPaymentRestoresDebtAndRemovesOrReviewsTheRepayment() {
        var s = base(); let p = plan(&s); let a = s.accounts[0].id
        s.plans[0].installments[0].paidOn = Date()
        s.entries.append(Entry(date: Date(), name: "Afterpay · Watch", amount: 3_000, kind: .repayment, category: .shopping, accountID: a, installmentID: p.installments[0].id))
        s.undoPayment(planID: p.id, installmentID: p.installments[0].id)
        XCTAssertEqual(s.plans[0].outstanding, 12_000); XCTAssertTrue(s.entries.isEmpty)
        XCTAssertEqual(Engine(state: s).bankCash, 100_000)
        // A bank payment is real money: it stays and goes to review instead.
        s.plans[0].installments[1].paidOn = Date()
        s.entries.append(Entry(date: Date(), name: "Afterpay · Watch", amount: 3_000, kind: .repayment, category: .shopping, accountID: a, externalID: 7))
        s.undoPayment(planID: p.id, installmentID: p.installments[1].id)
        XCTAssertEqual(s.entries.first?.kind, .expense); XCTAssertEqual(s.entries.first?.needsReview, true)
        XCTAssertEqual(Engine(state: s).bankCash, 97_000)
    }
    func testPlanEditsChangeUnpaidOnlyAndDeleteRemovesPlan() throws {
        var s = base(); let p = plan(&s)
        s.plans[0].installments[0].paidOn = Date()
        var edited = s.plans[0]; edited.installments[3].amount = 4_000; edited.installments[3].due = day(50); edited.name = "Nice watch"
        try s.updatePlan(edited)
        XCTAssertEqual(s.plans[0].total, 13_000); XCTAssertEqual(s.plans[0].name, "Nice watch")
        var bad = s.plans[0]; bad.installments[0].amount = 1_000
        XCTAssertThrowsError(try s.updatePlan(bad)) // Paid amounts are locked until the payment is undone.
        var removed = s.plans[0]; removed.installments.removeFirst()
        XCTAssertThrowsError(try s.updatePlan(removed))
        s.deletePlan(p.id)
        XCTAssertTrue(s.plans.isEmpty); XCTAssertEqual(Engine(state: s).afterpayDebt, 0)
    }
    func testSwitchingToMonthlyConvertsBudgetsAndStartsOnTheFirst() {
        var s = base()
        s.switchPeriod(to: .month)
        let first = Calendar.current.dateInterval(of: .month, for: Date())!
        XCTAssertEqual(s.periodStart, first.start); XCTAssertEqual(s.periodEnd, first.end)
        XCTAssertEqual(Engine(state: s).baseLimit(.entertainment), 30_000 * 52 / 12)
        XCTAssertEqual(Engine(state: s).periodName, "month")
        s.switchPeriod(to: .week)
        XCTAssertEqual(Engine(state: s).baseLimit(.entertainment), 30_000 * 52 / 12 * 12 / 52)
        XCTAssertEqual(s.periodEnd, Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))!)
    }
    func testBudgetReviewCoversAnyMonthOrWeek() {
        var s = base(); s.switchPeriod(to: .month); let a = s.accounts[0].id
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: s.periodStart)!
        s.entries.append(Entry(date: lastMonth.addingTimeInterval(86_400 * 3), name: "Jacket", amount: 40_000, kind: .expense, category: .entertainment, accountID: a))
        s.entries.append(Entry(date: Date(), name: "Socks", amount: 1_000, kind: .expense, category: .entertainment, accountID: a))
        let e = Engine(state: s)
        let past = e.review(.month, start: lastMonth).first { $0.category == .entertainment }!
        XCTAssertEqual(past.used, 40_000); XCTAssertEqual(past.limit, e.baseLimit(.entertainment))
        XCTAssertEqual(e.line(.entertainment).spent, 1_000) // This month only.
        let week = e.review(.week, start: Calendar.current.startOfDay(for: Date())).first { $0.category == .entertainment }!
        XCTAssertEqual(week.limit, e.baseLimit(.entertainment) * 12 / 52); XCTAssertEqual(week.used, 1_000)
    }
    func testFortnightlyBudgetsStartOnPaydayAndConvertThroughTheYear() {
        var s = base(); s.settings.nextPayday = day(4) // Last payday was 10 days ago.
        s.switchPeriod(to: .fortnight)
        XCTAssertEqual(s.periodStart, Calendar.current.startOfDay(for: day(-10)))
        XCTAssertEqual(s.periodEnd, Calendar.current.startOfDay(for: day(4)))
        XCTAssertEqual(Engine(state: s).baseLimit(.entertainment), 60_000) // $300 a week is $600 a fortnight.
        XCTAssertEqual(Engine(state: s).daysLeft, 4)
        s.switchPeriod(to: .month)
        XCTAssertEqual(Engine(state: s).baseLimit(.entertainment), 130_000)
    }
    func testAllowanceCountsAsIncomeAndHasAnExpectedDate() {
        var s = base(); s.settings.expectedWages = 140_000; s.settings.expectedAllowance = 160_000
        s.settings.nextAllowance = day(3); s.settings.nextPayday = day(10)
        s.switchPeriod(to: .month)
        let e = Engine(state: s)
        XCTAssertEqual(e.expectedPeriodIncome, (140_000 * 26 + 160_000 * 12) / 12)
        XCTAssertEqual(e.expectedPeriodWages + e.expectedPeriodAllowance, e.expectedPeriodIncome)
        XCTAssertEqual(e.upcoming().map(\.name), ["Parents’ allowance"]) // Payday is 10 days away, outside the next 7.
        s.settings.nextAllowance = day(-2); s.settings.allowanceDay = 31
        XCTAssertGreaterThanOrEqual(s.nextAllowance, Calendar.current.startOfDay(for: Date())) // A passed date rolls to the next month.
    }
    func testMK17MonthlySettingStillMeansMonthly() {
        var s = base(); s.settings.monthlyBudget = true
        XCTAssertEqual(s.period, .month)
        s.switchPeriod(to: .fortnight)
        XCTAssertNil(s.settings.monthlyBudget); XCTAssertEqual(s.period, .fortnight)
    }
    func testAfterpayIsSpreadAcrossThePeriodsItsInstalmentsFallIn() {
        var s = base()
        let today = Calendar.current.startOfDay(for: Date())
        s.plans = [AfterpayPlan(name: "Jacket", category: .entertainment, purchased: today, installments: (0..<4).map { Installment(due: Calendar.current.date(byAdding: .day, value: $0 * 14, to: today)!, amount: 5_000) })]
        let e = Engine(state: s)
        XCTAssertEqual(e.line(.entertainment).committed, 5_000) // Only the first $50 lands in this week.
        XCTAssertEqual(e.unreservedCash, 100_000 - 5_000) // Only the instalment due before payday comes out of today's cash.
        let inTwoWeeks = Calendar.current.date(byAdding: .day, value: 14, to: today)!
        XCTAssertEqual(e.review(.week, start: inTwoWeeks).first { $0.category == .entertainment }!.used, 5_000)
        XCTAssertEqual(e.review(.week, start: Calendar.current.date(byAdding: .day, value: 7, to: today)!).first { $0.category == .entertainment }!.used, 0)
        // Paying an instalment moves cash but not the budget it already used.
        s.plans[0].installments[0].paidOn = Date()
        s.entries.append(Entry(date: Date(), name: "Afterpay · Jacket", amount: 5_000, kind: .repayment, category: .entertainment, accountID: s.accounts[0].id))
        XCTAssertEqual(Engine(state: s).line(.entertainment).remaining, e.line(.entertainment).remaining)
        XCTAssertEqual(Engine(state: s).unreservedCash, e.unreservedCash)
    }
    func testSpendingBreakdownLeavesOutTransfersInvestingAndIncome() {
        var s = base(); let a = s.accounts[0].id, b = s.accounts[1].id
        s.entries += [
            Entry(date: Date(), name: "Woolworths", amount: 6_000, kind: .expense, category: .groceries, accountID: a),
            Entry(date: Date(), name: "Kmart", amount: 2_500, kind: .expense, category: .shopping, accountID: a),
            Entry(date: Date(), name: "Kmart refund", amount: 500, kind: .refund, category: .shopping, accountID: a),
            Entry(date: Date(), name: "To savings", amount: 50_000, kind: .transfer, category: .other, accountID: a, destinationID: b),
            Entry(date: Date(), name: "Stake", amount: 20_000, kind: .investment, category: .other, accountID: a),
            Entry(date: Date(), name: "Pay", amount: 90_000, kind: .wage, category: .other, accountID: a)]
        s.plans = [AfterpayPlan(name: "Shoes", purchased: Date(), installments: [Installment(due: Date(), amount: 3_000), Installment(due: day(40), amount: 3_000)])]
        let e = Engine(state: s)
        let week = e.spending(.week, start: e.chartStart(.week))
        XCTAssertEqual(week.map(\.category), [.groceries, .shopping])
        XCTAssertEqual(week.map(\.amount), [6_000, 5_000]) // $25 − $5 refund + $30 Afterpay due now.
        XCTAssertEqual(e.spending(.week, start: e.chartStart(.week, back: 1)).count, 0)
    }
    func testCorrectingOneTransactionRefilesSimilarPastAndFutureOnes() {
        var s = linked(); let a = s.accounts[0].id
        for name in ["TRANSLINK 1.0", "Visa Purchase TRANSLINK GO CARD 4821", "Translink"] {
            s.entries.append(Entry(date: Date(), name: name, amount: 100, kind: .expense, category: .other, accountID: a))
        }
        s.entries.append(Entry(date: Date(), name: "Woolworths 1234", amount: 5_000, kind: .expense, category: .groceries, accountID: a))
        XCTAssertEqual(Engine.groupKey("Visa Purchase TRANSLINK GO CARD 4821"), "translink")
        XCTAssertEqual(Engine(state: s).similar(to: "TRANSLINK 1.0").count, 3)
        s.categoriseSimilar(to: "TRANSLINK 1.0", as: .bills)
        XCTAssertEqual(s.entries.map(\.category), [.bills, .bills, .bills, .groceries])
        _ = s.importPocketSmith([tx(50, "TRANSLINK SOUTH BRISBANE", -2.5, 11)])
        XCTAssertEqual(s.entries.last?.category, .bills) // Future imports follow the rule.
        // A more specific choice still wins: Amazon Prime can be a subscription while other Amazon is shopping.
        s.categoriseSimilar(to: "Amazon Marketplace", as: .shopping)
        s.categoriseSimilar(to: "Amazon Prime", as: .subscriptions)
        XCTAssertEqual(Engine(state: s).categorise("AMAZON PRIME AU"), .subscriptions)
        XCTAssertEqual(Engine(state: s).categorise("Amazon Marketplace AU"), .shopping)
        XCTAssertNotEqual(Engine(state: s).categorise("Amazon"), .subscriptions) // A broader name is not pulled into a narrower group.
    }
    func testEntertainmentIsRecognised() {
        XCTAssertEqual(Engine(state: base()).categorise("EVENT CINEMAS CHERMSIDE"), .entertainment)
        XCTAssertEqual(Engine(state: base()).categorise("Timezone Carindale"), .entertainment)
    }
    func testAutoOrganiseLearnsFromYourOwnFiling() {
        var s = linked(); let a = s.accounts[0].id
        // You filed this barber under Other once and Shopping twice; the unknown one follows your majority.
        for (i, c) in [Category.shopping, .shopping, .other].enumerated() {
            s.entries.append(Entry(date: day(-i), name: "Fades Barber Shop \(i)", amount: 3_000, kind: .expense, category: c, accountID: a))
        }
        s.entries.append(Entry(date: Date(), name: "HOYTS SUNNYBANK", amount: 2_200, kind: .expense, category: .other, accountID: a))
        s.entries.append(Entry(date: Date(), name: "Mystery 123", amount: 900, kind: .expense, category: .other, accountID: a))
        let proposals = Engine(state: s).organiseProposals
        XCTAssertEqual(Set(proposals.map(\.category)), [.shopping, .entertainment])
        XCTAssertEqual(s.organise(), 2)
        XCTAssertEqual(s.entries.filter { $0.category == .other }.map(\.name), ["Mystery 123"])
        _ = s.importPocketSmith([tx(77, "FADES BARBER SHOP", -35, 11)])
        XCTAssertEqual(s.entries.last?.category, .shopping) // New imports use what it learned.
    }
    func testBrokerPaymentsBecomeStockDepositsNotSpending() {
        var s = linked(); s.investmentReserve = 50_000; s.settings.audPerUSD = 1.5
        _ = s.importPocketSmith([tx(1, "STAKE AUS PTY LTD", -300, 11), tx(2, "CommSec Trading", -200, 11), tx(3, "Kmart", -40, 11)])
        XCTAssertEqual(s.entries.map(\.kind), [.investment, .investment, .expense])
        XCTAssertEqual(s.investmentReserve, 0) // $500 deposited came out of the $500 set aside for investing.
        XCTAssertEqual(s.stakeCashUSD, 19_890) // Only Stake adds USD cash: $300 less the 0.55% FX fee, ÷ 1.5.
        let e = Engine(state: s)
        XCTAssertEqual(e.spending(.week, start: e.chartStart(.week)).map(\.category), [.shopping])
        XCTAssertEqual(e.bankCash, 100_000 - 54_000)
        // An older payment entered as spending is offered as a stock deposit.
        s.entries.append(Entry(date: Date(), name: "Pearler", amount: 10_000, kind: .expense, category: .shopping, accountID: s.accounts[0].id))
        XCTAssertEqual(Engine(state: s).organiseProposals.filter(\.stockDeposit).count, 1)
        s.organise(); XCTAssertEqual(s.entries.last?.kind, .investment)
    }
    func testForecastSpendsTheSameWhateverTheBudgetPeriod() {
        var weekly = base(); weekly.settings.nextPayday = day(60) // No pay inside the window.
        var monthly = weekly; monthly.switchPeriod(to: .month)
        let a = Engine(state: weekly).forecast(days: 14).last!.balance, b = Engine(state: monthly).forecast(days: 14).last!.balance
        XCTAssertLessThan(abs(a - b), 100) // Before the fix, monthly budgets were spent as if they were weekly.
        XCTAssertLessThan(abs(a - (100_000 - 30_000 * 52 / 365 * 14)), 100)
    }
    func ids(_ s: FinanceState) -> [String] { Engine(state: s).insights.map(\.id) }
    func testInsightsFlagOverspendingDoubleChargesAndPriceRises() {
        var s = base(); let a = s.accounts[0].id; s.settings.expectedWages = 1_000; s.settings.nextPayday = day(60)
        s.entries.append(Entry(date: Date(), name: "Kmart Chermside", amount: 35_000, kind: .expense, category: .entertainment, accountID: a))
        s.entries.append(Entry(date: Date().addingTimeInterval(3_600), name: "KMART CHERMSIDE 0042", amount: 35_000, kind: .expense, category: .entertainment, accountID: a))
        s.subs = [Subscription(name: "Netflix", keyword: "netflix", amount: 1_899, cycle: .monthly, start: day(-40))]
        s.entries.append(Entry(date: day(-35), name: "NETFLIX.COM", amount: 1_899, kind: .expense, category: .subscriptions, accountID: a))
        s.entries.append(Entry(date: day(-5), name: "NETFLIX.COM", amount: 2_299, kind: .expense, category: .subscriptions, accountID: a))
        let found = Engine(state: s).insights
        XCTAssertTrue(found.contains { $0.id.hasPrefix("over-") && $0.title.hasPrefix("Entertainment") })
        XCTAssertTrue(found.contains { $0.id.hasPrefix("dup-") && $0.notify })
        XCTAssertTrue(found.contains { $0.id.hasPrefix("price-") && $0.title.hasPrefix("Netflix went up") && $0.title.hasSuffix("4.00") })
        XCTAssertEqual(found.first?.level, .critical) // $700 spent leaves less cash than the plan needs.
        XCTAssertEqual(found.map(\.level), found.map(\.level).sorted())
    }
    func testEmergencyInsightOffersToMoveSpareCash() {
        var s = base(); s.settings.emergencyMinimum = 20_000
        let tip = Engine(state: s).insights.first { $0.id == "emergency" }!
        guard case let .redirect(target, amount)? = tip.action else { return XCTFail("no action") }
        XCTAssertEqual(target, "emergency"); XCTAssertEqual(amount, 20_000)
    }
    func testScoreAndKeptRateUseRealHistory() {
        var s = base(); let a = s.accounts[0].id; s.settings.emergencyMinimum = 10_000; s.emergency = 10_000
        s.entries.append(Entry(date: day(-40), name: "Pay", amount: 200_000, kind: .wage, category: .other, accountID: a, historical: true))
        s.entries.append(Entry(date: day(-20), name: "Groceries", amount: 60_000, kind: .expense, category: .groceries, accountID: a))
        let e = Engine(state: s)
        XCTAssertEqual(e.keptRate!.rate, 0.7, accuracy: 0.001)
        let score = e.score
        XCTAssertTrue((0...100).contains(score.total))
        XCTAssertEqual(score.parts.first { $0.name == "Saving" }?.points, 25)
        XCTAssertEqual(score.parts.first { $0.name == "Emergency fund" }?.points, 20)
    }
    func testMonthInReviewComparesWithTheMonthBefore() {
        var s = base(); let a = s.accounts[0].id
        let last = Engine(state: s).chartStart(.month, back: 1), before = Engine(state: s).chartStart(.month, back: 2)
        s.entries.append(Entry(date: last.addingTimeInterval(86_400), name: "Uber Eats", amount: 9_000, kind: .expense, category: .takeaway, accountID: a))
        s.entries.append(Entry(date: before.addingTimeInterval(86_400), name: "Uber Eats", amount: 3_000, kind: .expense, category: .takeaway, accountID: a))
        let review = Engine(state: s).lastMonthReview!
        XCTAssertEqual(review.spent, 9_000); XCTAssertEqual(review.previousSpent, 3_000)
        XCTAssertEqual(review.changes.first?.category, .takeaway); XCTAssertEqual(review.changes.first?.change, 6_000)
    }
    func testAnyPurchaseCanBecomeAStockDepositAndBack() {
        var s = base(); s.investmentReserve = 30_000
        s.entries.append(Entry(date: Date(), name: "Transfer to H Chang", amount: 20_000, kind: .expense, category: .other, accountID: s.accounts[0].id))
        s.fileAsStockDeposit(0, usd: 12_900)
        XCTAssertEqual(s.entries[0].kind, .investment); XCTAssertEqual(s.investmentReserve, 10_000); XCTAssertEqual(s.stakeCashUSD, 12_900)
        XCTAssertEqual(Engine(state: s).spending(.week, start: Engine(state: s).chartStart(.week)).count, 0)
        s.fileAsSpending(0)
        XCTAssertEqual(s.entries[0].kind, .expense); XCTAssertEqual(s.investmentReserve, 30_000)
    }
    func testPaydayButtonAndBankDepositAreNotCountedTwice() {
        var s = linked(); s.settings.expectedWages = 140_000; s.settings.nextPayday = Date()
        XCTAssertEqual(Engine(state: s).pendingPay?.kind, .wage)
        s.entries.append(Entry(date: Date(), name: "Wages", amount: 142_350, kind: .wage, category: .other, accountID: s.accounts[1].id))
        try? s.applyEffects(.wage, amount: 142_350)
        XCTAssertNil(Engine(state: s).pendingPay) // Entered, so the button goes away.
        let saved = s.savings
        XCTAssertEqual(s.importPocketSmith([tx(9, "ACME PAYROLL", 1_423.50, 11)]), 0)
        XCTAssertEqual(s.entries.count, 1); XCTAssertEqual(s.entries[0].externalID, 9); XCTAssertEqual(s.entries[0].accountID, s.accounts[0].id)
        XCTAssertEqual(s.savings, saved) // The savings rule was applied once.
    }
    func fourAccounts() -> FinanceState {
        var s = FinanceState()
        s.accounts = [Account(name: "Everyday", openingBalance: 5_000), Account(name: "Shopping", openingBalance: 90_000),
                      Account(name: "Emergency", openingBalance: 50_000), Account(name: "Savings", openingBalance: 100_000)]
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .groceries ? 15_000 : $0 == .fuel ? 5_000 : 0) } // $150 groceries, $100 fuel a fortnight
        s.settings.expectedWages = 140_000; s.settings.nextPayday = day(14)
        s.emergency = 50_000; s.savings = 120_000; s.investmentReserve = 30_000
        return s
    }
    func testMoneyPlanTellsYouWhichTransfersToMake() {
        let s = fourAccounts(); let e = Engine(state: s)
        XCTAssertEqual(s.accounts.map(\.effectiveRole), [.everyday, .shopping, .emergency, .savings])
        let plan = e.moneyPlan!
        XCTAssertEqual(plan.needs.map(\.name), ["Fuel", "Groceries"])
        XCTAssertEqual(plan.needs.map(\.amount), [10_500, 31_500]) // Two weeks of groceries and fuel, plus the 5% cushion.
        let names = Dictionary(uniqueKeysWithValues: s.accounts.map { ($0.id, $0.name) })
        let said = plan.transfers.map { "\(money($0.amount)) \(names[$0.from]!) → \($0.to.flatMap { names[$0] } ?? "Stake")" }
        XCTAssertEqual(said.count, 3)
        XCTAssertTrue(said[0].hasSuffix("Shopping → Everyday") && said[0].contains("370.00"))
        XCTAssertTrue(said[1].hasSuffix("Shopping → Savings") && said[1].contains("200.00"))
        XCTAssertTrue(said[2].hasSuffix("Shopping → Stake") && said[2].contains("300.00"))
        XCTAssertEqual(plan.targets[s.accounts[1].id], 3_000) // Shopping keeps what's left: $2,450 − $500 − $1,200 − $300 − $420.
        XCTAssertEqual(plan.shortfall, 0)
    }
    func testDoneTransfersAreNotDuplicatedWhenTheBankSyncs() {
        var s = fourAccounts()
        s.pocketsmith = PocketSmithLink(accountMap: ["1": s.accounts[0].id, "2": s.accounts[1].id, "4": s.accounts[3].id])
        let plan = Engine(state: s).moneyPlan!
        s.recordTransfers(plan.transfers)
        XCTAssertEqual(s.investmentReserve, 0)
        XCTAssertTrue(Engine(state: s).moneyPlan!.transfers.isEmpty) // Balances now match the plan.
        let before = s.entries.count
        let added = s.importPocketSmith([tx(10, "Transfer to Everyday", -370, 2), tx(11, "Transfer from Shopping", 370, 1),
                                         tx(12, "Transfer to Savings", -200, 2), tx(13, "Transfer from Shopping", 200, 4), tx(14, "STAKE", -300, 2)])
        XCTAssertEqual(added, 0); XCTAssertEqual(s.entries.count, before)
        XCTAssertEqual(s.investmentReserve, 0) // The Stake deposit was only counted once.
    }
    func testSavingsMustGrowEachMonthAndInvestingNeverGoesThroughIt() {
        var s = fourAccounts(); s.savings = 0; s.emergency = 50_000
        // Savings has $1,000 and started the month there, so it must reach $1,160. Shopping has plenty.
        let plan = Engine(state: s).moneyPlan!
        XCTAssertEqual(plan.savingsRule?.required, 116_000)
        XCTAssertTrue(plan.transfers.contains { $0.from == s.accounts[1].id && $0.to == s.accounts[3].id && $0.amount == 16_000 })
        XCTAssertFalse(plan.transfers.contains { $0.from == s.accounts[3].id }) // Nothing taken out of Savings.
        // Even when Savings is the only account with spare money, Stake is not paid from it.
        var poor = fourAccounts(); poor.accounts[1].openingBalance = 0; poor.savings = 0; poor.settings.savingsGrowth = 0
        XCTAssertFalse(Engine(state: poor).moneyPlan!.transfers.contains { $0.to == nil && $0.from == poor.accounts[3].id })
    }
    func testOnlyOneSavingsWithdrawalAMonth() {
        var s = fourAccounts(); s.savings = 0; s.settings.savingsGrowth = 0; s.investmentReserve = 0
        s.accounts[1].openingBalance = 0 // Shopping is empty, so Everyday's groceries and fuel can only come from Savings.
        // A deposit this month puts Savings $300 above where it started, so that much may come out.
        s.entries.append(Entry(date: Date(), name: "Gift", amount: 30_000, kind: .otherIncome, category: .other, accountID: s.accounts[3].id))
        XCTAssertEqual(Engine(state: s).moneyPlan!.transfers.filter { $0.from == s.accounts[3].id }.count, 1)
        s.entries.append(Entry(date: Date(), name: "Withdrawal", amount: 1_000, kind: .transfer, category: .other, accountID: s.accounts[3].id, destinationID: s.accounts[0].id))
        let plan = Engine(state: s).moneyPlan!
        XCTAssertEqual(plan.savingsRule?.withdrawals, 1)
        XCTAssertFalse(plan.transfers.contains { $0.from == s.accounts[3].id }) // Limit used: no more suggestions from Savings.
        XCTAssertTrue(Engine(state: s).insights.contains { $0.id.hasPrefix("savings-withdrawal-") })
    }
    func testEverydayCoversAllSpendingAndSpareMoneyKeepsTheRest() {
        var s = fourAccounts()
        s.budgets[s.budgets.firstIndex { $0.category == .takeaway }!].limit = 4_000  // $40 a week
        s.budgets[s.budgets.firstIndex { $0.category == .shopping }!].limit = 6_000  // Ignored: shopping is spare money, not a budget.
        s.investmentReserve = 0; s.savings = 100_000 // Leaves $790 free: enough for $504 of spending.
        let plan = Engine(state: s).moneyPlan!
        XCTAssertEqual(plan.needs.map(\.name), ["Fuel", "Groceries", "Takeaway"])
        XCTAssertEqual(plan.needs.reduce(0) { $0 + $1.amount }, (15_000 + 5_000 + 4_000) * 2 * 105 / 100)
        XCTAssertEqual(plan.targets[s.accounts[0].id], 50_400) // Everyday holds two weeks of every budget plus 5%.
        s.everydayBuffer = 3_000 // 30% of last period's unspent budget stays in Everyday.
        XCTAssertEqual(Engine(state: s).moneyPlan!.targets[s.accounts[0].id], 53_400)
        XCTAssertEqual(AccountRole.shopping.title, "Spare money")
    }
    func testSpareMoneyPerPayAndGoalsTakeAtMostHalf() {
        var s = fourAccounts(); s.settings.expectedAllowance = 0; s.settings.futurePercent = 50 // $1,400 a fortnight, $700 to keep
        let spare = Engine(state: s).spareMoney!
        XCTAssertEqual(spare.account.name, "Shopping")
        XCTAssertEqual(spare.perPay, 140_000 - 70_000 - 42_000) // Pay − future − two weeks of budgets + 5% cushion.
        s.goals = [Goal(name: "3D printer", target: 60_000, weekly: 10_000), Goal(name: "Headphones", target: 30_000, weekly: 5_000)] // $200 + $100 a pay
        s.investmentReserve = 0; s.savings = 0
        s.entries.append(Entry(date: Date(), name: "Wages", amount: 140_000, kind: .wage, category: .other, accountID: s.accounts[0].id))
        try? s.applyEffects(.wage, amount: 140_000, entry: s.entries.count - 1)
        XCTAssertEqual(s.goals.map(\.reserved), [14_000, 0]) // Half of the $280 spare, oldest goal first; the rest is yours to spend.
        XCTAssertEqual(Engine(state: s).spareMoney!.reserved, 14_000)
    }
    func testPayCutsSavingsOnlyByTheShortfall() throws {
        var s = fourAccounts(); s.accounts[1].openingBalance = 0; s.accounts[0].openingBalance = 0
        s.emergency = 50_000; s.savings = 100_000; s.investmentReserve = 0 // Everyday and Shopping empty: no free cash.
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .groceries ? 30_000 : 0) } // $600 a fortnight
        let e = Engine(state: s)
        XCTAssertEqual(e.unreservedCash, 0)
        // $1,000 pay: the full rule leaves $300, $300 short of $600 of budgets, so $300 comes off savings + investing, 60/40.
        s.entries.append(Entry(date: Date(), name: "Wages", amount: 100_000, kind: .wage, category: .other, accountID: s.accounts[0].id))
        try s.applyEffects(.wage, amount: 100_000, entry: s.entries.count - 1)
        XCTAssertEqual(s.entries.last?.cut, 30_000)
        XCTAssertEqual(s.savings, 100_000 + 42_000 - 18_000); XCTAssertEqual(s.investmentReserve, 28_000 - 12_000)
        // Deleting the pay reverses exactly what it set aside.
        try s.deleteEntry(s.entries.last!.id)
        XCTAssertEqual(s.savings, 100_000); XCTAssertEqual(s.investmentReserve, 0)
        // Enough cash: no cut.
        s.accounts[0].openingBalance = 100_000
        s.entries.append(Entry(date: Date(), name: "Wages", amount: 100_000, kind: .wage, category: .other, accountID: s.accounts[0].id))
        try s.applyEffects(.wage, amount: 100_000, entry: s.entries.count - 1)
        XCTAssertNil(s.entries.last?.cut)
    }
    func testShoppingIsSpareMoneyWithALimit() {
        var s = fourAccounts(); s.settings.shoppingLimit = 20_000
        XCTAssertFalse(Engine(state: s).lines.contains { $0.category == .shopping }) // Not a budget any more.
        s.entries.append(Entry(date: Date(), name: "Kmart", amount: 17_000, kind: .expense, category: .shopping, accountID: s.accounts[1].id))
        s.entries.append(Entry(date: Date(), name: "Coles", amount: 5_000, kind: .expense, category: .groceries, accountID: s.accounts[0].id))
        var e = Engine(state: s)
        XCTAssertEqual(e.shoppingSpent, 17_000) // Only the Shopping account counts.
        XCTAssertEqual(e.shoppingLimitLeft, 3_000)
        XCTAssertLessThanOrEqual(e.shoppingAvailable, 3_000)
        XCTAssertTrue(e.insights.contains { $0.id.hasPrefix("shop-80-") })
        s.entries.append(Entry(date: Date(), name: "JB Hi-Fi", amount: 5_000, kind: .expense, category: .shopping, accountID: s.accounts[1].id))
        e = Engine(state: s)
        XCTAssertTrue(e.insights.contains { $0.id.hasPrefix("shop-over-") })
        // Spending goal money is allowed, with a warning.
        s.goals = [Goal(name: "3D printer", target: 100_000, reserved: 90_000, weekly: 0)]
        XCTAssertGreaterThan(Engine(state: s).goalMoneyUsed, 0)
        XCTAssertTrue(Engine(state: s).insights.contains { $0.id.hasPrefix("goal-money-") })
    }
    func testFixItReleasesGoalsThenCutsExtrasBeforeGroceries() {
        var s = fourAccounts()
        s.budgets = Category.allCases.map { Budget(category: $0, limit: [.groceries: 15_000, .fuel: 5_000, .takeaway: 4_000, .entertainment: 2_000][$0] ?? 0) }
        s.goals = [Goal(name: "3D printer", target: 60_000, reserved: 10_000, weekly: 0)]
        s.savings = 100_000; s.accounts[1].openingBalance = 0 // Set-aside money matches the accounts; Shopping is empty, so the plan is over.
        let e = Engine(state: s)
        let over = -e.unallocated
        XCTAssertGreaterThan(over, 10_000 + 6_000) // More than goals + takeaway + entertainment
        let plan = e.fixPlan!
        XCTAssertEqual(plan.releaseGoals, 10_000)
        XCTAssertEqual(plan.cuts.filter { [.takeaway, .entertainment].contains($0.category) }.reduce(0) { $0 + $1.amount }, 6_000)
        XCTAssertTrue(plan.cuts.contains { $0.category == .groceries })
        XCTAssertFalse(plan.cuts.contains { $0.category == .bills || $0.category == .subscriptions })
        var fixed = s; fixed.apply(plan)
        XCTAssertEqual(Engine(state: fixed).unallocated, -plan.stillShort)
        XCTAssertEqual(fixed.savings, s.savings) // Never touched.
    }
    func testFeedRefreshOncePerDayAndOldLinksStillLoad() throws {
        let old = try JSONDecoder().decode(PocketSmithLink.self, from: Data(#"{"accountMap":{},"seen":[],"balances":{},"wageKeyword":"","allowanceKeyword":""}"#.utf8))
        XCTAssertFalse(old.feedRefreshDue(hasLogin: true)) // Off until you turn it on.
        var link = old; link.autoRefresh = true
        XCTAssertTrue(link.feedRefreshDue(hasLogin: true))
        XCTAssertFalse(link.feedRefreshDue(hasLogin: false))
        link.feedsRefreshed = Date().addingTimeInterval(-3_600)
        XCTAssertFalse(link.feedRefreshDue(hasLogin: true))
        link.feedsRefreshed = Date().addingTimeInterval(-21 * 3_600)
        XCTAssertTrue(link.feedRefreshDue(hasLogin: true))
    }
    func testPendingCountsUntilPostedWithoutDoubleCounting() {
        var s = linked()
        let start = Engine(state: s).accountBalance(s.accounts[0].id)
        XCTAssertEqual(s.importPocketSmith([tx(7, "Coles", -40, 11, status: "pending"), tx(8, "Refund", 5, 22, status: "pending")]), 0)
        XCTAssertEqual(Engine(state: s).accountBalance(s.accounts[0].id), start - 4_000)
        XCTAssertEqual(Engine(state: s).pending(s.accounts[1].id), 500)
        XCTAssertEqual(Engine(state: s).line(.groceries).spent, 0) // Not an entry yet.
        XCTAssertEqual(s.importPocketSmith([tx(7, "Coles", -40, 11)]), 1) // Posts: becomes an entry, pending clears.
        XCTAssertEqual(Engine(state: s).accountBalance(s.accounts[0].id), start - 4_000)
        XCTAssertEqual(Engine(state: s).pending(s.accounts[1].id), 0)
    }
    func testBuyAveragesSellKeepsCashAtStakeAndCountsBrokerage() throws {
        var s = base(); s.holdings = []; s.stakeCashUSD = 300_000; s.settings.audPerUSD = 1.5
        try s.buy("VOO", shares: 10, priceUSD: 10_000, brokerageUSD: stakeBrokerageUSD, fromCash: true)
        try s.buy("VOO", shares: 10, priceUSD: 12_000, brokerageUSD: stakeBrokerageUSD, fromCash: false)
        XCTAssertEqual(s.holdings.count, 1) // Same stock combines.
        XCTAssertEqual(s.holdings[0].costUSD, 220_600)
        XCTAssertEqual(s.holdings[0].averagePriceUSD, 11_030)
        XCTAssertEqual(s.stakeCashUSD, 300_000 - 100_300)
        let id = s.holdings[0].id
        try s.sell(id, shares: 5, priceUSD: 15_000, brokerageUSD: stakeBrokerageUSD)
        XCTAssertEqual(s.stakeCashUSD, 199_700 + 74_700) // Sale money stays at Stake.
        XCTAssertEqual(s.holdings[0].realisedUSD, 74_700 - 55_150)
        XCTAssertEqual(s.holdings[0].shares, 15); XCTAssertEqual(s.holdings[0].costUSD, 165_450)
        // Price now $150: 15 × 150 = 2,250 value on 1,654.50 cost, plus 195.50 already made.
        XCTAssertEqual(s.holdings[0].profitUSD, 225_000 - 165_450 + 19_550)
        XCTAssertEqual(s.holdings[0].profitAUD(1.5), s.holdings[0].profitUSD * 3 / 2) // Rate unchanged, so AUD = USD × 1.5.
        XCTAssertThrowsError(try s.sell(id, shares: 16, priceUSD: 15_000, brokerageUSD: 0))
        try s.sell(id, shares: 15, priceUSD: 15_000, brokerageUSD: stakeBrokerageUSD)
        XCTAssertEqual(s.holdings[0].shares, 0); XCTAssertEqual(s.holdings[0].costUSD, 0)
        XCTAssertEqual(s.holdings[0].profitUSD, 74_700 + 224_700 - 220_600) // Sold out: both sales' money less everything paid.
        XCTAssertEqual(Engine(state: s).portfolioProfitUSD, s.holdings[0].profitUSD)
        XCTAssertThrowsError(try s.buy("AAPL", shares: 1_000, priceUSD: 20_000, brokerageUSD: 300, fromCash: true))
    }
    func testStakeFXFeesAndMoneyInAndOut() throws {
        var s = base(); s.holdings = []; s.stakeCashUSD = 0; s.settings.audPerUSD = 1.5
        XCTAssertEqual(s.usdBought(aud: 150_000), 99_450)  // A$1,500 less 0.55% = A$1,491.75 → US$994.50
        XCTAssertEqual(s.audBack(usd: 99_450), 148_355)    // Straight back: A$1,483.55, the fee charged twice
        // Deposit A$1,500 with no USD typed: estimated after the fee.
        s.entries.append(Entry(date: Date(), name: "Stake deposit", amount: 150_000, kind: .investment, category: .other, accountID: s.accounts[0].id, destinationID: nil))
        s.entries[s.entries.count - 1].usd = try s.applyEffects(.investment, amount: 150_000)
        XCTAssertEqual(s.stakeCashUSD, 99_450)
        // Withdraw: A$500 reaches the bank; the USD that left Stake includes the fee.
        s.entries.append(Entry(date: Date(), name: "Stake withdrawal", amount: 50_000, kind: .fromStake, category: .other, accountID: s.accounts[0].id, destinationID: nil))
        s.entries[s.entries.count - 1].usd = try s.applyEffects(.fromStake, amount: 50_000)
        XCTAssertEqual(s.stakeCashUSD, 99_450 - 33_518)
        let m = Engine(state: s).stakeMoney
        XCTAssertEqual(m.sentAUD, 150_000); XCTAssertEqual(m.backAUD, 50_000)
        XCTAssertEqual(m.feesAUD, 825 + 277)
        // Deleting the withdrawal puts its USD back at Stake.
        try s.deleteEntry(s.entries.last!.id)
        XCTAssertEqual(s.stakeCashUSD, 99_450)
        // A withdrawal is never mistaken for pay.
        XCTAssertFalse(EntryKind.fromStake.income)
    }
    func testBankedProfitOnlyCountsWithdrawnMoney() throws {
        var s = base(); s.holdings = []; s.stakeCashUSD = 0; s.settings.audPerUSD = 1.5
        func add(_ kind: EntryKind, _ aud: Money, usd: Money) throws {
            let cost = kind == .fromStake ? s.withdrawalCost(usd: usd) : nil
            s.entries.append(Entry(date: Date(), name: "Stake", amount: aud, kind: kind, category: .other, accountID: s.accounts[0].id, destinationID: nil))
            s.entries[s.entries.count - 1].usd = try s.applyEffects(kind, amount: aud, usd: usd)
            s.entries[s.entries.count - 1].costAUD = cost
        }
        try add(.investment, 100_000, usd: 66_300)  // A$1,000 in
        s.stakeCashUSD = 80_000                      // Grew to US$800 (sold at a profit)
        // Shares still held don't change what the cash cost, whatever their price.
        s.holdings = [Holding(symbol: "VOO", shares: 1, costUSD: 10_000, priceUSD: 10_000, updated: Date(), costAUD: 15_000)]
        s.entries[0].amount += 15_000 // That share was bought with another A$150 sent.
        let cost = s.withdrawalCost(usd: 40_000)
        s.holdings[0].priceUSD = 90_000
        XCTAssertEqual(s.withdrawalCost(usd: 40_000), cost)
        s.holdings = []; s.entries[0].amount -= 15_000
        var m = Engine(state: s).stakeMoney
        XCTAssertEqual(m.insideAUD, 120_000 - 100_000); XCTAssertEqual(m.bankedAUD, 0) // Gain is on paper only.
        try add(.fromStake, 59_670, usd: 40_000)     // Take half out: A$596.70 reaches the bank
        m = Engine(state: s).stakeMoney
        XCTAssertEqual(s.entries.last?.costAUD, 50_000) // Half the pot cost half the A$1,000.
        XCTAssertEqual(m.bankedAUD, 9_670)
        XCTAssertEqual(m.basisAUD, 50_000); XCTAssertEqual(m.insideAUD, 60_000 - 50_000)
        try add(.fromStake, 59_670, usd: 40_000)     // The rest
        m = Engine(state: s).stakeMoney
        XCTAssertEqual(m.bankedAUD, 19_340); XCTAssertEqual(m.insideAUD, 0); XCTAssertEqual(m.basisAUD, 0)
    }
    func testStakeCashFollowsHistoryAndCanBeCorrected() throws {
        var s = base(); s.holdings = []; s.stakeCashUSD = 0; s.settings.audPerUSD = 1.5; s.investmentReserve = 300_000
        func deposit(_ aud: Money, usd: Money = 0) throws -> UUID {
            s.entries.append(Entry(date: Date(), name: "Stake deposit", amount: aud, kind: .investment, category: .other, accountID: s.accounts[0].id, destinationID: nil))
            s.entries[s.entries.count - 1].usd = try s.applyEffects(.investment, amount: aud, usd: usd, entry: s.entries.count - 1)
            return s.entries[s.entries.count - 1].id
        }
        let typed = try deposit(150_000, usd: 99_000)  // Real USD from Stake
        let guessed = try deposit(30_000)              // Estimated
        XCTAssertEqual(Engine(state: s).stakeCheck.estimated.map(\.id), [guessed])
        try s.buy("VOO", shares: 1, priceUSD: 50_000, brokerageUSD: 300, fromCash: true)
        try s.sell(s.holdings[0].id, shares: 1, priceUSD: 60_000, brokerageUSD: 300)
        var c = Engine(state: s).stakeCheck
        XCTAssertEqual(c.history, s.stakeCashUSD) // Deposits − shares bought + shares sold = Stake cash.
        // Entering the real USD on the estimated deposit moves Stake cash by the difference, and history still agrees.
        try s.setStakeUSD(guessed, usd: 19_000)
        XCTAssertEqual(Engine(state: s).stakeCheck.history, s.stakeCashUSD)
        XCTAssertTrue(Engine(state: s).stakeCheck.estimated.isEmpty)
        // Deleting a deposit takes its USD out of Stake cash as well as restoring investing money.
        let cash = s.stakeCashUSD
        try s.deleteEntry(typed)
        XCTAssertEqual(s.stakeCashUSD, cash - 99_000)
        XCTAssertEqual(Engine(state: s).stakeCheck.history, s.stakeCashUSD)
        // The Stake app shows US$12 more (a dividend): correcting matches both.
        s.correctStakeCash(to: s.stakeCashUSD + 1_200)
        c = Engine(state: s).stakeCheck
        XCTAssertEqual(c.history, s.stakeCashUSD); XCTAssertEqual(c.corrections, 1_200)
        // Moving a deposit back to spending also removes its USD.
        let before = s.stakeCashUSD
        let i = s.entries.firstIndex { $0.id == guessed }!
        s.fileAsSpending(i)
        XCTAssertEqual(s.stakeCashUSD, before - 19_000)
    }
    func testOverBudgetOnlyCountsWhatsRealAndExplainsItself() {
        var s = FinanceState()
        s.accounts = [Account(name: "Everyday", openingBalance: 49_300), Account(name: "Savings", openingBalance: 10_000)]
        s.budgets = Category.allCases.map { Budget(category: $0, limit: [.groceries: 25_000, .fuel: 12_000, .takeaway: 9_200, .entertainment: 4_700, .other: 6_000][$0] ?? 0) } // $569
        s.settings.expectedWages = 100_000; s.settings.nextPayday = day(5)
        s.savings = 34_691 // Set aside by the rule, but only $100 reached the Savings account.
        s.plans = [AfterpayPlan(name: "Shoes", purchased: day(-8), installments: [20, 34, 48].map { Installment(due: day($0), amount: 8_230) })]
        let e = Engine(state: s)
        XCTAssertEqual(e.afterpayDebt, 24_690)
        XCTAssertEqual(e.afterpayDueBeforePay, 0) // All due after payday: later pays cover them.
        XCTAssertEqual(e.unallocated, 59_300 - 34_691 - 56_900)
        XCTAssertEqual(e.cashBreakdown.reduce(0) { $0 + $1.amount }, e.unallocated) // The working adds up to what it says.
        let plan = e.fixPlan!
        XCTAssertEqual(plan.savingsTo, 10_000) // Matched to what Savings really holds.
        XCTAssertEqual(plan.releaseGoals, 0)
        XCTAssertEqual(plan.cuts.reduce(0) { $0 + $1.amount }, 7_600) // Really over by $76: $569 of budgets, $493 of spendable cash
        var fixed = s; fixed.apply(plan)
        XCTAssertEqual(Engine(state: fixed).unallocated, 0)
        XCTAssertFalse(plan.cuts.contains { $0.category == .groceries || $0.category == .fuel }) // Extras gave way first.
    }
    func testEveryStockDepositCountsAndCanBeCorrected() throws {
        var s = base(); s.holdings = []; s.stakeCashUSD = 0; s.settings.audPerUSD = 1.45; s.investmentReserve = 200_000
        let names = ["APPLE PAY HELLOSTAKE AU", "Stake deposit", "Transfer 4421"]
        for (name, aud) in zip(names, [100_000, 35_000, 32_400] as [Money]) {
            s.entries.append(Entry(date: Date(), name: name, amount: aud, kind: .expense, category: .other, accountID: s.accounts[0].id, destinationID: nil))
            s.fileAsStockDeposit(s.entries.count - 1)
        }
        // Old MK3.3 behaviour: a deposit whose description didn't say "stake" and had no USD was left out.
        s.entries[0].name = "APPLE PAY ST*KE"; s.entries[0].usd = nil; s.stakeCashUSD -= s.usdBought(aud: 100_000)
        XCTAssertEqual(Engine(state: s).stakeMoney.sentAUD, 167_400) // All three count now.
        // The real USD from Stake: A$1,000 → US$682.64 (never added to cash before), A$350 → US$243.42.
        try s.setStakeUSD(s.entries[0].id, usd: 68_264)
        try s.setStakeUSD(s.entries[1].id, usd: 24_342)
        // A$324 wasn't a Stake deposit.
        s.fileAsSpending(2)
        let m = Engine(state: s).stakeMoney
        XCTAssertEqual(m.sentAUD, 135_000)
        XCTAssertEqual(s.stakeCashUSD, 68_264 + 24_342)
        XCTAssertEqual(Engine(state: s).stakeCheck.history, s.stakeCashUSD)
        XCTAssertEqual(m.basisAUD, 135_000) // "Put in" is A$1,350, not A$674.
    }
    func testTransfersCanBeSkippedOrMadeForADifferentAmount() {
        var s = fourAccounts()
        let plan = Engine(state: s).moneyPlan!
        XCTAssertEqual(plan.transfers.count, 3) // Shopping → Everyday, → Savings, → Stake
        let everyday = plan.transfers[0], stake = plan.transfers[2]
        XCTAssertNil(stake.to)
        // Sent $300 instead of $370 to Everyday, skipped Savings and Stake.
        let made = [MoneyPlan.Transfer(from: everyday.from, to: everyday.to, amount: 30_000)]
        s.confirmTransfers(planned: plan.transfers, made: made, nextPay: plan.nextPay)
        XCTAssertEqual(s.entries.filter { $0.kind == .transfer }.map(\.amount), [30_000])
        XCTAssertTrue(Engine(state: s).moneyPlan!.transfers.isEmpty) // Nothing nags again until next payday.
        XCTAssertEqual(s.investmentReserve, 30_000) // Skipping Stake doesn't cancel the money waiting for it.
        // Next payday the suggestions come back.
        var later = s; later.skippedTransfers = later.skippedTransfers?.map { $0.replacingOccurrences(of: "@\(Int(plan.nextPay.timeIntervalSince1970))", with: "@0") }
        XCTAssertFalse(Engine(state: later).moneyPlan!.transfers.isEmpty)
    }
    // MARK: MK3.6 audit: each of these failed before the fix
    func testWeeklyBudgetsRollForwardKeepingTheirDay() {
        var s = base(); s.settings.budgetPeriod = "week"
        s.periodStart = Calendar.current.startOfDay(for: day(-10))
        XCTAssertEqual(s.newPeriodStart, Calendar.current.startOfDay(for: day(-3))) // Same weekday, the week containing today.
    }
    func testEverydayOnlyAsksForWhatsLeftOfABudget() {
        var s = fourAccounts(); s.settings.budgetPeriod = "fortnight"; s.settings.nextPayday = day(4)
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .groceries ? 30_000 : 0) }
        s.periodStart = s.start(of: .fortnight)
        s.entries.append(Entry(date: Date(), name: "Coles", amount: 28_000, kind: .expense, category: .groceries, accountID: s.accounts[0].id))
        XCTAssertEqual(Engine(state: s).moneyPlan!.needs.first { $0.name == "Groceries" }?.amount, 2_000 * 105 / 100) // $20 left, not 4/14 of $300 again.
    }
    func testAfterpayInsideABudgetIsNeededOnce() {
        var s = fourAccounts(); s.settings.budgetPeriod = "fortnight"; s.settings.nextPayday = day(14)
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .entertainment ? 20_000 : 0) }
        s.periodStart = s.start(of: .fortnight)
        s.plans = [AfterpayPlan(name: "Concert", category: .entertainment, purchased: day(-12), installments: [Installment(due: day(-12), amount: 10_000, paidOn: day(-12)), Installment(due: day(2), amount: 10_000)])]
        let needs = Engine(state: s).moneyPlan!.needs
        // $200 entertainment budget: $100 of it is this instalment, $100 is for other outings.
        XCTAssertEqual(needs.first { $0.name == "Entertainment" }?.amount, 10_500)
        XCTAssertEqual(needs.first { $0.name == "Afterpay" }?.amount, 10_000)
    }
    func testSuggestedBudgetsGiveShoppingNothing() {
        var s = base(); s.settings.expectedWages = 100_000
        let e = Engine(state: s), suggested = e.suggestedBudgets()
        XCTAssertEqual(suggested.first { $0.category == .shopping }?.limit, 0)
        XCTAssertEqual(suggested.filter { $0.category != .shopping }.reduce(0) { $0 + $1.limit }, e.allocation(e.expectedPeriodIncome).spending)
    }
    func testForecastIgnoresTheOldShoppingBudget() {
        var s = base(); s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .shopping ? 70_000 : 0) }
        let f = Engine(state: s).forecast(days: 3)
        XCTAssertEqual(f[1].balance, f[0].balance) // Shopping is spare money, not daily spending.
    }
    func testPaceIgnoresAfterpayInstalments() {
        var s = base(); s.periodStart = Calendar.current.startOfDay(for: day(-2)) // Entertainment $300 a week.
        s.plans = [AfterpayPlan(name: "Tickets", category: .entertainment, purchased: day(-1), installments: [Installment(due: day(-1), amount: 15_000, paidOn: day(-1))])]
        XCTAssertFalse(ids(s).contains { $0.hasPrefix("pace-") }) // One $150 instalment isn't a spending rate.
    }
    func testAfterpayPaymentFromBeforeThePlanIsLinked() throws {
        var s = linked()
        XCTAssertEqual(s.importPocketSmith([tx(30, "AFTERPAY AU", -25, 11)]), 1)
        XCTAssertEqual(s.entries.last?.needsReview, true) // No plan to match yet.
        try s.addPlan(name: "Jacket", total: 10_000, firstDue: Date(), category: .shopping)
        XCTAssertEqual(s.entries.last?.kind, .repayment)
        XCTAssertEqual(s.plans[0].outstanding, 7_500) // Not owed twice.
        // A payment a few cents off (rounding) still matches the next instalment when it syncs.
        XCTAssertEqual(s.importPocketSmith([tx(31, "AFTERPAY AU", -25.03, 11)]), 1)
        XCTAssertEqual(s.plans[0].outstanding, 5_000)
        XCTAssertFalse(s.entries.contains { $0.needsReview == true })
    }
    func testTimeOffSkipsWagesAndCountsAllowance() {
        var s = fourAccounts(); s.settings.budgetPeriod = "fortnight"; s.settings.nextPayday = day(3)
        s.settings.expectedAllowance = 50_000; s.settings.allowanceDay = Calendar.current.component(.day, from: day(10))
        s.periodStart = s.start(of: .fortnight)
        s.settings.timeOff = [TimeOff(from: day(1), to: day(20))] // Paydays on day 3 and day 17 pay nothing.
        let e = Engine(state: s)
        XCTAssertEqual(e.nextPayDate, Calendar.current.startOfDay(for: day(31)))
        XCTAssertFalse(e.upcoming(days: 20).contains { $0.id == "pay" })
        XCTAssertNil(e.pendingPay)
        XCTAssertEqual(e.moneyPlan!.needs.first { $0.name == "Allowance before then" }?.amount, -50_000)
        XCTAssertTrue(e.insights.contains { $0.id.hasPrefix("time-off-") })
        // The forecast adds no wages during time off.
        let f = e.forecast(days: 20)
        XCTAssertFalse(zip(f, f.dropFirst()).contains { $0.1.balance - $0.0.balance >= 140_000 - 10_000 })
    }
    func testPayBeforeTimeOffCoversTheBreakBeforeSavings() throws {
        var s = fourAccounts(); s.settings.budgetPeriod = "fortnight"; s.settings.nextPayday = day(0)
        s.budgets = Category.allCases.map { Budget(category: $0, limit: $0 == .groceries ? 30_000 : 0) } // $300 a fortnight
        s.periodStart = s.start(of: .fortnight)
        s.accounts[0].openingBalance = 0; s.accounts[1].openingBalance = 0
        s.emergency = 50_000; s.savings = 100_000; s.investmentReserve = 0
        var working = s
        s.settings.timeOff = [TimeOff(from: day(1), to: day(30))] // The paydays on day 14 and 28 pay nothing; next pay day 42.
        for i in [0, 1] {
            var t = i == 0 ? working : s
            t.entries.append(Entry(date: Date(), name: "Wages", amount: 100_000, kind: .wage, category: .other, accountID: t.accounts[0].id))
            try t.applyEffects(.wage, amount: 100_000, entry: t.entries.count - 1)
            if i == 0 { working = t } else { s = t }
        }
        XCTAssertNil(working.entries.last?.cut) // A normal fortnight: $300 kept covers $300 of groceries.
        // Before six weeks off: $900 of groceries; $300 kept, so savings and investing give up $600.
        XCTAssertEqual(s.entries.last?.cut, 60_000)
    }
    func testMatchingPocketSmithBalanceKeepsPendingOff() {
        var s = linked()
        _ = s.importPocketSmith([tx(40, "Coles", -40, 11, status: "pending")], historical: true)
        s.matchBalances(["11": 100_000]) // PocketSmith's balance doesn't include the pending $40.
        XCTAssertEqual(Engine(state: s).accountBalance(s.accounts[0].id), 96_000)
        s.pocketsmith?.balances["11"] = 100_000
        XCTAssertTrue(Engine(state: s).drifted.isEmpty) // Already matches once pending is counted.
    }
    #if canImport(CryptoKit) // Runs in Xcode; the Linux check has no CryptoKit.
    func testBackupLocksKeysWithThePasswordAndReadsOldBackups() throws {
        let sealed = try FullBackup.seal(["password": "hunter2", "developer-key": "abc"], password: "correct horse")
        XCTAssertFalse(String(decoding: sealed.box, as: UTF8.self).contains("hunter2")) // Not readable in the file.
        XCTAssertEqual(try FullBackup.open(sealed, password: "correct horse")["password"], "hunter2")
        XCTAssertThrowsError(try FullBackup.open(sealed, password: "wrong"))
        var full = FullBackup(state: base()); full.secrets = sealed
        let back = try FullBackup.read(JSONEncoder().encode(full))
        XCTAssertEqual(back.state.accounts.count, 2); XCTAssertNotNil(back.secrets)
        let old = try FullBackup.read(JSONEncoder().encode(base())) // A plain backup from before MK4.0
        XCTAssertEqual(old.state.accounts.count, 2); XCTAssertNil(old.secrets)
    }
    #endif
    func testDashboardNumbersAreFastWithAYearOfTransactions() {
        var s = fourAccounts(); s.settings.budgetPeriod = "fortnight"; s.periodStart = s.start(of: .fortnight)
        s.budgets = Category.allCases.map { Budget(category: $0, limit: 20_000) }
        let cats = Category.allCases
        for i in 0..<2_000 {
            s.entries.append(Entry(date: day(-i * 365 / 2_000), name: "Shop \(i % 40)", amount: Money(1_000 + i % 5_000), kind: .expense, category: cats[i % cats.count], accountID: s.accounts[i % 2].id))
        }
        s.plans = (0..<5).map { k in AfterpayPlan(name: "P\(k)", purchased: day(-k), installments: (0..<4).map { Installment(due: day($0 * 14 - k), amount: 2_500) }) }
        let start = Date(), e = Engine(state: s)
        // One redraw of the home screen asks for these many times over; 20 rounds is a few redraws.
        for _ in 0..<20 { _ = e.insights; _ = e.moneyPlan; _ = e.spareMoney; _ = e.lines; _ = e.unallocated; _ = e.bankCash; _ = e.takeawayLeft; _ = e.score }
        let seconds = Date().timeIntervalSince(start)
        print("Dashboard x20 with 2,000 transactions: \(String(format: "%.2f", seconds)) s")
        XCTAssertLessThan(seconds, 1.0)
    }
}
