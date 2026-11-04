import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Security)
import Security
#endif

// Saved link between MoneyPilot and PocketSmith. The developer key itself lives in the Keychain, never in this file or backups.
struct PocketSmithLink: Codable {
    var accountMap: [String: UUID] = [:] // PocketSmith transaction-account ID → MoneyPilot account
    var seen: Set<Int> = []              // PocketSmith transaction IDs already imported or covered by opening balances
    var lastSync: Date?
    var balances: [String: Money] = [:]  // Latest PocketSmith balance per transaction account, for the balance check
    var wageKeyword = ""
    var allowanceKeyword = ""
    var known: [String: String]? = nil  // Every PocketSmith account seen at the last check, ID → name; optional for MK1.2 files
    // MK2.15: sign in to the PocketSmith website and press refresh on the bank feeds. The login itself lives in the Keychain.
    var autoRefresh: Bool? = nil
    var feedsRefreshed: Date? = nil
    // MK2.19: pending (not yet posted) amounts per PocketSmith account, replaced at every sync. Negative = money going out.
    var pending: [String: Money]? = nil
    /// Once a day at most, when you open MoneyPilot.
    func feedRefreshDue(hasLogin: Bool, now: Date = Date()) -> Bool {
        autoRefresh == true && hasLogin && now.timeIntervalSince(feedsRefreshed ?? .distantPast) > 20 * 3_600
    }
}
struct PSAccount: Decodable, Identifiable {
    var id: Int; var name: String?; var number: String?; var currentBalance: Double?
    var institution: Institution?
    struct Institution: Decodable { var title: String? }
    var label: String { [institution?.title, name ?? number].compactMap { $0 }.joined(separator: " · ") }
}
struct PSTransaction: Decodable {
    var id: Int; var payee: String?; var originalPayee: String?; var date: String; var amount: Double
    var type: String?; var status: String?; var transactionAccount: Ref; var category: Hint? = nil
    struct Ref: Decodable { var id: Int }
    struct Hint: Decodable { var title: String? }
}
func centsOf(_ value: Double) -> Money { Money((value * 100).rounded()) }

struct PocketSmithClient {
    let key: String
    static let day: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: "https://api.pocketsmith.com/v2" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-Developer-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw AppError.invalid("PocketSmith rejected the developer key. Check it in PocketSmith → Settings → Security.")
        case let status: throw AppError.invalid("PocketSmith could not be reached (error \(status)). Try again later.")
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    func accounts() async throws -> [PSAccount] {
        struct Me: Decodable { var id: Int }
        let me: Me = try await get("/me")
        return try await get("/users/\(me.id)/transaction_accounts")
    }
    func transactions(account: Int, from: Date) async throws -> [PSTransaction] {
        var all: [PSTransaction] = []
        var page = 0
        while true {
            page += 1
            let batch: [PSTransaction] = try await get("/transaction_accounts/\(account)/transactions", [
                URLQueryItem(name: "start_date", value: Self.day.string(from: from)),
                URLQueryItem(name: "end_date", value: Self.day.string(from: Date())),
                URLQueryItem(name: "per_page", value: "1000"),
                URLQueryItem(name: "page", value: String(page))])
            all += batch
            if batch.count < 1000 { break }
        }
        return all
    }
}

