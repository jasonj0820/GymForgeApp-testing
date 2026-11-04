import Foundation
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
import UIKit
import CryptoKit
import CommonCrypto

@MainActor final class Store: ObservableObject {
    @Published var state = FinanceState() { didSet { version += 1 } }
    @Published var error: String?
    @Published var notice: String?
    private var loadFailed = false
    private var refreshing = false
    private var refreshAgain = false
    private let url: URL
    /// MK4.1: one Engine per version of your data (it remembers its answers); a fresh one after a minute, for the date.
    private var cachedEngine: Engine?
    var engine: Engine {
        if let e = cachedEngine, e.version == version, Date().timeIntervalSince(e.made) < 60 { return e }
        let e = Engine(state: state); e.version = version; cachedEngine = e; return e
    }
    private var version = 0
    init() {
        url = URL.documentsDirectory.appending(path: "MoneyPilot-v1.json")
        load()
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { state = try JSONDecoder().decode(FinanceState.self, from: Data(contentsOf: url)); state.migrate(); loadFailed = false; error = nil }
        catch {
            loadFailed = true
            // A background launch while the phone is locked cannot read the file yet; reloadIfNeeded tries again on unlock.
            if !isLocked { self.error = "Could not read saved data. Your file has not been overwritten. \(error.localizedDescription)" }
        }
    }
    private var isLocked: Bool { !UIApplication.shared.isProtectedDataAvailable }
    func reloadIfNeeded() { if loadFailed { load() } }
    /// Replaces everything with a backup the person chose, even when the saved file could not be read.
    func restore(_ backup: FinanceState) {
        var restored = backup; restored.migrate()
        loadFailed = false; error = nil
        change { $0 = restored }
        if error == nil { notice = "Backup restored: \(restored.entries.count) transactions." }
    }
    private static let saveQueue = DispatchQueue(label: "MoneyPilot.save", qos: .userInitiated)
    func change(_ action: (inout FinanceState) throws -> Void) {
        guard !loadFailed else { error = "Saved data could not be loaded. Recover the JSON file using Xcode’s device container before continuing."; return }
        var next = state
        do {
            try action(&next)
            let e = Engine(state: next)
            let point = HistoryPoint(date: Date(), assets: e.assets, netWorth: e.netWorth, emergency: next.emergency, investments: e.investmentsAUD)
            if let i = next.history.lastIndex(where: { Calendar.current.isDateInToday($0.date) }) { next.history[i] = point } else { next.history.append(point) }
            state = next
            // MK4.1: the file is written in the background, in order, so taps don't wait for it.
            let snapshot = next, url = self.url
            Store.saveQueue.async {
                do { try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                catch { DispatchQueue.main.async { self.error = "Couldn't save your last change: \(error.localizedDescription)" } }
            }
            Task {
                await refreshNotifications()
            }
        } catch { self.error = error.localizedDescription }
    }
    func addEntry(name: String, amount: Money, kind: EntryKind, category: Category, account: UUID, destination: UUID?, date: Date, usdReceived: Money = 0) {
        change { s in
            guard amount > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw AppError.invalid("Enter a description and an amount greater than zero.") }
            guard date <= Date() else { throw AppError.invalid("Record received or paid transactions only. Future income belongs in Settings.") }
            if kind == .transfer && (destination == nil || destination == account) { throw AppError.invalid("Choose a different destination account.") }
            s.entries.append(Entry(date: date, name: name, amount: amount, kind: kind, category: category, accountID: account, destinationID: destination))
            let cost = kind == .fromStake ? s.withdrawalCost(usd: usdReceived > 0 ? usdReceived : s.usdSold(aud: amount)) : nil
            let usd = try s.applyEffects(kind, amount: amount, usd: usdReceived, entry: s.entries.count - 1)
            if usd > 0 { s.entries[s.entries.count - 1].usd = usd }
            s.entries[s.entries.count - 1].costAUD = cost
        }
    }
    /// `similar` also refiles past and future transactions from the same merchant.
    func recategorise(_ id: UUID, category: Category, similar: Bool) {
        change { s in
            guard let i = s.entries.firstIndex(where: { $0.id == id }) else { return }
            s.entries[i].category = category
            if similar { s.categoriseSimilar(to: s.entries[i].name, as: category) }
        }
    }
    func split(_ id: UUID, amount: Money, category: Category) {
        change { s in
            guard let i = s.entries.firstIndex(where: { $0.id == id }), s.entries[i].kind == .expense,
                  amount > 0, amount < s.entries[i].amount else { throw AppError.invalid("Split amount must be less than the original expense.") }
            var part = s.entries[i]; part.id = UUID(); part.amount = amount; part.category = category
            s.entries[i].amount -= amount; s.entries.append(part)
        }
    }
    func createPlan(name: String, total: Money, firstDue: Date, category: Category, alreadyPaid: Int = 0) {
        change { try $0.addPlan(name: name, total: total, firstDue: firstDue, category: category, alreadyPaid: alreadyPaid) }
    }
    /// MK3.6: an imported Afterpay payment you link to an instalment yourself (from Activity → review).
    func linkAfterpay(_ entryID: UUID, planID: UUID, installmentID: UUID) {
        change { s in
            guard let p = s.plans.firstIndex(where: { $0.id == planID }), let k = s.plans[p].installments.firstIndex(where: { $0.id == installmentID }) else { return }
            s.linkAfterpay(entryID: entryID, plan: p, installment: k)
        }
    }
    func pay(planID: UUID, installmentID: UUID, account: UUID) {
        change { s in
            guard let p = s.plans.firstIndex(where: { $0.id == planID }), let i = s.plans[p].installments.firstIndex(where: { $0.id == installmentID }), s.plans[p].installments[i].paidOn == nil else { return }
            let amount = s.plans[p].installments[i].amount
            s.plans[p].installments[i].paidOn = Date()
            s.entries.append(Entry(date: Date(), name: "Afterpay · \(s.plans[p].name)", amount: amount, kind: .repayment, category: s.plans[p].category, accountID: account, installmentID: s.plans[p].installments[i].id))
        }
    }
    func allocateGoal(_ id: UUID, amount: Money) {
        change { s in
            guard let i = s.goals.firstIndex(where: { $0.id == id }) else { return }
            guard amount > 0, amount <= Engine(state: s).shoppingAvailable, amount <= s.goals[i].target - s.goals[i].reserved else { throw AppError.invalid("This exceeds your available shopping money or the goal’s remaining target.") }
            s.goals[i].reserved += amount
        }
    }
    func buyGoal(_ id: UUID, account: UUID) {
        change { s in
            guard let i = s.goals.firstIndex(where: { $0.id == id }), s.goals[i].reserved >= s.goals[i].target else { throw AppError.invalid("Fully fund this goal first.") }
            let g = s.goals.remove(at: i)
            s.entries.append(Entry(date: Date(), name: g.name, amount: g.target, kind: .expense, category: .shopping, accountID: account))
        }
    }
    func redirect(_ amount: Money, to target: String) {
        change { s in
            guard amount > 0, amount <= max(0, Engine(state: s).unallocated) else { throw AppError.invalid("Only unallocated cash can be redirected here.") }
            switch target { case "emergency": s.emergency += amount; case "savings": s.savings += amount; case "invest": s.investmentReserve += amount; default: s.shoppingCarry += amount }
        }
    }
    /// Pull down: work everything out again from the numbers already in MoneyPilot. Never contacts PocketSmith.
    func recalculate() {
        if Date() >= state.periodEnd { closePeriod() } // Weekly budgets roll too (MK3.6).
        objectWillChange.send()
    }
    func closePeriod() {
        change { s in
            guard Date() >= s.periodEnd else { throw AppError.invalid("This period has not ended yet.") }
            let e = Engine(state: s)
            // Unspent budget: 30% stays in Everyday as a buffer; the other 70% goes to spare money with the next transfers.
            let unspent = min(max(0, e.unreservedCash), e.lines.reduce(Money(0)) { $0 + max(0, $1.remaining) })
            s.everydayBuffer = unspent * 30 / 100
            s.shoppingCarry = 0
            s.periodStart = s.newPeriodStart
            s.notified = []
        }
        notice = "New \(engine.periodName) opened. 30% of what you didn't spend stays in Everyday as a buffer; the rest goes to spare money."
    }
    // MARK: PocketSmith
    @Published var syncing = false
    /// MK4.1: what the PocketSmith sign-in is doing, shown as a banner at the top of the app (it used to be a Live Activity).
    @Published var activity: String?
    static let historyDays = 120
    func linkPocketSmith(key: String, choices: [UUID: Int], accounts: [PSAccount], wage: String, allowance: String) async {
        guard !choices.isEmpty, Set(choices.values).count == choices.count else { error = "Choose a different PocketSmith account for each MoneyPilot account you want to sync."; return }
        guard Keychain.save(key) else { error = "Could not store the developer key in the iPhone Keychain."; return }
        change { s in
            if s.demo {
                // Real bank data must not mix with demo examples. Keep account IDs so the chosen matches still apply.
                var fresh = FinanceState()
                fresh.accounts = s.accounts.map { Account(id: $0.id, name: $0.name, openingBalance: 0) }
                s = fresh
            }
            var link = PocketSmithLink(wageKeyword: wage, allowanceKeyword: allowance)
            for (mine, theirs) in choices { link.accountMap[String(theirs)] = mine }
            s.pocketsmith = link
            s.recordAccounts(accounts)
        }
        await importHistory()
        if error == nil { notice = "PocketSmith linked. The last \(Self.historyDays) days of transactions are in Activity, and balances match PocketSmith. MoneyPilot now checks for new transactions automatically." }
    }
    /// Imports past transactions that are not in MoneyPilot yet, then matches balances to PocketSmith.
    func importHistory() async {
        guard state.pocketsmith != nil, let key = Keychain.read() else { return }
        syncing = true; defer { syncing = false }
        do {
            let client = PocketSmithClient(key: key)
            let from = Calendar.current.date(byAdding: .day, value: -Self.historyDays, to: Date())!
            var transactions: [PSTransaction] = []
            for id in (state.pocketsmith?.accountMap ?? [:]).keys.compactMap(Int.init) { transactions += try await client.transactions(account: id, from: from) }
            let accounts = try await client.accounts()
            change { s in
                // Only transactions that became entries count as done; MK1.2 skipped the 30 days before linking.
                s.pocketsmith?.seen = Set(s.entries.compactMap(\.externalID) + s.entries.compactMap(\.pairedID))
                _ = s.importPocketSmith(transactions, historical: true)
                s.recordAccounts(accounts)
                s.matchBalances(s.pocketsmith?.balances ?? [:])
                s.pocketsmith?.lastSync = Date()
            }
        } catch { report(error) }
    }
    func syncPocketSmith() async {
        guard let link = state.pocketsmith, !syncing else { return }
        guard let key = Keychain.read() else { error = "The PocketSmith developer key is missing. Disconnect and link again."; return }
        syncing = true; defer { syncing = false }
        do {
            let client = PocketSmithClient(key: key)
            // Overlap the last sync by two weeks to catch late-posting transactions; seen IDs prevent duplicates.
            let from = Calendar.current.date(byAdding: .day, value: -14, to: link.lastSync ?? Date())!
            var transactions: [PSTransaction] = []
            for id in link.accountMap.keys.compactMap(Int.init) { transactions += try await client.transactions(account: id, from: from) }
            let accounts = try await client.accounts()
            var added = 0
            change { s in
                added = s.importPocketSmith(transactions)
                if s.settings.autoOrganise != false { s.organise() }
                s.recordAccounts(accounts)
                s.pocketsmith?.lastSync = Date()
            }
            if added > 0 && state.entries.contains(where: { $0.needsReview == true }) { notice = "\(added) bank transactions imported. Some need a quick review in Activity." }
        } catch { report(error) }
    }
    /// Links a PocketSmith account found at a check, either to an existing MoneyPilot account or as a new one.
    func linkAccount(_ pocketsmithID: String, to account: UUID?) async {
        change { s in
            guard s.pocketsmith != nil else { return }
            let id = account ?? UUID()
            if account == nil { s.accounts.append(Account(id: id, name: s.pocketsmith?.known?[pocketsmithID] ?? "New account", openingBalance: 0)) }
            s.pocketsmith?.accountMap[pocketsmithID] = id
        }
        await importHistory()
    }
    /// Runs from iOS background refresh. Failures stay silent; the next check in the app reports them.
    func backgroundCheck() async {
        reloadIfNeeded()
        guard !loadFailed else { return }
        let before = error
        await refreshPrices(quiet: true)
        await syncPocketSmith()
        if error != before { error = before }
    }
    // MARK: Prices
    @Published var pricesUpdated: Date?
    /// Refreshes AUD/USD and, with a Finnhub key, each holding's price. `quiet` hides errors for automatic refreshes.
    func refreshPrices(quiet: Bool = false) async {
        guard !state.holdings.isEmpty || state.stakeCashUSD > 0 else { return }
        // MK4.1: each piece is fetched on its own, so one unknown ticker or a busy service doesn't stop the rest.
        var problem: Error?
        var rate: Double?
        do { rate = try await Prices.audPerUSD() } catch { problem = error }
        var quotes: [String: Money] = [:]
        if let key = Keychain.read("finnhub") {
            for symbol in Set(state.holdings.filter { $0.shares > 0 }.map(\.symbol)) { // Sold-out holdings don't need a price.
                do { if let price = try await Prices.quote(symbol, key: key) { quotes[symbol] = price } } catch { problem = problem ?? error }
            }
        }
        if rate != nil || !quotes.isEmpty {
            change { s in
                if let rate { s.settings.audPerUSD = rate }
                for i in s.holdings.indices { if let price = quotes[s.holdings[i].symbol] { s.holdings[i].priceUSD = price; s.holdings[i].updated = Date() } }
            }
            pricesUpdated = Date()
        }
        if let problem, !quiet { report(problem) }
    }
    func refreshPricesIfDue() async {
        guard (pricesUpdated.map { Date().timeIntervalSince($0) > 3_600 }) ?? true else { return }
        await refreshPrices(quiet: true)
    }
    /// Shows a network error, except a cancelled request: that only means the screen moved on, not that anything failed.
    private func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        self.error = error.localizedDescription
    }
    func syncIfDue() async {
        await refreshPricesIfDue()
        guard let last = state.pocketsmith?.lastSync, Date().timeIntervalSince(last) > 15 * 60 else { return }
        await syncPocketSmith()
    }
    /// MK2.15: true once a day when "Refresh bank feeds when I open MoneyPilot" is on and a login is saved.
    var feedRefreshDue: Bool { state.pocketsmith?.feedRefreshDue(hasLogin: Keychain.read("password") != nil) ?? false }
    /// After the feeds were refreshed on the PocketSmith website: give the bank a minute, then import what arrived.
    func afterFeedRefresh() async {
        change { $0.pocketsmith?.feedsRefreshed = Date() }
        // Ask iOS for time to finish if you leave the app; it must be handed back or iOS closes the app.
        var extra = UIBackgroundTaskIdentifier.invalid
        extra = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(extra) }
        defer { UIApplication.shared.endBackgroundTask(extra) }
        activity = "Waiting for your bank…"
        try? await Task.sleep(for: .seconds(20)) // If iOS pauses the app anyway, the hourly check imports it.
        activity = "Syncing MoneyPilot…"
        await syncPocketSmith()
        activity = nil
    }
    func unlinkPocketSmith() {
        Keychain.delete(); Keychain.delete("login"); Keychain.delete("password")
        change { $0.pocketsmith = nil }
    }
    /// Confirms an imported entry. `kind == nil` removes it because it was already recorded manually.
    func review(_ id: UUID, as kind: EntryKind?, category: Category, usd: Money = 0) {
        change { s in
            guard let i = s.entries.firstIndex(where: { $0.id == id }), s.entries[i].needsReview == true else { return }
            guard let kind else { s.entries.remove(at: i); return }
            // Money direction comes from the bank; only the meaning can change.
            guard kind.inflow == s.entries[i].kind.inflow else { throw AppError.invalid("That type does not match the direction of this bank transaction.") }
            s.entries[i].kind = kind; s.entries[i].category = category; s.entries[i].needsReview = nil
            if kind == .fromStake { s.entries[i].costAUD = s.withdrawalCost(usd: usd > 0 ? usd : s.usdSold(aud: s.entries[i].amount)) }
            let moved = try s.applyEffects(kind, amount: s.entries[i].amount, usd: usd, entry: i)
            if moved > 0 { s.entries[i].usd = moved }
        }
    }
    func markStockDeposit(_ id: UUID, usd: Money?) { change { s in if let i = s.entries.firstIndex(where: { $0.id == id && $0.kind == .expense }) { s.fileAsStockDeposit(i, usd: usd) } } }
    func markSpending(_ id: UUID) { change { s in if let i = s.entries.firstIndex(where: { $0.id == id }) { s.fileAsSpending(i) } } }
    func deleteEntry(_ id: UUID) { change { try $0.deleteEntry(id) } }
    func editEntry(_ id: UUID, name: String, amount: Money, date: Date, category: Category) { change { try $0.editEntry(id, name: name, amount: amount, date: date, category: category) } }
    func matchBalance(_ pocketsmithID: String, to balance: Money) { change { $0.matchBalances([pocketsmithID: balance]) } }
    /// MK3: you type what your bank app shows (pending already included); new transactions carry on from there.
    func setBalance(_ id: UUID, to balance: Money) {
        change { s in if let i = s.accounts.firstIndex(where: { $0.id == id }) { s.accounts[i].openingBalance += balance - Engine(state: s).accountBalance(id) } }
    }
    func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            change { $0.settings.notifications = allowed }
            if !allowed { notice = "Notifications are off. You can enable them in iPhone Settings." }
        } catch { self.error = error.localizedDescription }
    }
    func refreshNotifications() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        defer {
            refreshing = false
            if refreshAgain { refreshAgain = false; Task { await refreshNotifications() } }
        }
        let center = UNUserNotificationCenter.current()
        guard state.settings.notifications else { center.removeAllPendingNotificationRequests(); return }
        let e = engine
        var messages: [(String, String, String)] = []
        for line in e.lines {
            let thresholds = [state.settings.warningPercent, 90, 100].sorted()
            if let threshold = thresholds.last(where: { line.ratio * 100 >= Double($0) }) {
                messages.append(("\(state.periodStart.timeIntervalSince1970)-\(line.id)-\(threshold)", "\(line.id): \(Int(line.ratio * 100))% used", "\(money(e.spendable(line.category))) left · \(e.daysLeft) day\(e.daysLeft == 1 ? "" : "s") left this \(e.periodName). Includes Afterpay due this \(e.periodName) and goal reservations."))
            }
        }
        if state.emergency < state.settings.emergencyMinimum {
            messages.append(("emergency-\(state.periodStart.timeIntervalSince1970)", "Emergency fund below your target", "Shortfall: \(money(state.settings.emergencyMinimum - state.emergency))."))
        }
        // Pay just landed: say exactly how much to move, using your income rule.
        for pay in state.entries where pay.kind.income && pay.hadEffects && pay.date >= Date().addingTimeInterval(-3 * 86_400) {
            let kept = e.afterCut(pay.amount, cut: pay.cut ?? 0), cut = pay.cut ?? 0
            messages.append(("income-\(pay.id)", "\(pay.kind == .wage ? "Pay" : "Allowance") received: \(money(pay.amount))",
                             "Move \(money(kept.savings)) to savings and \(money(kept.investment)) to investing (Stake). \(money(pay.amount - kept.savings - kept.investment)) is for your budgets and spare money." + (cut > 0 ? " Savings and investing were cut by \(money(cut)) so your budgets are covered." : "")))
        }
        // Smart alerts: a new important tip from the Guide, such as a double charge, a price rise or pay that hasn't arrived.
        for tip in e.insights where tip.notify { messages.append((tip.id, tip.title, tip.detail)) }
        for (id, title, body) in messages where !state.notified.contains(id) {
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
                state.notified.append(id)
            } catch { self.error = "Notification could not be scheduled: \(error.localizedDescription)" }
        }
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("afterpay-") || $0.identifier.hasPrefix("payday-") }.map(\.identifier))
        // Morning-of reminders to enter your pay and see the split.
        var paydays: [(String, Date)] = []
        if state.settings.expectedWages > 0 { if let pay = e.upcoming(days: 15).first(where: { $0.id == "pay" }) { paydays.append(("Payday", pay.date)) } }
        if state.settings.expectedAllowance > 0 { paydays.append(("Allowance day", state.nextAllowance)) }
        for (title, date) in paydays {
            let content = UNMutableNotificationContent(); content.title = title; content.body = "Open MoneyPilot and enter what you received to see how much goes to savings and investing."; content.sound = .default
            content.interruptionLevel = .timeSensitive // Breaks through Focus once the Time Sensitive capability is added in Xcode; otherwise a normal alert.
            var when = Calendar.current.dateComponents([.year, .month, .day], from: date); when.hour = 14
            try? await center.add(UNNotificationRequest(identifier: "payday-\(title)-\(date.timeIntervalSince1970)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
        let upcoming = state.plans.flatMap { plan in plan.installments.filter { $0.paidOn == nil && $0.due > Date() }.map { (plan.name, $0) } }.sorted { $0.1.due < $1.1.due }.prefix(40)
        for (name, payment) in upcoming {
            let content = UNMutableNotificationContent(); content.title = "Afterpay payment due"; content.body = "\(name): \(money(payment.amount)). Mark paid after checking your account."; content.sound = .default
            var components = Calendar.current.dateComponents([.year, .month, .day], from: payment.due); components.hour = 9
            do { try await center.add(UNNotificationRequest(identifier: "afterpay-\(payment.id)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))) }
            catch { self.error = error.localizedDescription }
        }
        do { try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { self.error = "Could not save notification status: \(error.localizedDescription)" }
    }
}
/// MK4.0: "Back up everything": all your data and, if you choose, your PocketSmith key and login and Finnhub key,
/// sealed with AES-GCM under a key derived from your password (PBKDF2-SHA256), so the file never holds them readable.
struct FullBackup: Codable {
    var app = "MoneyPilot"; var version = 2; var created = Date()
    var state: FinanceState
    var secrets: Sealed? = nil
    struct Sealed: Codable { var salt: Data; var box: Data }
    static let keychainItems = ["developer-key", "login", "password", "finnhub"]
    static func key(_ password: String, salt: Data) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        _ = salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &out, out.count)
        }
        return SymmetricKey(data: out)
    }
    static func seal(_ items: [String: String], password: String) throws -> Sealed {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }) // System random: cryptographically secure on Apple platforms.
        guard let box = try AES.GCM.seal(JSONEncoder().encode(items), using: key(password, salt: salt)).combined else { throw AppError.invalid("Couldn't encrypt the keys.") }
        return Sealed(salt: salt, box: box)
    }
    static func open(_ sealed: Sealed, password: String) throws -> [String: String] {
        guard let data = try? AES.GCM.open(AES.GCM.SealedBox(combined: sealed.box), using: key(password, salt: sealed.salt)) else { throw AppError.invalid("That password doesn't match this backup.") }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    /// A backup file from any version: MK4.0 files, or the plain data files earlier versions exported.
    static func read(_ data: Data) throws -> FullBackup {
        if let full = try? JSONDecoder().decode(FullBackup.self, from: data), full.app == "MoneyPilot" { return full }
        return FullBackup(state: try JSONDecoder().decode(FinanceState.self, from: data))
    }
}
extension Store {
    /// Everything as one file. With a password, the keys and login in this iPhone's Keychain are included, encrypted.
    func backupEverything(password: String?) throws -> Data {
        var backup = FullBackup(state: state)
        if let password {
            var items: [String: String] = [:]
            for name in FullBackup.keychainItems { items[name] = Keychain.read(name) }
            if !items.isEmpty { backup.secrets = try FullBackup.seal(items, password: password) }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(backup)
    }
    /// Puts the keys and login from a backup back into this iPhone's Keychain.
    func restoreSecrets(_ sealed: FullBackup.Sealed, password: String) throws {
        for (name, value) in try FullBackup.open(sealed, password: password) where FullBackup.keychainItems.contains(name) {
            guard Keychain.save(value, account: name) else { throw AppError.invalid("Couldn't save the keys to the Keychain.") }
        }
    }
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(state: FinanceState) { data = (try? JSONEncoder().encode(state)) ?? Data() }
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
