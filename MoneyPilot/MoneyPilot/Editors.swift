import SwiftUI
import WebKit

@MainActor struct EditorShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    @ViewBuilder var content: Content
    var body: some View { NavigationStack { Form { content }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } } } }
}
@MainActor struct EntryEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var usd = ""
    @State private var kind: EntryKind = .expense
    @State private var category: Category = .other
    @State private var account: UUID?
    @State private var destination: UUID?
    @State private var date = Date()
    @State private var manualCategory = false
    var body: some View {
        EditorShell(title: "Add transaction") {
            Section("Transaction") {
                Picker("Type", selection: $kind) { ForEach(EntryKind.allCases.filter { $0 != .repayment }) { Text($0.rawValue).tag($0) } }
                TextField("Merchant or description", text: $name).onChange(of: name) { _, value in if !manualCategory { category = store.engine.categorise(value) } }
                TextField("Amount AUD", text: $amount).keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Picker("Account", selection: $account) { ForEach(store.state.accounts) { Text($0.name).tag(Optional($0.id)) } }
                if kind == .transfer { Picker("To account", selection: $destination) { Text("Choose").tag(Optional<UUID>.none); ForEach(store.state.accounts) { Text($0.name).tag(Optional($0.id)) } } }
                if kind == .expense || kind == .refund {
                    Picker("Category", selection: $category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Keep my category choice", isOn: $manualCategory)
                }
                if kind == .investment { TextField("USD credited by Stake (optional)", text: $usd).keyboardType(.decimalPad); Text("Reduces bank cash and investment reserve; adds the USD to Stake cash. Left blank, it's estimated at today's rate less the FX fee. Record purchases separately in Wealth.").font(.caption) }
                if kind == .fromStake { TextField("USD taken out of Stake (optional)", text: $usd).keyboardType(.decimalPad); Text("The AUD that reached your bank. Takes the USD off your Stake cash; left blank, it's estimated at today's rate plus the FX fee. Not counted as pay.").font(.caption) }
            }
            if kind.income, let value = cents(amount) {
                Section("Automatic reservation · no bank transfer") {
                    let a = store.engine.allocation(value)
                    MoneyRow(label: "Savings", value: a.savings); MoneyRow(label: "Investment reserve", value: a.investment); MoneyRow(label: "Spending", value: a.spending)
                }
            }
            Section {
                Button("Save transaction") {
                    guard let value = cents(amount), let account else { return }
                    store.addEntry(name: name, amount: value, kind: kind, category: category, account: account, destination: destination, date: date, usdReceived: cents(usd) ?? 0)
                    if store.error == nil { dismiss() }
                }.disabled(cents(amount) == nil || name.isEmpty || account == nil)
            } footer: { Text(store.state.pocketsmith == nil ? "Record Afterpay payments in Manage Afterpay so the matching instalment is cleared. Internal transfers do not count as income. Record transactions after your account opening-balance date only." : "Bank sync is on: bank transactions arrive automatically. Only add cash or transactions from accounts that are not synced, or they will be counted twice.") }
        }.onAppear { account = store.state.accounts.first?.id }
    }
}
@MainActor struct EntryDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var entry: Entry
    @State private var category: Category = .other
    @State private var similar = true
    @State private var splitAmount = ""
    @State private var usd = ""
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var deleting = false
    /// Unpaid Afterpay instalments, the ones due nearest this payment first.
    private var unpaidInstalments: [(plan: AfterpayPlan, instalment: Installment)] {
        store.state.plans.flatMap { p in p.installments.filter { $0.paidOn == nil }.map { (plan: p, instalment: $0) } }
            .sorted { abs($0.instalment.due.timeIntervalSince(entry.date)) < abs($1.instalment.due.timeIntervalSince(entry.date)) }
    }
    private func review(_ kind: EntryKind?) {
        store.review(entry.id, as: kind, category: category, usd: cents(usd) ?? 0)
        if store.error == nil { dismiss() }
    }
    var body: some View {
        EditorShell(title: entry.name) {
            Section { MoneyRow(label: entry.kind.rawValue, value: entry.amount); Text(entry.date, style: .date) }
            if entry.needsReview == true {
                Section {
                    if entry.kind.inflow {
                        Button("Wages") { review(.wage) }
                        Button("Parents’ allowance") { review(.allowance) }
                        Button("Refund or reimbursement · \(category.rawValue)") { review(.refund) }
                        Button("Other income · no savings rule") { review(.otherIncome) }
                        TextField("USD taken out of Stake (optional)", text: $usd).keyboardType(.decimalPad)
                        Button("Money back from Stake") { review(.fromStake) }
                    } else {
                        Button("Spending · \(category.rawValue)") { review(.expense) }
                        TextField("USD credited by Stake (optional)", text: $usd).keyboardType(.decimalPad)
                        Button("Deposit to Stake") { review(.investment) }
                        // MK3.6: an Afterpay payment that didn't match on its own (a fee, or a plan added later) can be linked here.
                        ForEach(unpaidInstalments.prefix(4), id: \.instalment.id) { item in
                            Button("Afterpay · \(item.plan.name) · \(money(item.instalment.amount)) due \(item.instalment.due.formatted(.dateTime.day().month(.abbreviated)))") {
                                store.linkAfterpay(entry.id, planID: item.plan.id, installmentID: item.instalment.id); dismiss()
                            }
                        }
                    }
                    Button("Already recorded · remove import", role: .destructive) { review(nil) }
                } header: { Text("Imported from your bank · what is this?") } footer: { Text("Wages and allowance apply your savings and investing rule. Pick the category below first for spending or refunds.") }
            }
            if entry.kind == .expense || entry.kind == .refund {
                Section("Correct the category") {
                    Picker("Category", selection: $category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                    let matches = store.engine.similar(to: entry.name)
                    let names = Array(Set(matches.map(\.name))).sorted().prefix(3)
                    Toggle("Also all similar transactions (\(matches.count))", isOn: $similar)
                    if similar && matches.count > 1 { Text("Includes \(names.joined(separator: ", "))\(Set(matches.map(\.name)).count > 3 ? "…" : ""), and future ones like them.").font(.caption).foregroundStyle(.secondary) }
                    Button("Apply correction") { store.recategorise(entry.id, category: category, similar: similar); dismiss() }
                }
            }
            if entry.kind == .expense && entry.needsReview != true {
                Section {
                    TextField("USD credited by Stake (optional)", text: $usd).keyboardType(.decimalPad)
                    Button("Move to Stock deposits", systemImage: "chart.line.uptrend.xyaxis") {
                        store.markStockDeposit(entry.id, usd: cents(usd)); if store.error == nil { dismiss() }
                    }
                } header: { Text("Stock deposit") } footer: { Text("For money sent to Stake or another broker. It leaves your spending and budgets and comes out of the money set aside for investing. For Stake, the USD is estimated at today's rate less the FX fee if you leave it blank.") }
            }
            if entry.kind == .investment {
                Section {
                    Button("Not a stock deposit · move to spending") { store.markSpending(entry.id); dismiss() }
                } footer: { Text("Returns the amount to your money set aside for investing. Adjust Stake cash in Settings if it was added.") }
            }
            if entry.kind == .expense {
                Section("Split purchase") {
                    TextField("Amount to put in selected category", text: $splitAmount).keyboardType(.decimalPad)
                    Button("Split transaction") { if let value = cents(splitAmount) { store.split(entry.id, amount: value, category: category); if store.error == nil { dismiss() } } }
                }
            }
            if entry.kind != .repayment {
                Section {
                    TextField("Description", text: $name)
                    TextField("Amount AUD", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    Button("Save changes") {
                        guard let value = cents(amount) else { return }
                        store.editEntry(entry.id, name: name, amount: value, date: date, category: category)
                        if store.error == nil { dismiss() }
                    }.disabled(cents(amount) == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Delete transaction", role: .destructive) { deleting = true }
                } header: { Text("Edit") } footer: { Text(entry.externalID != nil ? "This came from your bank. Changes stay in MoneyPilot and are not re-imported. Deleting it will make this account's balance differ from PocketSmith." : entry.kind.income ? "Changing or deleting income also adjusts the savings and investing amounts it set aside." : "Afterpay payments stay linked to their payment schedule.") }
            }
        }
        .onAppear { category = entry.category; name = entry.name; amount = String(Double(entry.amount) / 100); date = entry.date }
        .confirmationDialog("Delete this transaction?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.deleteEntry(entry.id); if store.error == nil { dismiss() } }
        } message: { Text(entry.kind == .investment ? "Your investment reserve is restored. Adjust Stake USD cash in Settings if needed." : "This cannot be undone.") }
    }
}
@MainActor struct BudgetEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var category: Category
    @State private var amount = ""
    @State private var locked = false
    var body: some View {
        EditorShell(title: category.rawValue) {
            Section {
                TextField("Base budget AUD", text: $amount).keyboardType(.decimalPad)
                Toggle("Lock against suggestions", isOn: $locked)
                Button("Save budget") {
                    guard let value = cents(amount) else { return }
                    store.change { s in if let i = s.budgets.firstIndex(where: { $0.category == category }) { s.budgets[i].limit = value; s.budgets[i].locked = locked } }
                    dismiss()
                }.disabled(cents(amount) == nil)
            } header: { Text("\(store.engine.periodName.capitalized)ly allocation") } footer: { Text("Changing a budget does not create cash. The dashboard limits available spending to the cash you actually have.") }
        }.onAppear { if let b = store.state.budgets.first(where: { $0.category == category }) { amount = String(Double(b.limit) / 100); locked = b.locked } }
    }
}
@MainActor struct BudgetSuggestionsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        EditorShell(title: "Suggested \(store.engine.periodName)") {
            Section {
                MoneyRow(label: "Expected income per \(store.engine.periodName) (wages + allowance)", value: store.engine.expectedPeriodIncome)
                MoneyRow(label: "Spending share", value: store.engine.allocation(store.engine.expectedPeriodIncome).spending)
                ForEach(store.engine.suggestedBudgets()) { b in MoneyRow(label: b.category.rawValue + (b.locked ? " · locked" : ""), value: b.limit) }
            } footer: { Text("Yearly income (fortnightly wages × 26 + monthly allowance × 12) divided into your budget periods. The remaining spending share is weighted 18% fuel, 36% groceries, 10% takeaway, 4% subscriptions, 12% bills, 6% entertainment and 4% other (scaled to 100%) until four weeks of past expense history are available. Locked budgets are preserved. These are starting suggestions, not a claim that essentials will fit.") }
            Section { Button("Accept these budgets") { let budgets = store.engine.suggestedBudgets(); store.change { $0.budgets = budgets }; dismiss() } }
        }
    }
}
@MainActor struct GoalEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var price = ""
    @State private var perPay = ""
    var body: some View {
        let spare = store.engine.spareMoney
        EditorShell(title: "New goal") {
            Section("What are you saving for?") {
                TextField("Goal, e.g. 3D printer", text: $name)
                TextField("Price AUD", text: $price).keyboardType(.decimalPad)
                TextField("Save amountEach pay AUD", text: $perPay).keyboardType(.decimalPad)
            }
            Section("Can you afford it?") {
                if let spare { MoneyRow(label: "Spare money amountEach pay", value: spare.perPay) }
                if let total = cents(price), let amountEach = cents(perPay), amountEach > 0 {
                    let pays = Int(ceil(Double(total) / Double(amountEach)))
                    Text("About \(pays) pays, around \(Calendar.current.date(byAdding: .day, value: pays * 14, to: Date())!.formatted(.dateTime.day().month(.abbreviated).year())).")
                    if let spare, amountEach > spare.perPay { Label("That's more than spare money gets amountEach pay (\(money(spare.perPay))), so other goals or spending would have to wait.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
                Text("Every payday, MoneyPilot sets this amount aside in your spare money account. Goal money isn't counted as spendable, and your savings and investing stay separate.").font(.caption)
                Button("Create goal") {
                    guard let total = cents(price), total > 0, let amountEach = cents(perPay), amountEach > 0 else { return }
                    store.change { $0.goals.append(Goal(name: name, target: total, weekly: amountEach / 2)) }; dismiss() // Stored weekly; pay is fortnightly.
                }.disabled(name.isEmpty || (cents(price) ?? 0) <= 0 || (cents(perPay) ?? 0) <= 0)
            }
        }
    }
}
@MainActor struct AfterpayView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var payment: PaymentChoice?
    @State private var undoing: PaymentChoice?
    @State private var editing: AfterpayPlan?
    struct PaymentChoice: Identifiable { var id: UUID; var planID: UUID }
    var body: some View {
        NavigationStack {
            List {
                Section { MoneyRow(label: "Total still owed", value: store.engine.afterpayDebt); Button("Add Afterpay purchase", systemImage: "plus") { adding = true } }
                Section { Text(store.state.pocketsmith == nil ? "Tap an unpaid instalment after paying it, or a paid one to undo it. This app cannot make the payment." : "Bank sync clears instalments automatically when an Afterpay payment of the same amount arrives. Tap a paid instalment to undo a wrong match.").font(.caption) }
                ForEach(store.state.plans) { plan in
                    Section {
                        MoneyRow(label: "Outstanding", value: plan.outstanding)
                        ForEach(plan.installments) { part in
                            Button {
                                if part.paidOn == nil { payment = PaymentChoice(id: part.id, planID: plan.id) } else { undoing = PaymentChoice(id: part.id, planID: plan.id) }
                            } label: {
                                HStack {
                                    Image(systemName: part.paidOn == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(.mint)
                                    VStack(alignment: .leading) {
                                        Text(part.due, style: .date)
                                        if let paid = part.paidOn { Text("Paid \(paid.formatted(date: .abbreviated, time: .omitted)) · tap to undo").font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    Spacer(); Text(money(part.amount))
                                }
                            }
                        }
                        Button("Edit dates & amounts", systemImage: "pencil") { editing = plan }.font(.subheadline)
                    } header: { Text("\(plan.name) · \(plan.category.rawValue)") }
                }
            }.navigationTitle("Afterpay").toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
        }.sheet(isPresented: $adding) { AfterpayEditor() }
            .sheet(item: $editing) { AfterpayPlanEditor(plan: $0) }
            .confirmationDialog("Record payment from which account?", isPresented: Binding(get: { payment != nil }, set: { if !$0 { payment = nil } }), titleVisibility: .visible) {
                if let p = payment { ForEach(store.state.accounts) { account in Button(account.name) { store.pay(planID: p.planID, installmentID: p.id, account: account.id); payment = nil } } }
            }
            .confirmationDialog("Undo this payment?", isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }), titleVisibility: .visible) {
                if let u = undoing { Button("Mark as unpaid", role: .destructive) { store.change { $0.undoPayment(planID: u.planID, installmentID: u.id) }; undoing = nil } }
            } message: { Text("The instalment becomes unpaid again. A payment you logged by hand is removed; a payment from your bank stays and moves to Needs review in Activity.") }
    }
}
@MainActor struct AfterpayPlanEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var plan: AfterpayPlan
    @State private var amounts: [UUID: String] = [:]
    @State private var deleting = false
    private func amountText(_ id: UUID) -> Binding<String> { Binding(get: { amounts[id] ?? "" }, set: { amounts[id] = $0 }) }
    var total: Money { plan.installments.reduce(Money(0)) { $0 + (($1.paidOn == nil ? cents(amounts[$1.id] ?? "") : $1.amount) ?? 0) } }
    var body: some View {
        EditorShell(title: "Edit Afterpay") {
            Section("Purchase") {
                TextField("Name", text: $plan.name)
                Picker("Category", selection: $plan.category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                DatePicker("Bought on", selection: $plan.purchased, in: ...Date(), displayedComponents: .date)
            }
            Section {
                ForEach($plan.installments) { $part in
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker(part.paidOn == nil ? "Due" : "Due · paid", selection: $part.due, displayedComponents: .date)
                        if part.paidOn == nil {
                            HStack { Text("Amount"); Spacer(); TextField("0.00", text: amountText(part.id)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 120) }
                        } else { MoneyRow(label: "Paid", value: part.amount) }
                    }
                    .deleteDisabled(part.paidOn != nil)
                }
                .onDelete { plan.installments.remove(atOffsets: $0) }
                Button("Add instalment", systemImage: "plus") {
                    let after = plan.installments.map(\.due).max() ?? Date()
                    let new = Installment(due: Calendar.current.date(byAdding: .day, value: 14, to: after)!, amount: plan.installments.last?.amount ?? 0)
                    plan.installments.append(new); amounts[new.id] = String(Double(new.amount) / 100)
                }
                MoneyRow(label: "Total", value: total)
            } header: { Text("Instalments") } footer: { Text("Swipe left to remove an unpaid instalment. To change a paid one's amount, undo its payment first. Each instalment counts against the budget of the week, fortnight or month it is due in.") }
            Section {
                Button("Save changes") { save() }
                Button("Delete this Afterpay plan", role: .destructive) { deleting = true }
            }
        }
        .onAppear { for part in plan.installments where amounts[part.id] == nil { amounts[part.id] = String(Double(part.amount) / 100) } }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) { let id = plan.id; store.change { $0.deletePlan(id) }; dismiss() }
        } message: { Text("For a plan entered by mistake. Payments you logged by hand are removed too. Payments imported from your bank stay and move to Needs review.") }
    }
    private func save() {
        var updated = plan
        for i in updated.installments.indices where updated.installments[i].paidOn == nil {
            guard let value = cents(amounts[updated.installments[i].id] ?? ""), value > 0 else { store.error = "Enter an amount for every unpaid instalment."; return }
            updated.installments[i].amount = value
        }
        store.change { try $0.updatePlan(updated) }
        if store.error == nil { dismiss() }
    }
}
@MainActor struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Done") { dismiss() } }
}
@MainActor struct AfterpayEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var due = Date()
    @State private var alreadyPaid = 0
    @State private var category: Category = .shopping
    var body: some View {
        EditorShell(title: "Afterpay purchase") {
            Section {
                TextField("Purchase name", text: $name)
                TextField("Full purchase price AUD", text: $amount).keyboardType(.decimalPad)
                Picker("Category", selection: $category) { ForEach(Category.allCases) { Text($0.rawValue).tag($0) } }
                DatePicker("First instalment due", selection: $due, displayedComponents: .date)
                Stepper("Already paid before tracking: \(alreadyPaid)", value: $alreadyPaid, in: 0...3)
            } footer: { Text("Creates four fortnightly instalments. Afterpay payments that already synced from your bank are linked to it automatically. For an older plan, mark payments made before your bank history starts; those do not deduct cash again. Record subsequent payments from the schedule. Do not also add the full purchase as a cash expense. Each instalment uses budget in the period it is due, so the purchase is spread across the coming weeks or months. Change dates or amounts later with “Edit dates & amounts”.") }
            Section { Button("Create schedule") { if let total = cents(amount) { store.createPlan(name: name, total: total, firstDue: due, category: category, alreadyPaid: alreadyPaid); if store.error == nil { dismiss() } } }.disabled(name.isEmpty || (cents(amount) ?? 0) < 4) }
        }
    }
}
@MainActor struct HoldingEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var existing: Holding?
    var buyMore: String? = nil // Ticker when opened from a stock's "Buy more"
    @State private var symbol = ""
    @State private var shares = ""
    @State private var price = ""
    @State private var cost = ""
    @State private var brokerage = String(Double(stakeBrokerageUSD) / 100)
    @State private var mode = "existing"
    @State private var status = ""
    @State private var key = ""
    @State private var hasKey = Keychain.read("finnhub") != nil
    @State private var removing = false
    var ticker: String { symbol.trimmingCharacters(in: .whitespaces).uppercased() }
    var qty: Double? { Double(shares).flatMap { $0.isFinite && $0 > 0 && $0 <= 1_000_000 ? $0 : nil } }
    /// Value in US cents of the shares at the current price, when both are known.
    var value: Money? { guard let qty, let p = cents(price) else { return nil }; return Money((qty * Double(p)).rounded()) }
    var body: some View {
        EditorShell(title: existing != nil ? "Edit holding" : buyMore.map { "Buy more \($0)" } ?? "Add holding") {
            Section {
                TextField("Ticker, e.g. AAPL or VOO", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Shares owned", text: $shares).keyboardType(.decimalPad)
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(status.hasPrefix("Live") ? .mint : .orange) }
                if let value {
                    LabeledContent(existing == nil ? "Shares cost" : "Value", value: money(value, currency: "USD")).font(.headline)
                    MoneyRow(label: "In AUD", value: store.engine.aud(value))
                }
            } header: { Text("Your shares") } footer: { Text("The price is fetched for you from Finnhub (US stocks and ETFs) and refreshes whenever MoneyPilot syncs.") }
            if !hasKey {
                Section {
                    SecureField("Paste your free Finnhub API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key") {
                        if Keychain.save(key.trimmingCharacters(in: .whitespaces), account: "finnhub") { hasKey = true; key = "" } else { store.error = "Could not store the key in the Keychain." }
                    }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("Turn on automatic prices") } footer: { Text("Sign up free at finnhub.io, then copy the API key from your dashboard. It is stored only in this iPhone's Keychain. Without it, type the price below yourself.") }
            }
            Section {
                if existing == nil {
                    TextField("Purchase price per share USD", text: $price).keyboardType(.decimalPad)
                    TextField("Brokerage USD", text: $brokerage).keyboardType(.decimalPad)
                    if let value, let fee = cents(brokerage) { LabeledContent("Total cost", value: money(value + fee, currency: "USD")).bold() }
                    Picker("Paid with", selection: $mode) { Text("Already bought · don't touch Stake cash").tag("existing"); Text("Stake cash").tag("buy") }
                } else {
                    TextField("Price per share USD · fills in automatically", text: $price).keyboardType(.decimalPad)
                    TextField("Total cost USD incl. brokerage", text: $cost).keyboardType(.decimalPad)
                }
            } header: { Text("Price & cost") } footer: { Text(existing == nil ? "The purchase price fills in with today's price; change it to what you actually paid. Brokerage starts at Stake's US$3 and is part of the cost. Buying a stock you already hold combines them at the average price." : "For corrections only. To sell, use Sell on the stock instead, so your profit and Stake cash are recorded.") }
            Section {
                Button(existing == nil ? "Save buy" : "Save holding") { save() }.disabled(ticker.isEmpty || qty == nil || cents(price) == nil || (existing == nil ? cents(brokerage) == nil : cents(cost) == nil))
                if existing != nil { Button("Remove holding", role: .destructive) { removing = true } }
            }
        }
        .onAppear {
            if let h = existing { symbol = h.symbol; shares = String(h.shares); price = String(Double(h.priceUSD) / 100); cost = String(Double(h.costUSD) / 100) }
            if let buyMore { symbol = buyMore; mode = "buy" }
            else if existing == nil && store.state.stakeCashUSD > 0 { mode = "buy" } // MK4.1: a new buy usually comes out of Stake cash
        }
        .task(id: "\(ticker)|\(hasKey)") { await lookUp() }
        .confirmationDialog("Remove \(ticker) from your portfolio?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let existing { store.change { $0.holdings.removeAll { $0.id == existing.id } } }; dismiss() }
        } message: { Text("This only changes MoneyPilot. Stake cash is not adjusted.") }
    }
    private func lookUp() async {
        guard !ticker.isEmpty, let key = Keychain.read("finnhub") else { status = ""; return }
        try? await Task.sleep(for: .milliseconds(700)) // Wait until typing pauses.
        guard !Task.isCancelled else { return }
        status = "Looking up \(ticker)…"
        do {
            if let latest = try await Prices.quote(ticker, key: key) {
                price = String(Double(latest) / 100)
                status = "Live price \(money(latest, currency: "USD")) per share"
            } else { status = "\(ticker) wasn't found. Check the ticker; only US-listed shares and ETFs are supported." }
        } catch { if !Task.isCancelled { status = error.localizedDescription } }
    }
    private func save() {
        guard let qty, let unit = cents(price), unit <= 1_000_000_000 else { return }
        store.change { s in
            if let existing, let i = s.holdings.firstIndex(where: { $0.id == existing.id }) {
                let paid = cents(cost) ?? s.holdings[i].costUSD
                if paid != s.holdings[i].costUSD { s.holdings[i].costAUD = nil } // Corrected cost: AUD follows today's rate.
                s.holdings[i].symbol = ticker; s.holdings[i].shares = qty; s.holdings[i].costUSD = paid
                s.holdings[i].priceUSD = unit; s.holdings[i].updated = Date()
            } else {
                try s.buy(ticker, shares: qty, priceUSD: unit, brokerageUSD: cents(brokerage) ?? 0, fromCash: mode == "buy")
            }
        }
        if store.error == nil { dismiss() }
    }
}
/// Wealth → Money to & from Stake: what went in, what came back, FX fees and currency moves, plus an FX calculator.
@MainActor struct StakeMoneyView: View {
    @EnvironmentObject var store: Store
    @State private var sendAUD = ""
    @State private var withdrawUSD = ""
    @State private var before = StakeHistory()
    @State private var editingUSD: Entry?
    @State private var usdText = ""
    var body: some View {
        let e = store.engine, m = e.stakeMoney, s = store.state
        EditorShell(title: "Actual profit & loss") {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.bankedAUD >= 0 ? "PROFIT BANKED" : "LOSS BANKED").font(.caption.bold()).foregroundStyle(m.bankedAUD >= 0 ? .mint : .orange)
                    Text(money(abs(m.bankedAUD))).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(m.bankedAUD >= 0 ? .mint : .orange)
                    Text("Real money: what came back to your bank minus what that money cost you").font(.caption).foregroundStyle(.secondary)
                }
                MoneyRow(label: "Back to your bank", value: m.backAUD)
                MoneyRow(label: "What that money cost you", value: m.withdrawnCostAUD)
            } footer: { Text("After every FX fee and currency move, because it compares Aussie dollars out with Aussie dollars back. Only withdrawals count; money still at Stake is on the Wealth tab.") }
            Section {
                MoneyRow(label: "Sent to Stake", value: m.sentAUD)
                MoneyRow(label: "Still invested (cost)", value: m.basisAUD)
                MoneyRow(label: "Worth at Stake now", value: m.worthAUD)
                MoneyRow(label: "FX fees paid so far", value: -m.feesAUD, color: .orange)
            } header: { Text("All money to and from Stake") }
            Section {
                Stepper(value: Binding(get: { s.settings.fxFeePercent ?? 0.55 }, set: { v in store.change { $0.settings.fxFeePercent = (v * 100).rounded() / 100 } }), in: 0...3, step: 0.05) {
                    LabeledContent("FX fee each way", value: "\((s.fxFee * 100).formatted(.number.precision(.fractionLength(2))))%")
                }
                LabeledContent("Today's rate", value: "1 USD = \(s.settings.audPerUSD.formatted(.number.precision(.fractionLength(4)))) AUD")
                TextField("If I send A$", text: $sendAUD).keyboardType(.decimalPad)
                if let aud = cents(sendAUD), aud > 0 {
                    Text("Stake credits about \(money(s.usdBought(aud: aud), currency: "USD")) · fee \(money(Money((Double(aud) * s.fxFee).rounded())))").font(.callout)
                }
                TextField("If I withdraw US$", text: $withdrawUSD).keyboardType(.decimalPad)
                if let usd = cents(withdrawUSD), usd > 0 {
                    let back = s.audBack(usd: usd)
                    Text("About \(money(back)) reaches your bank · fee \(money(Money((Double(usd) * s.settings.audPerUSD).rounded()) - back))").font(.callout)
                }
            } header: { Text("FX calculator") } footer: { Text("Stake charges 0.55% to convert AUD to USD and again from USD to AUD, with no other withdrawal fee. Change it here if your plan differs. The rate updates when prices refresh.") }
            Section {
                ForEach((e.stakeDeposits + e.stakeWithdrawals).sorted { $0.date > $1.date }) { entry in
                    Button { editingUSD = entry; usdText = "" } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.kind == .investment ? "To Stake" : "From Stake").bold()
                                Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(money(entry.amount)).monospacedDigit()
                                Text(money(entry.usd ?? (entry.kind == .investment ? s.usdBought(aud: entry.amount) : s.usdSold(aud: entry.amount)), currency: "USD") + (entry.usd == nil || entry.usdEstimated == true ? " est." : "")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                    .swipeActions { if entry.kind == .investment { Button("Not Stake") { store.markSpending(entry.id) }.tint(.orange) } }
                }
                if e.stakeDeposits.isEmpty && e.stakeWithdrawals.isEmpty { Text("No transfers yet. Bank payments to Stake are picked up automatically; mark money coming back as \"Money back from Stake\" when you review it in Activity.").foregroundStyle(.secondary) }
            } header: { Text("Transfers") } footer: { Text("Tap a transfer to enter the real USD from Stake. Swipe left on one that isn't a Stake deposit to move it back to spending.") }
            Section {
                AmountField(label: "AUD sent", value: $before.sentAUD)
                AmountField(label: "USD received", value: $before.usdIn)
                AmountField(label: "AUD back to bank", value: $before.backAUD)
                AmountField(label: "USD withdrawn", value: $before.usdOut)
                Button("Save earlier transfers") { let b = before; store.change { $0.stakeBefore = b } }
            } header: { Text("Before MoneyPilot") } footer: { Text("Totals from Stake's statements for transfers made before your bank history here. Without them, money already at Stake looks like profit.") }
        }
        .onAppear { before = s.stakeBefore ?? StakeHistory() }
        .alert("Real USD from Stake", isPresented: Binding(get: { editingUSD != nil }, set: { if !$0 { editingUSD = nil } }), presenting: editingUSD) { entry in
            TextField("USD, e.g. 682.64", text: $usdText).keyboardType(.decimalPad)
            Button("Save") { if let value = cents(usdText) { store.change { try $0.setStakeUSD(entry.id, usd: value) } }; editingUSD = nil }
            Button("Cancel", role: .cancel) { editingUSD = nil }
        } message: { entry in Text("\(entry.kind == .investment ? "Credited at Stake for" : "Taken out of Stake for") \(money(entry.amount)) on \(entry.date.formatted(date: .abbreviated, time: .omitted)).") }
    }
}
/// MK3.1: Wealth → Check Stake cash. Rebuilds Stake cash from your history, explains any gap, and lets you match the Stake app.
@MainActor struct StakeCheckView: View {
    @EnvironmentObject var store: Store
    @State private var stakeApp = ""
    @State private var real: [UUID: String] = [:]
    private func usd(_ v: Money) -> String { money(v, currency: "USD") }
    var body: some View {
        let c = store.engine.stakeCheck, shown = store.state.stakeCashUSD, gap = shown - c.history
        EditorShell(title: "Check Stake cash") {
            Section {
                LabeledContent("Before MoneyPilot", value: usd(c.before))
                LabeledContent("Deposits to Stake", value: usd(c.deposits))
                LabeledContent("Withdrawals to your bank", value: usd(-c.withdrawals))
                LabeledContent("Shares bought, incl. brokerage", value: usd(-c.bought))
                LabeledContent("Shares sold, after brokerage", value: usd(c.sold))
                if c.corrections != 0 { LabeledContent("Your corrections", value: usd(c.corrections)) }
                LabeledContent("History adds up to", value: usd(c.history)).bold()
                LabeledContent("MoneyPilot shows", value: usd(shown)).bold().foregroundStyle(gap == 0 ? .mint : .orange)
            } header: { Text("Stake cash from your history") } footer: { Text(gap == 0 ? "MoneyPilot's Stake cash follows from your history." : "MoneyPilot shows \(usd(abs(gap))) \(gap > 0 ? "more" : "less") than your history adds up to.") }
            if gap != 0 || c.notAdded > 0 || !c.estimated.isEmpty {
                Section("Why it might not add up") {
                    if c.notAdded > 0 { Label("\(usd(c.notAdded)) of past deposits imported from your bank never added to Stake cash, because they happened before you linked PocketSmith.", systemImage: "clock.arrow.circlepath") }
                    if !c.estimated.isEmpty { Label("\(c.estimated.count) deposit\(c.estimated.count == 1 ? "" : "s") or withdrawal\(c.estimated.count == 1 ? " is" : "s are") estimated from the exchange rate. Enter the real USD below.", systemImage: "questionmark.circle") }
                    if gap != 0 { Label("Shares added as \"already bought\" count as bought here. If they were paid for before MoneyPilot, enter those deposits under Before MoneyPilot on the Actual profit & loss page.", systemImage: "chart.line.uptrend.xyaxis") }
                    Label("Dividends, interest and Stake fees aren't tracked, so they only show up as a difference with the Stake app.", systemImage: "dollarsign.circle")
                }
            }
            Section {
                TextField("Cash in the Stake app (USD)", text: $stakeApp).keyboardType(.decimalPad)
                if let value = cents(stakeApp), value != c.history {
                    Text("The Stake app shows \(usd(abs(value - c.history))) \(value > c.history ? "more" : "less") than your history. Using it records that as a correction.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Use this number") {
                    guard let value = cents(stakeApp) else { return }
                    store.change { $0.correctStakeCash(to: value) }; stakeApp = ""
                }.disabled(cents(stakeApp) == nil)
            } header: { Text("Match the Stake app") } footer: { Text("Use the uninvested cash (buying power) in the Stake app. Your shares are checked separately: tap a stock to fix its shares or cost.") }
            if !c.estimated.isEmpty {
                Section("Estimated amounts") {
                    ForEach(c.estimated) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(entry.kind == .investment ? "To Stake" : "From Stake") · \(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(money(entry.amount))").font(.subheadline)
                            HStack {
                                TextField("Real USD, est. \(usd(entry.usd ?? (entry.kind == .investment ? store.state.usdBought(aud: entry.amount) : store.state.usdSold(aud: entry.amount))))",
                                          text: Binding(get: { real[entry.id] ?? "" }, set: { real[entry.id] = $0 })).keyboardType(.decimalPad)
                                Button("Save") {
                                    guard let value = cents(real[entry.id] ?? "") else { return }
                                    store.change { try $0.setStakeUSD(entry.id, usd: value) }; real[entry.id] = nil
                                }.disabled(cents(real[entry.id] ?? "") == nil)
                            }
                        }
                    }
                }
            }
        }
    }
}
/// MK3: shown from the Guide when your plan is bigger than your cash. Shows the changes, then applies them on tap.
@MainActor struct FixPlanView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let e = store.engine
        EditorShell(title: "Fix it for me") {
            if let plan = e.fixPlan {
                Section {
                    ForEach(e.cashBreakdown.indices, id: \.self) { i in MoneyRow(label: e.cashBreakdown[i].label, value: e.cashBreakdown[i].amount) }
                    MoneyRow(label: "Left over", value: e.unallocated, color: .orange).bold()
                } header: { Text("How it's worked out") } footer: { Text("Your plan is \(money(-e.unallocated)) bigger than your cash. If an amount above looks wrong, that's the thing to fix. MoneyPilot would:") }
                if plan.savingsTo != nil || plan.emergencyTo != nil {
                    Section {
                        if let to = plan.savingsTo { MoneyRow(label: "Savings set aside: \(money(store.state.savings)) → what Savings holds", value: to) }
                        if let to = plan.emergencyTo { MoneyRow(label: "Emergency fund: \(money(store.state.emergency)) → what Emergency holds", value: to) }
                    } header: { Text("Match set-aside money to your accounts") } footer: { Text("Savings set aside grows by your rule every pay. If less actually reached your Savings account, the difference isn't real money, so it's matched to the account. Nothing is moved.") }
                }
                if !plan.balances.isEmpty {
                    Section("Correct balances") {
                        ForEach(plan.balances.indices, id: \.self) { i in MoneyRow(label: "\(plan.balances[i].account.name) → PocketSmith's balance less pending", value: e.matched(plan.balances[i])) }
                    }
                }
                if plan.releaseGoals > 0 { Section("Release goal savings") { MoneyRow(label: "Back to spendable", value: plan.releaseGoals) } }
                if !plan.cuts.isEmpty {
                    Section {
                        ForEach(plan.cuts.indices, id: \.self) { i in
                            let c = plan.cuts[i], base = e.baseLimit(c.category)
                            MoneyRow(label: "\(c.category.rawValue): \(money(base)) → \(money(max(0, base - c.amount)))", value: -c.amount)
                        }
                    } header: { Text("Lower budgets") } footer: { Text("Takeaway, entertainment and other first; groceries and fuel last. Budgets stay at the new amounts until you change them.") }
                }
                if plan.stillShort > 0 {
                    Section { Label("Still \(money(plan.stillShort)) short after this. Check your balances, or move money in from savings yourself.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                Section {
                    Button("Apply these changes") { store.change { $0.apply(plan) }; dismiss() }
                } footer: { Text("Bills, subscriptions and investing money are never touched, and no money is moved between accounts.") }
            } else {
                Section { Label("Nothing to fix: your plan fits your cash.", systemImage: "checkmark.seal.fill").foregroundStyle(.mint) }
            }
        }
    }
}
/// MK3: type what your bank app shows for one account.
@MainActor struct SetBalanceView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var amount = ""
    var body: some View {
        let e = store.engine
        EditorShell(title: store.state.accounts.first { $0.id == id }?.name ?? "Balance") {
            Section {
                MoneyRow(label: "MoneyPilot shows", value: e.accountBalance(id))
                TextField("What your bank app shows", text: $amount).keyboardType(.decimalPad)
                Button("Set balance") { if let value = cents(amount) { store.setBalance(id, to: value); dismiss() } }.disabled(cents(amount) == nil)
            } footer: { Text("Use the available balance in your bank app; it already includes pending transactions. Budgets, spare money and transfer suggestions use it straight away, and new transactions carry on from here. It stays until you change it.") }
            if let drift = e.drifted.first(where: { $0.account.id == id }) {
                Section { Button("PocketSmith says \(money(e.matched(drift))) after pending · Use this") { store.matchBalance(drift.pocketsmithID, to: drift.theirs); dismiss() } }
            }
        }
    }
}
/// Tap a stock on Wealth: what it cost, what it's worth, what you've made, and Sell / Buy more.
@MainActor struct HoldingDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var shares = ""
    @State private var price = ""
    @State private var brokerage = String(Double(stakeBrokerageUSD) / 100)
    @State private var buying = false
    @State private var editing = false
    var body: some View {
        if let h = store.state.holdings.first(where: { $0.id == id }) {
            let rate = store.state.settings.audPerUSD
            EditorShell(title: h.symbol) {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(h.profitUSD >= 0 ? "YOU'VE MADE" : "YOU'VE LOST").font(.caption.bold()).foregroundStyle(h.profitUSD >= 0 ? .mint : .orange)
                        Text(usd(abs(h.profitUSD))).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(h.profitUSD >= 0 ? .mint : .orange)
                        Text("\(h.profitPercent.formatted(.percent.precision(.fractionLength(1)))) · \(money(h.profitAUD(rate))) in AUD").font(.subheadline).foregroundStyle(.secondary)
                    }
                    LabeledContent("On shares you hold", value: usd(h.unrealisedUSD))
                    LabeledContent("From shares sold", value: usd(h.realisedUSD ?? 0))
                } footer: { Text("After brokerage. AUD includes exchange-rate changes since you bought.") }
                Section("Holding") {
                    LabeledContent("Shares", value: h.shares.formatted())
                    LabeledContent("Average price paid", value: usd(h.averagePriceUSD))
                    LabeledContent("Price now", value: usd(h.priceUSD))
                    LabeledContent("Cost incl. brokerage", value: usd(h.costUSD))
                    LabeledContent("Worth now", value: usd(h.valueUSD))
                }
                if h.shares > 0 {
                    Section {
                        TextField("Shares to sell · you hold \(h.shares.formatted())", text: $shares).keyboardType(.decimalPad)
                        TextField("Selling price per share USD", text: $price).keyboardType(.decimalPad)
                        TextField("Brokerage USD", text: $brokerage).keyboardType(.decimalPad)
                        if let qty = Double(shares), qty > 0, qty <= h.shares, let unit = cents(price), let fee = cents(brokerage) {
                            let proceeds = Money((qty * Double(unit)).rounded()) - fee
                            let costPart = Money((Double(h.costUSD) * qty / h.shares).rounded())
                            LabeledContent("Money to Stake cash", value: usd(proceeds))
                            LabeledContent("Profit on this sale", value: usd(proceeds - costPart)).foregroundStyle(proceeds >= costPart ? .mint : .orange)
                        }
                        Button("Sell") { sell(h) }.disabled(Double(shares) == nil || cents(price) == nil || cents(brokerage) == nil)
                    } header: { Text("Sell") } footer: { Text("The money stays in your Stake cash, inside your portfolio. It doesn't go to your bank or budgets.") }
                }
                Section {
                    Button("Buy more", systemImage: "plus.circle") { buying = true }
                    Button("Edit holding", systemImage: "pencil") { editing = true }
                }
            }
            .onAppear { price = String(Double(h.priceUSD) / 100) }
            .sheet(isPresented: $buying) { HoldingEditor(existing: nil, buyMore: h.symbol) }
            .sheet(isPresented: $editing) { HoldingEditor(existing: h) }
        } else { Color.clear.onAppear { dismiss() } } // Removed while open.
    }
    private func usd(_ value: Money) -> String { money(value, currency: "USD") }
    private func sell(_ h: Holding) {
        guard let qty = Double(shares), let unit = cents(price), let fee = cents(brokerage) else { return }
        store.change { try $0.sell(h.id, shares: qty, priceUSD: unit, brokerageUSD: fee) }
        if store.error == nil { shares = "" }
    }
}
@MainActor struct PocketSmithView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var feeds = FeedRobot.shared
    @State private var key = ""
    @State private var accounts: [PSAccount] = []
    @State private var choices: [UUID: Int] = [:]
    @State private var wage = ""
    @State private var allowance = ""
    @State private var loading = false
    @State private var disconnecting = false
    @State private var login = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            Form {
                if let link = store.state.pocketsmith { linked(link) } else { setup }
            }
            .navigationTitle("Bank sync").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
            .sheet(isPresented: Binding(get: { feeds.running && feeds.visible }, set: { if !$0 { feeds.finish() } })) { FeedRefreshView() }
            .onAppear { wage = store.state.pocketsmith?.wageKeyword ?? ""; allowance = store.state.pocketsmith?.allowanceKeyword ?? ""; login = Keychain.read("login") ?? "" }
        }
    }
    @ViewBuilder private var setup: some View {
        Section {
            SecureField("PocketSmith developer key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(loading ? "Finding accounts…" : "Find my accounts") {
                loading = true
                Task {
                    do { accounts = try await PocketSmithClient(key: key.trimmingCharacters(in: .whitespaces)).accounts() } catch { store.error = error.localizedDescription }
                    loading = false
                }
            }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || loading)
        } header: { Text("1 · Developer key") } footer: { Text("In PocketSmith on the web: Settings → Security → Manage developer keys → create a key. It is stored in this iPhone's Keychain and only reads your PocketSmith data. It is never included in backups.") }
        if !accounts.isEmpty {
            Section("2 · Match your accounts") {
                ForEach(store.state.accounts) { mine in
                    Picker(mine.name, selection: Binding(get: { choices[mine.id] }, set: { choices[mine.id] = $0 })) {
                        Text("Don’t sync").tag(Int?.none)
                        ForEach(accounts) { Text($0.label).tag(Int?.some($0.id)) }
                    }
                }
            }
            Section {
                TextField("Wages payer contains, e.g. employer name", text: $wage)
                TextField("Allowance payer contains, e.g. parent’s name", text: $allowance)
            } header: { Text("3 · Recognise your income · optional") } footer: { Text("Matching deposits are recorded as wages or allowance and your savings rule is applied. Other deposits wait in Activity for you to review.") }
            Section {
                Button(store.syncing ? "Linking…" : "Link and use PocketSmith balances") {
                    Task { await store.linkPocketSmith(key: key.trimmingCharacters(in: .whitespaces), choices: choices, accounts: accounts, wage: wage, allowance: allowance) }
                }.disabled(choices.isEmpty || store.syncing)
            } footer: { Text(store.state.demo ? "Demo data is loaded. Linking removes all demo examples first, then sets each matched account's balance to match PocketSmith today. Re-enter your savings, emergency and investment amounts in Settings afterwards." : "Each matched account's balance is set to match PocketSmith today. Transactions from before linking are not imported again. Your savings, emergency and investment reservations stay as they are.") }
        }
    }
    @ViewBuilder private func linked(_ link: PocketSmithLink) -> some View {
        Section {
            if let last = link.lastSync { LabeledContent("Last sync", value: last.formatted(date: .abbreviated, time: .shortened)) }
            Button(store.syncing ? "Syncing…" : "Sync now") {
                // With a saved login, sign in to PocketSmith in view and refresh the feeds first; it syncs when that finishes.
                if Keychain.read("password") != nil { feeds.start(store, visible: true) } else { Task { await store.syncPocketSmith() } }
            }.disabled(store.syncing || feeds.running)
        } footer: { Text("Checks automatically when you open MoneyPilot (at most every 15 minutes) and in the background every few hours when iOS allows. Each check imports new transactions, refreshes balances and looks for new PocketSmith accounts. PocketSmith usually refreshes from your bank about once a day.") }
        let unlinked = (link.known ?? [:]).filter { link.accountMap[$0.key] == nil }.sorted { $0.value < $1.value }
        if !unlinked.isEmpty {
            Section {
                ForEach(unlinked, id: \.key) { item in
                    Menu {
                        Button("Add as a new MoneyPilot account") { Task { await store.linkAccount(item.key, to: nil) } }
                        ForEach(store.state.accounts.filter { a in !link.accountMap.values.contains(a.id) }) { a in Button("Use for \(a.name)") { Task { await store.linkAccount(item.key, to: a.id) } } }
                    } label: { Label(item.value, systemImage: "plus.circle") }
                }
            } header: { Text("Found in PocketSmith · not synced") } footer: { Text("Linking imports this account's last \(Store.historyDays) days and matches its balance.") }
        }
        Section {
            ForEach(store.state.accounts.filter { link.accountMap.values.contains($0.id) }) { account in
                let pending = store.engine.pending(account.id)
                MoneyRow(label: pending == 0 ? account.name : "\(account.name) · \(money(abs(pending))) pending", value: store.engine.accountBalance(account.id))
            }
            ForEach(store.engine.drifted, id: \.pocketsmithID) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(item.account.name): PocketSmith shows \(money(item.theirs)) (\(money(store.engine.matched(item))) after pending), a difference of \(money(store.engine.matched(item) - store.engine.accountBalance(item.account.id))).").font(.caption).foregroundStyle(.orange)
                    Button("Match PocketSmith balance") { store.matchBalance(item.pocketsmithID, to: item.theirs) }.font(.caption)
                }
            }
            Button(store.syncing ? "Importing…" : "Import past \(Store.historyDays) days & match balances") { Task { await store.importHistory() } }.disabled(store.syncing)
        } header: { Text("Accounts & balance check") } footer: { Text("Pending transactions are already taken off these balances. Importing past days adds anything missing, without applying your savings rule to old income, then sets balances to PocketSmith's.") }
        Section {
            TextField("PocketSmith email or username", text: $login).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField(Keychain.read("password") == nil ? "PocketSmith password" : "Password saved · type to change", text: $password).textContentType(.password)
            Button("Save login") {
                _ = Keychain.save(login.trimmingCharacters(in: .whitespaces), account: "login")
                _ = Keychain.save(password, account: "password"); password = ""
            }.disabled(login.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            Toggle("Refresh bank feeds when I open MoneyPilot", isOn: Binding(get: { link.autoRefresh == true }, set: { on in store.change { $0.pocketsmith?.autoRefresh = on } }))
            if let at = link.feedsRefreshed { LabeledContent("Feeds last refreshed", value: at.formatted(date: .abbreviated, time: .shortened)) }
        } header: { Text("Sign in for me") } footer: { Text("MoneyPilot signs in to the PocketSmith website out of sight while you use the app, presses refresh on each bank feed, then imports what arrives. Sync now signs you in and leaves PocketSmith open for you; tap Done to import. The daily refresh runs out of sight, with only the Dynamic Island showing it. Automatic refresh runs at most once a day. Your login is kept in this iPhone's Keychain and never backed up. The PocketSmith page only appears if it needs you, for example to type a code. Keep MoneyPilot open for the few seconds it takes; iOS pauses it if you leave.") }
        Section("Recognise your income") {
            TextField("Wages payer contains", text: $wage)
            TextField("Allowance payer contains", text: $allowance)
            Button("Save income rules") { store.change { $0.pocketsmith?.wageKeyword = wage; $0.pocketsmith?.allowanceKeyword = allowance } }
        }
        Section { Button("Disconnect PocketSmith", role: .destructive) { disconnecting = true } } footer: { Text("Imported transactions stay in MoneyPilot.") }
            .confirmationDialog("Stop syncing with PocketSmith?", isPresented: $disconnecting, titleVisibility: .visible) { Button("Disconnect", role: .destructive) { store.unlinkPocketSmith() } }
    }
}
@MainActor struct SubscriptionsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    var e: Engine { store.engine }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MoneyRow(label: "Per month", value: e.monthlySubscriptions)
                    MoneyRow(label: "Per year", value: e.monthlySubscriptions * 12)
                    Button("Add subscription", systemImage: "plus") { adding = true }
                }
                Section {
                    if store.state.subs.isEmpty { Text("None tracked yet. Add one, or add those found in your transactions below.").foregroundStyle(.secondary) }
                    ForEach(store.state.subs.sorted { e.nextCharge($0) < e.nextCharge($1) }) { sub in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sub.name)
                                Text("\(sub.cycle.rawValue) · next \(e.nextCharge(sub).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(money(sub.amount)).bold()
                        }
                        .swipeActions { Button("Remove", role: .destructive) { store.change { $0.subs.removeAll { $0.id == sub.id } } } }
                    }
                } header: { Text("Tracking") } footer: { Text("Next charge follows the latest matching bank transaction. Swipe left to stop tracking; this does not cancel the subscription itself.") }
                let found = e.detectedSubscriptions()
                if !found.isEmpty {
                    Section {
                        ForEach(found) { sub in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) { Text(sub.name); Text("\(sub.cycle.rawValue) · \(money(sub.amount))").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("Add") { store.change { s in s.subs.append(sub); s.entries.indices.filter { s.entries[$0].kind == .expense && Engine.merchantKey(s.entries[$0].name) == sub.keyword }.forEach { s.entries[$0].category = .subscriptions } } }.buttonStyle(.bordered)
                            }
                        }
                        Button("Add all \(found.count)") { store.change { s in for sub in found { s.subs.append(sub); s.entries.indices.filter { s.entries[$0].kind == .expense && Engine.merchantKey(s.entries[$0].name) == sub.keyword }.forEach { s.entries[$0].category = .subscriptions } } } }
                    } header: { Text("Found in your transactions") } footer: { Text("Charges that repeat at a steady interval with a similar amount. Adding one also files its past charges under Subscriptions.") }
                }
            }
            .navigationTitle("Subscriptions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
            .sheet(isPresented: $adding) { SubscriptionEditor() }
        }
    }
}
@MainActor struct SubscriptionEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var cycle: Cycle = .monthly
    @State private var start = Date()
    var body: some View {
        EditorShell(title: "Add subscription") {
            Section {
                TextField("Name, as it appears on your statement", text: $name)
                TextField("Amount AUD", text: $amount).keyboardType(.decimalPad)
                Picker("Billed", selection: $cycle) { ForEach(Cycle.allCases) { Text($0.rawValue).tag($0) } }
                DatePicker("Last or next charge", selection: $start, displayedComponents: .date)
            } footer: { Text("Bank charges whose name contains this name update the next charge date automatically.") }
            Section {
                Button("Save") {
                    guard let value = cents(amount), value > 0 else { return }
                    // First word only, so "Spotify Premium" still matches a bank line like "SPOTIFY P0A1B2".
                    let keyword = Engine.merchantKey(name).split(separator: " ").first.map(String.init) ?? ""
                    store.change { $0.subs.append(Subscription(name: name, keyword: keyword.isEmpty ? name.lowercased() : keyword, amount: value, cycle: cycle, start: start)) }
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (cents(amount) ?? 0) <= 0)
            }
        }
    }
}
@MainActor struct OrganiseView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var skipped: Set<UUID> = []
    var body: some View {
        let proposals = store.engine.organiseProposals
        let chosen = Set(proposals.map(\.id)).subtracting(skipped)
        NavigationStack {
            List {
                Section {
                    Text(proposals.isEmpty ? "Everything is sorted. Nothing is waiting in Other." : "MoneyPilot can file \(proposals.count) transaction\(proposals.count == 1 ? "" : "s") from Other. Untick any you want to leave.").font(.subheadline)
                } footer: { Text("It uses, in order: categories you've set for a merchant, how you've filed that merchant before, a list of known Australian merchants, and PocketSmith's category. New bank transactions are filed the same way when they arrive.") }
                ForEach([nil] + Category.allCases.map(Optional.some), id: \.self) { category in
                    let items = proposals.filter { category == nil ? $0.stockDeposit : !$0.stockDeposit && $0.category == category }
                    if !items.isEmpty { Section {
                        ForEach(items) { p in
                            Button {
                                if skipped.contains(p.id) { skipped.remove(p.id) } else { skipped.insert(p.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: skipped.contains(p.id) ? "circle" : "checkmark.circle.fill").foregroundStyle(.mint)
                                    VStack(alignment: .leading, spacing: 2) { Text(p.name).lineLimit(1).foregroundStyle(.primary); Text(p.reason).font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Text(money(p.amount)).font(.subheadline).foregroundStyle(.primary)
                                }
                            }
                        }
                    } header: { Label(category?.rawValue ?? "Stock deposits", systemImage: category?.icon ?? "chart.line.uptrend.xyaxis") } }
                }
            }
            .navigationTitle("Auto-organise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { DismissButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("File \(chosen.count)") { store.change { $0.organise(chosen) }; dismiss() }.disabled(chosen.isEmpty)
                }
            }
        }
    }
}

