# MoneyPilot — MK4.1 for iPhone

MK4.1: faster, simpler.
- **Speed:** every figure used to be recalculated from every transaction each time a screen asked, and the screens ask dozens of times per redraw. Now each figure is worked out once per change and remembered, sorting suggestions count each shop's categories once, and saving happens in the background. With a year of transactions (2,000), the home-screen numbers went from 17.1 s to 0.09 s for 20 redraws (a speed test now runs with every build).
- **Removed the Live Activity and the widget.** PocketSmith sign-in progress shows as a banner at the top of the app; Move money has a copy button next to each transfer instead of "Transfer now"; the payday card and 2pm reminder stay. No App Group or Live Activity permissions any more.
- **PocketSmith in desktop mode:** the sign-in page (hidden daily run and Sync now) loads PocketSmith's desktop site.
- **Stocks:** a price refresh no longer stops when one ticker or the exchange-rate service fails; sold-out holdings aren't looked up; a new buy defaults to "Paid with Stake cash" when you have Stake cash.

MK4.0: **Back up everything** (Settings → Data).
- One file with all your data: transactions, accounts, budgets, Afterpay, goals, Stake, time off and every setting.
- Optionally your PocketSmith key and login and Finnhub key, encrypted with a password you choose (AES-GCM, key from PBKDF2-SHA256). Without the password they can't be read; your money data restores without it.
- Save it anywhere in Files, e.g. iCloud Drive. **Restore from backup** reads MK4.0 backups and older ones, then asks for the password to put your keys and login back.

