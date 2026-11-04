# Ductile

A study calendar made of blocks. Tap a block (in the app or on the widget) and it:

1. starts a countdown timer,
2. runs a Shortcut that turns your Focus on **until the block ends** (so it switches off by itself),
3. notifies you when time's up so you can tick it off as **Full** or **Minimum**. Both count.

Stopping early runs a second Shortcut that turns Focus off.

While a block runs, a **Live Activity** shows the countdown on the Lock Screen and Dynamic Island, with a **Pause / Resume** button. Pausing freezes the timer and its alert. Focus isn't touched, so it still switches off at the block's original end time.

## Build and install

**Option A: Xcode (needs Xcode 16 or newer)**

1. Open `Ductile.xcodeproj`.
2. Select the **Ductile** project → each target → **Signing & Capabilities**, and check your team is selected.
3. Plug in your iPhone, pick it as the run destination, and press ▶︎ Run.

**Option B: GitHub + SideStore (same as Splitday)**

1. Make a new GitHub repo (e.g. `jasonj0820/Ductile`) and push this folder to it.
2. GitHub builds it automatically: **Actions → Build Ductile → latest run → Artifacts → Ductile-IPA**.
3. Install the IPA with SideStore.

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

Long-press the home screen → **+** → **Ductile** → pick small, medium or large. Medium and large let you tap any block to start it. Small starts the next unfinished block.

## Layout

- `App/`: calendar, block editor, timer screen
- `Widget/`: home-screen widget
- `Shared/Block.swift`: data model and storage (App Group `group.com.jason.ductile`, shared with the widget)
- `Scripts/checks/main.swift`: logic checks run on every build
