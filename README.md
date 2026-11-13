# Ductile MK2

A study calendar made of blocks. Each block is a **window** (e.g. 1:00–3:30) with a **focus target** inside it (e.g. 2h uninterrupted). Start anytime before the "start by" time. Press **Start** on a block (or tap it on the widget) and it:

1. starts a countdown for the focus target,
2. runs a Shortcut that turns your Focus on **until the focus target ends** (so it switches off by itself),
3. notifies you when time's up so you can tick it off as **Full** or **Minimum**. Both count.

Stopping early runs a second Shortcut that turns Focus off.

While a block runs, a **Live Activity** shows the countdown on the Lock Screen and Dynamic Island, with a **Pause / Resume** button. Pausing freezes the timer and its alert. Focus isn't touched, so it still switches off at the block's original end time.

## MK2 — what changed

**Fixed**
- **Tapping a row no longer starts it.** A tap anywhere on a block used to start the timer and jump to Shortcuts. Rows now have a **Start** button (today's unfinished blocks only); tapping the row edits it.
- **The widget can see your blocks after sideloading.** Sideloadly and friends rename the App Group, so the widget read an empty store. The app and widget now find the group the install really has, and blocks saved by MK1 are moved across on first launch. ⋯ → *Widget storage* says whether it's connected.
- **"Stop, didn't do it" asks first.**
- One unreadable block no longer empties the whole calendar; deleting the running block stops its timer; the widget refreshes on every new build (build number was stuck at 1).

**New**
- **Tick off from the Lock Screen.** When time's up, the Live Activity (and the Dynamic Island) swaps Pause for **Full** / **Minimum**.
- **Reminders** when a block's window opens and again at its "start by" time. ⋯ → *Remind me when a block opens*.
- **Tick off without the timer**: swipe a block right for Full / Minimum, or Untick. The editor has a Result picker too.
- **Missed** blocks are marked in red (and on the widget), and can still be ticked off as the minimum.
- **Week at a glance** above the list: time focused, blocks done, minimums, day streak. Focus time is what the timer really ran, so a block stopped at 40 minutes counts 40.
- **Week strip dots**: green = all done, red = something missed, grey = still to do. A **Today** button jumps back.
- **Copy** a block to tomorrow or next week (swipe left, touch and hold, or in the editor), and on an empty day, **copy last week's same weekday** in one tap.
- **Focus is optional**: ⋯ → *Turn Focus on with a block*. Off = a block is just a timer and Shortcuts never opens.
- **Focus setup is in the app** (⋯ → Focus setup), with a test button for each Shortcut.
- The timer has a progress ring and says when the window closes.

## Build and install

**Option A: Xcode (needs Xcode 16 or newer)**

1. Open `Ductile.xcodeproj`.
2. Select the **Ductile** project → each target → **Signing & Capabilities**, and check your team is selected.
3. Plug in your iPhone, pick it as the run destination, and press ▶︎ Run.

**Option B: GitHub + Sideloadly (same as Splitday)**

1. Make a new GitHub repo (e.g. `jasonj0820/Ductile`) and push this folder to it.
2. GitHub builds it automatically: **Actions → Build Ductile → latest run → Artifacts → Ductile-IPA**.
3. Install the IPA with Sideloadly.

The `App`, `Shared` and `Widget` folders are synced into the project, so any new `.swift` file you drop into them is picked up automatically, with no need to add it in Xcode.

## One-time Shortcut setup (on the iPhone)

Make a Focus first if you haven't (Settings → Focus → e.g. "Study"), and set which apps it silences or hides.

**Shortcut 1: name it exactly `Ductile Focus On`**

1. Shortcuts app → **+** → add action **Adjust Date**: *Add* `Shortcut Input` *minutes* to `Current Date`.
2. Add action **Set Focus**: turn **Study** *On* → tap "Until Turned Off" → **Until Time** → pick `Adjusted Date`.
3. In the shortcut's settings (ⓘ), make sure it accepts **Text** input.

**Shortcut 2: name it exactly `Ductile Focus Off`**

1. Add action **Set Focus**: turn **Study** *Off*.

The first run asks permission to open Shortcuts and to change Focus; allow both. The screen flicks to Shortcuts for a moment and comes straight back.

## Widget

Long-press the home screen → **+** → **Ductile** → pick small, medium or large. Medium and large let you tap any block to start it. Small starts the next unfinished block. Missed blocks stay on it in red.

## Layout

- `App/`: calendar, block editor, timer screen
- `Widget/`: home-screen widget
- `Shared/Block.swift`: data model, week stats, reminders plan and storage (App Group `group.com.jason.ductile`, or whatever the installer renamed it to)
- `Shared/TimerControl.swift`: the running timer, Live Activity buttons and notifications
- `Scripts/checks/main.swift`: logic checks run on every build
