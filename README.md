# Splitday MK22.1 — gym and daily routine in one app (iPhone + Apple Watch)

## MK22.1 — More Training: what to do on the widget, sideways timers, pause from the island
- **The widget says what to do.** While a timer runs, the More Training widget shows the step's instruction under a smaller clock: the guided PAC cue ("Clamp set 1 · Vacuum −8 inHg (−27 kPa) · clamp +8 inHg…"), or the step's setting ("Extender on, NIR on · Tension 1.8 kg", "Vacuum 5.0 inHg (17 kPa)"). During a rest it says what to get ready for ("Switch to PAC · Fill up…", "Next: round 3 of 4"). The headline comes first; if it doesn't all fit on the small widget, the tip at the end is what's cut. Stamina shows "Feel close? Pause to cool down." The Lock Screen card and the Dynamic Island still only say Timer / Work / Rest.
- **The timer turns sideways.** Turn the iPhone on its side on the session timer and the ring fills the left half with the step, its instruction and the buttons on the right. The Stamina screen does the same while a session runs: the time large on the left, Cool down / Resume / Finish on the right. The rest of the app stays upright, and turns back as soon as you leave the timer.
- **Pause stamina from the Dynamic Island.** Press and hold the island: **Cool down** while you're going, **Resume** during the cool-down. The same button is on the Lock Screen card. Interval timers get **Pause / Resume** and **Skip** in both places. Finishing or stopping a session stays in the app and on the widget, so a stray tap can't end one.
- **The buttons keep working after iOS closes the app.** If Splitday has been closed in the background (or you locked More Training with a timer running), a button on the widget, the card or the island now reads the saved timer, changes it and saves it again — without unlocking More Training and without showing anything. Only when the iPhone itself is locked and the app is gone does it still say "Open the app to control the timer", now on the card as well as the widget.
- **Continue instead of starting over.** If part of today's routine is already done, the row says **Continue** and the timer covers only what's left: extender minutes already in are taken off (the NIR part on its own), finished static-pump rounds are dropped. Guided PAC always starts from its first step.
- **Timer screen**: the extender steps now say "Extender on, NIR on" and "NIR off, keep extending"; during a rest the screen shows what's next so you can set up for it.
- A minimised timer (and a stamina session in progress) sits at the top of More Training instead of half-way down the list.
- Stamina's "Cancel without saving" asks before throwing the session away.

**Elsewhere**
- **Deleting asks first.** Swiping a workout out of History, a routine out of Workouts, or a run or game out of Cardio used to delete it on the spot with no way back. Each now asks before it goes.
- **History is grouped by month**, with the number of workouts in each.
- **Start from the Workouts tab**: swipe a routine right (or touch and hold it) to start it. Rows show when you last did each one.
- The app calls itself **Splitday** everywhere now (Watch title, connection help, Health and Focus help, backup reminder, the Sergeant Cluck widget). File names of backups are unchanged, so old backups still restore.
- **Progress opens and searches faster** with a long history: every lift's trend comes from one pass over the log instead of one pass per exercise.
- Ticking a routine step gives a light tap.
- The app icon's long-press menu in `project.yml` matches the app (Routine, Wake-up).

## MK22 — one app instead of two halves
Until now Splitday was two apps behind a switch: the gym side, and "Dayfold" with its own tab bar, its own dark theme, its own Settings and a button to jump back. The switch is gone.
- **Routine card on Today**, under the session card: "3 of 8", a progress bar and the next three steps, which you tick right there. Wake-up steps come first in the morning and before-bed steps in the evening. Tap the header for the full list.
- **Routine screen**: everything due today in one list, in the order the day runs — Wake-up, Today, Before bed — instead of four pages by frequency. Weekly, monthly and yearly steps appear on the days they're due and say so on the row. Steps waiting for their next retry are folded away at the bottom. **Edit** adds, reorders and removes steps; the bell sets reminders.
- **Same look as the rest of the app**: follows light / dark mode and uses the same cards. The forced dark theme and green tint are gone, including on the wake-up and before-bed checklists.
- **One Settings**: Settings → Routine has Steps, Reminders and Watch sync, and Quotes and widget.
- **Weigh-in steps open the weigh-in.** A step with "weigh" in its name opens the Sunday weigh-in sheet until this week's weight is logged, then ticks itself.
- **Reminders** for the routine now open it over whatever tab you're on.
- **App icon long-press**: Before bed, Routine, Wake-up (the "GymForge" / "Dayfold" switchers are gone).
- **Watch**: the list is called Routine.
- The evening recap says "Routine 5 / 8 steps".

Nothing was deleted: steps, check-offs and reminder times carry over.

## MK21.1 — Progress, rebuilt
The old Progress tab opened on one exercise's chart behind three pickers (mode, exercise, metric). It now opens on the answer to "am I getting stronger?".
- **Range** (1M / 3M / 6M / 1Y / All, starts on 3M) drives the whole page.
- **Summary**: "7 of 12 lifts are going up", with Going up / Holding / Slipping counts, sessions, records and the biggest gain in the range.
- **Every lift, grouped by direction**: Going up (biggest gain first), Slipping, Holding, Too few sessions, Cardio. Each row shows the latest best set and when, a small trend line and the % change. Search finds any exercise.
- **Tap a lift** for its own page: Best ever / Latest / Change, one chart (Strength, Top weight or Volume; orange diamonds mark records), the coach's next step, and the last 8 sessions.
- **Records** in the range, newest first.
- **Sets per muscle group** (unchanged), then links to **Strength standards**, **Year in training** and **Workout history**.

**How "going up" is decided.** Strength is the estimated one-rep max from each session's best set (assisted lifts: least help used, lower is better; bodyweight lifts with no added load: most reps in a set). A lift needs 3 sessions in the range. With 4 or more, the first two are averaged against the last two; ±2.5% or more is up / slipping, anything inside is holding. Deload sessions and sessions tagged sick, short on time and so on are left out of the comparison, and still appear on the chart.

**Dropped:** the chart's weight-increase and rep-range-change lines, and the "reps at top weight" / "best set" / "total reps" chart options for weighted lifts.

## MK21 — a shorter home screen
Today went from ~20 stacked cards (with Start at the very bottom) to five blocks, about a screen and a half.
- **Today's session, first.** One card answers "what am I doing today?" and carries the Start button: the split / planned routine with its exercise count, estimated time and block week; or Resume while a workout runs; Done today (with View summary); Rest day; the Friday basketball question; a basketball / run day with its own Start; sick and travel days. Deload status and its End button are on it too. The button reads "Start on iPhone + Watch" only when the Watch app is connected.
- **This week**: sessions against your goal, the day row, a row of chips (streak, last 4 weeks, running / basketball goals, **Goals** to change them), Sergeant Cluck, and Rest day / Plan week.
- **For you**: one-line rows that only appear when they apply — Sunday weigh-in, weekly review, block review, plan your week, low recovery, bulk / cut warnings, and the coach's top note.
- **Nutrition**: protein bar with +20 g / +40 g and the creatine tick. **Details** opens the full cards.
- **More workouts**: your other routines as compact rows (tap for the plan, Start to go), then Run / Basketball.
- Sleep appears on Today only around bedtime or while "Going to sleep" is running.

**Where the rest went** (nothing was deleted):
- Full protein / creatine card, Calories, and the bulk / cut Phase card → **Body → Nutrition & phase** (also "Details" on Today).
- Sleep card and the recovery score → **Body → Sleep & recovery** (with your last 7 nights). Recovery is also still on Coach.
- Goals this week → the chips on the week card; block week → a line on the top card.
- Dropped from Today: the adherence bar (the last 4 weeks are now a chip on the week card, and the monthly report on Coach has the percentage), and the Watch status line (still in Settings → Apple Watch).
- With the fixed-day split on, Today no longer asks you to "Plan your week" — the split already sets the days. Plan week is still on the week card for rest, sick and travel days.

**Also fixed while going through the app**
- **Sleep logged by hand is no longer thrown away.** "I'm awake" only saved to Apple Health; when Health can't take it (sideloaded installs without Health access) the night was dropped silently. It's now kept in the app (and its backups), so last night, the sleep score and the recovery score work without Health.
- Hints that said "log your weight in Apple Health" now point to the Body tab; the red Health error on Body is a plain note.