extension FinanceState {
    /// Adds new posted PocketSmith transactions once each. Returns how many entries were added.
    /// `historical` imports past activity for the record only: no income reservations and nothing to review.
    mutating func importPocketSmith(_ transactions: [PSTransaction], historical: Bool = false) -> Int {
        guard var link = pocketsmith else { return 0 }
        var added = 0
        // Pending items count against the balance until they post (or the bank drops them); they never become entries.
        link.pending = transactions.filter { $0.status == "pending" }.reduce(into: [:]) { total, t in
            let debit = t.type == "debit" || (t.type == nil && t.amount < 0)
            total[String(t.transactionAccount.id), default: 0] += debit ? -centsOf(abs(t.amount)) : centsOf(abs(t.amount))
        }
        for t in transactions.sorted(by: { $0.date < $1.date }) where t.status != "pending" && !link.seen.contains(t.id) {
            guard let account = link.accountMap[String(t.transactionAccount.id)], let date = PocketSmithClient.day.date(from: t.date) else { continue }
            link.seen.insert(t.id)
            let amount = centsOf(abs(t.amount))
            guard amount > 0 else { continue }
            let payee = (t.payee ?? t.originalPayee ?? "").trimmingCharacters(in: .whitespaces)
            let name = payee.isEmpty ? "Bank transaction" : payee
            let lower = name.lowercased()
            let debit = t.type == "debit" || (t.type == nil && t.amount < 0)
            let near: (Entry) -> Bool = { e in e.externalID != nil && e.amount == amount && abs(e.date.timeIntervalSince(date)) <= 3 * 86_400 }
            // Second half of a transfer that is already recorded (MK1.2 stored only one half's ID).
            if let i = entries.firstIndex(where: { near($0) && $0.kind == .transfer && $0.pairedID == nil && (debit ? $0.accountID : $0.destinationID) == account }) {
                entries[i].pairedID = t.id
                continue
            }
            // The other half of a move between two linked accounts becomes one internal transfer.
            if let i = entries.firstIndex(where: { near($0) && $0.accountID != account && $0.destinationID == nil && (debit ? $0.kind == .otherIncome : $0.kind == .expense) }) {
                let other = entries[i].accountID
                entries[i].kind = .transfer; entries[i].category = .other; entries[i].needsReview = nil; entries[i].pairedID = t.id
                entries[i].accountID = debit ? account : other; entries[i].destinationID = debit ? other : account
                continue
            }
            // Something you recorded by hand (pay, a planned transfer, a Stake deposit, a purchase): link it to the bank's copy
            // instead of counting it twice.
            if let i = entries.firstIndex(where: { e in
                e.amount == amount && abs(e.date.timeIntervalSince(date)) <= 3 * 86_400 && (debit
                    ? e.externalID == nil && e.accountID == account && [.expense, .investment, .transfer].contains(e.kind)
                    : (e.externalID == nil && e.kind.income) || (e.kind == .transfer && e.destinationID == account && e.pairedID == nil && e.externalID == nil))
            }) {
                if !debit && entries[i].kind == .transfer { entries[i].pairedID = t.id }
                else { entries[i].externalID = t.id; if entries[i].kind.income { entries[i].accountID = account } }
                continue
            }
            let category = Engine(state: self).autoCategory(name, hint: t.category?.title).category
            var entry = Entry(date: date, name: name, amount: amount, kind: .expense, category: category, accountID: account, destinationID: nil, externalID: t.id, historical: historical ? true : nil)
            if debit && lower.contains("afterpay") {
                // Clear the matching instalment instead of charging the budget a second time.
                if let (p, i) = instalmentFor(amount: amount, date: date) {
                    plans[p].installments[i].paidOn = date
                    entry.kind = .repayment; entry.category = plans[p].category; entry.name = "Afterpay · \(plans[p].name)"; entry.installmentID = plans[p].installments[i].id
                } else if historical { entry.category = .shopping } else { entry.needsReview = true }
            } else if debit {
                // A deposit to a broker is investing. With auto-organise off, live ones wait for review so you can enter the USD received.
                if Engine.isStockDeposit(lower) {
                    if historical { entry.kind = .investment }
                    else if settings.autoOrganise != false { entries.append(entry); fileAsStockDeposit(entries.count - 1); added += 1; continue }
                    else { entry.needsReview = true }
                }
            } else if !link.wageKeyword.isEmpty && lower.contains(link.wageKeyword.lowercased()) {
                entry.kind = .wage
            } else if !link.allowanceKeyword.isEmpty && lower.contains(link.allowanceKeyword.lowercased()) {
                entry.kind = .allowance
            } else {
                entry.kind = .otherIncome; entry.category = .other; entry.needsReview = historical ? nil : true
            }
            entries.append(entry); added += 1
            if entry.kind.income && !historical { try? applyEffects(entry.kind, amount: amount, entry: entries.count - 1) }
        }
        pocketsmith = link
        return added
    }
    /// Remembers every PocketSmith account and the latest balance of each linked one.
    mutating func recordAccounts(_ list: [PSAccount]) {
        pocketsmith?.known = Dictionary(list.map { (String($0.id), $0.label) }, uniquingKeysWith: { first, _ in first })
        for a in list { if let balance = a.currentBalance, pocketsmith?.accountMap[String(a.id)] != nil { pocketsmith?.balances[String(a.id)] = centsOf(balance) } }
    }
    /// Sets each linked account's opening balance so today's balance equals PocketSmith's.
    mutating func matchBalances(_ balances: [String: Money]) {
        for (id, balance) in balances {
            guard let mine = pocketsmith?.accountMap[id], let i = accounts.firstIndex(where: { $0.id == mine }) else { continue }
            // MK3.7: PocketSmith's balance leaves out pending transactions, so they still come off it here.
            let e = Engine(state: self)
            accounts[i].openingBalance += balance + e.pending(mine) - e.accountBalance(mine)
        }
    }
}

#if canImport(Security)
enum Keychain {
    // The service name predates the Finnhub key; kept so existing PocketSmith keys still load.
    private static func base(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MoneyPilot.PocketSmith", kSecAttrAccount as String: account] }
    static func read(_ account: String = "developer-key") -> String? {
        var query = base(account); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String, account: String = "developer-key") -> Bool {
        delete(account)
        var query = base(account); query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
    static func delete(_ account: String = "developer-key") { SecItemDelete(base(account) as CFDictionary) }
}
#endif