MK3.7: matching balances to PocketSmith (importing the past 120 days, linking, "Match PocketSmith balance", Fix it for me, Set balance's "Use this") now keeps pending transactions off your balance. PocketSmith's balance leaves them out, so matching used to undo the pending amount.

MK3.6: budget and Afterpay calculations checked line by line, and **time off**.

Fixed (each confirmed with a test that failed on MK3.5):
1. **Weekly budgets now roll over on their own**, keeping the same start day. They used to stay on an old week until you closed it by hand, so new spending landed outside any budget.
2. **Move money only asks for what's left of each budget.** It used to ask for a full slice of every budget until payday, even when most of it was already spent (e.g. $89.99 for groceries when $21 was left).
3. **Afterpay inside a budget is counted once.** An instalment for, say, entertainment was counted in the entertainment budget *and* again as Afterpay in Move money, the payday split and spare money ($210 + $100 instead of $105 + $100).
4. **Suggested budgets** no longer give part of your income to the old shopping budget.
5. **Cash forecast** no longer spends the old shopping budget every day, and handles Afterpay correctly.
6. **Pace warnings** no longer treat an Afterpay instalment as a daily spending rate.
7. **Afterpay bank payments that synced before you added the plan** are linked to it when you add it, so the instalment isn't owed twice. Payments a few cents off (rounding) match too.
8. **Link an Afterpay payment yourself:** reviewing an Afterpay bank payment in Activity now lists the unpaid instalments to link it to.

New: **Time off** (Settings → Time off · no wages). Paydays between the dates pay nothing; allowance still counts. Everyday is planned to last until the first pay after the time off, less the allowance due meanwhile, and the pay before gives up savings and investing first if it has to. Payday reminders, late-pay warnings, the Dynamic Island payday prompt and the forecast skip those dates. Move money and the Guide show the time off.

MK3.5:
- **Cancel money waiting for Stake:** Wealth → Stake card → "Waiting to go to Stake: $X · Cancel". It stops being set aside for investing and becomes normal cash. New pays still set aside your investing share (change it in Settings).
- **"I've made them…"** (Move money) opens a sheet: switch off any transfer you're not making, or change the amount to what you actually sent. Anything not made exactly as suggested isn't suggested again until next payday.

MK3.4 fixes Stake deposits.
- Every stock deposit now counts as money sent to Stake unless it clearly went to another broker (CommSec, Pearler…). Before, a deposit was skipped unless its bank description said "Stake", so Apple Pay deposits were left out of "put in" and never added USD to Stake cash.
- Actual profit & loss → Transfers: each shows its bank description; **tap** one to enter the real USD from Stake (Stake cash adjusts by the difference); **swipe left → Not Stake** on one that wasn't a Stake deposit to move it back to spending (its USD comes out of Stake cash).

MK3.3 fixes "overallocated" amounts that didn't make sense.
- **Afterpay:** only instalments due before your next payday come out of today's cash. Later ones come out of later pays (the payday rule covers them).
- **Savings / emergency set aside:** these only ever grew with each pay. If your Savings or Emergency account holds less, Fix it for me now matches the set-aside amount to the account (nothing is moved).
- **Shows its working:** the overallocated warning on the home screen opens Fix it for me, which lists cash in your accounts, minus savings, emergency, money waiting for Stake, Afterpay due before payday, goals and budgets left, so you can see exactly which number is off.

MK3.2 replaces "safe to spend today" with two numbers everywhere (home, Lock Screen, Dynamic Island, widget): **spare money** (Shopping account minus goal savings, within your shopping limit) and **takeaway left** this period (never more than the cash you have).

MK3.1: **Check & fix Stake cash** (Wealth → Stake card).
- Rebuilds Stake cash from your history: before MoneyPilot + deposits − withdrawals − shares bought (incl. brokerage) + shares sold (after brokerage) + your corrections, and compares it with what MoneyPilot shows.
- Explains gaps: imported past deposits that never added USD, deposits with estimated USD (enter the real amount right there), shares added as already bought, and untracked dividends/interest/fees.
- **Match the Stake app:** type the cash shown in Stake; the difference is saved as a correction so your history adds up to it.
- Fixed: deleting a Stake deposit, or moving it back to spending, now also takes its USD out of Stake cash; editing a deposit's amount scales its USD; saving Settings no longer overwrites Stake cash that changed while it was open (a typed change is recorded as a correction).

MK3 reworks how money flows on payday and how spare money works.
1. **Shopping is spare money, not a budget.** What you can spend is your Shopping account (after planned transfers) minus goal savings, and within your shopping limit if you set one (Settings → Budgets & alerts, per fortnight or month). Only purchases paid from the Shopping account count; you're warned at 80% and when you go over.
2. **Goals** take their "save each pay" amount on payday, oldest first, but together never more than half of what that pay leaves spare. You can still spend goal money; MoneyPilot warns you when you do.
3. **Budgets come before savings.** On payday, if the 30% you keep plus your free cash can't cover the next fortnight's budgets and subscriptions (Afterpay is already set aside), savings and investing give up just the shortfall, 60/40. Nothing is caught up later. The cut is stored with the pay, so editing or deleting it reverses exactly.
4. **Everyday holds budgets + 5% cushion** (plus subscriptions and Afterpay due). Anything more goes to spare money.
5. **End of each period:** 30% of unspent budget stays in Everyday as a buffer; the other 70% goes to spare money with the next transfers.
6. **Pull down** recalculates from the numbers already in MoneyPilot. It never contacts PocketSmith.
7. **Sync now** (Bank sync) signs you in to PocketSmith and leaves it open for you. Tap Done to import what's new.
8. **Set balance:** Wealth → tap an account → type what your bank app shows (pending included). It stays until you change it; if PocketSmith differs you'll see "PocketSmith says $X · Use this".
9. **Fix it for me** (Guide, when your plan is bigger than your cash): shows the changes first, then corrects drifted balances, releases goal savings, and lowers budgets evenly (takeaway, entertainment and other first; groceries and fuel last). Bills, subscriptions, savings, emergency and investing are never touched.

MK2.23: a withdrawal's cost is worked out from **Stake cash only**. The cash's cost is everything still invested minus what the shares you hold cost (at their purchase rate); each withdrawal takes its share of that. Share prices never change it, so reviewing a withdrawal late gives the same answer.

MK2.22 separates **money still at Stake** from **profit actually banked**.
- **Wealth → Stake card:** "Gain/loss on money at Stake" = what's at Stake now (AUD) minus what that money cost you. It moves with share prices and the exchange rate and includes FX fees, but it isn't banked. "Share profit" (USD) is the stocks alone.
- **Actual profit & loss** page: only withdrawals count. Each withdrawal records what the money cost you (from Stake cash; see MK2.23). Profit banked = AUD back to your bank − that cost, so every FX fee and currency move is included.
- Example: put in A$1,000, it grows to US$800 (A$1,200 inside). Withdraw half: A$596.70 reaches your bank, which cost A$500, so A$96.70 is banked and A$100 remains a paper gain.

MK2.21 tracks **money to and from Stake, with FX fees** (Wealth → Money to & from Stake · FX fees).
- **FX fee** of 0.55% each way (Stake's AUD→USD and USD→AUD conversion; no other withdrawal fee). Adjustable.
- **Deposits** (To Stake): the USD credited is optional; left blank it's estimated at today's rate less the fee. Bank payments to Stake are picked up automatically.
- **Withdrawals** (new "From Stake" type): review the bank credit in Activity as "Money back from Stake", or add it yourself. It takes the USD off Stake cash (estimated with the fee if blank) and is never counted as pay.
- **Summary:** AUD sent, AUD back, worth at Stake now, overall gain or loss, split into shares/dividends/brokerage, currency moves and FX fees paid (overall = shares + currency − fees).
- **FX calculator:** "If I send A$…" → USD credited and fee; "If I withdraw US$…" → AUD reaching your bank and fee.
- **Before MoneyPilot:** enter totals from Stake's statements for earlier transfers so money already at Stake isn't counted as profit.

MK2.20 adds **buying, selling and profit** for stocks (Wealth tab).
- **Add holding / Buy more:** purchase price per share (fills in with today's price; change it to what you paid), brokerage (starts at Stake's US$3), and whether it was paid from Stake cash. Buying a stock you already hold combines them at the average price.
- **Tap a stock:** what you've made or lost in USD, % and AUD; split into shares you still hold and shares already sold; average price paid, price now, cost and value.
- **Sell:** part or all of a holding, at your selling price, less brokerage. The money stays in Stake cash (part of your portfolio), not your bank or budgets. It shows the profit on that sale before you confirm.
- **Wealth** shows total profit across all stocks; sold-out stocks stay listed so their profit still counts.
- AUD profit uses the exchange rate on the day of each buy, so it includes currency gains or losses. Holdings from before MK2.20 use today's rate for their cost.

MK2.19 counts **pending transactions**. Every sync reads PocketSmith's pending items and takes them off that account's balance (pending deposits are added), so balances, safe-to-spend and transfer suggestions match what you really have. When an item posts it becomes a normal transaction and the pending amount clears, so it is never counted twice. Bank sync shows "· $X pending" next to an account that has any. Pending purchases don't count toward category budgets until they post.

MK2.18:
- **Activity → Bank sync → Sync now** shows the PocketSmith page while it signs in and refreshes your feeds (with a saved login). It closes itself when done, then syncs. Pull-down on Overview and the daily refresh still run out of sight.
- **Fixed:** the Dynamic Island could stay on "Waiting for your bank…" if you left MoneyPilot during the wait. The wait is now 20 seconds, MoneyPilot asks iOS for time to finish after you leave, and a sign-in status expires by itself after 2 minutes.

MK2.17: **pull down on Overview** also signs in to PocketSmith (out of sight) and refreshes your bank feeds, once your login is saved in Bank sync → Sign in for me. It imports what's already there straight away, then syncs again after the feeds refresh. The Dynamic Island shows the progress.

MK2.16 makes the PocketSmith sign-in **invisible**. It runs behind the app while you use MoneyPilot; only the Dynamic Island and Lock Screen show "Logging in to PocketSmith…" → "Refreshing bank feeds…" → "Waiting for your bank…" → "Syncing MoneyPilot…". The PocketSmith page only appears if it needs you (a code, a wrong password, a page it doesn't recognise, or more than 90 seconds without finishing). iOS pauses web pages once you leave the app, so keep MoneyPilot open for the few seconds it takes; if you leave, it carries on when you come back.

MK2.15 **signs in to PocketSmith for you** and refreshes your bank feeds.
- Activity → Bank sync → **Sign in for me**: save your PocketSmith email and password (kept in this iPhone's Keychain, never backed up), and optionally turn on **Refresh bank feeds when I open MoneyPilot** (at most once a day).
- **Log in & refresh bank feeds** opens PocketSmith's own website inside MoneyPilot, fills in the login, goes to Feeds and presses refresh on each feed. A minute later MoneyPilot syncs what arrived.
- The Lock Screen and Dynamic Island show each step: "Logging in to PocketSmith…", "Refreshing bank feeds…", "Waiting for your bank…", "Syncing MoneyPilot…".
- If PocketSmith or your bank asks for a code, or PocketSmith changes its page, the page stays open for you to finish, and the Live Activity says "Open MoneyPilot to finish".
- Disconnecting PocketSmith also deletes the saved login.

MK2.14 adds **Spare money and goals** to the home screen.
- **Comfortable to spend:** what your spare-money (Shopping) account will hold after the planned transfers, minus money saved for goals. That's what you can spend on extras without touching budgets, savings, investing or goals.
- **Each pay adds about $X:** one fortnight's pay (wages + allowance) minus your savings and investing share, two weeks of every budget, and subscriptions and Afterpay due. "How each pay is split" shows the sums.
- **Goals** (e.g. a 3D printer): set a price and how much to save each pay. Every payday (when wages are entered, synced or reviewed) MoneyPilot sets that amount aside from spare cash, so it stops counting as spendable. Each goal shows how many pays are left; reserve extra, release it, or record the purchase from its card.
- **PocketSmith:** its API cannot trigger a bank refresh, and MoneyPilot does not store your PocketSmith password. Activity → Bank sync now has **Refresh bank feeds in PocketSmith**, which opens PocketSmith's Feeds page so you can tap Sync (and enter any bank security code); MoneyPilot picks up the new numbers on its next check or when you pull to refresh.

# MoneyPilot — MK2.13 for iPhone

MK2.13 matches how you use your accounts. **Everyday** pays all your spending, so Move money keeps enough there until next pay for **every** budget (groceries, fuel, takeaway, shopping, entertainment, bills, other) plus subscriptions and Afterpay due. Your **Shopping** account is shown as **Spare money**: it keeps whatever is left over (and money reserved for purchase goals). Budget categories, including the Shopping category, are unchanged.

# MoneyPilot — MK2.12 for iPhone

MK2.12 follows your Savings account's rules in Move money:
- **Investing never goes through Savings.** The investing share goes from Everyday or Shopping straight to Stake.
- **Monthly growth:** Savings must finish each month at least **$160** above its balance on the 1st. Move money tops it up first (from Shopping, then Everyday), and the Guide warns "Savings needs $X more by 31 Oct" until it's there.
- **One withdrawal a month:** MoneyPilot only suggests taking from Savings when it's above the month's requirement, combines that into one transfer, and stops suggesting withdrawals once the month's limit is used (counting withdrawals you made yourself). The Guide warns when it's used.
- Both numbers are in Settings → Savings account rules.

# MoneyPilot — MK2.11 for iPhone

MK2.11 adds **Transfer now** to the Move money card. It shows the transfers one at a time on the Dynamic Island and Lock Screen ("Transfer $350.00 · Shopping → Everyday · 1 of 3") and copies the amount, so you can open the Suncorp app and paste it. Tap **Done** on the island or Lock Screen to show and copy the next one; after the last, it returns to the normal view. Then tap "I've made them" in MoneyPilot (or wait for the bank sync) to update balances. Needs Live Activities allowed for MoneyPilot (iPhone Settings → MoneyPilot).

# MoneyPilot — MK2.10 for iPhone

MK2.10 adds **Move money**: transfer instructions between your accounts.
- Each account has a job: **Everyday** (wages land here; pays groceries, fuel, bills, subscriptions and Afterpay), **Shopping** (takeaway, shopping, entertainment, goals), **Emergency** and **Savings**. Jobs are guessed from account names; change them in Settings → Accounts → Used for.
- Using your real balances (from PocketSmith), the home screen says, e.g., "Transfer $350 from Shopping to Everyday · Transfer $200 from Shopping to Savings · Transfer $300 from Shopping to Stake".
- **Everyday target** = what your budgets need until next payday: groceries and fuel at their budgeted rate for the days left (e.g. $150/week groceries = $300 for a fortnight; $100/fortnight fuel), bills, subscriptions actually due before payday, and Afterpay instalments due before payday. **Emergency** and **Savings** hold what you've set aside; the **investing** share goes to **Stake**; **Shopping** keeps the rest. Money is taken from Shopping first and Savings last; amounts are whole dollars and anything under $5 is skipped. If free cash can't cover essentials, it says how much short.
- When pay lands in Everyday, the same plan tells you where to move it.
- "I've made these transfers" updates balances straight away; when the bank syncs, its copies are linked to them rather than counted twice (the same now applies to anything you enter by hand that later arrives from the bank).

# MoneyPilot — MK2.9 for iPhone

MK2.9: the payday reminder now arrives at **2pm**, and payday shows on the **Lock Screen and Dynamic Island**: "Payday · enter what you received" when you open the app that day, then "Move $X to savings · Move $Y to investing · $Z is yours to spend" once you enter it, even if the everyday Lock Screen view is off. iOS only lets an app start a Live Activity while it is open, so the 2pm alert is a notification and the live view appears when you open MoneyPilot. The alert asks to be Time Sensitive (shows through Focus); to allow that, add **Time Sensitive Notifications** under Signing & Capabilities for the MoneyPilot target, if your Apple account offers it. Without it, it is a normal notification.

# MoneyPilot — MK2.8 for iPhone

MK2.8 adds a **payday button**. iPhone apps cannot read other apps' notifications, so MoneyPilot cannot see Suncorp's alerts. Instead, on payday and allowance day (and the two days after, until it's recorded) the home screen shows a card: enter the amount that landed and pick the account, and it shows exactly how much to move to savings and to investing and how much is yours to spend, then records it. The split stays on the home screen for two days. A 9am reminder arrives on each expected payday and allowance day. When PocketSmith later imports the same deposit, it is linked to your entry instead of being counted twice.

# MoneyPilot — MK2.7 for iPhone

MK2.7:
- **Move any purchase into Stock deposits:** tap the transaction → Stock deposit → Move to Stock deposits (optionally with the USD Stake credited). "Not a stock deposit" moves it back.
- **Pay notification:** when wages or allowance arrive (synced, reviewed or entered), a notification says exactly how much to move to savings and to investing under your rule, and how much is yours to spend.
- **Hourly bank checks:** background refresh is requested every hour, and the app also syncs hourly while open. iOS decides the exact background timing (it runs less often in Low Power Mode, after the app is swiped away, or if the app is rarely used), and PocketSmith itself refreshes from Suncorp on its own schedule.

# MoneyPilot — MK2.6 for iPhone

MK2.6 makes the Guide smarter and fills some gaps.

**Smarter Guide**
- **Money score (0–100)** from budgets, saving, emergency fund, Afterpay and cash runway, each part shown with its points and the reason.
- **Ranked tips** (Act now, Watch, Opportunity, Going well, Good to know), each with its numbers and, where useful, a one-tap action:
  - cash could run out, or full budgets would dip into savings, and when (only once expected pay is set)
  - a category on pace to overspend, with the daily amount that keeps you on budget
  - a category well above or below your usual, with the yearly difference
  - how much of your income you have actually kept, against your 70% target
  - emergency fund in months of essentials, and an offer to move spare cash into it
  - Afterpay owed, due in two weeks, payoff date and share of income
  - subscription price rises; charges that look like untracked subscriptions
  - possible double charges; unusually large purchases
  - wages or allowance that are 1–3 days late (with bank sync)
  - transactions to sort, deposits to review, money ready to invest, idle Stake cash, spare cash to give a job, goal timelines
- **Month in review:** last month's spending against the month before, income, what you kept, and the biggest category changes.
- **What if:** spend less in a category and see the yearly amount kept and how much sooner your goal is funded.
- **Smart alerts:** a notification the first time an important tip appears (cash running low, overspending pace, double charge, price rise, late pay).
- The cash forecast shows your protected savings as a line to stay above.

**Fixes and features**
- Fixed: the cash forecast spent fortnightly and monthly budgets as if they were weekly (2× and 4.3× too much).
- **Restore from backup** in Settings → Data (works even if saved data could not be loaded).
- **Require Face ID to open** in Settings. Balances are also hidden in the app switcher.

# MoneyPilot — MK2.5 for iPhone

MK2.5 adds a **Week / Fortnight / Month** switch to the Budgets page. Your own budget period (from Settings) shows as before and can be edited. The other two show the same plan scaled to that length (each budget × its periods per year ÷ the view's), against what you've spent in the current week, fortnight (from payday) or month, with income for that length. "Budget …ly instead" makes the view your budget period.

# MoneyPilot — MK2.4 for iPhone

MK2.4 adds **Stock deposits**. Bank payments to Stake, CommSec, Superhero, Pearler, SelfWealth, Raiz, Spaceship, Vanguard, Moomoo, Webull, eToro and similar are recognised automatically and filed as stock deposits, not spending: they leave your spending charts and budgets, come out of the money set aside for investing, and (for Stake) add the USD credited to Stake cash, estimated at today's exchange rate. Older ones entered as spending appear in Auto-organise under "Stock deposits". Activity shows them as their own group. With auto-organise off, new ones wait in Needs review so you can enter the exact USD.

# MoneyPilot — MK2.3 for iPhone

MK2.3 adds:
- **Entertainment category** (cinemas, events and tickets, bowling, Timezone, theme parks, games and similar), with its own budget, colour and keywords. It gets a budget line automatically; set an amount in Budgets.
- **Auto-organise engine.** Every transaction is filed by, in order: your merchant rules, how you've filed that merchant before (majority of your past choices), known Australian merchants, then PocketSmith's category. New bank transactions are filed this way when they arrive, and after each sync anything left in Other that the engine now recognises is filed too. Activity → **Auto-organise** shows what it would file and why, with ticks to leave any out. Turn automatic filing off in Settings → Budgets & alerts.

# MoneyPilot — MK2.2 for iPhone

MK2.2 groups similar transactions. When you correct a category (tap a transaction → Correct the category), "Also all similar transactions" (on by default) refiles every past transaction from the same merchant and remembers it for future imports. MoneyPilot shows how many will change and a few example names first.

"Similar" = the same merchant after removing bank wording, numbers and codes: "TRANSLINK 1.0", "Visa Purchase TRANSLINK GO CARD 4821" and "TRANSLINK SOUTH BRISBANE" are one group. A more specific choice still wins for its own transactions, so Amazon Prime can be Subscriptions while other Amazon purchases stay Shopping. Turn the toggle off to change just one transaction.

# MoneyPilot — MK2.1 for iPhone

MK2.1 adds to the home screen:
- **Total assets:** bank cash plus shares and Stake cash in AUD, a small trend line from your daily snapshots, Afterpay owed, and net worth.
- **Spending breakdown** with a Week / Month switch: the total, a bar per category (largest first), and the last 6 weeks or months stacked by category. Tap a bar to see that period's total. Only purchases count (net of refunds, plus Afterpay instalments due); transfers between your accounts, Stake deposits and income are left out. Category colours are a colour-blind-checked palette.

# MoneyPilot — MK2 for iPhone

MK2 changes how Afterpay uses your budget:
- **Each instalment counts in the period it is due**, not the whole purchase at once. A $200 jacket on four fortnightly payments uses $50 of this week's (or fortnight's, or month's) shopping budget, then $50 in each period a later payment falls due. Monthly budgets pick up every instalment due that month.
- Everything you still owe stays set aside from free cash, so "safe to spend" and "available for shopping" never count money already promised to Afterpay.
- Paying an instalment moves cash but does not use budget again. Editing due dates moves the instalment to the matching period.
- Version number is now 2.0.

# MoneyPilot — MK1.8 for iPhone

MK1.8 adds:
- **Fortnightly budgets:** Settings → Budget period now offers Weekly, **Fortnightly · from payday** and Monthly · from the 1st. A fortnight starts on your payday (from "Next expected payday"). Switching converts every budget through its yearly total (e.g. $300/week = $600/fortnight = $1,300/month). Fortnightly and monthly periods close themselves when they end.
- **Allowance as part of your income:** Settings → Expected income shows wages + allowance as one total per budget period. Budgets shows "Income this fortnight/month" split into wages and allowance, with the savings / investing / spending share. Budget suggestions use the combined amount.
- **Expected allowance date:** pick the next allowance date; it then repeats on the same day each month. It appears in "Next 7 days" on the home screen next to payday, and in the cash forecast.
- **Check budget** now has Month, Fortnight and Week views.

# MoneyPilot — MK1.7.1 for iPhone

MK1.7.1 fixes pull-to-refresh showing "Please check · cancelled". SwiftUI cancels a refresh when the screen redraws mid-way; the sync now runs independently of the gesture, and a cancelled request is never reported as an error.

# MoneyPilot — MK1.7 for iPhone

MK1.7 adds:
- **Monthly budgets (optional):** Settings → Budgets & alerts → Budget period → *Monthly · from the 1st*. On save, every budget is converted (weekly × 52 ÷ 12) and the period runs from the 1st to the end of the month. A finished month closes itself the next time you open the app, rolling leftovers forward once. Safe-to-spend, pace, alerts, the Live Activity and the widget all follow the chosen period. Switch back any time.
- **Check budget** (Budgets → Check budget): budget against actual spending for this month or week and any earlier one, by category, with totals, wages and allowance received, and money sent to investing. Past periods are compared with your current budgets (MoneyPilot does not keep old budget amounts).

# MoneyPilot — MK1.6 for iPhone

MK1.6 adds Afterpay corrections (Activity → Manage Afterpay):
- **Undo a payment:** tap a paid instalment → Mark as unpaid. A payment you logged by hand is removed and the money returns to that account's balance. A payment imported from your bank stays (the money did leave) and moves to Needs review so you can say what it was.
- **Edit dates and amounts:** "Edit dates & amounts" under each plan changes the name, category, purchase date, every due date, and the amount of any unpaid instalment. Add or swipe away unpaid instalments for non-standard schedules. A paid instalment's amount is locked until you undo its payment.
- **Delete a plan** entered by mistake, together with the payments logged against it.


MK1.5 adds:
- **Shares by count:** in Wealth → +, type the ticker and how many shares you own. MoneyPilot fetches the live price and shows the value in USD and AUD. "Total you paid" is optional; leave it empty to track gains from today. You can also remove a holding. Prices refresh whenever the app syncs.
- **Shopping money widget** for the Home Screen (small and medium) and Lock Screen (rectangular, round and inline). It shows what you can spend on shopping right now, the share of this week's shopping budget used, and (medium) safe to spend today.

### Widget setup (one time)
The app and the widget share their numbers through an **App Group**, `group.com.jasonchang.MoneyPilot`.
1. In Xcode, open each target (**MoneyPilot** and **MoneyPilotLive**) → Signing & Capabilities. Check that **App Groups** shows that group ticked; Xcode registers it for your team automatically.
2. If Xcode says the group is unavailable, change it to something unique such as `group.<your-name>.MoneyPilot` in both `.entitlements` files and in `appGroupID` at the bottom of `Shared/MoneyActivity.swift`.
3. Run the app once, then long-press the Home Screen → Edit → Add Widget → MoneyPilot → Shopping money.

The widget updates whenever MoneyPilot's numbers change (including background checks) and refreshes its "updated" time hourly.

---


MK1.4 adds:
- **Dynamic home screen:** a daily **safe to spend** figure with an animated week ring and pace ("on track" or "$X ahead of pace"), swipeable category cards, the next 7 days of subscriptions, Afterpay and paydays, smart tips, recent activity and a live sync indicator. Pull down to refresh.
- **Live Activity** on the Lock Screen and Dynamic Island: safe to spend today, what's left this week, days to go and the next charge. Updates whenever new transactions arrive, including background checks.
- **Budget alerts with time left:** percentage used, dollars left and days left in the week.
- **Edit and delete transactions.** Changing or deleting wages or allowance also adjusts the savings and investing amounts they set aside (not for imported history, which never set any aside).
- **Live prices:** the AUD/USD rate updates automatically (Frankfurter, no key). Add a free Finnhub key in Settings for live US share prices.

**Safe to spend today** = money left in everyday budgets this week (everything except Bills and Subscriptions), limited by free cash after protected savings, Afterpay, goals and fixed costs still due, divided by the days left in the budget week.

### First build with the Live Activity
The project now has a second target, **MoneyPilotLive** (the Lock Screen / Dynamic Island extension).
1. In Xcode, select the **MoneyPilotLive** target → Signing & Capabilities → choose the same Personal Team as the app.
2. If you changed the app's bundle identifier, set MoneyPilotLive's to the app's identifier plus `.LiveActivity` (e.g. `com.yourname.MoneyPilot.LiveActivity`). It must start with the app's identifier.
3. Run the **MoneyPilot** scheme as usual; the extension is built and embedded automatically.
4. In MoneyPilot: Settings → **Lock Screen & Dynamic Island** → Save. iOS ends a Live Activity after about 8 hours; MoneyPilot starts a new one the next time you open it.

Open the complete project in this folder. Saved data from earlier versions loads unchanged.

A native SwiftUI personal finance app for Jason. iOS 17+. No packages. A PocketSmith developer key is needed only for bank sync. Working name: MoneyPilot.

## Open on your Mac

1. Unzip this folder and open **MoneyPilot.xcodeproj** in Xcode 16 or later.
2. Select the **MoneyPilot** scheme and an iPhone simulator, then press **⌘R**.
3. To run on your iPhone: select the MoneyPilot target → Signing & Capabilities → choose your Personal Team. If necessary, change `com.jasonchang.MoneyPilot` to a unique bundle identifier. Select your connected iPhone, enable Developer Mode if prompted, and run.
4. Run the bundled calculation tests with **⌘U**. The test target also needs your team when running on a physical device. The simulator needs no signing team.

This is source code, not an installable signed IPA. It has NOT been compiled or run in Xcode in the delivery environment, which has no Apple SDK or iOS simulator. Swift syntax and project references were checked here; those checks do not replace an Xcode build.

## Connect PocketSmith (bank sync)

1. In PocketSmith, connect your Suncorp accounts and wait for transactions to appear there.
2. In PocketSmith on the web: **Settings → Security → Manage developer keys** → create a key.
3. In MoneyPilot: **Activity → Connect bank sync** → paste the key → **Find my accounts**.
4. Match each MoneyPilot account to its PocketSmith account. Optionally type part of your employer's and parents' names as they appear on deposits.
5. Tap **Link and use PocketSmith balances**. Each matched account's balance is set to PocketSmith's balance today; the last 30 days of transactions are treated as already counted.

After that, MoneyPilot syncs when you open it (at most every 15 minutes), when you pull down in Activity, or with **Sync now**. PocketSmith itself usually refreshes from the bank about once a day.

How imports are treated:
- **Spending** → expense, categorised by your merchant rules and keywords.
- **Moves between two linked accounts** (same amount within 3 days) → one internal transfer, never income or spending.
- **Deposits matching your wage / allowance names** → wages / parents' allowance, with the 42/28/30 rule applied.
- **Afterpay payments** → clear the earliest unpaid instalment of the same amount. No budget charge.
- **Anything unclear** (other deposits, payments mentioning Stake, Afterpay payments with no matching instalment) → **Needs review** at the top of Activity. Imported history is never sent to review. Choose what it is; Stake deposits ask for the USD received. "Already recorded" removes an import you had entered by hand.
- Pending transactions are skipped until they post. Each PocketSmith transaction is imported once.

With sync on, do not also add bank transactions by hand or tap Afterpay instalments paid from synced accounts — they would count twice. **Activity → Bank sync → Balance check** compares each account with PocketSmith and can match it.

The developer key is stored in the iPhone Keychain (this device only) and is not included in backups. MoneyPilot only reads from PocketSmith.

## Start using it

- The app starts empty. Settings contains four editable account names and opening balances.
- Enter balances as at the start of tracking. Enter existing savings, emergency and investment reservations as portions of that same cash. For example, $5,000 of emergency money in a $7,000 bank account is not an extra $5,000 asset.
- Set expected fortnightly wages, next payday, monthly parents’ allowance and payment day.
- Budgets → Review suggested budgets → inspect and accept. You can change each budget or lock it against suggestions.
- Activity → Add transaction. New wages and parents’ allowance reserve 42% for savings and 28% for investing by default. The rest remains eligible for spending budgets.
- For a bank-to-bank move, choose Internal transfer and both accounts. Never record it as income.
- An actual Stake deposit uses “To Stake”: enter AUD paid and USD actually received. This reduces the investment reserve and adds Stake USD cash.
- Wealth → add opening holdings or a new purchase funded from Stake cash. Enter prices and exchange rates manually.
- Budgets → add purchase goals, then explicitly reserve affordable shopping money. Record the purchase from the goal card once fully funded; this replaces its reservation with the expense.
- Activity → Manage Afterpay. Add a four-instalment plan. Each instalment counts against its category budget in the period it falls due. Existing payments already reflected in your opening bank balances can be marked as already paid during setup. Later, record each paid instalment from its schedule; do not also enter it as an ordinary expense.
- Close an ended budget week from Budgets to roll unused, cash-backed category money into shopping. Closing starts a new seven-day period today. It never fabricates allowances for weeks when the app was unused.
- Settings → request notification permission, then save. Thresholds default to 75%, 90%, 100%. Afterpay reminders are scheduled for 9am local time on due dates.
- Settings → Export JSON backup before resetting or loading demo data. The current build exports a backup; restoration currently requires replacing the app's `Documents/MoneyPilot-v1.json` through Xcode's downloaded device container while the app is stopped. An in-app restore/import flow is deferred. Exported backups contain sensitive data.

## Included

- Five native tabs: Overview, Budgets, Activity, Wealth and Guide.
- Four accounts, independent income sources and a configurable savings/investment rule.
- Cash-backed shopping availability and over-allocation warnings.
- Budget suggestions from expected income; recent expense history supplies category weights once at least four weeks of past-period history exists. Suggestions need approval; they do not silently change limits.
- Merchant keyword categorisation, remembered exact merchant corrections, manual entries and expense splits.
- Editable weekly budgets, carry-forward shopping money, purchase goals and estimated funding durations.
- Afterpay liabilities, payment schedules, upfront reservations and payment records without double-charging a budget.
- Local threshold notifications, emergency-fund warning, scheduled instalment reminders.
- Rule-based financial guidance with visible reasoning and explicit surplus-allocation actions.
- USD holdings, cost basis, manual share prices and AUD conversion; manual Stake cash.
- Cash-flow forecast, category-spending chart and daily asset snapshots.
- Local JSON persistence with atomic writes and iOS complete file protection. No analytics. The only network requests are to api.pocketsmith.com, and only once you link it.
- Clearly labelled, opt-in demo data; loading it requires confirmation when replacing existing data.

## Calculation conventions

Money is stored as integer cents. Suggested split rounding preserves the original amount.

**Assets:** bank cash + USD Stake cash converted to AUD + holdings converted to AUD.
**Net worth:** assets less unpaid Afterpay. Other debts/assets are not yet supported.
**Protected cash:** existing savings + emergency fund + money reserved for investing.
**Free cash before category budgets:** bank cash − protected cash − unpaid Afterpay − purchase-goal reservations.

A category's usage is cash expenses − refunds + the full price of Afterpay purchases made this budget week + purchase-goal reservations (shopping only). Instalment payments do not use budget. All unpaid instalments stay reserved out of free cash until paid.

“Available for shopping” is the lower of shopping headroom and cash remaining after all other category envelopes. Values are floored at zero. Overspending elsewhere can reduce shopping availability even if its own budget looks healthy.

Afterpay reporting is cash-and-commitment budgeting: the full liability is reserved from cash until paid, and the purchase is charged to the budget once. It is not a full accrual-accounting purchase ledger. Standard four-payment fortnightly plans only; fees and custom schedules are not supported.

Rollover carries only positive leftovers backed by cash, keeps existing purchase goals reserved, and does not carry the same original budget a second time. Locked amounts can exceed suggested income; Guide flags insufficient cash rather than silently changing the locked amounts.

Forecasts use scheduled wages/allowance, a uniform daily category-spending assumption and dated instalments. The instalment provision is removed from the uniform spending pool before dated payments are applied. This is an estimate, not a bank forecast. Forecast income never increases available cash. It does not model every possible timing change, fee or missing transaction.

## Not connected or not yet included

- Bank data comes only through PocketSmith (paid plan with bank feeds). No CSV importer. No bank credentials are requested by MoneyPilot.
- Background checks depend on iOS Background App Refresh being on for MoneyPilot; iOS may run them rarely if the app is seldom used, and never after you swipe the app away. Budget alerts for new bank transactions arrive after the next check.
- No automatic Stake sync, trade-email import, live stock quotes or live FX. A verified provider and integration are still required.
- No automatic bank payments, transfers, investing or Afterpay payments.
- Budget notifications evaluate data when it changes in the app, not unseen bank transactions while the app is closed. Previously scheduled instalment notifications can arrive while closed, subject to iOS permissions/Focus settings.
- No automatic recurring goal top-ups or unattended week rollover. Both currently require explicit actions.
- No realised investment returns, historical cost-basis lots, automated dividends/splits/sales, watchlist or stock-price alerts. Opening holdings and buys are supported; reconcile other changes manually.
- No cloud sync, Face ID app lock, custom Afterpay fees, other debts, multiple currency bank accounts or App Store distribution setup.
- Existing transaction amounts cannot be edited/deleted in MK1; category corrections and splits are supported. Cash expense errors can be corrected with offsetting refunds/expenses. Check income and transfer amounts carefully before saving.
- Financial guide is a local rule engine, not an LLM or personalised investment recommendation service.

## Validation

`Tools/check_source.py` checks Swift grammar using tree-sitter when installed, XML and privacy-manifest validity, and project reference integrity. This was run successfully in the delivery environment.

`MoneyPilotTests/EngineTests.swift` contains 22 XCTest cases covering the income rule, transfers, Afterpay (including the once-only budget charge), cash reservations, goals, investments, refunds, suggestions, categorisation, amount parsing, persistence, loading MK1.1 files, and PocketSmith imports (duplicates, transfer pairing, income rules, pending skips, Afterpay matching). MK1.3 adds history import, transfer de-duplication, subscription categorisation and detection, PocketSmith category hints and migration tests (22 in total). All 22 were compiled and **passed with Swift 6.0.3 on Linux** against `Models.swift`, `Engine.swift` and `PocketSmith.swift`. The SwiftUI screens, Keychain and live PocketSmith calls could not be compiled or run here and still need an Xcode build.

On Mac, run `bash Tools/verify_on_mac.sh` or use Xcode's Build and Test. Before relying on this build, also exercise saving/relaunch, real transaction entry, notification permission and delivery, week closing, goal purchase, and opening-balance reconciliation with known totals.

## Sources used for notification implementation

Apple: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
Apple: https://developer.apple.com/documentation/usernotifications