## MK20.9 — workout screen tidy-up, "Feeling sick", coach plan text fixed
- **Top of the workout screen**: timer and sets done, then **Sergeant Cluck saying your quote**, then the speeches player. The block name is gone from that row.
- Removed from the workout screen: the Sergeant Cluck session card, the "Last time…" row and "How this screen works".
- **Swap · Skip · Note** and **Variation · Pain** are two rows of equal-width buttons.
- **Today's context** is a two-column grid, one line per tag, with a new **Feeling sick** tag. It works like "Unusually tired": lower numbers are excused and the day doesn't drive progression.
- **Coach fix** (the plan's reason line, still shown on the session preview): it quoted sets that never happened and said "last set to failure" when it wasn't. With 2 sets of 12 at 106 kg last time and 5 sets planned it said "Last time: 12/12/12/12/12 at 106 kg, last set to failure"; it now says "Last time: 12/12 at 106 kg — top of the range on 2 sets at that weight. Today's plan is 5 sets: hit 12 on every one and it goes up." The targets themselves were right. 4 new checks cover it.

## MK20.8 — live workout screen reorganised (logging first)
Nothing removed; everything needed to log a set now fits on one screen.
- **Pinned bottom bar**: **Complete set & rest** is always on screen (and sits above the keyboard). The rest timer with **+30s / Skip** appears there while resting; once all sets are done it becomes **Finish & save workout**.
- **Status in one line**: time · block · sets done.
- **Now** comes first: exercise name and "Set 1 of 5 · 8–12 reps", then one row of small buttons — **Swap · Skip · Note · Variation · Pain** (scrolls sideways).
- **Today's plan** has the sets − / + beside it (was its own "Sets today" row).
- **Weight and Reps side by side** in two big boxes; tap anywhere in a box to type.
- **Last time & the coach's reasoning** is one line; tap to unfold.
- **Coach** (Sergeant Cluck, quote, speeches) moved below the exercise. Cluck shows his line; tap him for the reminders and "Explain, Sergeant".
- **Today's context** tags are one sideways-scrolling row.
- The long grey explanations are together under **How this screen works** at the bottom.

### MK20.8.1 — flatter quote widget
- The quote widget's panel is now one flat, even matte tint: no gradient, no bright rim, no shadow, and a bit more see-through — on the Lock Screen and the Home Screen. Two numbers set it in `MatteGlassPanel`: `lockScreenTint` (0.10) and `strength` (0.55); lower = clearer.

## MK20.7 — widgets work on sideloaded installs, bedtime card yields to the timer
- **Why the More Training widget only showed the quote**: Sideloadly / AltStore / SideStore re-sign the app with a *renamed* App Group, so the name written in the code never matched and no widget could see the app's data. The app and widgets now look up the group this install was really given (the built-in name, else the one in the signing profile). Settings saved under the old name are carried over. This also connects Sergeant Cluck's widget and the Motivation widget's topic settings.
- **No App Group at all?** The Lock Screen timer card hands its state to the widget from inside the widget extension (current step only).
- **More Training → Settings → Widget** shows whether shared storage is connected and when the widget last refreshed.
- **Bedtime card vs timer**: while a More Training timer runs, the bedtime card is held back and comes back when the timer ends (wind-down and bedtime notifications still arrive). The timer card also ranks first.
- **Stamina runs keep More Training open in the background**, like the other timers, so the widget's Cool down / Finish buttons work from StandBy.
- **Widget buttons on a locked iPhone**: the timer changes straight away (card, widget, alerts); the encrypted file is written when you next open the app, because it can only be written while the iPhone is unlocked.
- Sunday weigh-in reminders are planned 4 weeks ahead instead of 8 (iOS keeps at most 64 pending notifications per app).

## MK20.6 — More Training widget (StandBy)
- New **More Training** widget (small / medium; made for StandBy). No timer running → the motivation quote. Timer running → the step you're on (e.g. "HTE + NIR", "PAC"), Work / Rest and round, the live countdown, and buttons:
  - Programs: **Pause / Resume**, **Skip** (this phase, e.g. the rest), **Next** (straight to the next step, dropping the rest of this one's rounds).
  - Stamina: **Cool down / Resume**, **Finish**. Open timers: **Stop**.
- Keeps up on its own while the app sleeps (each upcoming phase is pre-planned), then goes back to quotes when the program ends.
- Buttons run inside the app. If iOS has closed the app, the widget says to open it.
- If the App Group isn't shared (some sideloading tools drop it — Sergeant Cluck's widget then says "Open GymForge once…"), the widget reads the running timer from the Live Activity instead. It then shows the current phase only, and says to open the app once a phase ends while the app is asleep.
- Unlike the Live Activity, this widget names the step — only add it where you're happy for that to show.
- It's under **Splitday** in the widget gallery. Every build now gets its own build number (date + time), so iOS picks up new widgets; before, the build number never changed and iOS kept showing its old widget list until the phone restarted.

## MK20.5 — Stamina timer on the Dynamic Island
- More Training → **Stamina** runs now show on the **Dynamic Island and Lock Screen** like the other More Training timers: counting down to your goal, then counting up your total active time ("Goal reached"); during a cool-down it counts down the cool-down, with your active time and pauses underneath. Ends when you finish or cancel.
- Still discreet: it only says "Timer", "Cool-down" or "Goal reached".

## MK20.4 — Import an Apple Health export
- **Settings → Apple Health export → Import**. In the Health app: your picture → **Export All Health Data** → Save to Files, then pick **export.zip** (no need to unzip; an unzipped export.xml works too).
- Brings in **all your weight and body fat**, **height, birthday and sex** (fills in Your details), and the last **2 years of sleep, resting heart rate and HRV** (HRV as a daily average).
- Read a chunk at a time straight out of the zip (zip64 OK), so multi-GB exports don't run out of memory; a progress bar shows while it reads.
- Stored on the iPhone (not in backups or synced to the Watch) and merged everywhere: Body charts, coach, calorie targets, readiness, sleep report, monthly report. Live Apple Health wins on any day it also has; readings already in Health aren't counted twice. Typed-in weigh-ins are kept.
- Importing again replaces the earlier import; **Remove imported data** takes it out.

## MK20.3 — Your details, past weights
- **Settings → Your details**: height (cm), birthday and sex, typed in since Apple Health isn't connected. Shows your age, BMI and maintenance calories.
  - With no body fat reading, maintenance now uses **Mifflin–St Jeor** (height, weight, age, sex) instead of the rough weight × 22.
  - Max heart rate falls back to **208 − 0.7 × age** (Tanaka) when you haven't set one, instead of a flat 190.
- **Past weights**: **Add past weight** on the Body card or in **Settings → Your details → Weight & body fat**. Pick any past date; **Save & add another** keeps the sheet open and steps the date back a week, for entering old readings quickly. The full list is under **All** — tap to edit, swipe to delete.

## MK20.2 — Sunday weigh-in, matte-glass quote widget
- **Sunday weigh-in**: type in your weight (kg) and body fat (%) — **Body → Sunday weigh-in → Log**, the card on **Today** on Sundays, or tap the reminder. One entry per day (saving again replaces it); tap an entry to edit, long-press to delete.
- **Reminder at 9:00am every Sunday** you haven't logged yet ("Sunday weigh-in"). Switch it off on the Body card.
- Typed-in weigh-ins show with your Apple Health readings everywhere — Body charts, lean mass, coach, calorie and protein targets, monthly report — and tick Dayfold's weigh-in task. They're stored in the app (and its backups), not written to Apple Health.
- **Quote widget** (Lock Screen and Home Screen): the quote sits on a frosted, matte glass panel, 30% more see-through than first drafted (`MatteGlassPanel.strength`) (smoked tint, soft top sheen, hairline edge) so it's easier to read. Tinted / clear Home Screens skip the panel and use the system's own glass.

## MK20.1 — More Training: two routine options
- **Daily routine now shows two options**, each with its own Start: **NIR + PAC** (extender 15 min with NIR, then 35 min without, then guided PAC 25 min) and **No NIR · static pump** (extender 40 min, then static pump 4 × 5 min). NIR always goes with PAC; static pump days have no NIR.
- The one you didn't do on your last training day is tagged **Today** (fresh start → NIR + PAC; once you've started one today, that one stays Today). You can still start the other.
- More Training checks: 41.

## MK20 — Fixed-day split
- **Your week is fixed**: Mon chest + side delts · Tue back + rear delts · Wed legs · Thu buffer · Fri chest (or basketball) · Sat back · Sun rest. Uses your own Chest Day / Back Day / Leg Day (matched by their exercises). **Plan week → Auto-plan** fills Mon/Tue/Wed/Fri/Sat with them and Sunday as rest; Thursday stays open.
- **Today → "Today in your split"** says what's on and why; **UP NEXT** starts it already adjusted.
- **Missed Mon/Tue are skipped, never shifted**, so Friday and Saturday stay fresh.
- **Wednesday missed → legs on Thursday**, and Saturday's back day swaps lower-back-heavy lifts (bent-over rows → chest-supported rows, deadlifts → lat pulldowns). Your current Back Day has none, so nothing changes unless you add them.
- **Friday asks about basketball**: full-court/hard → no chest (planned as basketball); light shootaround → 25-min micro chest (4 × bench press, 3 × lateral raises, counts as your 2nd chest session); no basketball → full chest day.
- **Volume top-up**: if Monday chest (or Tuesday back) was missed, Friday chest (or Saturday back) gets +1 set on its first two main lifts and every exercise's last set goes to failure (0 RIR).
- **Settings → Weekly split** turns it off (back to rotating your routines).

## Auto-refresh with Apple Health (your Mac does it)
Sideloadly and SideStore re-sign the app and drop Apple Health. Instead, your Mac rebuilds Splitday with
your own Xcode Personal Team and installs it straight onto the iPhone twice a week, so it never expires
and Health keeps working. Your data stays (it installs over the existing app).
1. Once: Xcode → Settings → Accounts → sign in with your Apple ID. Open `GymForge.xcodeproj`, and on all four
   targets set Signing & Capabilities → Team to your Personal Team. Plug in the iPhone, and in
   Window → Devices and Simulators tick **Connect via network**.
2. Find the iPhone's name: `xcrun devicectl list devices`
3. Test once: `zsh Scripts/auto_install.sh "Jason's iPhone"`
4. Turn on the schedule (Mondays and Thursdays 12:30; runs on wake if the Mac was asleep):
   `zsh Scripts/schedule_refresh.sh "Jason's iPhone"` · off: `zsh Scripts/schedule_refresh.sh --off`
- Log: `~/Library/Logs/Splitday/refresh.log`. The Mac needs to be on (or wake) with you logged in, and the
  iPhone on the same Wi-Fi or plugged in.

## MK19.1 — Progression fixes, +1 min, back to timer

**Fixes**
- **Guided PAC is saved as one session** (25 min at −10 inHg) instead of five, so the log, stats and progression cards see one PAC. The girth card no longer says "You changed settings 1 day ago" forever: settings are read as one value per day (the day's highest), so step-by-step PAC logs from MK18.2/MK19 are fine too.
- **Each after-session measurement is saved once** (on the latest pump/PAC and the latest extender session), so one PAC day no longer counts as five readings.
- **Your max is respected**: static pump 8.5 inHg, PAC −10 inHg. The cards never suggest going past it ("Go up to 8.5 inHg — your max — and no higher"); at your max they say add time instead: ~5 min more of static pump, PAC's final set 10 → 12 min, or repeat fresh blood + clamp set 2.
- **"Pressure is high"** now only shows above your plan (pump over 8.5, PAC over −10 inHg), so it means something when it appears.
- **8:45pm "Time to train"** is skipped while a timer is running or the stretcher is on (steps are only saved when they finish), and on days the safety check says rest.
- **"Couldn't measure this time"** at the bottom of the measuring screen saves the session without the missing reading (warning signs and notes still save), so you never have to type a guess.

**New**
- **+1 min** on the interval timer adds a minute to the step you're on (e.g. PAC's final set 10 → 12 min).
- **Back to timer**: skipping the last step can now be undone from the measuring screen.
- Sergeant Cluck's Lock Screen card comes back as soon as the training timer ends, instead of at the next app open.
- More Training checks: 39.

**Real Xcode builds before you sideload (one-time setup)**
1. Make a **private** GitHub repo (it holds the More Training code) and upload this folder's contents with GitHub Desktop — see "Build without a Mac" under MK16.
2. In claude.ai: **Settings → Connectors → GitHub**, and give it access to that repo.
3. Tell me the repo name. From then on I push each new version to its own branch, wait for the Actions build, fix anything Xcode flags, and only then send you the zip — with the IPA ready under the run's Artifacts.

## MK19 — Slide between halves, PAC 25 min, undo skip, 8:45pm reminder
- **GymForge ↔ Dayfold** now slides across instead of snapping.
- **Motivation announcements removed**: Sergeant Cluck's twice-daily motivation messages are gone, and the 3-a-day quote notifications are now **off** by default (Dayfold → Settings → Motivation to turn back on). The Motivation widget is unchanged.
- **PAC**: clamp set 2 is now 5 min and the final set 10 min (25 min total). Every vacuum and clamp setting shows in **inHg and kPa**, and the step note on the timer wraps onto as many lines as it needs (no more "…"). The timer header shows kPa too.
- **Undo skip**: after Skip, an **Undo skip** button takes you back to the phase you skipped with the time it had left (and drops a session the skip saved). Available until the next phase ends on its own.
- **Measuring screen stays until filled**: after a session, Done stays greyed out until girth before/after (pump/PAC) and stretched length before/after (HTE) are in. If you leave, it's saved in the vault and comes back next time you open More Training.
- **"Time to train" at 8:45pm** (Time Sensitive notification) on any day with no More Training logged; skipped on rest days you marked. Planned 7 days ahead whenever More Training is open.

## MK18.2 — Guided PAC (Karl's routine) and PAC guide
- **PAC is now a guided timer** (daily routine PAC days and the standalone PAC card): fill up 2 min (−7 to −8, clamp off) → clamp set 1 5 min (−8 / +8) → fresh blood 3 min (clamp off, RIP to −12 then near zero) → clamp set 2 8 min (−9 / +10) → final set 11 min (−10 / +12). 29 min, no rests. Each step shows its vacuum/clamp cue on the timer screen (never on the Lock Screen). Replaces the old PAC 4 × 5; static pump days stay 4 × 5.
- **How to do PAC** page (link on the PAC / routine card): what it is, the routine, VEGF/hypoxia note, seal and clamp-gauge notes, safety (petechiae, aloe + vitamin E, deep not painful, tingling = stop, 3–4×/week, RIP or milking later, weak erections after = dial back) and tips (start semi-erect, 850 nm NIR pad, pulse-clamping, keep the vacuum on).
- New safety card when PAC is done on more than 4 of the last 7 days. The "Numbness / cold" warning is now "Numbness / tingling / cold".

