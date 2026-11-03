# GymForge — Features Logbook (MK11.3)

Every function in the app, what it does and **why it's there**. Grouped by area, not by version (see the Full Logbook for when each arrived).

---

## 1. Foundations: devices, sync and your data

| Function | What it does | Why |
|---|---|---|
| iPhone + Watch, one workout | A set logged on either device appears on both; finish/discard/skip/jump from either | You don't always have the phone in hand at the rack — the Watch must be a full controller, not a remote |
| Revision-based sync | Every change carries a revision; older updates never overwrite newer ones; simultaneous sets on both devices are both kept | Bluetooth messages arrive late or out of order; without this, sets got lost or doubled |
| Queued transfers, file fallback | Finished workouts always go through a guaranteed queue; big payloads compress and fall back to file transfer | Instant messages drop on failure, and history easily exceeds the ~64 KB sync limit |
| Watch works alone | The Watch keeps routines, history and the workout itself if the phone is left behind | Phone-free gym sessions shouldn't lose data |
| "Start" launches the Watch | Starting on iPhone opens the Watch app straight onto the set screen, recording heart rate | One tap instead of two devices to fiddle with |
| Workout survives app closes | Live workout saved on both devices; HealthKit session is recovered after a crash | iOS kills background apps; a lost session means lost sets and heart rate |
| Unreadable data never overwritten | A file that can't be read is copied aside and the backup offered | An old build installed over a newer one used to start blank and save over your history |
| iCloud backup | 14 daily copies, auto-restore on a fresh install | Re-signing / reinstalling the sideloaded app shouldn't cost your history |
| Export & import everything | One passcode-encrypted file with gym + private data + photos, verified after writing | Moving signing tools or Apple IDs wipes the Keychain key; this is the only full escape hatch |
| Automatic weekly backup | Every 7 days into a Files folder you pick, newest 4 kept | Backups you have to remember don't happen |
| Strong import | Reads Strong's CSV exports, matches exercises, skips duplicates | Years of history shouldn't be retyped |
| Apple Health | Saves strength workouts, runs and basketball; reads weight, body fat, sleep, resting HR, HRV | Health is where your scale and Watch already put the data; the coach needs it |
| Notification permission order | Health first, then notifications, then re-plan everything; Settings → Check notifications | Notifications planned before permission are silently dropped by iOS |

## 2. The live workout