// MARK: Sign in to PocketSmith and refresh the bank feeds
/// Shown only when the hidden sign-in needs you: a code to type, a wrong password, or a page it doesn't recognise.
@MainActor struct FeedRefreshView: View {
    @ObservedObject private var robot = FeedRobot.shared
    var body: some View {
        NavigationStack {
            WebPage(view: robot.web)
                .safeAreaInset(edge: .top) {
                    Label(robot.status, systemImage: robot.stuck ? "hand.tap.fill" : "arrow.triangle.2.circlepath").font(.footnote.weight(.semibold)).foregroundStyle(robot.stuck ? .orange : .primary)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                }
                .navigationTitle("PocketSmith").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { robot.finish() } } }
        }
    }
}
/// The one web view moves between the hidden spot behind the app and the sheet, so each place holds it in its own box.
struct WebPage: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> UIView { let box = UIView(); adopt(box); return box }
    func updateUIView(_ box: UIView, context: Context) { if view.superview !== box { adopt(box) } }
    private func adopt(_ box: UIView) {
        view.frame = box.bounds; view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.addSubview(view)
    }
}
/// Signs in to PocketSmith's website out of sight (the page sits behind the app) and presses refresh on every bank feed.
/// Steps: login → (any code you are asked for) → Feeds → press refresh. Only a banner at the top of the app Island show progress.
/// shortcut: relies on PocketSmith's login field IDs and refresh button wording; if they redesign, it stops and shows the page for you to finish by hand.
@MainActor final class FeedRobot: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = FeedRobot()
    /// MK4.1: PocketSmith's desktop site, as Safari on a Mac sees it (wider, and steadier for the automatic sign-in).
    /// The default data store keeps PocketSmith's "remember me" cookie, so later runs often skip the login page.
    let web: WKWebView = {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        return view
    }()
    @Published private(set) var running = false
    @Published private(set) var stuck = false // true shows the page so you can finish
    @Published private(set) var visible = false // Started from Bank sync → Sync now: the page shows the whole time
    @Published private(set) var status = ""
    private var store: Store?
    private var submitted = false
    private var reachedFeeds = false
    private var run = 0
    private static let feeds = URL(string: "https://my.pocketsmith.com/feeds")!

    func start(_ store: Store, visible: Bool = false) {
        guard !running || stuck else { return } // A run waiting on you can be started over.
        self.store = store; self.visible = visible
        running = true; stuck = false; submitted = false; reachedFeeds = false; run += 1
        let thisRun = run
        store.change { $0.pocketsmith?.feedsRefreshed = Date() } // An attempt counts, so a failing login doesn't pop up every time you open the app.
        web.navigationDelegate = self
        say("Logging in to PocketSmith…")
        web.load(URLRequest(url: URL(string: "https://my.pocketsmith.com/login")!))
        Task { // Never leave it spinning out of sight.
            try? await Task.sleep(for: .seconds(90))
            if running && !stuck && !visible && run == thisRun { say("PocketSmith is taking too long. Finish on screen, then Done.", stuck: true) }
        }
    }
    /// Done (or the page closed): stop, and sync if the feeds were reached. After Sync now you did the refreshing, so import straight away.
    func finish() {
        guard running, let store else { return }
        running = false; stuck = false
        let refreshed = reachedFeeds, manual = visible
        Task {
            if manual { store.activity = "Syncing MoneyPilot…"; await store.syncPocketSmith(); store.activity = nil }
            else if refreshed { await store.afterFeedRefresh() } else { store.activity = nil }
        }
    }
    private func say(_ text: String, stuck: Bool = false) {
        status = text; self.stuck = stuck
        store?.activity = stuck ? nil : text // When it needs you, the PocketSmith page itself comes up instead.
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { await step() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard running else { return }
        say("PocketSmith could not be reached: \(error.localizedDescription)", stuck: true)
    }
    private func step() async {
        guard running, !reachedFeeds, let path = web.url?.path else { return }
        if path.hasPrefix("/login") {
            guard !submitted, let login = Keychain.read("login"), let password = Keychain.read("password") else {
                return say(submitted ? "PocketSmith didn’t accept the login. Sign in on screen, or fix it in Bank sync." : "Save your PocketSmith login in Bank sync first.", stuck: true)
            }
            submitted = true
            do { _ = try await web.callAsyncJavaScript(Self.fill, arguments: ["login": login, "password": password], contentWorld: .page) }
            catch { say("Couldn’t fill in the login form. Sign in on screen.", stuck: true) }
        } else if visible {
            // Sync now: just signed in. You refresh what you want; Done imports it.
            reachedFeeds = true
            say("Signed in. Refresh your feeds in PocketSmith, then tap Done.")
        } else if path.hasPrefix("/feeds") {
            reachedFeeds = true
            say("Refreshing bank feeds…")
            var pressed = 0
            for _ in 0..<10 where pressed == 0 { // The feed list draws a moment after the page loads.
                try? await Task.sleep(for: .seconds(1))
                pressed = (try? await web.callAsyncJavaScript(Self.refresh, contentWorld: .page) as? Int) ?? 0
            }
            guard pressed > 0 else { return say("Couldn’t find the refresh button. Tap it on screen, then Done.", stuck: true) }
            try? await Task.sleep(for: .seconds(4))
            if await asksForCode() { return say("Your bank wants a code. Enter it on screen, then Done.", stuck: true) }
            finish()
        } else if await asksForCode() {
            say("Finish signing in on screen (e.g. your PocketSmith code).", stuck: true)
        } else {
            say("Opening your bank feeds…")
            web.load(URLRequest(url: Self.feeds))
        }
    }
    private func asksForCode() async -> Bool {
        (try? await web.callAsyncJavaScript(Self.codeField, contentWorld: .page) as? Bool) ?? false
    }
    private static let fill = """
        const set = (id, value) => { const el = document.getElementById(id); el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); };
        set('user_session_login', login); set('user_session_password', password);
        const remember = document.getElementById('user_session_remember_me'); if (remember) remember.checked = true;
        const form = document.getElementById('new_user_session');
        form.requestSubmit ? form.requestSubmit() : form.submit();
        """
    private static let refresh = """
        const words = /^(refresh|sync|update)( now| feeds?| all)?$/i;
        const buttons = [...document.querySelectorAll('button, a, [role=button]')]
            .filter(b => b.offsetParent && words.test((b.innerText || b.getAttribute('aria-label') || b.title || '').trim()));
        buttons.forEach(b => b.click());
        return buttons.length;
        """
    private static let codeField = """
        return [...document.querySelectorAll('input[autocomplete=one-time-code], input[type=password], input[name*=otp i], input[name*=code i], input[name*=token i]:not([type=hidden])')]
            .some(i => i.offsetParent);
        """
}