## MK18.1 — Training timer replaces Sergeant Cluck's Live Activity
- While a More Training timer runs, Sergeant Cluck's Lock Screen / Dynamic Island card is hidden and only the training timer shows. Cluck comes back the next time Splitday refreshes after the timer ends (opening the app or the "Update Splitday cards" shortcut).

## MK18 — More Training routine and "when to progress"

**Daily routine** (More Training → Log)
- NIR every other day: **NIR day** = HTE 15 min with NIR + 35 min without (50 min). **Other days** = HTE 40 min.
- Pumping alternates by day: **static pump 4×5 min**, then **PAC 4×5 min** the next day.
- The card works out today's plan from what you logged (NIR yesterday → no NIR today; pump yesterday → PAC today). **Start** runs it as an interval timer.
- The HTE start sheet has a **With NIR** toggle.

**Expansion logging**
- The after-session review asks for girth before/after (pump/PAC) and stretched length before/after (HTE) and saves the %.
- Targets: girth **6–12%** right after pumping, length about **3–4%** after extending.

**When to progress** (new cards for girth and length)
- Good stretch and rising → change nothing.
- Good stretch, flat ~3 months → add time or a second session, not pressure.
- Stretch shrinking at the same settings → raise one small step (0.5–1 inHg or ~1 lb), then hold it 2+ weeks.
- Weaker erections, swelling that lasts to the next session, irritated skin or blisters → back off a few days (new warning options in the review).
- Already added time and intensity in the last ~6 months and still flat → take a proper break.
- Over 12% girth → don't chase pressure. Growth is judged 2–3 months after your last change.
- Only **rested** measurements count (3+ days after a session); Measure warns if it's too soon. Changes under ~0.3 cm (0.1–0.15") are treated as measuring error.
- The existing safety note "Pressure is high" (over 6 inHg) still shows at your 8.5 inHg plan.

**Checks**: `zsh Scripts/run_mt_checks.sh` (39 checks, also run by GitHub Actions).

## MK17 — More Training timer stays open, coaching logic review

**More Training timer**
- While a timer runs (open timer or intervals) the **screen doesn't auto-lock**, whether the timer is full screen or minimised.
- **Leaving the app no longer locks More Training mid-timer.** Come back and it's still open, no Face ID. Once nothing is running it locks as before, and if the timer finished more than 10 minutes before you came back, it locks then.
- The timer shows on the **Lock Screen, Dynamic Island and Watch Smart Stack**: a countdown to the end of the phase (or to an open timer's limit, then a count-up past it), "Work · 2 of 3" / "Rest", what's next, and when the whole program ends. Paused shows frozen. It only ever says "Timer" / "Work" / "Rest", never what the session is. Tap it to come back.
- If iOS suspends the app, the card can't switch phases by itself. When a phase ends it shows "Next step" with the time left in the whole program, and the ⏱ notification still marks each change.

**Coaching logic review: 11 fixes**
1. Bodyweight exercises (weight step 0) at the top of their range: "hold it, slow the lowering, add a pause or a harder variation", never "+2.5 kg" (Coach tab, Sergeant Cluck screen). Titles say "Keep bodyweight", not "Keep 0 kg".
2. Lose Fat goal and gaining weight with body fat rising: "trending up while your goal is Lose Fat", not "too fast for lean gain".
3. Losing weight on a Build Muscle / Get Stronger goal: "add 200–300 kcal", no longer "still positive progress".
4. The Coach tab's strength trend leaves out deload / short / easy / tired sessions and keeps each variation separate.
5. The Coach tab now uses the same week numbers as Today: a break or sick/travel week shows "No target this week" (no "3 to go"), and break weeks are left out of adherence and averages, so no "make your goal realistic" or "only hit 40%" after a break.
6. Bulk rate: "sweet spot" only for +0.25–0.5%/week. Slower is "on the slow side" and faster "at the fast end", each with its own tip.
7. "Bulk adding mostly fat" protein advice uses your real protein target (phase × weight), not a separate 1.8 g/kg.
8. Like with like everywhere: plateau, stall and strength-trend checks compare a variation (paused, wide grip, belt…) only with itself, so a planned variation block isn't read as a stall or a strength drop. Today's set targets come from the last session done the same way, when there is one.
9. Phase report cards count gym sessions only; runs and basketball no longer inflate sessions or adherence.
10. "Ready to add weight" says why for each lift: top of the range, 3+ reps left, or a new rep range.
11. No more "drops ~−0.40 kg/week" double negative.
- Reviewed and fine as written: double progression and the failure rule, set-by-set comparisons (2+ reps / 3% e1RM to count as a drop), the per-set re-aiming, the effort targets through a block, the stall and plateau thresholds, the deload maths, readiness scoring, body-weight trend maths, Katch–McArdle and the self-correcting maintenance, and the fat-gain check.
- 167 logic checks (17 new for these fixes).

## MK16 — automatic builds, motivation widget, Sunday meal prep

**Build without a Mac (GitHub Actions)**
1. Make a GitHub repo (private is fine) and upload the *contents* of this folder, so `.github/`, `GymForge.xcodeproj` and `Scripts/` sit at the top. GitHub Desktop is the easiest way.
2. Every push builds it on GitHub's Macs: logic checks → Dayfold tests → an unsigned IPA. Or run it by hand: **Actions → Build Splitday → Run workflow**.
3. Open the finished run → **Artifacts → Splitday-IPA**, download, unzip, and open the `.ipa` with SideStore/AltStore. It signs it with your Apple ID.
- A red ✗ means it didn't compile; the failing step shows the exact error. Send it to me.
- Unsigned builds are ad-hoc signed with their entitlements (Health, App Group) so the signing tools keep them. Free GitHub accounts get a monthly allowance of Mac build minutes; one build takes roughly 10–20 of them.

**Motivation (widget + 3 quotes a day)**
- Long-press the Home Screen → **+** → **Splitday** → **Motivation** (small, medium, large, or Lock Screen). A serif quote over a dark gradient tinted by topic; **↻** shows the next one.
- Changes at **8:00, 13:00, 18:00**, and the same quote arrives as a silent notification.
- **Dayfold → Settings → Motivation**: topics (Discipline, Gym & training, Letting go, Stoic, Study & career, Confidence, Rest & recovery), tone **Calm** or **Tough (Sergeant Cluck)**, notifications on/off.
- Mostly original lines plus a few public-domain classics (Seneca, Epictetus, Marcus Aurelius, Lao Tzu).

**Meal prep every Sunday**: Dayfold's Weekly list (and the Weekly reminder) gets "Meal prep · 5 lunches × 50 g protein", sized from your protein target (about 30% of the day per lunch). It carries forward until done.

**Notification budget**: Dayfold's own reminders now cap at 10 upcoming so quotes fit under iOS's 64.

## MK15 — end a block, nightly recap, rest-day abs, More Training button, wake-up checklist

**End a block**: Coach → Training block → **End this block** (asks first). Workouts and history stay. The section then offers **Start a block today**, so the new block's weeks count from now.

**Nightly recap**: when you tap I'm going to bed, or finish the before-bed list, you get "🪖 Day recap: 2 of 3 on target":
- protein vs target, creatine ✓/✗, trained or rest day, Dayfold steps done
- up to 3 lines of advice, e.g. "45 g short. Tomorrow: protein at breakfast and a shake after training", "Creatine missed: take 5 g with breakfast", "Push tomorrow. Bag packed".
- It stays in Notification Centre and is shown again on the next morning's wake-up checklist.

**Abs once a week on a rest day**: "Abs · 10 min (rest-day core)" appears in Dayfold's Weekly list (and Home's due list) on a rest day, meaning no session planned in Plan week and none logged that day. Once ticked it stays done for the rest of the week, then comes back next week.

**More Training**: a 🛡 button at the top of Today. It still needs Face ID or your passcode, and the title long-press still works.

**Wake-up checklist (Dayfold)**
- Steps with the new **Wake-up** switch (Dayfold → Routines → a step). Existing setups get three starters once: water, make the bed, 5 min of daylight. Plus **Creatine 5 g**, the same tick as GymForge's nutrition card.
- A notification at your **wake time** (Today → Sleep → Schedule), and "🪖 Wake-up checklist still open" 45 min later unless it's done. Tap either, or use Dayfold home → Wake-up checklist (`gymforge://wakeup`).
- Shows "Push today" on gym days and last night's recap at the bottom.
- Dayfold's own reminders are now capped at 12 upcoming, to stay under iOS's 64 with everything else.

## MK14 — enforcement: protein and Dayfold chase you

**Protein** (GymForge → Today → nutrition card; target = your phase × latest body weight)
- Three checkpoints: **12:00** (35% of target), **16:00** (60%), **19:30** (85%). A nag fires only if you're behind at that time: "Protein behind: 50 g so far, should be 58 g by now", and at 19:30 "🪖 PROTEIN: 70 g SHORT".
- **+25 g / +40 g** buttons right on the notification (long-press it) log protein without opening the app, and move the later nags.
- Logging protein anywhere reschedules them, so you're only nagged while actually behind. Tomorrow's are set up too, in case you don't open the app.
- No body weight in Apple Health = no target = no nags.

**Dayfold**
- If a reminder's steps are still undone, follow-ups come **1 hour** and **3 hours** later ("🪖 Still not done · Daily", with the list). Never after 21:00, since the evening is the before-bed checklist's job.
- Ticking the steps off cancels the follow-ups.
- Reminders must be on (Dayfold → Settings → Reminders). Dayfold's home screen warns you when they're all off.

Workouts are still enforced by Sergeant Cluck (weekly quota, Lock Screen card, nags) as before.

## MK13.1 — bedtime card goes up early
- The bedtime card now appears whenever Splitday is opened (or the Shortcuts automation runs) in the **2 hours before bed**, so it's already on the Lock Screen at wind-down instead of needing the notification tapped. Until then it counts down to lights out with the checklist and **Start**; Sergeant Cluck's gym card has ended by 9 pm.
- Set the **Update Splitday cards** automation anywhere in that window, e.g. **21:30** for a 23:00 bedtime. The wind-down notification still comes 10 minutes before bed.

## MK13 — the app is now called Splitday
- The name under the icon, on the Watch, in the widget gallery, in permission prompts and in Shortcuts is **Splitday**. Inside, the two halves keep their names: **GymForge** (training) and **Dayfold** (routines).
- Nothing else changes: same bundle ID (`com.jason.gymforge`), same Xcode project and schemes, same `gymforge://` links, so your data, history and signing carry over. Install it over the old app; don't delete the old one first.
- The Shortcuts action is now **Update Splitday cards**. Automations made with the old name need the action re-added.


## Run it
1. Open `GymForge.xcodeproj`, then Product → Clean Build Folder (⇧⌘K).
2. Check Signing & Capabilities on the **GymForge**, **GymForgeWatch** and **GymForgeWidgets** targets (same team on all three).
   - iCloud backup is switched off in the entitlements because free (personal) Apple developer accounts can't use iCloud. Backups still work via Settings → Export backup file. With a paid account you can turn it back on: Signing & Capabilities → + Capability → iCloud → tick iCloud Documents and add the container `iCloud.com.jason.gymforge`.