| Function | What it does | Why |
|---|---|---|
| Workout screen (iPhone) | Full-screen, current exercise, plan chips, typed weight/reps, rest timer | One place for everything during a set |
| Watch set screen | Time, HR, calories, target, last time, Complete Set, rest, Exercises / Swap / Skip | Usable with sweaty hands, phone in the bag |
| Per-set targets | Same weight every set, reps from last time and your usual drop-off ("80 kg × 10·10·9") | You asked for same weight every set; reps per set make "beat last time" concrete |
| Grey prefill numbers | Today's plan is pre-typed; you only type what differs | Fewer taps between sets |
| Set falls short → suggestion | Below the range → "Use 97.5 kg / Keep weight"; 2+ short → fewer reps on the rest | You wanted the coach to suggest, not change things for you |
| Set-by-set comparison | "9 vs 8 ↑" on each set; one line reading the pattern after 2 sets | Totals hide the story (9·9·6 vs 8·8·8 is the same total but a pacing problem) |
| Effort rating (reps left) | Fail · 1 · 2 · 3 · 4+ per set (iPhone) | Drives autoregulation, honest volume counting and failure warnings |
| Effort target | "Leave ~2 reps" shown on the plan and Watch | Effort is the dial that makes blocks work; without a target you'd grind every set |
| Warm-ups | Ramp sets (≈50/70/85%) for heavy compounds; none for isolation | Proper ramps protect joints on big lifts without wasting time on curls |
| Rest timer | Automatic after a set, +30 s / skip, ends on time or by heart rate (auto rest) | Rest is training; consistent rest makes sessions comparable |
| Rest-end sound | Train-announcement chime + Australian voice ("The next exercise is Lat Pulldown, 8 reps"), or ding, or vibrate | You asked for the Sydney-train style; it tells you what's next without looking |
| Set tick | Green tick + double vibration; gold + confetti for PRs; "done ✓" on the last set | Instant confirmation the set was saved, and a small reward |
| PR detection | Heaviest, best e1RM, least assistance — against all-time bests (also on Watch) | Celebrating PRs keeps you coming back; false PRs ruin the trust |
| Supersets | Alternate set by set, rest after the round | Saves time; matches how you train |
| Swap (today only) | Preset alternatives; each keeps its own history | Machine taken? Swap without corrupting the other exercise's numbers |
| Make swap permanent | After a swap: "Make permanent" puts it in the routine | You asked to switch exercises for good from the workout |
| Add exercise mid-workout | "+" → library or your own, just today or also to the routine | Ideas happen mid-session |
| Add swap option | Type a new alternative mid-workout; saved to the routine | New machine at the gym? It's there next time |
| Skip / Sets today | Skip an exercise (comes back on tap); +/− planned sets for today | Real sessions don't always match the plan |
| Fix logged sets | Tap any set to edit or swipe to delete; PRs re-checked | Typos shouldn't live in your history forever |
| Notes per exercise | Seat height, grip, cues — on iPhone and Watch | Machine settings are easy to forget |
| Pain flag | Pain button → area + severity; advice next time; feeds the coach | Training through joint pain is how injuries become long-term |
| Coach quote | A line in your coach style above the exercise, changes every set | Motivation in your chosen voice |
| Live Activity | Lock Screen / Dynamic Island: exercise, "Set 2 of 3", last set, rest countdown, quote during rest | Glance at the phone without unlocking |
| Motivational speech player | Your imported audio; Lock Screen controls; resumes; ducks music; chime plays over it | You wanted your own speeches, only when you press play |
| Cardio inside routines | Minutes/km or Watch stopwatch; **optional** — workout completes when weights are done | You said you can skip cardio but not weights |
| Time budget | Pick 30–90 min: cuts cardio first, then sets from least important exercises, then whole exercises; supersets stay together | Short on time shouldn't mean skipping the gym; you wanted sets cut before exercises |
| Light session / deload | One less set, ~10% lighter, excluded from progression | Bad sleep days still count without wrecking your numbers |
| Heart-rate recovery | HR drop in the first minute of rest | A simple fitness and fatigue signal for the coach |

## 3. Progression engine

| Function | What it does | Why |
|---|---|---|
| Double progression | All planned sets at the top of the range → add one weight step, reps restart | Your stated method: reps first, then weight |
| Failure rule | Top of range but last set to failure → repeat the weight | Grinding into a weight increase usually stalls next session |
| "Felt easy — go up" | Every set with 3+ reps left → go up now | Don't waste weeks on weights that are too light |
| Even out lopsided sets | After 9·9·6, next targets are 9·8·8 | Even sets build more than one heroic set and a collapse |
| Too heavy → step down | Every set below the range → one step lighter | Stay in the productive range |
| Assisted exercises | Less assistance = harder; PR = least assistance; deload adds help | Pull-up machine maths is backwards; it had to be handled properly |
| Bodyweight exercises | No weight to type; at the top it says hold / harder variation | "Add 2.5 kg" makes no sense for dips |
| Equipment & load conventions | Machine names keep their own history; total / per side / per hand / pin-stack levels | Two chest presses at one gym aren't the same exercise; per-side plates were mis-logged |
| Program blocks | Hypertrophy / strength / endurance / deload phases shift rep ranges, re-aim weight from estimated strength | Variety and planned recovery, without manual edits |

## 4. The coach

