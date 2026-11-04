import SwiftUI
import Charts
import LocalAuthentication

let ink = Color(red: 0.035, green: 0.065, blue: 0.09)
let panel = Color(red: 0.075, green: 0.115, blue: 0.15)

@MainActor struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 14) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(panel, in: RoundedRectangle(cornerRadius: 24)) }
}
@MainActor struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { content }.padding(.horizontal, 20).padding(.bottom, 30) }.background(ink) }
}
@MainActor struct MoneyRow: View {
    var label: String; var value: Money; var color: Color = .primary
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(money(value)).foregroundStyle(color).monospacedDigit() } }
}
@MainActor struct Header: View {
    var eyebrow: String; var title: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(eyebrow.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(.mint); Text(title).font(.largeTitle.bold()) }.padding(.top, 12) }
}
@MainActor struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var settings = false
    @State private var locked = false
    @State private var authenticating = false
    @ObservedObject private var feeds = FeedRobot.shared
    @Environment(\.scenePhase) private var phase
    private var lockOn: Bool { store.state.settings.appLock == true }
    /// Asks for Face ID (or the passcode) once; a second prompt never stacks on the first.
    private func unlock() {
        guard !authenticating else { return }
        authenticating = true
        LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your money") { ok, _ in
            DispatchQueue.main.async { authenticating = false; if ok { locked = false } }
        }
    }
    var body: some View {
        TabView {
            nav("Overview") { OverviewView() }.tabItem { Label("Overview", systemImage: "square.grid.2x2.fill") }
            nav("Budgets") { BudgetsView() }.tabItem { Label("Budgets", systemImage: "chart.pie.fill") }
            nav("Activity") { ActivityView() }.tabItem { Label("Activity", systemImage: "arrow.left.arrow.right") }
            nav("Wealth") { WealthView() }.tabItem { Label("Wealth", systemImage: "chart.line.uptrend.xyaxis") }
            nav("Guide") { GuideView() }.tabItem { Label("Guide", systemImage: "sparkles") }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        // The PocketSmith sign-in runs out of sight behind the app; its page only comes up when it needs you (never over the lock).
        .background { if feeds.running && !feeds.stuck && !feeds.visible { WebPage(view: feeds.web).opacity(0.01).allowsHitTesting(false).accessibilityHidden(true) } }
        .sheet(isPresented: Binding(get: { feeds.stuck && !feeds.visible && !(lockOn && locked) }, set: { if !$0 { feeds.finish() } })) { FeedRefreshView() }
        // Once a day, sign in to PocketSmith and refresh the bank feeds (only after Face ID when the app lock is on).
        .onChange(of: locked) { _, now in if !now && store.feedRefreshDue { feeds.start(store) } }
        .onChange(of: phase, initial: true) { _, now in
            if now == .active && locked { unlock() }
            if now == .background && lockOn { locked = true }
            if now == .active {
                store.reloadIfNeeded()
                // A finished budget period closes itself (leftovers roll forward once).
                if Date() >= store.state.periodEnd { store.closePeriod() } // MK3.6: weekly budgets used to be left out and never rolled.
                Task { await store.syncIfDue() }
                if !lockOn && store.feedRefreshDue { feeds.start(store) } // With Face ID on, the unlock starts it.
            }
            if now == .background { scheduleBackgroundCheck() }
        }
        // Hides balances in the app switcher and until unlocked.
        // MK4.1: PocketSmith sign-in progress, in the app instead of the Dynamic Island.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let activity = store.activity {
                Label(activity, systemImage: "building.columns.fill").font(.footnote.weight(.semibold)).foregroundStyle(.mint)
                    .padding(.vertical, 6).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .overlay { if lockOn && (locked || phase != .active) { LockScreen(unlock: unlock).transition(.opacity) } }
        .task { if lockOn { locked = true; unlock() } }
        // While MoneyPilot is open, check the bank every hour as well.
        .task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(3_600)); await store.syncPocketSmith() } }
        .alert("Please check", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .alert("MoneyPilot", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) { Button("OK") { store.notice = nil } } message: { Text(store.notice ?? "") }
    }
    private func nav<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().navigationTitle("MoneyPilot").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Settings") } }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if store.state.demo { Text("DEMO DATA · Not connected to your accounts").font(.caption.bold()).frame(maxWidth: .infinity).padding(8).background(Color.orange.opacity(0.2)) }
                }
        }
    }
}
@MainActor struct OverviewView: View {
    @EnvironmentObject var store: Store
    @State private var appeared = false
    @State private var selected: Entry?
    @State private var fixing = false
    var e: Engine { store.engine }
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { return "Late night" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }
    var paceColor: Color { e.weekPace > 0 ? .orange : .mint }
    var body: some View {
        Page {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting.uppercased()).font(.caption.bold()).tracking(2).foregroundStyle(.mint)
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month())).font(.largeTitle.bold())
                }
                Spacer()
                SyncPill()
            }.padding(.top, 12)
            hero
            if !e.drifted.isEmpty { Label("\(e.drifted.count == 1 ? "An account balance differs" : "\(e.drifted.count) account balances differ") from PocketSmith. Check Activity → Bank sync.", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.subheadline).foregroundStyle(.orange) }
            if e.unallocated < 0 {
                Button { fixing = true } label: { Label("Your plan is overallocated by \(money(-e.unallocated)). Tap to see why and fix it.", systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange) }
                    .buttonStyle(.plain).sheet(isPresented: $fixing) { FixPlanView() }
            }
            AssetsCard()
            PayCard()
            MoveMoneyCard()
            SpareMoneySection()
            SpendingCard()
            if store.state.entries.isEmpty && !store.state.demo {
                Card {
                    Text("Start with your accounts").font(.headline)
                    Text("Connect bank sync in Activity, then set budgets in Budgets. Or explore with demo data first.").foregroundStyle(.secondary)
                    Button("Explore demo data") { store.change { $0 = FinanceState.sample() } }.buttonStyle(.bordered)
                }
            }
            let active = e.lines.filter { $0.limit > 0 }
            if !active.isEmpty {
                Text("This \(e.periodName) by category").font(.headline).padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) { ForEach(active) { PaceChip(line: $0, appeared: appeared) } }
                }.scrollClipDisabled()
            }
            let upcoming = e.upcoming()
            Card {
                HStack { Text("Next 7 days").font(.headline); Spacer(); Text(money(upcoming.filter { !$0.income }.reduce(0) { $0 + $1.amount })).font(.subheadline).foregroundStyle(.secondary) }
                if upcoming.isEmpty { Text("No subscriptions, Afterpay or paydays due.").foregroundStyle(.secondary) }
                ForEach(upcoming) { item in
                    HStack(spacing: 12) {
                        VStack(spacing: 0) {
                            Text(item.date.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                            Text(item.date.formatted(.dateTime.day())).font(.headline)
                        }.frame(width: 38)
                        Image(systemName: item.icon).foregroundStyle(.mint).frame(width: 22)
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Text("\(item.income ? "+" : "−")\(money(item.amount))").bold().foregroundStyle(item.income ? .mint : .primary)
                    }
                }
            }
            ForEach(e.suggestions.filter { $0.id != "rule" }.prefix(2)) { tip in
                Card {
                    Label(tip.title, systemImage: "sparkles").font(.headline).foregroundStyle(.mint)
                    Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                }.transition(.move(edge: .bottom).combined(with: .opacity))
            }
            let recent = store.state.entries.sorted { $0.date > $1.date }.prefix(5)
            if !recent.isEmpty {
                Card {
                    Text("Recent activity").font(.headline)
                    ForEach(Array(recent)) { entry in
                        Button { selected = entry } label: {
                            HStack(spacing: 12) {
                                Image(systemName: ActivityView.icon(ActivityView.group(entry))).foregroundStyle(.mint).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) { Text(entry.name).lineLimit(1); Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text("\(entry.kind.inflow ? "+" : entry.kind == .transfer ? "" : "−")\(money(entry.amount))").foregroundStyle(entry.kind.inflow ? .mint : .primary).font(.subheadline.bold())
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Card {
                Text("Protected for your future").font(.headline)
                MoneyRow(label: "Savings", value: store.state.savings, color: .mint)
                MoneyRow(label: "Emergency fund", value: store.state.emergency, color: store.state.emergency < store.state.settings.emergencyMinimum ? .orange : .primary)
                MoneyRow(label: "Ready to invest", value: store.state.investmentReserve)
                MoneyRow(label: "Investments", value: e.investmentsAUD)
            }
        }
        .refreshable { store.recalculate() } // PocketSmith only updates once or twice a day, so pulling down never calls it.
        .sheet(item: $selected) { EntryDetail(entry: $0) }
        .animation(.snappy, value: store.state.entries.count)
        .onAppear { withAnimation(.spring(duration: 1.0)) { appeared = true } }
    }
    private var hero: some View {
        Card {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 12)
                    Circle().trim(from: 0, to: appeared ? min(1, e.weekUsed) : 0)
                        .stroke(paceColor.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(e.daysLeft)").font(.title2.bold()).contentTransition(.numericText())
                        Text(e.daysLeft == 1 ? "day left" : "days left").font(.caption2).foregroundStyle(.secondary)
                    }
                }.frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SPARE MONEY").font(.caption.bold()).tracking(1.5).foregroundStyle(.mint)
                    Text(money(e.shoppingAvailable)).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText(value: Double(e.shoppingAvailable))).animation(.snappy, value: e.shoppingAvailable)
                    Text("Takeaway: \(money(e.takeawayLeft)) left this \(e.periodName)").font(.subheadline.bold())
                    Label(e.weekPace > 0 ? "\(money(e.weekPace)) ahead of pace" : "On track", systemImage: e.weekPace > 0 ? "hare.fill" : "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundStyle(paceColor)
                }
            }
            Divider()
            MoneyRow(label: "Bank cash", value: e.bankCash)
        }
    }
}
@MainActor struct PaceChip: View {
    @EnvironmentObject var store: Store
    var line: BudgetLine
    var appeared: Bool
    var body: some View {
        let pace = store.engine.pace(line)
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle().trim(from: 0, to: appeared ? min(1, max(0, line.ratio)) : 0).stroke(line.ratio >= 0.9 ? Color.orange : .mint, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: line.category.icon).font(.caption).foregroundStyle(.mint)
            }.frame(width: 44, height: 44)
            Text(line.category.rawValue).font(.subheadline.bold())
            Text("\(money(store.engine.spendable(line.category))) left").font(.caption)
            Text(pace > 0 ? "\(money(pace)) ahead" : "On pace").font(.caption2.bold()).foregroundStyle(pace > 0 ? .orange : .secondary)
        }
        .padding(14).frame(width: 130, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }
}
@MainActor struct SyncPill: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let last = store.state.pocketsmith?.lastSync {
            HStack(spacing: 6) {
                if store.syncing { ProgressView().controlSize(.mini) } else { Circle().fill(.mint).frame(width: 7, height: 7) }
                if store.syncing { Text("Syncing") } else { Text(last, style: .relative) }
            }
            .font(.caption2.bold()).padding(.horizontal, 10).padding(.vertical, 6)
            .background(panel, in: Capsule())
        }
    }
}
@MainActor struct BudgetsView: View {
    @EnvironmentObject var store: Store
    @State private var selected: Category?
    @State private var showSuggestions = false
    @State private var goal = false
    @State private var closing = false
    @State private var reviewing = false
    @State private var view: BudgetPeriod?
    var body: some View {
        let e = store.engine
        let shown = view ?? store.state.period
        let native = shown == store.state.period // Your real budget period: editable, with cash checks and carry-forward.
        let start = native ? store.state.periodStart : e.chartStart(shown)
        let lines = native ? e.lines : e.review(shown, start: start)
        let income = e.expectedIncome(per: shown)
        Page {
            Header(eyebrow: "A job for every dollar", title: "Plan your \(shown.rawValue).")
            Picker("Show", selection: Binding(get: { shown }, set: { view = $0 })) {
                Text("Week").tag(BudgetPeriod.week); Text("Fortnight").tag(BudgetPeriod.fortnight); Text("Month").tag(BudgetPeriod.month)
            }.pickerStyle(.segmented)
            HStack { Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(Calendar.current.date(byAdding: .day, value: -1, to: shown.end(from: start))!.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary); Spacer() }
            if !native {
                Card {
                    Label("Your budget runs \(store.state.period.rawValue)ly. This shows it as a \(shown.rawValue): each budget × \(store.state.period.perYear) ÷ \(shown.perYear), against what you've spent this \(shown.rawValue).", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    Button("Budget \(shown.rawValue)ly instead") { store.change { $0.switchPeriod(to: shown) }; view = nil }.font(.caption.bold())
                }
            }
            if income.total > 0 {
                Card {
                    HStack { Text("Income this \(shown.rawValue)").font(.headline); Spacer(); Text(money(income.total)).font(.headline).foregroundStyle(.mint) }
                    MoneyRow(label: "Wages", value: income.wages)
                    MoneyRow(label: "Parents’ allowance", value: income.allowance)
                    let split = e.allocation(income.total)
                    Text("\(money(split.savings)) to savings · \(money(split.investment)) to investing · \(money(split.spending)) to spend").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Suggested budgets", systemImage: "sparkles") { showSuggestions = true }.buttonStyle(.borderedProminent).foregroundStyle(ink)
                Button("Check budget", systemImage: "calendar") { reviewing = true }.buttonStyle(.bordered)
            }
            ForEach(lines) { line in
                Button { selected = line.category } label: {
                    Card {
                        HStack { Label(line.category.rawValue, systemImage: line.category.icon).font(.headline); Spacer(); Text("\(Int(line.ratio * 100))%").foregroundStyle(line.ratio > 0.9 ? .orange : .mint) }
                        ProgressView(value: min(1, max(0, line.ratio)))
                        HStack { Text("\(money(line.used)) of \(money(line.limit))"); Spacer(); Text("\(money(native ? e.spendable(line.category) : max(0, line.remaining))) left").bold() }.font(.caption)
                        if line.committed > 0 { Text("Includes \(money(line.committed)) of Afterpay instalments due this \(shown.rawValue)").font(.caption).foregroundStyle(.secondary) }
                        if line.goalReserved > 0 { Text("Includes \(money(line.goalReserved)) reserved for goals").font(.caption).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain).disabled(!native) // Budgets are edited in their own period's amounts.
            }
            HStack { Text("Purchase goals").font(.title2.bold()); Spacer(); Button { goal = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Add purchase goal") }
            if store.state.goals.isEmpty { Text("Plan a watch, holiday or something just for you.").foregroundStyle(.secondary) }
            ForEach(store.state.goals) { g in GoalCard(goal: g) }
            Card {
                Text("Unused money, carried forward").font(.headline)
                Text("At the end of each \(store.engine.periodName), close it to start the next. Cash-backed leftovers go into shopping by default. Goals and outstanding Afterpay remain protected. Inactive periods never create extra money.").font(.subheadline).foregroundStyle(.secondary)
                Button("Close \(store.engine.periodName) & roll forward") { closing = true }.disabled(Date() < store.state.periodEnd)
            }
        }
        .sheet(item: $selected) { BudgetEditor(category: $0) }
        .sheet(isPresented: $showSuggestions) { BudgetSuggestionsView() }
        .sheet(isPresented: $reviewing) { BudgetReviewView() }
        .sheet(isPresented: $goal) { GoalEditor() }
        .confirmationDialog("Close this budget \(store.engine.periodName)?", isPresented: $closing, titleVisibility: .visible) { Button("Roll forward once") { store.closePeriod() } } message: { Text("This starts the next \(store.engine.periodName). 30% of what you didn't spend stays in Everyday as a buffer and the rest goes to spare money. Your budgets stay the same.") }
    }
}
@MainActor struct GoalCard: View {
    @EnvironmentObject var store: Store
    var goal: Goal
    @State private var amount = ""
    @State private var paying = false
    var body: some View {
        Card {
            HStack { Text(goal.name).font(.headline); Spacer(); Text(money(goal.target)).foregroundStyle(.secondary) }
            ProgressView(value: min(1, Double(goal.reserved) / Double(max(1, goal.target))))
            Text("\(money(goal.reserved)) reserved · \(money(max(0, goal.target - goal.reserved))) to go").font(.caption)
            if goal.weekly > 0 {
                Text("About \(Int(ceil(Double(max(0, goal.target - goal.reserved)) / Double(goal.weekly * 2)))) pays at up to \(money(goal.weekly * 2)) each, set aside on payday from up to half of what the pay leaves spare.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Top-up AUD", text: $amount).keyboardType(.decimalPad)
                Button("Reserve") { if let value = cents(amount) { store.allocateGoal(goal.id, amount: value); amount = "" } }.disabled(cents(amount) == nil)
            }
            HStack {
                Button("Release funds") { store.change { s in if let i = s.goals.firstIndex(where: { $0.id == goal.id }) { s.goals[i].reserved = 0 } } }.disabled(goal.reserved == 0)
                Spacer()
                Button("Record purchase") { paying = true }.disabled(goal.reserved < goal.target)
            }.font(.caption)
        }
        .confirmationDialog("Which account paid for this purchase?", isPresented: $paying, titleVisibility: .visible) { ForEach(store.state.accounts) { a in Button(a.name) { store.buyGoal(goal.id, account: a.id) } } } message: { Text("This records the purchase and releases its reservation. It does not make a bank payment.") }
    }
}
@MainActor struct ActivityView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var afterpay = false
    @State private var bank = false
    @State private var subscriptions = false
    @State private var organising = false
    @State private var selected: Entry?
    @State private var search = ""
    @State private var filter = "All"
    static let groups = Category.allCases.map(\.rawValue) + ["Income", "Stock deposits", "Transfers"]
    static func group(_ e: Entry) -> String {
        switch e.kind {
        case .transfer: return "Transfers"
        case .investment, .fromStake: return "Stock deposits"
        case .expense, .refund, .repayment: return e.category.rawValue
        default: return "Income"
        }
    }
    static func icon(_ group: String) -> String {
        Category(rawValue: group)?.icon ?? ["Income": "arrow.down.left", "Stock deposits": "chart.line.uptrend.xyaxis"][group] ?? "arrow.left.arrow.right"
    }
    var filtered: [Entry] { store.state.entries.filter { (filter == "All" || Self.group($0) == filter) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) } }
    var months: [(start: Date, entries: [Entry])] {
        Dictionary(grouping: filtered) { Calendar.current.dateInterval(of: .month, for: $0.date)!.start }
            .map { (start: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }.sorted { $0.start > $1.start }
    }
    /// This month's total per group: spending net of refunds, income received, money sent to investing.
    var thisMonth: [(group: String, total: Money)] {
        let start = Calendar.current.dateInterval(of: .month, for: Date())!.start
        let totals = Dictionary(grouping: store.state.entries.filter { $0.date >= start && $0.kind != .transfer }, by: Self.group)
            .mapValues { $0.reduce(Money(0)) { $0 + ($1.kind == .refund ? -$1.amount : $1.amount) } }
        return Self.groups.compactMap { g -> (group: String, total: Money)? in
            guard let total = totals[g], total != 0 else { return nil }
            return (g, total)
        }
    }
    var body: some View {
        List {
            Section {
                Button("Add transaction", systemImage: "plus.circle.fill") { adding = true }
                Button("Auto-organise\(store.engine.organiseProposals.isEmpty ? "" : " · \(store.engine.organiseProposals.count) to sort")", systemImage: "wand.and.stars") { organising = true }
                Button("Subscriptions · \(money(store.engine.monthlySubscriptions)) a month", systemImage: "repeat") { subscriptions = true }
                Button("Manage Afterpay", systemImage: "calendar.badge.clock") { afterpay = true }
                Button(store.state.pocketsmith == nil ? "Connect bank sync" : "Bank sync · PocketSmith", systemImage: "building.columns") { bank = true }
            }
            let review = store.state.entries.filter { $0.needsReview == true }.sorted { $0.date > $1.date }
            if !review.isEmpty {
                Section("Needs review · \(review.count)") { ForEach(review) { row($0) } }
            }
            if !thisMonth.isEmpty {
                Section("This month by category") {
                    ForEach(thisMonth, id: \.group) { item in
                        Button { filter = item.group } label: {
                            HStack { Label(item.group, systemImage: Self.icon(item.group)).foregroundStyle(.primary); Spacer(); Text(money(item.total)).bold().foregroundStyle(item.group == "Income" ? .mint : .primary) }
                        }
                    }
                }
            }
            Section {
                Picker("Show", selection: $filter) { ForEach(["All"] + Self.groups, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
                if filtered.isEmpty { Text(store.state.entries.isEmpty ? "No transactions yet. Connect bank sync or add one yourself." : "Nothing in \(filter) yet.").foregroundStyle(.secondary) }
            }
            ForEach(months, id: \.start) { month in
                Section(month.start.formatted(.dateTime.month(.wide).year())) { ForEach(month.entries) { row($0) } }
            }
        }.scrollContentBackground(.hidden).background(ink).searchable(text: $search)
            .sheet(isPresented: $adding) { EntryEditor() }
            .sheet(isPresented: $afterpay) { AfterpayView() }
            .sheet(isPresented: $bank) { PocketSmithView() }
            .sheet(isPresented: $subscriptions) { SubscriptionsView() }
            .sheet(isPresented: $organising) { OrganiseView() }
            .refreshable { store.recalculate() }
            .sheet(item: $selected) { EntryDetail(entry: $0) }
    }
    private func row(_ entry: Entry) -> some View {
        let reviewing = entry.needsReview == true
        return Button { selected = entry } label: {
            HStack(spacing: 12) {
                Image(systemName: Self.icon(Self.group(entry))).foregroundStyle(.mint).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).foregroundStyle(.primary).lineLimit(1)
                    Text(reviewing ? "Needs review" : Self.group(entry) == entry.category.rawValue ? entry.category.rawValue : entry.kind.rawValue).font(.caption).foregroundStyle(reviewing ? .orange : .secondary)
                    Text(entry.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entry.kind.inflow ? "+" : entry.kind == .transfer ? "" : "−")\(money(entry.amount))").foregroundStyle(entry.kind.inflow ? .mint : .primary).font(.subheadline.bold())
            }.padding(.vertical, 4)
        }
    }
}
@MainActor struct WealthView: View {
    @EnvironmentObject var store: Store
    @State private var holding = false
    @State private var selected: Holding?
    @State private var stakeMoney = false
    @State private var balanceFor: Account?
    @State private var checkingStake = false
    @State private var cancellingStake = false
    var e: Engine { store.engine }
    var body: some View {
        Page {
            Header(eyebrow: "The bigger picture", title: "Build your future.")
            Card {
                Text("NET WORTH · AUD").font(.caption.bold()).foregroundStyle(.mint)
                Text(money(e.netWorth)).font(.system(size: 38, weight: .bold, design: .rounded))
                MoneyRow(label: "Total assets", value: e.assets)
                MoneyRow(label: "Afterpay liabilities", value: e.afterpayDebt)
                Text("Net worth currently includes bank cash, Stake cash and holdings, less Afterpay. Other debts and assets are not included.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("Your accounts").font(.headline)
                ForEach(store.state.accounts) { a in
                    Button { balanceFor = a } label: { HStack { MoneyRow(label: a.name, value: e.accountBalance(a.id)); Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                }
                Text("Tap an account to set its balance from your bank app.").font(.caption2).foregroundStyle(.secondary)
                if let last = store.state.pocketsmith?.lastSync { Text("Synced with PocketSmith \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                else { Text("Manual balances · no bank connection").font(.caption).foregroundStyle(.orange) }
            }
            Card {
                HStack { Text("Stake · US portfolio").font(.headline); Spacer(); Button { holding = true } label: { Image(systemName: "plus.circle") }.accessibilityLabel("Add holding") }
                Text(money(e.investmentUSD, currency: "USD")).font(.title.bold())
                MoneyRow(label: "AUD equivalent", value: e.investmentsAUD)
                HStack {
                    Text("Stake cash: \(money(store.state.stakeCashUSD, currency: "USD"))").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check & fix") { checkingStake = true }.font(.subheadline)
                }
                if store.state.investmentReserve > 0 {
                    HStack {
                        Text("Waiting to go to Stake: \(money(store.state.investmentReserve))").foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { cancellingStake = true }.font(.subheadline).tint(.orange)
                    }
                    .confirmationDialog("Cancel \(money(store.state.investmentReserve)) waiting to go to Stake?", isPresented: $cancellingStake, titleVisibility: .visible) {
                        Button("Cancel it · keep it as cash", role: .destructive) { store.change { $0.investmentReserve = 0 } }
                    } message: { Text("It stops being set aside for investing and becomes normal cash for budgets and spare money. Each new pay still sets aside your investing share; change that in Settings.") }
                }
                let inside = e.stakeMoney
                if inside.basisAUD > 0 {
                    HStack {
                        Text("Gain/loss on money at Stake").foregroundStyle(.secondary); Spacer()
                        Text(money(inside.insideAUD)).bold().foregroundStyle(inside.insideAUD >= 0 ? .mint : .orange).monospacedDigit()
                    }
                    Text("Worth \(money(inside.worthAUD)) vs \(money(inside.basisAUD)) put in · includes currency moves and FX fees, not banked yet").font(.caption2).foregroundStyle(.secondary)
                }
                Button { stakeMoney = true } label: { Label("Actual profit & loss · money to & from Stake", systemImage: "arrow.left.arrow.right.circle") }.font(.subheadline)
                if !store.state.holdings.isEmpty {
                    HStack {
                        Text("Share profit").foregroundStyle(.secondary); Spacer()
                        Text("\(money(e.portfolioProfitUSD, currency: "USD")) · \(money(e.portfolioProfitAUD))").bold().foregroundStyle(e.portfolioProfitUSD >= 0 ? .mint : .orange).monospacedDigit()
                    }
                }
                HStack {
                    Text("1 USD = \(store.state.settings.audPerUSD.formatted(.number.precision(.fractionLength(4)))) AUD").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh prices", systemImage: "arrow.clockwise") { Task { await store.refreshPrices() } }.font(.caption).labelStyle(.titleAndIcon)
                }
                if Keychain.read("finnhub") == nil { Text("Add a free Finnhub key in Settings for live share prices. The exchange rate updates on its own.").font(.caption).foregroundStyle(.orange) }
                ForEach(store.state.holdings) { h in
                    Button { selected = h } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(h.symbol).bold(); Spacer(); Text(money(h.valueUSD, currency: "USD")) }
                            Text(h.shares > 0 ? "\(h.shares.formatted()) shares · avg \(money(h.averagePriceUSD, currency: "USD")) · now \(money(h.priceUSD, currency: "USD"))" : "Sold").font(.caption)
                            Text("Profit \(money(h.profitUSD, currency: "USD")) (\(h.profitPercent.formatted(.percent.precision(.fractionLength(1))))) · tap for details").font(.caption2).foregroundStyle(h.profitUSD >= 0 ? .mint : .orange)
                        }
                    }.buttonStyle(.plain)
                }
            }
            Card {
                Text("Asset history").font(.headline)
                if store.state.history.count < 2 { Text("Daily snapshots will appear as you use the app. No invented historical returns.").foregroundStyle(.secondary) }
                Chart(store.state.history) { p in LineMark(x: .value("Date", p.date), y: .value("Assets AUD", Double(p.assets) / 100)).foregroundStyle(.mint); PointMark(x: .value("Date", p.date), y: .value("Assets AUD", Double(p.assets) / 100)).foregroundStyle(.mint) }.frame(height: 180)
            }
        }.refreshable { await Task { await store.refreshPrices() }.value }.sheet(isPresented: $holding) { HoldingEditor(existing: nil) }.sheet(item: $selected) { HoldingDetail(id: $0.id) }.sheet(isPresented: $stakeMoney) { StakeMoneyView() }.sheet(item: $balanceFor) { SetBalanceView(id: $0.id) }.sheet(isPresented: $checkingStake) { StakeCheckView() }
    }
}
@MainActor struct GuideView: View {
    @EnvironmentObject var store: Store
    @State private var amount = ""
    @State private var destination = "savings"
    @State private var sheet: GuideSheet?
    @State private var whatIf: Category = .takeaway
    @State private var cut = 20.0
    @State private var showAll = false
    enum GuideSheet: String, Identifiable { case organise, subscriptions, afterpay, review, fixPlan; var id: String { rawValue } }
    var e: Engine { store.engine }
    var body: some View {
        let insights = e.insights
        let score = e.score
        Page {
            Header(eyebrow: "Explainable, adjustable", title: "Your financial guide.")
            scoreCard(score)
            Text(insights.isEmpty ? "Nothing needs your attention right now." : "What matters most, first. Every tip shows the numbers behind it; nothing moves unless you tap.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(showAll ? insights : Array(insights.prefix(6))) { tip in insightCard(tip) }
            if insights.count > 6 { Button(showAll ? "Show fewer" : "Show all \(insights.count) tips") { withAnimation(.snappy) { showAll.toggle() } }.font(.subheadline.bold()) }
            if let review = e.lastMonthReview { monthCard(review) }
            whatIfCard
            Card {
                Text("Allocate spare cash").font(.headline)
                MoneyRow(label: "Unallocated now", value: max(0, e.unallocated))
                Picker("Destination", selection: $destination) { Text("Savings").tag("savings"); Text("Investment reserve").tag("invest"); Text("Emergency fund").tag("emergency"); Text("Shopping").tag("shopping") }
                TextField("Amount AUD", text: $amount).keyboardType(.decimalPad)
                Button("Apply allocation") { if let v = cents(amount) { store.redirect(v, to: destination); amount = "" } }.buttonStyle(.bordered)
            }
            Card {
                Text("35-day cash forecast").font(.headline)
                let points = e.forecast()
                Chart(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.date), y: .value("Bank cash AUD", Double(point.balance) / 100)).foregroundStyle(.mint).lineStyle(StrokeStyle(lineWidth: 2))
                    RuleMark(y: .value("Protected", Double(e.protected) / 100)).foregroundStyle(Color.white.opacity(0.25)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }.frame(height: 180)
                Text("If you spend your budgets evenly, with expected wages, allowance and Afterpay on their dates. The dashed line is your protected savings, emergency and investing money; staying above it means you never touch them.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Text("Income · this \(e.periodName)").font(.headline)
                ForEach([EntryKind.wage, .allowance], id: \.self) { kind in MoneyRow(label: kind.rawValue, value: store.state.entries.filter { $0.kind == kind && e.inPeriod($0.date) }.reduce(0) { $0 + $1.amount }) }
                MoneyRow(label: "Total income", value: e.income, color: .mint)
                MoneyRow(label: "Stock deposits", value: e.contributions)
                Text("Your rule: of every $1,000 received, \(money(e.allocation(100_000).savings)) to savings, \(money(e.allocation(100_000).investment)) to investing and \(money(e.allocation(100_000).spending)) to spend.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .organise: OrganiseView()
            case .subscriptions: SubscriptionsView()
            case .afterpay: AfterpayView()
            case .review: BudgetReviewView()
            case .fixPlan: FixPlanView()
            }
        }
    }
    private func color(_ level: Insight.Level) -> Color {
        switch level { case .critical: return .red; case .warning: return .orange; case .opportunity: return .mint; case .good: return .green; case .info: return .secondary }
    }
    private func label(_ level: Insight.Level) -> String {
        switch level { case .critical: return "ACT NOW"; case .warning: return "WATCH"; case .opportunity: return "OPPORTUNITY"; case .good: return "GOING WELL"; case .info: return "GOOD TO KNOW" }
    }
    private func scoreCard(_ score: MoneyScore) -> some View {
        Card {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                    Circle().trim(from: 0, to: Double(score.total) / 100).stroke(score.total >= 60 ? Color.mint : .orange, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(score.total)").font(.title.bold()).contentTransition(.numericText())
                }.frame(width: 84, height: 84).accessibilityLabel("Money score \(score.total) out of 100")
                VStack(alignment: .leading, spacing: 4) {
                    Text("MONEY SCORE").font(.caption.bold()).tracking(1.5).foregroundStyle(.mint)
                    Text(score.label).font(.title3.bold())
                    Text("Out of 100, from the parts below.").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(score.parts) { part in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(part.name).font(.subheadline); Spacer(); Text("\(part.points)/\(part.max)").font(.subheadline.bold()).monospacedDigit() }
                    ProgressView(value: Double(part.points), total: Double(part.max)).tint(part.points * 2 >= part.max ? .mint : .orange)
                    Text(part.note).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func insightCard(_ tip: Insight) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tip.icon).font(.title3).foregroundStyle(color(tip.level)).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(label(tip.level)).font(.caption2.bold()).tracking(1.2).foregroundStyle(color(tip.level))
                    Text(tip.title).font(.headline)
                    Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let action = tip.action, let title = tip.actionTitle {
                        Button(title) { perform(action) }.buttonStyle(.bordered).font(.subheadline.bold()).padding(.top, 2)
                    }
                }
            }
        }
    }
    private func perform(_ action: Insight.Action) {
        switch action {
        case let .redirect(target, amount): store.redirect(amount, to: target)
        case .organise: sheet = .organise
        case .subscriptions: sheet = .subscriptions
        case .afterpay: sheet = .afterpay
        case .review: sheet = .review
        case .fixPlan: sheet = .fixPlan
        }
    }
    private func monthCard(_ r: MonthReview) -> some View {
        Card {
            HStack { Text("\(r.month.formatted(.dateTime.month(.wide))) in review").font(.headline); Spacer(); Button("Details") { sheet = .review }.font(.caption.bold()) }
            MoneyRow(label: "Spent", value: r.spent)
            if r.previousSpent > 0 {
                let change = Double(r.spent - r.previousSpent) / Double(r.previousSpent) * 100
                Text("\(change >= 0 ? "Up" : "Down") \(Int(abs(change).rounded()))% on the month before (\(money(r.previousSpent)))").font(.caption).foregroundStyle(change > 10 ? .orange : .secondary)
            }
            MoneyRow(label: "Income received", value: r.income)
            if let kept = r.kept { MoneyRow(label: "Kept (not spent)", value: r.income - r.spent, color: kept * 100 >= Double(store.state.settings.futurePercent) ? .mint : .orange) }
            ForEach(r.changes, id: \.category) { item in
                HStack {
                    Label(item.category.rawValue, systemImage: item.category.icon).font(.subheadline)
                    Spacer()
                    Text("\(item.change > 0 ? "+" : "−")\(money(abs(item.change)))").font(.subheadline.bold()).foregroundStyle(item.change > 0 ? .orange : .mint)
                }
            }
            Text("Transfers between your accounts and stock deposits are not spending.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var whatIfCard: some View {
        let options = Category.allCases.filter { !Engine.fixed.contains($0) && e.usualMonthly($0) > 0 }
        let chosen = options.contains(whatIf) ? whatIf : (options.first ?? .takeaway)
        let usual = e.usualMonthly(chosen)
        let yearly = Money(Double(usual * 12) * cut / 100)
        let goal = store.state.goals.first { $0.reserved < $0.target && $0.weekly > 0 }
        return Card {
            Text("What if…").font(.headline)
            if options.isEmpty {
                Text("Once you have a month of spending, try cutting a category here to see what it's worth.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: Binding(get: { chosen }, set: { whatIf = $0 })) { ForEach(options) { Text($0.rawValue).tag($0) } }
                Text("I spent \(Int(cut))% less on \(chosen.rawValue.lowercased())").font(.subheadline.bold())
                Slider(value: $cut, in: 5...50, step: 5)
                MoneyRow(label: "Usual a month", value: usual)
                MoneyRow(label: "You'd keep a year", value: yearly, color: .mint)
                if let goal {
                    let left = Double(goal.target - goal.reserved), before = left / Double(goal.weekly), after = left / (Double(goal.weekly) + Double(yearly) / 52)
                    Text("\(goal.name) would be funded about \(max(0, Int((before - after).rounded()))) week\(Int((before - after).rounded()) == 1 ? "" : "s") sooner.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
@MainActor struct BudgetReviewView: View {
    @EnvironmentObject var store: Store
    @State private var period: BudgetPeriod = .month
    @State private var offset = 0 // 0 = the current period, 1 = the one before, ...
    var e: Engine { store.engine }
    var monthly: Bool { period == .month }
    var start: Date {
        let c = Calendar.current
        // Line up with your budget when it uses this period; weeks otherwise start on the week's first day.
        let current = period == store.state.period ? store.state.periodStart : period == .week ? c.dateInterval(of: .weekOfYear, for: Date())!.start : store.state.start(of: period)
        switch period {
        case .month: return c.date(byAdding: .month, value: -offset, to: current)!
        case .fortnight: return c.date(byAdding: .day, value: -14 * offset, to: current)!
        case .week: return c.date(byAdding: .day, value: -7 * offset, to: current)!
        }
    }
    var end: Date { period.end(from: start) }
    var title: String {
        monthly ? start.formatted(.dateTime.month(.wide).year())
            : "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(Calendar.current.date(byAdding: .day, value: -1, to: end)!.formatted(.dateTime.day().month(.abbreviated)))"
    }
    var body: some View {
        let lines = e.review(period, start: start).filter { $0.limit > 0 || $0.used != 0 }
        let budget = lines.reduce(Money(0)) { $0 + $1.limit }
        let used = lines.reduce(Money(0)) { $0 + $1.used }
        let income = store.state.entries.filter { $0.kind.income && $0.date >= start && $0.date < end }.reduce(Money(0)) { $0 + $1.amount }
        let invested = store.state.entries.filter { $0.kind == .investment && $0.date >= start && $0.date < end }.reduce(Money(0)) { $0 + $1.amount }
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $period) { Text("Month").tag(BudgetPeriod.month); Text("Fortnight").tag(BudgetPeriod.fortnight); Text("Week").tag(BudgetPeriod.week) }.pickerStyle(.segmented)
                        .onChange(of: period) { offset = 0 }
                    HStack {
                        Button { offset += 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Earlier")
                        Spacer(); Text(title).font(.headline); Spacer()
                        Button { offset -= 1 } label: { Image(systemName: "chevron.right") }.disabled(offset == 0).accessibilityLabel("Later")
                    }.buttonStyle(.borderless)
                }
                Section {
                    MoneyRow(label: "Budgeted", value: budget)
                    MoneyRow(label: "Spent", value: used)
                    MoneyRow(label: used > budget ? "Over budget" : "Left", value: abs(budget - used), color: used > budget ? .orange : .mint)
                    MoneyRow(label: "Wages & allowance received", value: income)
                    MoneyRow(label: "Sent to investing", value: invested)
                } footer: { Text(offset == 0 ? "So far this \(period.rawValue). Afterpay counts each instalment in the period it is due." : "Compared with your current budgets\(period == store.state.period ? "" : ", converted to a \(period.rawValue)ly amount"). Past budget changes are not kept.") }
                Section("By category") {
                    if lines.isEmpty { Text("No budgets or spending in this period.").foregroundStyle(.secondary) }
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Label(line.category.rawValue, systemImage: line.category.icon); Spacer(); Text("\(money(line.used)) of \(money(line.limit))").font(.subheadline).foregroundStyle(line.used > line.limit ? .orange : .primary) }
                            ProgressView(value: min(1, max(0, line.ratio))).tint(line.ratio > 1 ? .orange : .mint)
                            Text(line.used > line.limit ? "\(money(line.used - line.limit)) over" : "\(money(line.limit - line.used)) left").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Check budget").navigationBarTitleDisplayMode(.inline)
            .onAppear { period = store.state.period }
            .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
        }
    }
}
extension Category {
    /// Chart colours: a validated categorical palette (dark-surface steps), assigned in fixed category order.
    var color: Color {
        let hex: Int
        switch self {
        case .fuel: hex = 0x3987E5; case .groceries: hex = 0xD95926; case .takeaway: hex = 0x199E70; case .shopping: hex = 0xC98500
        case .subscriptions: hex = 0xD55181; case .bills: hex = 0x008300; case .entertainment: hex = 0x9085E9; case .other: hex = 0xE66767
        }
        return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
@MainActor struct AssetsCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let e = store.engine
        Card {
            Text("TOTAL ASSETS").font(.caption.bold()).tracking(1.5).foregroundStyle(.mint)
            Text(money(e.assets)).font(.system(size: 32, weight: .bold, design: .rounded))
                .contentTransition(.numericText(value: Double(e.assets))).animation(.snappy, value: e.assets)
            if store.state.history.count >= 2 {
                Chart(store.state.history.suffix(90)) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Assets AUD", Double(point.assets) / 100))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(.mint)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 48).accessibilityLabel("Total assets over time")
            }
            MoneyRow(label: "Bank cash", value: e.bankCash)
            MoneyRow(label: "Shares & Stake cash", value: e.aud(e.investmentUSD + store.state.stakeCashUSD))
            if e.afterpayDebt > 0 { MoneyRow(label: "Owed to Afterpay", value: -e.afterpayDebt) }
            MoneyRow(label: "Net worth", value: e.netWorth, color: .mint)
        }
    }
}
@MainActor struct SpendingCard: View {
    @EnvironmentObject var store: Store
    @State private var period: BudgetPeriod = .month
    @State private var picked: Date?
    struct Bar: Identifiable { var id: String; var start: Date; var category: Category; var amount: Money }
    var body: some View {
        let e = store.engine
        let now = e.spending(period, start: e.chartStart(period))
        let total = now.reduce(Money(0)) { $0 + $1.amount }
        let starts = (0..<6).reversed().map { e.chartStart(period, back: $0) }
        let bars = starts.flatMap { start in e.spending(period, start: start).map { Bar(id: "\(start.timeIntervalSince1970)-\($0.category.rawValue)", start: start, category: $0.category, amount: $0.amount) } }
        let unit: Calendar.Component = period == .month ? .month : .weekOfYear
        let pickedStart = picked.flatMap { p in starts.last { $0 <= p } }
        Card {
            HStack {
                Text("Spending").font(.headline)
                Spacer()
                Picker("Period", selection: $period) { Text("Week").tag(BudgetPeriod.week); Text("Month").tag(BudgetPeriod.month) }
                    .pickerStyle(.segmented).frame(width: 150)
            }
            Text(money(total)).font(.title.bold()).contentTransition(.numericText(value: Double(total))).animation(.snappy, value: total)
            Text("This \(period.rawValue) · transfers between your accounts, Stake deposits and income are not counted").font(.caption).foregroundStyle(.secondary)
            if now.isEmpty {
                Text("No spending yet this \(period.rawValue).").foregroundStyle(.secondary)
            } else {
                let top = Double(now.first?.amount ?? 1) / 100
                Chart(now, id: \.category) { item in
                    BarMark(x: .value("Spent", Double(item.amount) / 100), y: .value("Category", item.category.rawValue), height: .fixed(16))
                        .foregroundStyle(item.category.color).cornerRadius(4)
                        .annotation(position: .trailing) { Text(money(item.amount)).font(.caption2).foregroundStyle(.secondary) }
                }
                .chartXScale(domain: 0...(top * 1.4)).chartXAxis(.hidden)
                .chartYAxis { AxisMarks { AxisValueLabel().foregroundStyle(.secondary) } }
                .frame(height: CGFloat(now.count) * 28 + 8)
            }
            Divider()
            HStack {
                Text("Last 6 \(period.rawValue)s").font(.subheadline.bold())
                Spacer()
                if let pickedStart {
                    Text("\(pickedStart.formatted(period == .month ? .dateTime.month(.wide) : .dateTime.day().month(.abbreviated))): \(money(bars.filter { $0.start == pickedStart }.reduce(0) { $0 + $1.amount }))")
                        .font(.caption.bold())
                } else { Text("Tap a bar for its total").font(.caption).foregroundStyle(.secondary) }
            }
            Chart(bars) { bar in
                BarMark(x: .value("Period", bar.start, unit: unit), y: .value("Spent", Double(bar.amount) / 100))
                    .foregroundStyle(by: .value("Category", bar.category.rawValue))
                    .opacity(pickedStart == nil || pickedStart == bar.start ? 1 : 0.35)
            }
            .chartForegroundStyleScale(domain: Category.allCases.map(\.rawValue), range: Category.allCases.map(\.color))
            .chartXAxis { AxisMarks(values: starts) { AxisValueLabel(format: period == .month ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated)) } }
            .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(Color.white.opacity(0.08)); AxisValueLabel().foregroundStyle(.secondary) } }
            .chartLegend(position: .bottom, spacing: 10)
            .chartXSelection(value: $picked)
            .frame(height: 190)
        }
        .onChange(of: period) { picked = nil }
    }
}
@MainActor struct LockScreen: View {
    var unlock: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.mint)
            Text("MoneyPilot is locked").font(.title2.bold())
            Button("Unlock", systemImage: "faceid") { unlock() }.buttonStyle(.borderedProminent).foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(ink)
    }
}
/// Payday: type what arrived and see where it goes. Shows the split for two days after.
@MainActor struct PayCard: View {
    @EnvironmentObject var store: Store
    @State private var amount = ""
    @State private var account: UUID?
    var body: some View {
        let e = store.engine
        let recent = store.state.entries.filter { $0.kind.income && $0.hadEffects && $0.date >= Date().addingTimeInterval(-2 * 86_400) }.max { $0.date < $1.date }
        if let due = e.pendingPay {
            Card {
                Label(due.kind == .wage ? "Payday" : "Allowance day", systemImage: "banknote.fill").font(.headline).foregroundStyle(.mint)
                Text("Enter what landed in your account and MoneyPilot will tell you where to put it.").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("Amount received", text: $amount).keyboardType(.decimalPad).font(.title3.bold())
                    Picker("Account", selection: $account) { ForEach(store.state.accounts) { Text($0.name).tag(Optional($0.id)) } }.labelsHidden()
                }
                if let value = cents(amount), value > 0 { split(value) }
                Button(due.kind == .wage ? "I got paid" : "Allowance received") {
                    guard let value = cents(amount), value > 0, let account = account ?? store.state.accounts.first?.id else { return }
                    store.addEntry(name: due.kind == .wage ? "Wages" : "Parents’ allowance", amount: value, kind: due.kind, category: .other, account: account, destination: nil, date: Date())
                    amount = ""
                }.buttonStyle(.borderedProminent).foregroundStyle(ink).disabled((cents(amount) ?? 0) <= 0)
            }
            .onAppear { if amount.isEmpty { amount = String(Double(due.expected) / 100) }; if account == nil { account = store.state.accounts.first?.id } }
        } else if let pay = recent {
            Card {
                Label("\(pay.kind == .wage ? "Pay" : "Allowance") received · \(money(pay.amount))", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.mint)
                split(pay.amount, entry: pay)
            }
        }
    }
    /// A recorded pay shows what it actually set aside; a pay being typed shows the preview.
    private func split(_ value: Money, entry: Entry? = nil) -> some View {
        let e = store.engine
        let p = entry.map { pay -> Engine.PaySplit in let k = e.afterCut(pay.amount, cut: pay.cut ?? 0); return .init(savings: k.savings, investment: k.investment, cut: pay.cut ?? 0, spare: 0) }
            ?? e.paySplit(value, alreadyIn: false)
        return VStack(alignment: .leading, spacing: 8) {
            MoneyRow(label: "Move to savings", value: p.savings, color: .mint)
            MoneyRow(label: "Move to investing (Stake)", value: p.investment, color: .mint)
            MoneyRow(label: "For budgets and spare money", value: value - p.savings - p.investment)
            if p.cut > 0 { Label("Savings and investing cut by \(money(p.cut)) so the next fortnight's budgets are covered.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            Text("Your rule: \(store.state.settings.futurePercent)% for your future, split \(store.state.settings.savingsSplit)/\(100 - store.state.settings.savingsSplit) savings and investing. MoneyPilot only plans it; move the money in your bank and Stake apps.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
/// Which transfers to make between your accounts so each holds what it should until next pay.
@MainActor struct MoveMoneyCard: View {
    @EnvironmentObject var store: Store
    @State private var why = false
    @State private var confirming = false
    private func name(_ id: UUID?) -> String { id.flatMap { i in store.state.accounts.first { $0.id == i }?.name } ?? "Stake" }
    var body: some View {
        if let plan = store.engine.moneyPlan {
            let until = plan.nextPay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            Card {
                HStack {
                    Label("Move money", systemImage: "arrow.left.arrow.right.circle.fill").font(.headline).foregroundStyle(.mint)
                    Spacer()
                    Text("until \(until)").font(.caption).foregroundStyle(.secondary)
                }
                if let off = store.state.timeOff(before: plan.nextPay).first {
                    Label("Includes time off \(off.from.formatted(.dateTime.day().month(.abbreviated)))–\(off.to.formatted(.dateTime.day().month(.abbreviated))): no wages, allowance only. Everyday has to last until \(until).", systemImage: "beach.umbrella").font(.caption).foregroundStyle(.orange)
                }
                if plan.transfers.isEmpty {
                    Text("All set. Everyday holds what you need until next pay, and every other account holds what it should.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(plan.transfers) { t in
                    HStack(alignment: .firstTextBaseline) {
                        Text("Transfer \(money(t.amount))").font(.subheadline.bold())
                        Text("from \(name(t.from)) to \(name(t.to))").font(.subheadline)
                        // MK4.1: replaces "Transfer now" on the Dynamic Island: copy, switch to Suncorp, paste.
                        Button { UIPasteboard.general.string = String(format: "%.2f", Double(t.amount) / 100) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).accessibilityLabel("Copy \(money(t.amount))")
                        Spacer()
                    }
                }
                if plan.shortfall > 0 {
                    Label("Your free cash is \(money(plan.shortfall)) short of essentials until \(until). Lower a budget, or take from savings only if you must.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                if !plan.transfers.isEmpty {
                    Button("I've made them…") { confirming = true }.buttonStyle(.borderedProminent).foregroundStyle(ink)
                    Text("Tap the copy button next to a transfer, open the Suncorp app and paste the amount. Then tell MoneyPilot which ones you made.").font(.caption2).foregroundStyle(.secondary)
                }
                DisclosureGroup("Why these amounts", isExpanded: $why) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Everyday pays what is left of your spending until \(until):").font(.caption).foregroundStyle(.secondary)
                        ForEach(plan.needs) { MoneyRow(label: $0.name, value: $0.amount) }
                        Divider()
                        ForEach(store.state.accounts.filter { plan.targets[$0.id] != nil }) { a in
                            MoneyRow(label: "\(a.name) should hold", value: plan.targets[a.id] ?? 0)
                            Text("Now \(money(store.engine.accountBalance(a.id)))").font(.caption2).foregroundStyle(.secondary)
                        }
                        if let rule = plan.savingsRule {
                            Text("Savings must reach at least \(money(rule.required)) by month end (\(money(rule.monthStart)) at the start + \(money(rule.required - rule.monthStart))). Withdrawals this month: \(rule.withdrawals) of \(rule.allowed).").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Emergency and Savings hold what you've set aside. Your investing share goes to Stake, never through Savings. Everything left over sits in your spare-money account (named Shopping), along with money reserved for purchase goals. Set what each account is for in Settings.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 6)
                }.font(.subheadline)
            }
            .sheet(isPresented: $confirming) { TransfersMadeView(plan: plan) }
        } else if store.state.pocketsmith != nil {
            Card { Label("Set what each account is for (Everyday, Spare money, Emergency, Savings) in Settings, and MoneyPilot will tell you which transfers to make.", systemImage: "arrow.left.arrow.right").font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
/// MK3.5: "I've made them": set each transfer's real amount, or switch it off if you're not making it.
@MainActor struct TransfersMadeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let plan: MoneyPlan
    @State private var amounts: [String: String] = [:]
    @State private var made: [String: Bool] = [:]
    private func name(_ id: UUID?) -> String { id.flatMap { i in store.state.accounts.first { $0.id == i }?.name } ?? "Stake" }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(plan.transfers) { t in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("\(name(t.from)) → \(name(t.to))", isOn: Binding(get: { made[t.id] ?? true }, set: { made[t.id] = $0 }))
                            if made[t.id] ?? true {
                                TextField("Amount", text: Binding(get: { amounts[t.id] ?? String(Double(t.amount) / 100) }, set: { amounts[t.id] = $0 })).keyboardType(.decimalPad)
                                if let typed = cents(amounts[t.id] ?? ""), typed != t.amount { Text("Suggested \(money(t.amount))").font(.caption).foregroundStyle(.secondary) }
                            } else {
                                Text("Not making this one. It won't be suggested again until next payday.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: { Text("Switch off any you're not making, or change the amount to what you actually sent. Balances update now; when your bank syncs, its copies are linked to these, not counted again.") }
                Section {
                    Button("Save") {
                        let done = plan.transfers.compactMap { t -> MoneyPlan.Transfer? in
                            guard made[t.id] ?? true else { return nil }
                            let amount: Money = amounts[t.id].map { cents($0) ?? 0 } ?? t.amount
                            return amount > 0 ? MoneyPlan.Transfer(from: t.from, to: t.to, amount: amount) : nil
                        }
                        store.change { $0.confirmTransfers(planned: plan.transfers, made: done, nextPay: plan.nextPay) }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Transfers made").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
/// Spare money (the Shopping account): what you can comfortably spend, what each pay adds, and goals saving from it.
@MainActor struct SpareMoneySection: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var why = false
    var body: some View {
        if let spare = store.engine.spareMoney {
            Card {
                Label("Spare money · \(spare.account.name)", systemImage: "wallet.pass.fill").font(.headline).foregroundStyle(.mint)
                Text("COMFORTABLE TO SPEND").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
                Text(money(spare.comfortable)).font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(spare.comfortable))).animation(.snappy, value: spare.comfortable)
                Text("Each pay adds about \(money(spare.perPay))\(spare.reserved > 0 ? " · \(money(spare.reserved)) is saved for goals" : "")").font(.subheadline).foregroundStyle(.secondary)
                let e = store.engine
                if let limit = store.state.settings.shoppingLimit, limit > 0 {
                    let spent = e.shoppingSpent
                    ProgressView(value: min(1, Double(spent) / Double(limit))).tint(spent > limit ? .red : spent * 100 >= limit * 80 ? .orange : .mint)
                    Text("\(money(spent)) of your \(money(limit)) shopping limit this \(e.shoppingLimitName)").font(.caption).foregroundStyle(spent > limit ? .red : .secondary)
                }
                if e.goalMoneyUsed > 0 { Label("You've spent \(money(e.goalMoneyUsed)) of goal savings", systemImage: "target").font(.caption).foregroundStyle(.orange) }
                DisclosureGroup("How each pay is split", isExpanded: $why) {
                    VStack(spacing: 6) {
                        MoneyRow(label: "Pay (wages + allowance, per fortnight)", value: spare.income)
                        MoneyRow(label: "To savings and investing", value: -spare.future)
                        MoneyRow(label: "Everyday budgets + 5% cushion", value: -spare.spending)
                        MoneyRow(label: "Subscriptions and Afterpay", value: -spare.bills)
                        Divider()
                        MoneyRow(label: "Into spare money", value: spare.perPay, color: .mint)
                    }.padding(.top, 6)
                }.font(.subheadline)
            }
            HStack {
                Text("Goals").font(.title2.bold())
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus.circle.fill") }.accessibilityLabel("Add goal")
            }
            if store.state.goals.isEmpty { Text("Saving for something, like a 3D printer? Add a goal and MoneyPilot sets money aside from spare money every payday, never more than half of what a pay leaves spare.").foregroundStyle(.secondary) }
            ForEach(store.state.goals) { GoalCard(goal: $0) }
            Color.clear.frame(height: 0).sheet(isPresented: $adding) { GoalEditor() }
        }
    }
}