3. Run the **GymForge** scheme on your iPhone. The Watch app and the Live Activity extension are built and installed with it.
4. Allow Health access (now also Sleep, Resting Heart Rate and HRV) and notifications. On the Watch, allow Location the first time you start an outdoor run (for the route map).
5. Logic checks (no device needed): `./Scripts/run_checks.sh`

## Private section ("More Training")
- Long-press the **Today** title → "More training?" → Yes → Face ID (or passcode).
- Its own encrypted storage (AES-GCM, key in this device's Keychain), excluded from device backups, iCloud, the Watch, Apple Health, reports and coaching. Locks whenever you leave or the app goes to the background (MK17: except while a timer runs); hidden in the app switcher.
- Photos come from an in-app camera and are stored encrypted inside the app only.
- Export/import is a separate encrypted file protected by a passcode you choose.

## MK12 — Dayfold merged in, before-bed checklist, new icon

One app, two halves, so it takes **one** of the 3 sideload slots on a free account. Dayfold's code lives in `Dayfold/` (Shared / iOS / Watch) and its scheduling tests in `Dayfold/Tests` (`cd Dayfold && swift test`).

**Switching halves**
- GymForge → Today → **Dayfold** (top left). Dayfold → **GymForge** (top right of its home). The app reopens in whichever half you used last.
- **Long-press the app icon**: Before bed · Dayfold · GymForge.
- **Two Home Screen icons (optional)**: in Shortcuts, make a one-step shortcut "Open URL" → `gymforge://dayfold`, then ⓘ → Add to Home Screen, name it Dayfold and pick `Docs/Shortcut icons/Dayfold.png` (save it to Photos first). Same with `gymforge://gym` and `GymForge.png`. Shortcuts flashes for a moment before the app opens.
- Links: `gymforge://gym`, `gymforge://dayfold`, `gymforge://dayfold/weekly` (daily/weekly/monthly/yearly), `gymforge://winddown`, `gymforge://bedtime`.

**Before-bed checklist (wind-down)**
- Wind-down is now **10 minutes** before bed (was 15). Set bedtime in Today → Sleep → Schedule.
- The wind-down notification opens the **Before bed** checklist: every Dayfold step with **Before bed** on (Skincare, Hair care, Check the door, the jaw opening drill by default), plus **"Pack gym bag · Push tomorrow"** when Plan week has a session tomorrow.
- The Lock Screen / Dynamic Island card shows what's left with a **Start** button until you start; then "Before bed · 2/5 · Next: Skincare" and **I'm going to bed**.
- **Finishing the list during wind-down = I'm going to bed**: the card goes, the nags stop and your Sleep Focus shortcut runs.
- **Gym tomorrow**: one extra nag right at bedtime ("LIGHTS OUT … Bag packed?"), and every later nag says what's tomorrow.
- **Streak**: "In bed on time · 5 nights running" — nights you tapped I'm going to bed (or finished the list) by bedtime.
- **Weigh-in ticks itself** when Apple Health gets a new weight (your scale → Health) on or after its due day. Matches steps with "weigh" in the name.

**MK12.1: cards without opening the app**
- Shortcuts → Automation → + → **Time of Day** → pick a time → **Run Immediately**, Notify When Run **off** → add the Splitday action **Update Splitday cards**. It runs in the background: no app switch, no Shortcuts screen.
- Suggested: **7:00 am daily** (Sergeant Cluck's gym card on days you still owe a session; it turns angry at 5:10 pm on its own and ends at 9 pm) and **2 hours or less before bedtime**, e.g. 21:30 for 23:00 (the Before bed card with Start). One automation per bedtime if your bedtime changes by night.
- The wind-down notification at 10:10 still comes as well, and tapping it still opens the checklist.

**Limits**
- Without the automation above, iOS only lets the app start the card while it's open, so it appears when you tap the wind-down notification (or open the app during wind-down). You can still swipe it away; it ends an hour after bedtime.
- Dayfold reminders are capped at 16 upcoming (iOS allows 64 per app, shared with GymForge's own).
- Data from the separate Dayfold app doesn't carry over (different app container); Dayfold starts with its starter routines.
- On the Watch, Dayfold is under GymForge → Dayfold. "Pack gym bag" is iPhone-only.
- The new icon: GymForge orange and Dayfold lavender, split down the middle with a dumbbell through it. The old icons are in `Docs/Shortcut icons/`.

**Fixed**: `Scripts/run_checks.sh` didn't compile `Widgets/Cluck.swift`, so the checks failed to build. 132 checks pass.

## MK11.3 — Grip / variation notes, "Give me a break"

**Variation notes ("today is wide grip")**
- Workout screen → under each lift: **Variation** — Wide grip, Narrow grip, Neutral grip, Close / Wide stance, Paused, Slow tempo, Belt, Straps, or your own. "Same as last time" one tap away, and "Last time: wide grip" shows under it.
- Saved with that exercise in the workout (History and the summary show it; the Watch shows it under the exercise name).
- **The coach only compares like with like**: wide-grip bench is compared with your last wide-grip bench, not your usual grip — so a grip change is never read as a strength drop.

**Give me a break (Plan week → Give me a break)**
- Hard to switch on, on purpose: pick a reason **with a number** (2+ assignments/exams due, 3+ days of 10+ hour work, or 2+ days of a move / family emergency), say what's due, and when the last one is due (1–14 days away). Once every 6 weeks.
- **Sergeant Cluck pushes back** first and offers **maintenance mode** (goal drops to 2 short sessions, workouts default to 30 min) before a **full break** (no goal). Then type **BREAK** to confirm.
- During it: he doesn't nag (Empathetic mood, break lines), no "you're behind" reminders on a full break, your **streak is paused** not broken, break sessions stay out of plateau / strength trends, and no "inconsistent training" comments about it afterwards. End it early any time.
- **Comeback**: after a break of 5+ days, Today suggests a light comeback session until you've trained again.

**More Training — daily routine**
- More Training → Settings → Plan → **Daily routine**: high tension extender 3 × 20 min, then pump 2 × 5 min, every day (a "Daily routine" preset, editable; 1 min between sets). A "Today's routine" card replaces the PAC card, the weekly goal becomes 7 days, and the PAC every-other-day plan, its warnings and Cluck's PAC comments are off.
- Turn it off to go straight back to PAC every other day and your previous weekly goal.

## MK11.2 — Sergeant Cluck nags you to bed, "I'm going to bed" turns on Sleep Focus

- **Bedtime card that won't leave you alone**: from 15 minutes before bed it's the wind-down card; at bedtime it turns red and Sergeant Cluck yells "GO TO BED, RECRUIT" with a live counter of how late you are (Lock Screen, Dynamic Island, Watch Smart Stack).
- **Escalating nags** after bedtime: +10, +20, +30, then every 5 minutes until an hour late ("IT'S 35 MINUTES PAST YOUR BEDTIME"), on iPhone and Watch, with sound.
- **"I'm going to bed"** (on the card and Today → Sleep): the card goes, the rest of tonight's nags are cancelled — and GymForge runs your Sleep Focus shortcut. Sleep itself is left to your Apple Watch.
- **Sleep Focus setup** (Today → Sleep → Schedule): make a one-action shortcut in Shortcuts ("Set Focus → Sleep → Turn On"), type its name in GymForge. iOS doesn't let apps switch Focus directly, so tapping the button opens GymForge (Face ID if locked) and the Shortcuts app flashes for a second.
- Limits: iOS only lets apps start the card while GymForge is open — tap the wind-down notification (or any nag) and it appears. The nags still come if you don't.

## MK11.1 — Fairer comparisons, session context, separate goals, 4 new Cluck moods, Cluck as your coach

**Better coaching comparisons**
- **Like for like**: sets at the same load are paired set-for-set — an extra set isn't "improved", a missing set isn't a "decline" ("80 kg · 2 of 3 sets").
- **Rep range or load changed**: judged on estimated 1RM ("Lighter, similar strength", "New rep range — est. 1RM +3%").
- **Effort counts**: same reps with more left in the tank = progress; same reps closer to failure is noted, not praised.
- **A drop has to be real**: 2+ reps on matching sets, or 3%+ est. 1RM. One rep down is "within a rep of last time".
- **More cautious about plateaus and strength loss**: plateau = 4 normal sessions over 3+ weeks with no new best; coach stall = 4+ sessions and 4+ weeks; cut strength-drop needs the last two sessions down 5%+; muscle-loss warning needs strength down 3%+ (was 2%). The after-workout "Flat 4 sessions" line only counts normal sessions.

**Session context**
- Tag a workout **Short on time, Equipment unavailable, Easier on purpose or Unusually tired** — during it (Today's context, above Finish) or afterwards (summary and History).
- Using the time-budget picker tags "Short on time" automatically.
- Tagged sessions stay out of plateau, stall and strength-trend checks; a lower number on a tagged day is noted ("— you were run down, not a real drop") instead of called a decline. Easy-on-purpose and run-down sessions also aren't used as "last time" for your next targets (like a deload).

**Training goals**
- Today → **Goals this week**: lifting (your weekly goal, still the one Cluck enforces), running (runs a week and/or km a week) and **basketball tracked separately** (a goal, or just a count). Edit from the card.

**Sleep stays in its lane**
- The bedtime Live Activity only appears in the **wind-down window** (15 min before bed until bedtime) instead of counting down all evening — the rest of the day the Lock Screen is about the gym.
- The 15-minute **wind-down notification** now plays a sound on iPhone and Watch; tapping it (or opening GymForge then) starts the wind-down card.
- Late nights no longer make Sergeant Cluck worried during the day — he calls them out at bedtime (Lights out mood).

**Sergeant Cluck — new moods, accessories, animation**
- **He's a chicken again** (white feathers, beak, wattle, drill-sergeant hat) everywhere — the soldier is only the 🪖 emoji on his notifications. His chicken lines are back too ("the coop salutes you", "I didn't hatch for this"). All 10 MK11 / MK11.1 moods are drawn on the chicken.
- **Analytical** (glasses + clipboard; plenty of time left and you use the Analytical coach style, and in "Explain, Sergeant"), **Locked in** (red sweatband + whistle; whenever a workout is running — widget too), **Protective** (shield; an open pain flag, and in More Training when the safety check says rest), **Empathetic** (soft heart; sick/travel days and sessions tagged unusually tired).
- **Impressed** now wears a medal, **Smug** wears aviator shades.
- **Subtle animations in the app**: a slow bob, blinks every few seconds, a swinging medal, a shades glint, a beating heart. Widgets, the Lock Screen and the Watch face stay still (iOS doesn't animate them), and Reduce Motion turns it off.

**Cluck as your coach (workout screen)**
- **Session introduction** before the first set: exercises, sets, minutes, today's effort target and the first exercise.
- **Accepted-plan reminders**: coaching you accepted that applies to today's exercises ("You agreed: drop bench to 3 sets").
- **Current-set cue**: set number, target weight × reps, reps to leave in the tank, and a form cue that rotates each set.
- **Rest cue**: rest length and the next set's target (and "take the full rest" after a set to failure).
- **"Explain, Sergeant"**: why today's numbers are what they are — the progression rule, the per-set plan, the block/effort target, pain flags and today's context.

**Fixed**
- A logic check from MK10.2 ("coach suggests a more realistic weekly goal") used empty workouts that no longer count as training; it now uses real sets. All 117 logic checks pass.

## MK11 — Sleep schedule & wind-down, Sergeant Cluck the soldier, new moods and pattern comments

**Sleep (Today → Sleep, Watch → Sleep)**
- **Schedule per night**: a bedtime and wake time for each day of the week ("Friday night" = bed Friday, up Saturday). Syncs to the Watch.
- **Last night vs plan**: hours asleep, bed and wake times and how far off the plan ("+18 min late"), on iPhone and Watch.
- **Consistency**: a 0–100 score over 14 nights, on-time streak, late nights this week.
- **Wind-down**: a Live Activity (Lock Screen, Dynamic Island, Watch Smart Stack) counting down to bed that turns into "Wind down" 15 minutes before — open GymForge once in the evening (iOS only lets apps start it while open). A quiet reminder also taps your Watch 15 minutes before every night.
- **Manual tracking**: "Going to sleep / I'm awake" on iPhone and Watch, saved to Apple Health — only used when the Watch didn't track that night (the Watch's own sleep always wins).

**Sergeant Cluck**
- **A drill sergeant now, not a chicken** — new face (campaign hat, moustache, uniform with stripes) on the widget, Dynamic Island, Watch face and Today; notifications use 🪖 and no chicken talk.
- **6 new moods**: Suspicious (the weekday you keep skipping), Impressed (3+ weeks at your goal), Smug (trained on a rest day), Worried (pain, low readiness or 3+ late nights — he eases off), Relieved (first session after 5+ days), Lights out (after bedtime).
- **Comments on inconsistent gym training**: planned weekdays you keep missing, weeks under goal in a row, long gaps, sessions getting shorter, strong Mondays that fade — on Today and in his notifications.
- **Late nights**: he tells you to go to bed after your bedtime and calls out late nights.
- **More Training**: his comments on your PE consistency (days off, PAC overdue, stretcher hours dropping, starts and stops) appear **only inside More Training** (Today tab, behind Face ID) — never in notifications, widgets or on the Watch.

## MK10.2 — Calorie targets, bulk fat check, mini-cut reminder, cardio as extras, quiet training nudge

**Calories (Today → Calories)**
- A daily target for your phase: bulk = maintenance + 300, recomp ≈ maintenance, cut − 500, mini-cut − 750, with protein / fat / carbs.
- Maintenance starts as an estimate from your scale's weight and body fat (Katch–McArdle × how often you train + your runs and games). Log calories for 2 weeks (+100 / +250 / +500 or type the total) and it switches to your **real** maintenance from what you ate and how your weight moved.
- Same target every day; tip: put more of the carbs around training.

**Bulk going too fat**
- On a bulk it compares the first and last 2 weeks of the last 6: how much of the gain was fat. About half fat (or body fat rising ~0.5%/month) → "keep an eye on it", −100 kcal; two-thirds or more (or ~1%/month) → "bulk is adding mostly fat", −200 kcal and a notification.
- Advice: trim from fats/snacks not protein, protein check (if you log it), carbs around training, cut liquid calories, steps 7–10k, and whether your lifts say the bulk is working.

**Mini-cut reminder**
- The mini-cut card now also comes as a notification (at most every 2 weeks). A mini-cut sets the −750 target and ends at 5 weeks or once body fat is ~5% under your limit (after 2 weeks at least).

**Cardio is an extra**
- Runs, basketball and cardio-only sessions no longer count toward the weekly goal, streak or Sergeant Cluck (they still show on the week row).
- Cardio inside a gym routine is optional: the workout counts as complete when the weights are done, and a time budget cuts cardio first.

**More Training**
- A quiet "⏱" (no sound) at 7:30pm on day 3 without training, once more on day 6, then nothing. Training = 1 h+ stretcher, 30+ min extender, or any PAC / pump. Never on rest days or when the safety check says rest. Toggle in More Training settings.

## MK10.1 — Heart rate after the workout, the coach's brief, set-by-set advice, edit routines anywhere

**Heart rate**
- After a workout (and in History): peak, average and your **usual peak** for that routine ("Peak 12 bpm higher than your usual Legs"), a **graph** of the whole session with a grey line at every set, time in zones 1–5, and which exercise pushed your heart rate highest.
- The Watch keeps a reading every ~10 s for the graph (kept on the iPhone only). The Watch summary now shows **peak HR** too.

**Coach's brief**
- Replaces the old three-line verdict: a one-line rating (Strong / Solid / Mixed session, Tough day, or "Easy week, job done" on a deload), then a few sentences — what went well (PRs, lifts up, % of targets hit), what fell short (lifts down, sets to failure when the block said leave reps), context (low recovery, a hard game the day before) and **one thing for next time**. Ends with a line in your coach style.
- **Read aloud** button. The Watch summary shows the rating line.

**Set-by-set comparison**
- Each logged set shows how it compares to the same set last time ("9 vs 8 ↑").
- After two sets, and when the exercise is done, one line of advice that reads the pattern: e.g. last time 20×8·8·8, today 20×9·9·6 → "Same total (24), but you ran out on the last set. Rest a bit longer before it, or pace for 9·8·8 — even sets build more." Also: up on every set, down on every set, slow first set, heavier but fewer reps, less assistance.
- The same advice is under each exercise in the workout summary.
- **Next session's plan follows it**: after a lopsided 9·9·6, the targets become 9·8·8 (one more rep, evened out).

**More Training**
- Measure tab: a **Preferred size** card compares your NBP, mid-shaft girth and base girth with the average of what women preferred in a 3D-model study and the best-selling toys (≈16.1 cm × 12.8 cm), with the sources listed.
- Type up to 3 readings per measurement (e.g. "16.1 16.3 16.2") and the average is saved; a "measure the same way" checklist on the entry screen.
- Safety: a warning for pressure above 6 inHg and clamp sets over 15 minutes (on top of the EQ, morning-erection and warning-sign checks).

**Edit routines from anywhere**
- Tap a routine (e.g. Chest Day): each exercise has a **⋯** menu — **Replace permanently** (coach-suggested swaps first, then the whole searchable library, or type your own), **Move up / down**, **Remove**. **Add exercise** at the bottom suggests what the routine is missing.
- During a workout: **+** adds an exercise (just today, or to the routine too), and after a swap, **Make permanent** puts it in the routine.
- A replaced exercise keeps its own history; the old one stays as a one-tap swap option.

## MK10 — A coach that plans: training blocks, effort targets, stall diagnosis; runs & basketball without the Watch

**Training blocks (Coach → Training block)**
- Start a fixed-length block: 3–6 build weeks (default 4) then a planned deload week, repeating. Size focus uses your normal rep ranges; strength focus uses the strength block.
- **Effort targets** rise through the block: about 3 reps left in week 1, 2 in week 2, 1 by the end; the deload is easy (4+ left). Shown on Today, on the workout screen ("Effort: ~2 reps left (last set ~1)") and on the Watch next to the plan. Without a block the target is ~2 reps left.
- From week 2 the coach suggests **one more set a week** for up to 2 muscles that are recovering well (priorities first), up to the middle of their range (priorities: near the top).
- **Block review** on Today during the deload and the week after: sessions, each lift's change from the start to the end of the block, hard sets per muscle, and what to do next block.

**Smarter coaching**
- **Honest volume**: sets rated 4+ reps left count as half a hard set. The effort buttons now go Fail · 1 · 2 · 3 · 4+.
- **Set fell short?** If a set lands below your rep range, the coach now *suggests* a lighter weight ("Use 97.5 kg" / "Keep weight") instead of changing the plan.
- **Stall diagnosis**: a lift with no progress for 3+ weeks gets one suggestion for the most likely cause, checked in order — on a cut (that's fine), recovery (lots of sets to failure / low readiness), too much volume (−1 set), too little (+1 set), a stale accessory (swap to a similar exercise; the old one stays as a swap option), or for main lifts a new rep range.
- **Pain flags** now feed the coach: sore / sharp pain → swap to a gentler machine or cable option while it heals; a niggle → go gently.
- **Diet phase**: on a cut, no extra volume is suggested (bottom of the range is enough); on a bulk, priority muscles aim a little higher.
- **Runs and basketball count**: a long run or hard game in the last ~30 h triggers a leg-day warning on the routine preview.
- **Consistency**: weekdays you keep missing in your week plan, and routines that need more days than you actually train, get a suggestion (e.g. a 3-day split).

**Plan your week**
- Today shows **Plan your week** when the rest of the week is open; Plan week is also linked from the weekly review (on Sunday it opens next week).
- **Auto-plan the open days**: tick your training days (pre-selected from the days you usually train, as many as your weekly goal); your routines go on them in order, continuing from the last one you did, and the other days become rest days.
- **Copy the week before**: same plan, same weekdays. Both only fill open days from today on.
- **Sergeant Cluck is chill on planned rest days** — a rest day planned the day before or earlier keeps him calm on the day ("Planned rest day. Eat, sleep, grow."), and Today shows "Planned rest day — Sergeant Cluck is off duty". Planned rest days don't lower the weekly goal, so he still counts them as days you can't train when working out how much slack you have. A rest day declared on the day itself still gets you nagged.

**Runs & basketball without the Watch**
- In the start sheet choose **Record with: Apple Watch / iPhone** (iPhone is automatic when no Watch is set up).
- Outdoor run on iPhone: GPS distance, pace, km splits with a haptic, auto-pause, goals and the route (keeps recording with the screen locked; allow Location when asked). Treadmill and basketball: a timer.
- No heart rate, so at the end you rate **how hard it was (1–10)**; treadmill distance and basketball minutes/shots go in the same screen. Training load = effort × minutes, used by the coach.
- **Log one you didn't record** (Today → Cardio): date, duration, distance or shots, effort.
- Phone sessions and logged ones are saved to Apple Health (Running / Basketball, with distance and route). Watch sessions can be rated too, from their detail screen.
- If the app is closed mid-session, it offers to save what was recorded up to the last 30 s.

**Notes**
- Treadmill / basketball on the iPhone: the timer is always right, but the Lock Screen card only updates while GymForge is open (GPS runs keep it live).

## MK9.1 — A smarter coach, runs and basketball

**Coach**
- **Knows the exercises**: a built-in library of ~100 gym exercises with the muscles each one trains (main muscle = 1 set, helper muscles = ½ set), sensible rep ranges, rest times, weight steps and good swaps. Your own exercise names are matched automatically ("Incline DB Press", "Lat Pulldown (Hammer Strength)"…). The exercise editor has **Use coach settings** to fill in the library's numbers.
- **Size or strength focus** (Coach tab → Focus, top of Suggested changes). Size is the default: moderate reps on most lifts. Strength moves the main lifts to heavy, low-rep sets with longer rest. You can switch any time.
- **Suggestions, never automatic changes**: Coach → Suggested changes lists changes with a one-line reason — e.g. more sets for a muscle that's below ~10 hard sets a week, fewer sets where strength is dropping, longer rest on heavy lifts, a missing muscle (hamstrings, side/rear delts, calves), more pulling than pushing, the big lift before isolation work, splitting a muscle over two days. Tap **Accept** to apply it to the routine or **Not now** to hide it for 4 weeks.
  - After you accept a volume change for a muscle, the coach waits 3 weeks before suggesting more for it, so it can see if it worked.
  - During a deload week it doesn't suggest volume changes or another deload.
  - Accepted suggestions are followed up in the Sunday weekly review ("Suggested for next week" too).
- **Weekly sets per muscle** (Coach → Muscles & routine check): what you've actually done lately vs what your routines plan, against the usual target range, plus each muscle's strength trend.
- **Routine check and builder**: the check (same screen) reviews your routines without any history. Coach → Build a routine makes a new split for 2–6 days a week, a time limit and priority muscles (it trims isolation sets before dropping exercises). Built routines are added next to yours, never replacing them.
- **Effort ratings feed back in** (iPhone only, optional per set): if every set had 3+ reps left, the next session goes up straight away ("Felt easy — go up").
- **Warm-ups** from the library: ramp-up sets (≈50/70/85%) before heavy compounds only.
- **Recovery warnings** on the routine preview (e.g. quads trained hard yesterday), a short **verdict** after each workout (what went up, what's stuck), and a longer rest hint after a heavy set taken to failure.

**Running**
- **Start from the iPhone** (Today → Cardio card → Run): choose outdoor or treadmill and a goal (none, distance, time or pace). The Watch app opens already recording — if the Watch asks, tap once to confirm. You can also start on the Watch: Home → Run & basketball.
- On the Watch: time, distance, current and average pace (min/km), heart rate with zone colour, a tap and banner every km with the split, goal alerts ("Speed up / Ease off" for a pace goal), auto-pause outdoors when you stop, cadence and running power. Swipe up for Pause / End / Discard.
- Saved to Apple Health as a Running workout, with the GPS route for outdoor runs.
- The Lock Screen card on the iPhone shows distance, pace and heart rate while you run.
- **Run history** on the iPhone: route map, km splits chart, best 1 km and 5 km, and an easy-run heart-rate trend (are you getting fitter at the same effort). Treadmill distance can be corrected afterwards.
- Runs count as a workout for your week (**CA** on the week row), streaks and Sergeant Cluck. The week planner can plan Run days.

**Basketball**
- Start the same way (Today → Cardio card → Basketball); pick Pickup game, Shooting practice or Training session. Saved to Apple Health as Basketball.
- Afterwards add minutes played and shots made / attempted (shooting %). You also get an effort score (from heart rate and time) and time in each heart-rate zone.
- Counts as a workout (**BB** on the week row); plannable in the week planner.

**Settings**
- Max heart rate for zones (otherwise estimated from the highest heart rate seen in the last year).

**Notes**
- If the run is started on the Watch or the phone is locked, the iPhone's Lock Screen card appears once GymForge is opened on the phone.
- More Training data is still never used by the coach, runs or basketball.

## MK9 — Coaching per set, time budget, week planning, weekly review, corrections, equipment, speeches, More Training goals

**Coaching**
- **A target for every set**: the same weight on every set, with reps from last time and how much you usually drop off, e.g. "80 kg × 10 · 10 · 9 — last time 10/9/8, 2 more reps". It shows on the routine preview ("Why: …"), as chips on the workout screen and as the grey numbers you type over (Watch too).
- **Re-aimed mid-workout**: if a set goes clearly worse, the rest adjust. Below the range means one step lighter (more help for assisted exercises); 2+ reps short means same weight, fewer reps. A strong set adds a rep.
- **Time budget**: pick 30–90 min before starting. Sets come off the least important exercises first (down to 2, then 1); only then are whole exercises skipped. Supersets are trimmed and dropped together. Big compound lifts, weak / priority muscles and muscles behind this week are kept first. Skipped ones can still be tapped mid-workout.

**Planning and review**
- **Plan week** (Today → Plan week): choose a workout, rest, sick or travel day for this week or next.
  - Planned workouts show first on Today, and in grey on the week row.
  - Sick and travel days lower the week's goal by one each and stand Sergeant Cluck down (he still nags on rest days).
  - Travel days offer a no-equipment Hotel Workout.
- **Weekly review**: Sunday 7:30pm (with Sergeant Cluck's recap, or on its own), or from the Today card until Tuesday.
  - Sessions vs goal and planned workouts done.
  - Sets per muscle, with secondary work counted as half a set, against target ranges.
  - Priority muscles (star them).
  - Follow-up on coaching you accepted with "I'll do this" (plateau tips, weak points, deload): did you do it, and is it working.

**Workouts and equipment**
- **Workout corrections**: History → a workout → Edit, to fix sets, weights, reps, exercises, date and duration, or delete it. History → + logs a missed session by hand (not added to Apple Health). PRs across your history are re-checked after every correction or delete.
- **Equipment**: give an exercise a machine name ("Hammer Strength") and it keeps its own history, PRs and progression ("Chest Press (Hammer Strength)"). "Weight is" can be total, per side, per hand or pin-stack level, shown with the right unit everywhere. A weight step of 0 makes it a bodyweight exercise (no weight to type).
- **Live Activity**: always the exercise and "Set 2 of 3" (the set you're on; during rest, the one coming up) plus your last set. The quote only appears during rest.

**Speeches**
- **Motivational speech player**: import your own audio files (Settings → Motivational speeches, or the ♫ button on the workout screen).
  - Nothing plays until you press play.
  - Your music pauses while a speech plays and can resume after.
  - Controls on the Lock Screen / Control Center.
  - Resumes where you stopped.
  - The rest-end chime and announcement play over it at lower volume.
  - Pauses if your headphones disconnect.

**More Training**
- **A goal for each measurement** (BPEL, BPFSL, NBPL, MG, BG), in cm or inches.
  - Progress bar from where you started.
  - Uses your recent average, so one reading doesn't swing it.
  - Projected date from the trend.
- **Compared with the average**: % over/under and an approximate percentile.
  - Default: Herbenick 2014 (1,661 US men, self-measured: 14.15 cm length, 12.23 cm girth).
  - Or Veale 2015 (clinician-measured: 13.12 / 11.66 cm).
  - BPFSL uses Veale's stretched figure.
  - No study measures NBP, so its average is a clearly labelled estimate (bone-pressed average − ~1 cm).
  - Percentiles use the clinical study's spread.
- **BP vs NBP gap over 1 inch**: explains it's mostly the fat pad, with cutting advice based on your latest body fat (read from the gym side; nothing flows back).
- **Plateau check now 8 weeks** (BPEL / BPFSL), with a safe order:
  1. Consistency.
  2. More time at the same tension.
  3. One small tension step within the device's limits.
  4. A high-tension extender.
  5. A break.
  
  It never suggests more force after a recent warning sign (pain, numbness, swelling) or falling erection quality — it says rest instead.

## MK8.8 — Train announcement, 20 new quotes, big bug sweep

**New**
- **Rest ends like a station announcement** (Settings → Rest timer → When rest ends: Train announcement / Ding / Vibrate only). A three-note "du-du-du" chime, then an Australian voice over your music: "The next exercise is Lat Pulldown. 8 reps." (or "The next set is …, set 3 of 4"). Reps are today's target. With the iPhone locked you hear the chime only (iOS can't speak from a notification). Tip: download "Karen (Enhanced)" or another English (Australia) voice in iPhone Settings → Accessibility → Spoken Content → Voices for a nicer voice. Train announcement is now the default.
- **20 new reflective Heartbreak quotes.** The Lock Screen Live Activity drops the routine/time row for long quotes so the whole quote fits.

**Fixed (from a full review of the app)**
- **Watch**:
  - Added the "workout processing" background mode. Without it, watchOS can stop the workout session when your wrist drops, so heart rate, calories and the rest-finished buzz can fail.
  - "Rest finished" no longer comes back a second time after you tap Go.
  - The Rest button no longer stays greyed out when the iPhone left a half-typed set and went out of range.
  - Health sessions no longer keep running after a workout is cancelled or never arrives.
- **Sync**: a set logged on the iPhone and the Watch at the same moment is no longer lost (both are kept). Cancelled workouts can't reappear from late Watch updates. A Finish from the iPhone always reaches the Watch.
- **The workout in progress is saved on the iPhone**, so if iOS closes GymForge mid-session nothing is lost (it reopens where you were).
- **Unreadable data is never overwritten**: if the saved file can't be read (e.g. an older build installed over a newer one), a copy is kept and the iCloud backup is offered instead of starting blank.
- **Watch PRs** are judged against your all-time bests (the Watch used to only know your last session, which could flag false PRs).
- **Program blocks**: switching rep range (e.g. 8–12 → 5–8) now re-aims the weight from your estimated strength (80 kg × 12 → ~90 kg) instead of adding one plate. Deload weights round to the nearest step (80 → 72.5 kg).
- **Set tick**: the green tick could fade out before it was shown; fixed (iPhone and Watch).
- **Workout screen**:
  - Tapping the exercise you're on no longer cancels the rest timer; it opens its sets.
  - A note can't land on the wrong exercise.
  - A first-time assisted exercise shows a sensible warm-up.
- **Routines and progress**:
  - Duplicated routines no longer share exercise IDs (which mixed their histories).
  - Saving an exercise saves the routine straight away.
  - The weight-step field keeps what you type.
  - Form cues accept Return anywhere.
  - Progress shows least-assistance PRs for assisted exercises.
- **Live Activity**: fits long quotes, comes back if it was swiped away or couldn't start, and has a tiny timer crash guard.
- **More Training**:
  - A failed read can no longer wipe the vault.
  - An opaque cover now hides every screen, including open photos and sheets, in the app switcher.
  - Timer alerts sound while the app is open.
  - "Stop & save" during a rest no longer logs a step twice.
  - Imports skip photos that couldn't be written.
  - Fewer pending alerts at once, so Sergeant Cluck's nags aren't pushed out of iOS's 64-notification limit.
- Launch no longer runs its setup twice (overlapping permission prompts). The automatic backup's summary work moved off the main thread.

## MK8.7 — Set ticks, fixing sets, add/remove sets, new swaps

- **Green tick on every set**: a green circle pops up mid-screen and the tick draws itself (about a second, never blocks taps), with a two-quick-tap "success" vibration.
  - **PR set**: gold circle, trophy and confetti, plus a heavier thump after the double tap.
  - **Last set of an exercise**: says "Bench Press done ✓" ("All sets done ✓" at the very end).
  - **Sets logged on the Watch** get the tick on the iPhone too.
  - **Watch**: its own small tick with a light double tap (PR sets keep the full-screen PR celebration).
  - **Settings → Set complete**: turn the tick or the vibration off. With Reduce Motion on, it just fades in.
- **Fix logged sets**: tap any logged set to change weight / reps / reps-left (or time / distance for cardio), or delete it. Swipe left to delete. PRs are re-checked, and the Watch updates.
- **Any exercise, not just the current one**: tap ✎ next to it in the Exercises list to see its sets, fix them, change how many sets are planned, or jump to it.
- **Add or drop sets**: "Sets today" + / − on the current exercise (for today only; never below what's logged). Dropping to what's done moves you on to the next exercise.
- **New swap options mid-workout**: Swap → "Add swap option…" → type a name → "Add & swap now" or "Just add". It's saved to that exercise in your routine (so it's there next time and on the Watch) and keeps its own history.
- **Watch "Rest finished" screen**: "Go" is now one proper button inside a scrolling screen (it could end up partly off-screen on smaller Watches, under a competing tap area). The alert also clears itself after 20 s if missed.

## MK8.6 — Full quotes on the Live Activity
- Lock Screen: the quote now gets up to 4 lines (instead of 2) and only shrinks a little if it's very long. To make room, the header and exercise rows are tighter, the last set moved next to "Set 2 of 3", and the rest countdown is slightly smaller.
- Dynamic Island (expanded): quote up to 4 lines; last set sits beside the exercise name.
- The Live Activity now shows the same coach quote as the workout screen for every coach style (not just Hard Truth / Heartbreak).
- Note: iOS caps a Live Activity at about 160 pt tall, so extremely long quotes still scale down slightly rather than grow the card further.

## MK8.5 — Rest ding
- When rest finishes, the iPhone plays a ding (two-note chime, `iOS/ding.wav`) along with the vibration. It plays over your music (briefly lowering it) and even with the silent switch on.
- With the iPhone locked and the Watch not connected, the "Rest finished" notification uses the same ding.
- Settings → Rest timer → "Ding when rest is done" (turning it on plays a preview).

## MK8.4 — Coach quote on the workout screen
- A separate section above the exercise you're doing shows a quote from your coach style. It changes after every set, matching the Lock Screen line for Hard Truth and Heartbreak; Push Me, Motivating, Analytical and Supportive got their own sets of lines.

## MK8.3 — Assisted pull-ups done right
- Any exercise with "Assisted" in its name is treated as **assistance weight: less = harder**.
- Progression: hit 10 reps on every set → **less** assistance (e.g. 30 → 27.5 kg); every set under 6 reps → more assistance. At 0 kg it suggests moving to regular pull-ups. The effort rule still applies (top of range but to failure → repeat).
- PRs: "Least assistance ever" when you do a full set (6+ reps) with less help than before. More assistance is never a PR.
- Deload / light sessions add ~10% assistance instead of removing weight. Warm-up suggests ~40% *more* assistance × 6.
- Labels say "Assistance — less = harder" on iPhone and "kg assist" on the Watch; the session preview and session comparisons read correctly ("−2.5 kg assistance").
- Estimated 1RM, strength standards, plateau and phase analytics skip assisted lifts (1RM doesn't make sense there); the progress chart shows the assistance used instead.
- Assisted pull-ups / chin-ups are set to **6–10 reps** (one-time update of your routines; new ones you create default to 6–10).

## MK8.2 — Sergeant Cluck on the Dynamic Island
- On days you haven't trained and still owe sessions (he's watching, annoyed, furious or doomed), opening GymForge puts Sergeant Cluck on the Lock Screen and Dynamic Island: his face, sessions left / days left, his line, and an "Angry in 1:23:45" countdown to 5:10pm.
- At 5:10 he switches to his angry face and line by himself, even if the app isn't opened again.
- Compact: chicken face + "4/4" (left/days). Long-press to expand.
- Disappears when you start a workout (the workout Live Activity takes over), when you've trained today, use "Not today", or after 9pm.
- iOS only lets an app *start* a Live Activity while it's open, and ends it after ~8 hours — so open GymForge after about 9am for him to still be there at 5:10. Turn it off in Settings → Quota enforcer → Show on Dynamic Island.

## MK8.1 — Notifications fixed
- Cause: on launch the app planned Sergeant Cluck's notifications before asking for permission, and only asked later (when the app came back from the background) — while the Apple Health prompt could be on screen at the same time. Notifications planned without permission are dropped by iOS, and nothing re-planned them.
- Now: on launch it asks for Health first, then notifications, then re-plans everything. Whenever the permission changes (e.g. you allow it in iPhone Settings) everything is re-planned again.
- While GymForge is open, reminders and Sergeant Cluck now show as banners too (rest and More Training timers still just buzz in the app).
- Settings → Reminders → **Check notifications**: permission status, what's scheduled (nags, motivation, recap…), when Sergeant Cluck's next one is, a 5-second test notification, and "Re-plan all notifications".

## MK8 — Phase-aware coaching
- **One Phase setting** (Settings → Goal, the Phase screen, or the Nutrition card): Bulk / Recomp / Cut, with a start date. It drives protein (1.6 or 2.2 g/kg), the coach's goal, plateau advice and report cards. Phase history is kept.
- **Plateau pop-up**: every time you open a routine, its lifts are checked. A lift is stalled when its best estimated 1RM in the last 3 sessions hasn't beaten the earlier best (last 12 weeks). The pop-up lists each one with advice based on *why*: fatigue (sets to failure / short sleep), no surplus on a bulk, protein short, same exercise 8+ weeks (swap), reps stuck low, or add a set / change rep range. The orange button in the toolbar reopens it.
- **Mid-workout**: the same advice shows under the exercise name (tap to expand).
- **Cut**: flat strength isn't flagged — only a drop of more than 5% from the start of the cut, with cut-specific advice.
- **Muscle-loss warning** (recomp & cut, cautious): lean mass down 0.5+ kg AND strength down 2%+ — last 4 weeks vs the 4 before.
- **Bulk / cut rate monitor**: weekly weight change from your weigh-ins (needs 6+ over 2+ weeks). Bulk 0.25–0.5%/wk, cut 0.5–1%/wk, recomp roughly stable — with what to change.
- **Auto deload**: when 3+ lifts (or 40%) stall AND fatigue shows (sets to failure, short sleep or worse HR recovery), with a one-tap "Start a deload week". Not within 4 weeks of the last deload.
- **Weak-point finder**: muscle groups under ~10 sets/week (6 for arms) or progressing well behind the rest.
- **Mini-cut**: on a bulk, if your 4-week body-fat average goes above your limit (default 20%, Settings), a 5-week mini-cut is suggested; when it ends, one tap back to bulking.
- **Phase report cards** (Phase screen): weeks, sessions, adherence, weight / lean / body-fat change, each lift's estimated 1RM first 3 weeks → last 3 weeks, a grade A–F and Sergeant Cluck's verdict. The current phase shows "so far".
- **Sergeant Cluck celebrates**: the Sunday recap leads with lifts that got stronger this week and muscle gained this month (or held on a cut).
- **Today**: a Phase card (phase, week number, the most important alert) opens the Phase screen.

## MK7.5 — Cluck gets louder, smarter training, better tracking
**Sergeant Cluck**
- Two random motivation notifications a day (morning and afternoon), based on his mood and tuned to your coach style (Heartbreak leans into heartbreak lines).
- **Rest day today** button on Today. It shows as a grey moon on the week row — but doesn't count toward the quota, and he nags extra (10am, 12, 2pm, 4pm, plus 5:10/7:00/8:30).
- **Sunday 7:30pm recap**: sessions vs goal, PRs, lifts that went up, rest days taken, and his verdict.
- **Watch face complication** (new watch widget extension): circular, corner, rectangular and inline. The iPhone sends his state to the Watch whenever it changes; he turns angry at 5:10pm on his own.

**Week rows**: past days with no training are a **red circle with a white ✕** (gym row and More Training row). Days marked as rest are grey. More Training also has a rest-day button under its week row.

**Workouts**
- **Warm-up**: before the first set of each lift, a warm-up at 40% of today's working weight × 10 (iPhone and Watch).
- **Effort per set**: tap reps left (Fail / 1 / 2 / 3+) before completing a set. If you hit the top of the rep range but the last set was to failure, the next session repeats the weight instead of adding more.
- **Pain flags**: Pain button on the exercise (area + niggle / sore / sharp). Next time — on the workout and the session preview — you get advice (lighter, or your swap) until you tap "Feels fine now".

**Nutrition** (Today): creatine tick and protein tracker. Daily target = body weight × 2.2 g/kg when cutting or recomp, 1.6 g/kg when bulking (defaults from your training goal; change it on the card).

**Progress → Standards**: best estimated 1RM on bench, squat, deadlift, overhead press and barbell row vs body weight, from Beginner to Elite (approximate men's standards).
**Progress → Year**: 12-month heatmap coloured by CH / B / U / L / CA, rest days in grey, plus a count of each session type.
**Body → Tape measurements**: neck, chest, shoulders, arm, forearm, waist, hips, thigh, calf — chart per site.

**Automatic backup** (Settings → Backup → Export & import everything → Automatic weekly backup): pick a folder in Files and a backup passcode once. Every 7 days, when you open the app, everything (gym, More Training, photos) is saved there, encrypted with that passcode. The newest 4 are kept.

**More Training**
- Camera: **self-timer** (3/5/10 s) and **burst** (5 shots), then pick which to keep. Still never touches your photo library.
- **Trend line** on the measurement chart with your rate per month.
- **BPFSL plateau advice** when it hasn't gone up in about a month (based on your wear time and extender use).
- **EQ vs training load** chart (Progress): daily load bars above EQ check-ins, and your average EQ the morning after heavy vs light days.

**Signing note**: there are now 4 bundle IDs (app, `.watchkitapp`, `.widgets`, `.watchkitapp.widgets`), and the Watch app + its widget use the App Group too. Free Apple IDs allow 10 app IDs per 7 days. If signing the Watch widget fails, delete the GymForgeWatchWidgets target's embed from the Watch target — everything else still works.

## MK7.4 — Sergeant Cluck (quota enforcer)
- A furious drill sergeant guards your weekly goal. Spare rest days = days left this week (including today) − workouts still needed. He's relaxed with 2+ spare, watching you with 1 or 0, and at **5:10pm** turns annoyed (1 spare) or FURIOUS (0 spare). Can't hit the goal any more → disappointed "damage control". Trained today → proud; goal met → celebrating.
- **Widget** (Home Screen small/medium, Lock Screen circular/rectangular/inline): its timeline is planned ahead, so it turns angry at 5:10pm by itself even if you haven't opened the app.
- **Notifications** at 5:10pm, 7:00pm and an 8:30pm last call (chicken voice, then your coach style), only on days that matter. Planned 8 days ahead; logging or starting a workout cancels/re-plans them. "Not today" on the notification (or on Today) snoozes once per week.
- **Today**: Sergeant Cluck sits above the week row with his current mood and line.
- **Settings → Quota enforcer** to turn him off. While he's on, he replaces the old "behind your goal" reminders.
- Needs notification permission (asked on launch) and an **App Group** (`group.com.jason.gymforge`) so the widget can read your week. If Xcode refuses to sign with the App Group on your account, remove it from both targets' Signing & Capabilities — the app and notifications still work; only the widget will say "Open GymForge once".

## MK7.3 — Session preview & coaching
- Tap a routine card on Today ("Plan & coaching") to open its preview. The top shows estimated time, sets, last done and a session game plan (readiness, deload, program phase, how many lifts go up today).
- One card per exercise: today's target (the exact weight × reps the workout will prefill, including phase and deload), last time's sets, trend (Improving / Steady / Plateau / Down / New), PR badge, and coaching from your history — progress or hold, plateau (suggests slow negatives or your swap), rep drop-off (rest longer), comeback after 14+ days — all in your coach style.
- Form cues per exercise from a built-in library (bench, incline, rows, pulldowns, squats, RDLs, curls, pushdowns, raises, cardio…, with a fallback per muscle group). Edit your own in the exercise editor → Form cues.
- Start workout (and Start light session on low-readiness days) pinned at the bottom. The Start button on the Today card still starts straight away.

## MK7.2 — Photo folders
- More Training → Photos has folders, starting with **Measurement** and **Pump**. Tap a folder chip to filter, **+ Folder** to add one, long-press a chip to rename or delete it (photos inside are kept and become Unfiled).
- Photos taken or imported while a folder is open go straight into it; the import screen also has a folder picker. The camera ghost uses the latest photo from the open folder.
- Long-press a photo (or use ••• in the viewer) to move it to another folder.
- Compare: each side picks its own folder and photo, e.g. Measurement on the left and Pump on the right. Changing a side's folder auto-picks the photo closest in time to the other side, so same-session shots line up. ⇄ swaps sides. Labels show folder and date.
- Folders are included in the full export/import (folders with the same name merge).

## MK7.1 — Zoom on More Training photos
- Photo viewer: pinch to zoom (up to 8x, around your fingers), drag to move around, double-tap a spot to zoom in there, double-tap again or tap Reset to zoom out.
- Compare: zoom works in both modes. Side by side, both photos zoom and pan together so you're looking at the same spot on each.

## MK7 — Gym week row
- Today → This week card now shows Monday–Sunday circles above the progress bar. Trained days are green with the session code: CH (chest), B (back), U (upper), L (legs/lower), CA (cardio). Two different sessions on one day show e.g. CH+CA. Tap a day to see what you did. Codes come from the routine name, falling back to the muscles actually trained.

## MK6.5
- Heartbreak style: 25 brutal lines added (75 total) — gut punch first, then the turn.

## MK6.4 — "Heartbreak" coach style
- New coach style: 50 original breakup-fuel lines on the Lock Screen / Dynamic Island and Watch rest screen, plus matching coaching, reminders and monthly report text. Edit them in `Shared/HeartbreakLines.swift`.

## MK6.3 — "Hard Truth" coach style
- New coach style (Settings → Coach style): blunt, no-excuses discipline talk in coaching, reports and reminders.
- 40 original lines rotate on the Lock Screen / Dynamic Island Live Activity (new line every set) and on the Watch rest screen.

## MK6.2 — vibrate on both devices when a timer is up
- Gym rest: the Watch buzzes 3× (as before); the iPhone now also vibrates when the app is open, and sends a "Rest finished" notification when the Watch app isn't connected.
- PE timers (interval rounds, program end, time limit, stamina goal and cool-down): 2 s strong vibration on the iPhone plus a buzz on the Watch when GymForge is open there. With the iPhone locked, the notification (just "⏱" — iOS drops completely empty ones) vibrates the iPhone or, if you're wearing it, the Watch.

## MK6.1
- "Export everything" now stops with an error instead of silently leaving out the private section or any photo, re-opens the finished file to verify it, and tells you exactly what's inside (workouts, routines, PE sessions, measurements, photos, stamina sessions, check-ins).

## Making an .ipa (for auto-signing tools)
On your Mac, in this folder: `./Scripts/build_ipa.sh` → `build/ipa/GymForge-MK6.5.ipa`.
It archives with your Xcode team so HealthKit/notification entitlements are embedded for the re-signing tool to copy.
Before switching to a new signing tool or Apple ID: **Settings → Backup → Export & import everything** first (see notes below).
- Three bundle IDs are used (app, `.watchkitapp`, `.widgets`); free Apple IDs allow 10 app IDs per week.
- If the tool changes the bundle ID or team, iOS treats it as a new app: data and the private section's Keychain key don't carry over — restore from the export.
- Not every tool signs Watch apps; if the Watch app doesn't install, the iPhone app still works on its own.

## MK6 — Apple Watch workout controls
- The Watch's Rest button only shows when the iPhone isn't connected; with the iPhone connected, sets are logged on the iPhone.
- New buttons on the Watch set screen: **Exercises** (pick any exercise to do next; done ones add an extra set, skipped ones come back), **Swap** (preset alternatives) and **Skip** (skip for today, with confirmation).
- Skip also on iPhone. Skipped exercises are treated as done, marked "skipped", and can be tapped to bring them back.

## mk5.5
- Body charts: the touch-and-hold callout no longer shows as a black block.
- More Training: when any timer reaches zero (each interval phase, the end of a program, or an open timer's limit) the phone vibrates at full strength for 2 seconds.

## mk5.4
- Photos grid: three equal square tiles; each photo is cropped to its tile so photos no longer overlap.

## mk5.3 — More Training sessions
- Starting Pump, PAC, extender or clamp (open timer, intervals or a preset) opens a dedicated full-screen session screen: big countdown/elapsed ring, round dots, pause/skip, stop & save, then the warning-sign check. Minimise with the chevron; a card on Today reopens it. Screen stays awake while it's open.
- Timer notifications in More Training (limit, interval changes, stamina) are now silent of text — sound/vibration only. In-app, the end of a timer buzzes three times.

## mk5.2 — Watch ↔ iPhone sync fix
- The Watch app was embedded in the iPhone app's PlugIns folder; it must be in `GymForge.app/Watch`. iOS didn't treat it as GymForge's companion, so the iPhone reported it as not installed and sent nothing. Fixed in the project file and project.yml.
- Routines/history are compressed and fall back to a file transfer when large (application context is limited to ~64 KB, which history plus a Strong import easily exceeds).
- Settings → Backup → **Export & import everything**: one passcode-encrypted file with routines, history, settings and the private section (including photos); Face ID is needed to include private data. Optional weekly reminder. Use it before re-signing the app.
- Stamina: tag sessions with/without porn; chart shows a separate average line for each.
- Settings → Apple Watch shows connection status, last sync, last error, and a "Test connection" button. The Watch home screen shows iPhone reachability and last sync.

## mk5.1 — More Training
- Phallosan totals: lifetime hours (starts from 173 h from your Phallosan log, editable in Settings), this week/month, hours by level.
- Daily wear goal ring in green-equivalent hours (Red ×3, High Green/Yellow ×1.5, Green ×1; default 6) with a goal streak.
- Milestones at 50, 100, 250, 500, 750, 1000… hours with progress to the next.
- Import existing photos (dates from the photo's EXIF), then optionally delete the originals from Photos.
- Stamina training: goal timer, "Close — cool down" pause (default 60 s), pause count, goal/cool-down alerts, charts, history, and a suggestion to raise the goal; blue dot on the week row.

## mk5 — More Training
- Today screen: Mon–Sun row (green ✓ trained, yellow ✓ PAC day, yellow outline = PAC planned, white = not yet); tap a day for details.
- PAC every other day: due 2 days after your last PAC, with a warning (not a block) if you start early.
- Pressure (inHg) for Pump and PAC, tension (kg/lb) for the High Tension Extender, Phallosan Forte levels (Green, High Green, Yellow, Red) with level changes mid-day.
- Interval timer (rounds of work/rest, pause/skip, discreet "Timer" notifications) and saved presets.
- Daily EQ / morning-wood check-in, warning signs after each session, and rest-day suggestions.
- Photo compare (side by side or overlay) and a ghost of your last photo in the camera; measuring reminders.
- Charts: wear by level, pressure/tension trends, EQ trend, hours trained vs monthly gains.

## v3 additions
- **Start → workout screen**: starting a routine opens the live workout full-screen on iPhone; the Watch asks the iPhone for the workout as soon as it launches, so it lands straight on the set screen.
- **Exercise swaps**: preset swap options per exercise (e.g. Chest Press → Bench Press / Incline Bench). Swap mid-workout on iPhone or Watch; each keeps its own weights and history, and the log notes what it replaced.
- **Notes per exercise**: set in the editor or mid-workout; shown on iPhone and Watch.
- **PR celebration** (Watch full screen + haptic, iPhone banner) and **workout summary** on both devices.
- **Supersets**: link exercises in the routine editor; they alternate set by set with rest after the round.
- **Cardio exercises** (category Cardio): minutes/km on iPhone or a stopwatch on the Watch; logged inside the same Health workout.
- **Heart-rate recovery**: HR drop in the first minute of rest, per set and per workout; feeds the coach.
- **Auto rest**: optionally end rest when HR falls below a threshold (never before half the rest).
- **Deload weeks** and **light sessions** (one less set, ~10% lighter, excluded from progression); coach suggests them when fatigue or HR recovery says so.
- **Program blocks**: hypertrophy / strength / endurance / deload cycles that shift rep ranges automatically.
- **Weekly volume per muscle** (Progress → Muscles) with a 10–20 sets guide.
- **Sleep & recovery**: readiness from last night's sleep, resting HR and HRV vs your baseline; suggests a light session on bad days.
- **Monthly report**: workouts vs goal, volume, time, PRs, strength gained per exercise, most improved, sets per muscle, body weight/fat, sleep, HR recovery, cardio, training-day heatmap, milestones.
- **Import from Strong** (CSV, both export formats) with exercise matching and duplicate protection.
- **iCloud backup** (automatic, 14 daily copies, auto-restore on a fresh install) plus export/restore of a backup file.
- **Reminders** when you're behind your weekly goal or 2+ days off (in your coach style), monthly report notification, and an iPhone rest notification when the Watch isn't connected.
- **Live Activity**: current exercise, set and rest countdown on the Lock Screen and Dynamic Island.
- **App icon** and orange accent colour.

## What was fixed
- **No launch screen key** → iOS ran the app letterboxed. Added `UILaunchScreen`.
- **Routines never reached the Watch** if the Watch app was installed after the iPhone app, or the session wasn't ready. The iPhone now re-sends on activation / Watch-install / when the Watch asks, and the Watch requests a sync on launch. Snapshots are trimmed (only the last session of each exercise) so payloads don't grow forever.
- **Finished workouts could be lost** (sent with `sendMessageData`, which drops on failure). Now always queued with `transferUserInfo`, persisted on the Watch, and de-duplicated on iPhone.
- **Stale "start workout" messages** queued while the Watch was off could start a phantom workout later. Now ignored after 5 minutes.
- **Two HealthKit sessions** could start (iPhone launch + Watch tap racing). Now guarded.
- **Workouts saved to Health as "Other"**: the configuration passed by `startWatchApp` often arrives as a default; the Watch now always uses Traditional Strength Training.
- **Body tab never refreshed** (nested ObservableObject). Fixed.
- `startWatchApp(toHandle:)` (deprecated) → `startWatchApp(with:)`.
- Watch workout survives the app being terminated (state saved to disk + HealthKit session recovery).
- Progression: increase only when **all planned** working sets hit the top of the range; increments add exactly one step (old rounding could add 1.5 or 3.7 kg).
- `ProgressView` renamed `ExerciseProgressView` so it no longer shadows SwiftUI's.

## What was finished
- **One workout across two devices**: complete sets, skip/extend rest, jump exercise, add extra set, finish or discard from either device. Sync uses a revision counter so older updates never overwrite newer ones. If the Watch can't be reached, the iPhone saves the workout itself and the Watch's version (with HR/calories) replaces it when it arrives.
- **Watch**: workout time, HR, calories on every screen; target rep range, last time, Complete Set → automatic rest with haptic, +30s/Skip, swipe-up controls (finish, discard, jump), "all sets done" screen.
- **History**: every workout with duration, calories, avg/max HR, volume, each set's actual vs planned, and comparison with the previous session.
- **Progress graphs**: working weight, reps at top weight, best set, total reps, volume, estimated 1RM; 1M/3M/6M/1Y/All; PR, weight-increase and rep-range-change markers.
- **Body**: weight, body fat %, lean mass estimate with 7-day trend lines, weekly rate of change, ranges.
- **Consistency**: weekly adherence, streak, last-4-week adherence, missed sessions.
- **Coach**: goal-aware and context-aware (plateau + low consistency → keep program; flat strength + losing weight → still progress; fatigue detection; gain too fast; unrealistic weekly goal), in Push Me / Motivating / Analytical / Supportive styles.
- **Settings**: goal, workouts/week, coach style, Health access, Watch status + manual sync.
- Routines: reorder exercises and routines, duplicate routines, starter Chest/Back/Leg days.

## Not built yet
Live weight/rep edits *before* a set is completed aren't mirrored (completed sets are). Widgets, complications, Live Activity, Shortcuts, notifications, RIR/RPE, warm-up/drop sets, app icon.