| Function | What it does | Why |
|---|---|---|
| Exercise library | ~100 exercises: muscles (main = 1 set, helper = ½), rep ranges, rest, steps, swaps; matches your names | You wanted a coach that knows optimal sets for most exercises |
| Size / strength focus | Size: moderate reps; strength: heavy main lifts, longer rest | You're mostly after size now but want to switch |
| Suggestions, never automatic | Accept / Not now (hidden 4 weeks), followed up in the weekly review | You wanted suggestions, not silent changes |
| Weekly sets per muscle | Hard sets/week (4+ reps left = half) vs research ranges; strength trend | ~10–20 hard sets per muscle per week is the evidence-based target |
| Volume suggestions | More sets for under-trained muscles, fewer where strength drops, trims past the ceiling; 3-week wait after a change | Volume is the main lever; the wait stops it ratcheting before results show |
| Routine check | Rest too short on heavy lifts, isolation before its compound, missing muscles, push > pull, one-day-a-week muscles | Catches plan problems before you lose weeks to them |
| Routine builder | 2–6 days, time limit, priority muscles; trims isolation sets first | A sound split in seconds |
| Training blocks | Fixed 3–6 build weeks + planned deload, repeating | You chose fixed-length blocks; planned deloads beat crashing into one |
| Block ramp | From week 2: +1 set/week for up to 2 recovering muscles | Progressive volume across a block, only where you're recovering |
| Block review | During the deload: lifts start vs end, sets per muscle, next-block advice | Each block should inform the next |
| Stall diagnosis | 3+ weeks flat → one cause in order: cut, recovery, too much volume, too little, stale accessory (swap), new rep range | A good coach checks causes in order rather than always adding sets |
| Pain-aware swaps | Sore/sharp flag → gentler machine/cable swap | Train around injuries |
| Diet-aware coaching | Cut: no extra volume; bulk: priorities aim higher | Recovery capacity depends on food |
| Cardio-aware recovery | Hard game / long run in the last ~30 h → leg-day warning | Basketball fatigue is real leg volume |
| Consistency coaching | Weekdays you keep missing; routines needing more days than you train | A plan you keep missing is the wrong plan |
| Readiness | Sleep, resting HR and HRV vs your baseline → light-session suggestion | Train hard when recovered, back off when not |
| Recovery warnings | Muscles trained hard in the last ~40 h, heavy hinges two days running | Avoids stacking fatigue |
| Session preview | Tap a routine: today's targets, last time, trend, coaching, form cues, edit menu | Know the plan before you walk in |
| Plateau pop-up & weak points | Stalled lifts on opening a routine; muscles behind the rest | Catch stalls early |
| Auto deload | 3+ stalls plus fatigue → one-tap deload week | Fatigue masks fitness |
| Coach's brief | Rating + what went well / short / context / one next step, in your style; Read aloud | You wanted a coach-style summary of today |
| Heart-rate review | Peak, average, usual peak, graph with set markers, zones, per-exercise peak | You asked for peak HR after workouts |
| Coach styles | Push Me, Motivating, Analytical, Supportive, Hard Truth, Heartbreak | Motivation is personal |
| Weekly review | Sunday 7:30pm: sessions, sets per muscle, priorities, accepted-advice follow-up, plan next week | Weekly reflection without spreadsheets |
| Monthly report | Volume, PRs, strength gained, body, sleep, cardio, heatmap | Bigger-picture progress |
| Strength standards | Big lifts vs bodyweight, Beginner → Elite | Context for your numbers |

## 5. Planning your week

| Function | What it does | Why |
|---|---|---|
| Plan week | Workout / run / basketball / rest / sick / travel per day, this or next week | Plan Sunday night, from scratch each week (your choice) |
| Auto-plan | Tick training days → routines in rotation, rest on the others | Planning in 5 seconds |
| Copy the week before | Same plan on the same weekdays | Most weeks look alike |
| Sick / travel days | Lower the goal by one; Cluck stands down; hotel workout | Life happens; it shouldn't break your streak |
| Planned rest days | Planned the day before or earlier → Cluck is chill | You wanted rest without being yelled at; same-day "rest" stays nagged to stop dodging |
| Edit routines anywhere | ⋯ menu on the routine screen: replace permanently, move, remove; Add exercise with gap suggestions | You wanted to change Chest Day from the routine itself |

