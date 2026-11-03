# GymForge — Full Logbook

Every version of GymForge, newest first: what was added, changed and fixed. The early versions (before mk5) are grouped under "v3 additions", "What was fixed" and "What was finished".

## Versions at a glance

| Version | Headline |
|---|---|
| MK11.3 | Grip / variation notes, "Give me a break" |
| MK11.2 | Sergeant Cluck nags you to bed; "I'm going to bed" turns on Sleep Focus |
| MK11.1 | Fairer comparisons, session context, separate goals, 4 new Cluck moods, Cluck as your coach |
| MK11 | Sleep schedule & wind-down, Sergeant Cluck the soldier, new moods and pattern comments |
| MK10.2 | Calorie targets, bulk fat check, mini-cut reminder, cardio as extras, quiet training nudge |
| MK10.1 | Heart rate after the workout, the coach's brief, set-by-set advice, edit routines anywhere |
| MK10 | A coach that plans: training blocks, effort targets, stall diagnosis; runs & basketball without the Watch |
| MK9.1 | A smarter coach, runs and basketball |
| MK9 | Coaching per set, time budget, week planning, weekly review, corrections, equipment, speeches, More Training goals |
| MK8.8 | Train announcement, 20 new quotes, big bug sweep |
| MK8.7 | Set ticks, fixing sets, add/remove sets, new swaps |
| MK8.6 | Full quotes on the Live Activity |
| MK8.5 | Rest ding |
| MK8.4 | Coach quote on the workout screen |
| MK8.3 | Assisted pull-ups done right |
| MK8.2 | Sergeant Cluck on the Dynamic Island |
| MK8.1 | Notifications fixed |
| MK8 | Phase-aware coaching |
| MK7.5 | Cluck gets louder, smarter training, better tracking |
| MK7.4 | Sergeant Cluck (quota enforcer) |
| MK7.3 | Session preview & coaching |
| MK7.2 | Photo folders |
| MK7.1 | Zoom on More Training photos |
| MK7 | Gym week row |
| MK6.5 | 25 more Heartbreak lines |
| MK6.4 | "Heartbreak" coach style |
| MK6.3 | "Hard Truth" coach style |
| MK6.2 | vibrate on both devices when a timer is up |
| MK6.1 | Export everything is verified |
| MK6 | Apple Watch workout controls |
| mk5.5 | Body chart fix, 2 s timer vibration |
| mk5.4 | Photo grid fix |
| mk5.3 | More Training sessions |
| mk5.2 | Watch ↔ iPhone sync fix |
| mk5.1 | More Training |
| mk5 | More Training |
| v3 | Watch workout, swaps, supersets, coach, backups, reports |
| v1–v2 fixes | Launch screen, sync, lost workouts, Health type |
| v1–v2 | Core app: two-device workout, history, progress, body, coach |

## Build fixes after release

- **MK10.1** (first Xcode build): `Bests` type moved out of a generic function (Swift doesn't allow nested types there) — "Bests cannot be nested in generic function recomputingPRs()".
- **MK10.1**: Exercise editor footer closure took no argument ("Contextual type for closure argument list expects 1 argument") — fixed; unused `var weight` warning in Planning made `let`.
- **MK10.1**: Preferred size card moved to the top of More Training → Measure so it's visible without scrolling.
- **MK10.2**: training nudge moved from 9pm to 7:30pm.

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
- A furious drill-sergeant chicken guards your weekly goal. Spare rest days = days left this week (including today) − workouts still needed. He's relaxed with 2+ spare, watching you with 1 or 0, and at **5:10pm** turns annoyed (1 spare) or FURIOUS (0 spare). Can't hit the goal any more → disappointed "damage control". Trained today → proud; goal met → celebrating.
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
