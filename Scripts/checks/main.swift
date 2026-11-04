import Foundation

// Logic checks, run on GitHub: swiftc Shared/Block.swift Scripts/checks/main.swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Brisbane")!
let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!

let a = Block(title: "Afternoon", start: morning.addingTimeInterval(5 * 3600), minutes: 90)
let b = Block(title: "Morning", start: morning, minutes: 30)
let late = Block(title: "Late", start: morning.addingTimeInterval(14 * 3600 + 30 * 60), minutes: 30) // 23:30 same day
let tomorrow = Block(title: "Tomorrow", start: morning.addingTimeInterval(86400), minutes: 30)

let today = dayBlocks([a, tomorrow, late, b], on: morning, calendar: cal)
assert(today.map(\.title) == ["Morning", "Afternoon", "Late"], "one day only, earliest first: \(today.map(\.title))")
assert(a.end == a.start.addingTimeInterval(90 * 60), "end = start + minutes")

let url = Links.runShortcut(Links.focusOn, text: "90").absoluteString
assert(url.hasPrefix("shortcuts://x-callback-url/run-shortcut?"), url)
assert(url.contains("name=Ductile%20Focus%20On") && url.contains("text=90") && url.contains("x-success=ductile://"), url)

let data = try! JSONEncoder().encode([a])
assert(try! JSONDecoder().decode([Block].self, from: data) == [a], "blocks survive save/load")

// Pause / resume: time left freezes while paused, then the end moves out by the paused time.
let t0 = ActiveTimer(blockID: a.id, ends: morning.addingTimeInterval(600))
let paused = t0.toggled(at: morning.addingTimeInterval(240))                 // pause with 6 min left
assert(paused.isPaused && paused.pausedLeft == 360, "pause freezes 6 min")
assert(paused.left(at: morning.addingTimeInterval(9999)) == 360, "paused time doesn't tick")
let resumed = paused.toggled(at: morning.addingTimeInterval(1000))           // resume much later
assert(!resumed.isPaused && resumed.ends == morning.addingTimeInterval(1360), "resume pushes end out")
assert(t0.left(at: morning.addingTimeInterval(700)) == 0, "never negative")
let old = #"{"blockID":"\#(a.id.uuidString)","ends":0}"#.data(using: .utf8)!
assert((try? JSONDecoder().decode(ActiveTimer.self, from: old))?.isPaused == false, "timers saved before pause existed still load")

// Window + focus target: 1:00–3:30 with 2h focus → start by 1:30.
let one = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 13))!
let w = Block(title: "Timber", start: one, minutes: 150, focusMinutes: 120)
assert(w.focus == 120 && w.startBy == one.addingTimeInterval(30 * 60), "start by 1:30")
assert(Block(title: "x", start: one, minutes: 60, focusMinutes: 120).focus == 60, "focus never longer than the window")
assert(Block(title: "x", start: one, minutes: 90).focus == 90, "no target = whole window")
let mk12 = #"[{"id":"\#(UUID().uuidString)","title":"Old","start":0,"minutes":90,"fullTask":"","minTask":""}]"#.data(using: .utf8)!
assert((try? JSONDecoder().decode([Block].self, from: mk12))?.first?.focus == 90, "MK1.2 blocks still load")
assert(durationText(150) == "2h 30m" && durationText(120) == "2h" && durationText(45) == "45m")

print("✓ checks passed")