## 6. Sergeant Cluck

| Function | What it does | Why |
|---|---|---|
| Quota enforcer | Mood from sessions left vs days left; angry at 5:10pm | Accountability that actually bites |
| Widgets & complication | Home/Lock Screen widgets, Watch face; turn angry on their own | He's visible without opening the app |
| Nags | 5:10 / 7:00 / 8:30pm in your coach style; "Not today" once a week | Escalating reminders only on days that matter |
| Dynamic Island | His face, "4/4", countdown to angry | Ambient pressure on training days |
| Weekly recap | Sunday: sessions, PRs, lifts up, verdict | Celebrate wins, call out misses |
| Weight training only | Runs, basketball and cardio-only sessions don't count | You said cardio is skippable, weights aren't |

## 7. Runs and basketball

| Function | What it does | Why |
|---|---|---|
| Watch recording | Outdoor/treadmill run or basketball as its own Health workout: HR, zones, pace, km splits, goals, auto-pause, GPS route | You wanted it to start like Apple's Workout app and record everything |
| iPhone recording | GPS run, or timer for treadmill/basketball; rate effort 1–10 at the end | You wanted it to work without the Watch |
| Log afterwards | Date, duration, distance or shots, effort | Forgot to start it? Still counts for the coach |
| Effort & training load | Effort × minutes (or estimated from heart-rate zones) | Without HR, your rating is the only honest measure; feeds leg-fatigue checks |
| Run history | Route map, splits, best 1 km / 5 km, easy-run HR trend, treadmill distance fix | You wanted all of these |
| Basketball details | Minutes, shots made/attempted, %, zones, load | You wanted all of these |
| Lock Screen card | Distance, pace, HR while running | Glanceable |
| Planner & week row | Plan run/basketball days; shown as CA/BB extras | Visible without counting as sessions |

## 8. Body and nutrition

| Function | What it does | Why |
|---|---|---|
| Body charts | Weight, body fat, lean mass, trends, weekly rate | Your Xiaomi scale feeds Apple Health; this makes it readable |
| Tape measurements | Neck … calf, chart per site | Size gains show in tape before the mirror |
| Phase (bulk / recomp / cut) | Drives protein, calories, coaching and report cards | One setting steers everything diet-related |
| Rate monitor | Weekly weight change vs the phase's ideal range, with what to change | Bulking too fast is mostly fat; cutting too fast costs muscle |
| Muscle-loss warning | Lean mass AND strength both dropping | Cautious by design: one signal alone is noise |
| Calorie target | Maintenance (Katch–McArdle from your scale, then your real number after 2 weeks of logging) ± phase | You asked for a calculator that changes with cutting / bulking |
| Macros | Protein 1.6–2.2 g/kg, fat ≥ 0.8 g/kg, carbs the rest | Calories alone don't protect muscle |
| Bulk fat-gain check | How much of the last 6 weeks' gain was fat → trim 100–200 kcal + diet advice | You asked for diet advice when body fat climbs on a bulk |
| Mini-cut reminder | Body fat over your limit → card + notification; 5 weeks or ~5% under the limit | You asked for a reminder when body fat is too high |
| Protein & creatine | Daily tracker and tick | The two supplements that matter |
| Phase report cards | Grade A–F per phase with strength and body changes | Was the bulk worth it? |

## 9. History and progress

| Function | What it does | Why |
|---|---|---|
| History & corrections | Every workout; edit sets, date, duration; log a missed session; PRs re-checked | Accurate history is what the coach learns from |
| Progress graphs | Weight, reps, best set, volume, e1RM, 1M → All, markers | See the trend, not just the last session |
| Week row & year heatmap | CH / B / U / L / CA codes, rest days, 12-month view | Consistency at a glance |
| Consistency stats | Adherence, streak, last 4 weeks | Showing up is the first progression |

## 10. More Training (private section)

