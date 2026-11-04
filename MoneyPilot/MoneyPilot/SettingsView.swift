import SwiftUI

@MainActor struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FinanceState()
    @State private var openedCash: Money = 0 // Stake cash when Settings opened: only a change you typed is saved
    @State private var exporting = false
    @State private var reset = false
    @State private var demo = false
    @State private var loaded = false
    @State private var finnhubKey = ""
    @State private var importing = false
    @State private var backup: FullBackup?
    @State private var backingUp = false
    @State private var saveWhenClosed = false // The save dialog can only open once the backup sheet has gone
    @State private var backupFile = BackupDocument(data: Data())
    @State private var secretsToRestore: FullBackup.Sealed?
    @State private var restorePassword = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Income rule") {
                    Stepper("Savings + investing: \(draft.settings.futurePercent)%", value: $draft.settings.futurePercent, in: 0...100)
                    Stepper("Savings share of that: \(draft.settings.savingsSplit)%", value: $draft.settings.savingsSplit, in: 0...100)
                    Text("Default: 42% savings, 28% investment reserve, 30% spending. Applies to new wages and parents’ allowance entries. Existing allocations do not change.").font(.caption)
                }
                Section {
                    AmountField(label: "Fortnightly wages AUD", value: $draft.settings.expectedWages)
                    DatePicker("Next expected payday", selection: $draft.settings.nextPayday, displayedComponents: .date)
                    AmountField(label: "Monthly parents’ allowance AUD", value: $draft.settings.expectedAllowance)
                    DatePicker("Next allowance date", selection: Binding(get: { draft.settings.nextAllowance ?? draft.nextAllowance }, set: { draft.settings.nextAllowance = $0; draft.settings.allowanceDay = Calendar.current.component(.day, from: $0) }), displayedComponents: .date)
                    MoneyRow(label: "Total income per \(draft.period.rawValue)", value: Engine(state: draft).expectedPeriodIncome)
                } header: { Text("Expected income · wages + allowance") } footer: { Text("Your allowance counts as part of your income alongside wages: both set aside your savings and investing share, both feed budget suggestions, and both appear in upcoming paydays. It then repeats on the same day each month (the last day in shorter months). Expected income never changes recorded balances.") }
                Section {
                    ForEach(Array((draft.settings.timeOff ?? []).enumerated()), id: \.element.id) { k, _ in
                        DatePicker("From", selection: Binding(get: { draft.settings.timeOff?[k].from ?? Date() }, set: { draft.settings.timeOff?[k].from = $0; if let t = draft.settings.timeOff?[k], t.to < $0 { draft.settings.timeOff?[k].to = $0 } }), displayedComponents: .date)
                        DatePicker("To", selection: Binding(get: { draft.settings.timeOff?[k].to ?? Date() }, set: { draft.settings.timeOff?[k].to = $0 }), in: (draft.settings.timeOff?[k].from ?? .distantPast)..., displayedComponents: .date)
                        Button("Remove these dates", role: .destructive) { draft.settings.timeOff?.remove(at: k) }
                    }
                    Button("Add dates I'm not working", systemImage: "plus") {
                        let start = Calendar.current.startOfDay(for: Date())
                        draft.settings.timeOff = (draft.settings.timeOff ?? []) + [TimeOff(from: start, to: Calendar.current.date(byAdding: .day, value: 13, to: start)!)]
                    }
                } header: { Text("Time off · no wages") } footer: { Text("Paydays between these dates pay nothing; your allowance still counts. Everyday is planned to last until the first pay after them, using the allowance due meanwhile, and the pay before gives up savings and investing first if it has to. Payday reminders and late-pay warnings skip these dates.") }
                Section("Accounts · opening balances") {
                    ForEach($draft.accounts) { $account in
                        TextField("Account name", text: $account.name)
                        Picker("Used for", selection: $account.role) {
                            Text(AccountRole.guess(account.name).map { "Auto · \($0.title)" } ?? "Not set").tag(AccountRole?.none)
                            ForEach(AccountRole.allCases) { Text($0.title).tag(AccountRole?.some($0)) }
                        }
                        AmountField(label: "Opening balance AUD", value: $account.openingBalance)
                    }
                    Text("Enter balances as at the start of tracking. Later entries are added to these balances. Do not replace opening balances with today's balances after entering transactions. With bank sync, use the balance check in Activity → Bank sync instead.").font(.caption)
                }
                Section {
                    AmountField(label: "Must grow each month by", value: Binding(get: { draft.settings.savingsGrowth ?? 16_000 }, set: { draft.settings.savingsGrowth = $0 }))
                    Stepper("Withdrawals allowed a month: \(draft.settings.savingsWithdrawals ?? 1)", value: Binding(get: { draft.settings.savingsWithdrawals ?? 1 }, set: { draft.settings.savingsWithdrawals = $0 }), in: 0...10)
                } header: { Text("Savings account rules") } footer: { Text("Move money plans keep your Savings account at least this much above its balance on the 1st, never send investing money through it, and stop suggesting withdrawals once the monthly limit is used.") }
                Section("Existing cash reservations · AUD") {
                    AmountField(label: "Savings", value: $draft.savings)
                    AmountField(label: "Emergency fund", value: $draft.emergency)
                    AmountField(label: "Investment reserve", value: $draft.investmentReserve)
                    AmountField(label: "Emergency minimum", value: $draft.settings.emergencyMinimum)
                    Text("These are parts of your existing bank cash, not extra assets. A dollar should belong to one reservation only.").font(.caption)
                }
                Section("Stake manual reconciliation") {
                    AmountField(label: "Uninvested USD cash", value: $draft.stakeCashUSD)
                    HStack { Text("AUD per 1 USD"); Spacer(); TextField("Exchange rate", value: $draft.settings.audPerUSD, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    SecureField(Keychain.read("finnhub") == nil ? "Finnhub API key (free)" : "Finnhub key saved · paste to replace", text: $finnhubKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save key and refresh prices") {
                        guard Keychain.save(finnhubKey.trimmingCharacters(in: .whitespaces), account: "finnhub") else { store.error = "Could not store the key in the Keychain."; return }
                        finnhubKey = ""
                        Task { await store.refreshPrices(); draft.settings.audPerUSD = store.state.settings.audPerUSD }
                    }.disabled(finnhubKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("The AUD/USD rate updates automatically. Share prices update automatically once you add a free key from finnhub.io (Dashboard → API key). Stake cash and share counts are still entered by you.").font(.caption)
                }
                Section("Budgets & alerts") {
                    Picker("Budget period", selection: Binding(get: { draft.period }, set: { draft.settings.budgetPeriod = $0.rawValue; draft.settings.monthlyBudget = nil })) {
                        ForEach(BudgetPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.period != store.state.period {
                        Text("On save, every budget is converted to a \(draft.period.rawValue)ly amount (through its yearly total) and a new period starts \(draft.period == .month ? "from the 1st of this month" : draft.period == .fortnight ? "from your latest payday" : "today").").font(.caption).foregroundStyle(.orange)
                    }
                    AmountField(label: "Shopping limit (0 = none)", value: Binding(get: { draft.settings.shoppingLimit ?? 0 }, set: { draft.settings.shoppingLimit = $0 > 0 ? $0 : nil }))
                    Picker("Shopping limit per", selection: Binding(get: { draft.settings.shoppingMonthly == true }, set: { draft.settings.shoppingMonthly = $0 })) { Text("Fortnight").tag(false); Text("Month").tag(true) }
                    Toggle("Require Face ID to open", isOn: Binding(get: { draft.settings.appLock == true }, set: { draft.settings.appLock = $0 }))
                    Toggle("Auto-organise transactions", isOn: Binding(get: { draft.settings.autoOrganise != false }, set: { draft.settings.autoOrganise = $0 }))
                    Stepper("First warning: \(draft.settings.warningPercent)%", value: $draft.settings.warningPercent, in: 50...89)
                    Toggle("Notifications enabled", isOn: $draft.settings.notifications)
                    Button("Request iPhone notification permission") { Task { await store.enableNotifications(); draft.settings.notifications = store.state.settings.notifications } }
                    Text("Alerts at your first warning, 90% and 100%, showing amount and days left. They run whenever new transactions arrive, including background checks.").font(.caption)
                }
                Section("Data") {
                    Button("Back up everything", systemImage: "externaldrive.badge.checkmark") { backingUp = true }
                    Button("Restore from backup", systemImage: "arrow.counterclockwise") { importing = true }
                    Button("Load demo data") { demo = true }
                    Button("Clear data & start fresh", role: .destructive) { reset = true }
                    Text("Stored locally with iOS file protection. Backup exports contain your financial data. No analytics or bank credentials are collected. Keep your backup private.").font(.caption)
                }
                Section("Connections") {
                    Label(store.state.pocketsmith == nil ? "Banks · not connected" : "Banks · PocketSmith sync", systemImage: "building.columns")
                    Label("Stake · manual holdings", systemImage: "chart.line.uptrend.xyaxis")
                    Text("Manage bank sync from Activity. Automatic Stake reconciliation is not built yet. MoneyPilot only reads data; it cannot send payments or change your bank accounts.").font(.caption)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard draft.settings.audPerUSD.isFinite, draft.settings.audPerUSD > 0, draft.settings.audPerUSD < 100 else { store.error = "Enter a valid AUD per USD exchange rate."; return }
                        // Only editable fields are copied; transaction updates and permission changes are not overwritten.
                        store.change { s in let chosen = draft.period; var settings = draft.settings; settings.budgetPeriod = s.settings.budgetPeriod; settings.monthlyBudget = s.settings.monthlyBudget; s.settings = settings; s.switchPeriod(to: chosen); s.accounts = draft.accounts; s.savings = draft.savings; s.emergency = draft.emergency; s.investmentReserve = draft.investmentReserve; if draft.stakeCashUSD != openedCash { s.correctStakeCash(to: draft.stakeCashUSD) } }
                        if store.error == nil {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { if !loaded { draft = store.state; openedCash = store.state.stakeCashUSD; loaded = true } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                backup = try FullBackup.read(Data(contentsOf: url))
            } catch { store.error = "That file couldn't be read as a MoneyPilot backup. \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace everything with this backup?", isPresented: Binding(get: { backup != nil }, set: { if !$0 { backup = nil } }), titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                if let backup { store.restore(backup.state); draft = store.state; openedCash = store.state.stakeCashUSD; secretsToRestore = backup.secrets }
                backup = nil
            }
        } message: { Text("The backup from \(backup?.created.formatted(date: .abbreviated, time: .shortened) ?? "") has \(backup?.state.entries.count ?? 0) transactions. Everything currently in MoneyPilot is replaced.\(backup?.secrets != nil ? " It also has your keys and PocketSmith login; you'll be asked for its password next." : "")") }
        .alert("Restore keys and login?", isPresented: Binding(get: { secretsToRestore != nil }, set: { if !$0 { secretsToRestore = nil; restorePassword = "" } })) {
            SecureField("Backup password", text: $restorePassword)
            Button("Restore") {
                if let sealed = secretsToRestore { do { try store.restoreSecrets(sealed, password: restorePassword); store.notice = "Keys and PocketSmith login restored." } catch { store.error = error.localizedDescription } }
                secretsToRestore = nil; restorePassword = ""
            }
            Button("Skip", role: .cancel) { secretsToRestore = nil; restorePassword = "" }
        } message: { Text("Enter the password you chose when you made this backup. Skip to keep using this iPhone's keys.") }
        .sheet(isPresented: $backingUp, onDismiss: { if saveWhenClosed { saveWhenClosed = false; exporting = true } }) {
            BackupSheet { data in backupFile = BackupDocument(data: data); saveWhenClosed = true; backingUp = false }
        }
        .fileExporter(isPresented: $exporting, document: backupFile, contentType: .json, defaultFilename: "MoneyPilot-backup-\(Date().formatted(.iso8601.year().month().day()))") { result in
            switch result {
            case .success: store.notice = "Backup saved. Keep it somewhere safe, like iCloud Drive."
            case let .failure(error): store.error = error.localizedDescription
            }
        }
        .confirmationDialog("Replace all current data with examples?", isPresented: $demo, titleVisibility: .visible) { Button("Replace with demo data", role: .destructive) { store.change { $0 = FinanceState.sample() }; draft = store.state; openedCash = store.state.stakeCashUSD } } message: { Text("Export a backup first if you want to keep current data.") }
        .confirmationDialog("Delete all MoneyPilot data?", isPresented: $reset, titleVisibility: .visible) { Button("Delete and start fresh", role: .destructive) { store.change { $0 = FinanceState() }; draft = store.state; openedCash = store.state.stakeCashUSD } } message: { Text("This does not affect your real accounts. Export a backup first if needed.") }
    }
}
@MainActor struct AmountField: View {
    var label: String
    @Binding var value: Money
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(label); Spacer(); TextField("0.00", text: $text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused).frame(maxWidth: 150) }
            if !text.isEmpty && cents(text) == nil { Text("Enter a positive amount with digits and a decimal point.").font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { text = String(Double(value) / 100) }
        .onChange(of: text) { _, new in if let amount = cents(new) { value = amount } }
        .onChange(of: value) { _, new in if !focused { text = String(Double(new) / 100) } }
    }
}
/// MK4.0: choose whether keys and the PocketSmith login go in the backup, and the password that locks them.
@MainActor struct BackupSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var done: (Data) -> Void
    @State private var withKeys = true
    @State private var password = ""
    @State private var again = ""
    private var ready: Bool { !withKeys || (password.count >= 6 && password == again) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("\(store.state.entries.count) transactions, accounts, budgets, Afterpay, goals, Stake and every setting", systemImage: "checkmark.circle.fill")
                    Toggle("Include PocketSmith key & login and Finnhub key", isOn: $withKeys)
                    if withKeys {
                        SecureField("Backup password (6+ characters)", text: $password)
                        SecureField("Same password again", text: $again)
                        if !again.isEmpty && password != again { Text("The passwords don't match.").font(.caption).foregroundStyle(.orange) }
                    }
                } footer: { Text(withKeys ? "The keys and login are encrypted with this password; without it they can't be read. MoneyPilot can't recover a forgotten password, but your money data restores without it." : "Without them you'll re-enter your PocketSmith key and login after restoring.") }
                Section {
                    Button("Create backup") {
                        do { done(try store.backupEverything(password: withKeys ? password : nil)) } catch { store.error = error.localizedDescription }
                    }.disabled(!ready)
                } footer: { Text("Next, choose where to save it. iCloud Drive keeps it safe if you lose your iPhone. The file holds your financial data, so keep it private.") }
            }
            .navigationTitle("Back up everything").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