| Function | What it does | Why |
|---|---|---|
| Vault | Long-press "Today" → Face ID; AES-GCM encrypted, own Keychain key | Private data must be private even if someone has your phone |
| Isolation | Never sent to the Watch, Health, iCloud, reports or the coach; only in passcode-protected full exports | Your rule: data flows in (body fat), never out |
| Privacy cover | Opaque cover in the app switcher; locks on leaving | No accidental glimpses |
| Discreet notifications | Just "⏱", no words | Nothing readable on the Lock Screen |
| Sessions | Pump, PAC, extender, clamp: full-screen timer, rounds, presets, pressure/tension, warning-sign check | Structured, safe sessions |
| PAC every other day | Due 2 days after the last, warning if early | Recovery between sessions |
| All Day Stretcher | Wear timer by level, green-equivalent daily goal, totals from your log, milestones | Hours worn is what drives length gains |
| Check-ins | Daily erection quality and morning erections | The main overtraining signal |
| Safety advice | Rest after pain/numbness/swelling, EQ drops, high pressure (>6 inHg), long clamp sets (>15 min) | Injuries come from intensity; the app should stop you first |
| Training nudge | Silent "⏱" at 7:30pm on day 3 without training (1 h+ stretcher / 30+ min extender / any PAC or pump), once more on day 6 | You wanted a subtle reminder; it stays quiet on rest days and when safety says rest |
| Measurements | BPEL, BPFSL, NBPL, mid and base girth; type 3 readings → averaged; measure-the-same-way checklist | Measurement noise is bigger than monthly gains |
| Goals | A goal per measurement, progress bar, projected date | You set separate goals per measurement |
| Compared with the average | Herbenick 2014 (default) or Veale 2015; NBP estimate; percentile | You asked for comparisons with published averages |
| Preferred size | NBP, mid and base girth vs ≈16.1 cm × 12.8 cm (average of women's preference and best-selling sizes) | You asked what a good size is, from research |
| BP–NBP gap | Over 1 inch → fat-pad explanation and cutting advice from your body fat | Losing fat shows more length |
| Plateau advice | 8 weeks flat → consistency, time, small tension step, extender, break — never more force after warning signs | Safe order of escalation |
| Photos | In-app camera only, folders, ghost overlay, self-timer, burst, compare, zoom, import | Photos never touch your photo library |
| Stamina training | Goal timer, cool-down pauses, charts | Separate goal, tracked privately |
| Charts | Wear by level, pressure/tension, EQ vs load, hours vs gains | See what's actually working |

## 11. Sleep (MK11)

| Function | What it does | Why |
|---|---|---|
| Sleep schedule | Bedtime and wake time for each night of the week, synced to the Watch | You wanted a schedule you can adjust per day |
| Last night vs plan | Hours, bed/wake times, minutes off plan — iPhone and Watch | Seeing the gap is the first step to closing it |
| Consistency score | 0–100 over 14 nights, on-time streak, late nights | Regular timing matters about as much as hours |
| Bedtime Live Activity | Wind-down 15 min before bed, then red "GO TO BED" with a live minutes-late counter until you tap "I'm going to bed" (MK11.2) | You asked for a Live Activity 15 minutes before bed |
| Manual sleep log | "Going to sleep / I'm awake", saved to Health; Watch tracking wins | Nights without the Watch still count, without double-counting |
| Cluck on sleep | "Lights out" mood after bedtime, late-night call-outs, eases off when sleep is bad | You wanted him to comment on late nights |

## 12. Sergeant Cluck (MK11 changes)

| Function | What it does | Why |
|---|---|---|
| Notification emoji | 🪖 on his notifications; he's still a chicken everywhere else (MK11.1) | You wanted a soldier emoji, not a soldier character |
| New moods | Suspicious, Impressed, Smug, Worried, Relieved, Lights out | More range = more believable feedback |
| Gym pattern comments | Missed weekdays, weeks under goal, gaps, shrinking sessions, fading weeks | You wanted comments on inconsistent training |
| More Training comments | Days off, PAC overdue, stretcher hours dropping, starts and stops — only inside More Training | Comments you asked for, without anything private leaving the vault |

## 13. Coaching comparisons, session context, goals and Cluck as coach (MK11.1)

| Function | What it does | Why |
|---|---|---|
| Like-for-like comparison | Pairs sets at the same load set-for-set; extra sets aren't "better", missing sets aren't "worse" | Doing 2 of 3 sets on a busy day isn't getting weaker |
| Rep-range / load changes | Judged on estimated 1RM | 85×5 and 80×8 are the same strength — reps alone can't compare them |
| Effort in comparisons | More reps left at the same reps = progress; closer to failure is noted | Strength shows up as reps in reserve before it shows up as reps |
| Meaningful-drop rule | Decline only at 2+ reps or 3%+ est. 1RM | One rep is normal day-to-day noise |
| Cautious plateau / loss rules | 4 normal sessions over 3+ weeks; 4+ weeks for stalls; two bad sessions for a cut drop; −3% for muscle-loss | False alarms make you change a program that's working |
| Session context tags | Short on time, equipment unavailable, easier on purpose, unusually tired — live or afterwards; time budget auto-tags | So the coach reads an odd day as an odd day |
| Tags in the engine | Kept out of trends; easy / tired days not used as "last time" | A bad day shouldn't lower next session's targets or trigger a plateau |
| Training goals | Lifting, running (runs and/or km) and basketball, each on its own bar | Running and basketball are separate goals and never count toward lifting |
| Analytical mood | Glasses + clipboard | Shown with the Analytical style and when he explains his reasoning |
| Locked in mood | Sweatband + whistle while a workout runs | He's all business mid-session |
| Protective mood | Shield with an open pain flag | Pain means guard the joint, not yell |
| Empathetic mood | A heart on sick/travel days and run-down sessions | Bad days need support, not nagging |
| Medal / aviator shades | Impressed and Smug accessories | Each mood readable at a glance |
| Subtle animation | Bob, blink and accessory motion in the app only; off with Reduce Motion | Makes him feel alive without being distracting; widgets can't animate |
| Session introduction | What today is, how long, the effort target, first exercise | Start with a plan, not a list |
| Accepted-plan reminders | Coaching you accepted that applies to today | Changes you agreed to are easy to forget mid-workout |
| Current-set and rest cues | Target × reps, reps in reserve, rotating form cue; rest length and next target | The next thing to do, always on screen |
| Explain, Sergeant | The rule, the set plan, the block, pain flags and context behind today's numbers | Trust comes from knowing why |
| Bedtime nags (MK11.2) | +10, +20, +30, then every 5 min to an hour late; cancelled by "I'm going to bed" | You wanted him to bother you until you go to bed |
| "I'm going to bed" (MK11.2) | Clears the card and nags, runs your Sleep Focus shortcut; doesn't log sleep | Your Apple Watch tracks the sleep; iOS only lets apps change Focus through Shortcuts |

## 14. Variation notes and breaks (MK11.3)

| Function | What it does | Why |
|---|---|---|
| Variation notes | "Today: wide grip" per exercise, quick picks or your own, "Same as last time" | Grip, stance and tempo change what a lift is |
| Like-for-like by variation | Comparisons, the brief and stall checks only pair sessions with the same variation | A grip change shouldn't look like a strength drop |
| Give me a break | Reason with a number, ≤ 14 days, once per 6 weeks, Cluck pushback, type BREAK | You wanted a break for busy weeks that can't be triggered easily |
| Maintenance mode | Goal 2 short sessions, 30-min default | Two short sessions a week keeps nearly all your strength |
| Break effects | No nags, streak paused, break sessions out of trends, no pattern comments | A planned break isn't inconsistency |
| Comeback session | Light session offered in the first week back | Easing back in avoids soreness and the feeling of going backwards |
| Daily routine (More Training) | HTE 3×20 min + pump 2×5 min every day; PAC plan off; one toggle to revert | Your current routine, without the every-other-day PAC plan nagging |
