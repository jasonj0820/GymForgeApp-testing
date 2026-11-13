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

// MK2: missed / open, credited time, copies
let noon = one.addingTimeInterval(-3600)
assert(!w.isMissed(at: one) && w.isOpen(at: one) && w.isMissed(at: w.end) && !w.isOpen(at: noon), "open inside the window, missed after it")
var doneW = w; doneW.outcome = .minimum
assert(!doneW.isMissed(at: w.end.addingTimeInterval(9999)), "a ticked block is never missed")
assert(doneW.creditedMinutes == 0, "a minimum ticked by hand has no time")
doneW.focusedMinutes = 40
assert(doneW.creditedMinutes == 40, "timer time counts")
var fullW = w; fullW.outcome = .full
assert(fullW.creditedMinutes == 120 && w.creditedMinutes == 0, "full by hand = the target; not done = 0")
let copy = doneW.copied(byDays: 7, calendar: cal)
assert(copy.id != doneW.id && copy.outcome == nil && copy.focusedMinutes == nil && copy.start == one.addingTimeInterval(7 * 86400)
       && copy.title == "Timber" && copy.focus == 120, "a copy is the same block a week on, not ticked")

// MK2: week summary (4 Nov 2026 is a Wednesday; ISO weeks start Monday)
var iso = Calendar(identifier: .iso8601)
iso.timeZone = cal.timeZone
func at(_ day: Int, _ hour: Int, _ outcome: Block.Outcome? = nil, ran: Int? = nil) -> Block {
    var block = Block(title: "d\(day)", start: iso.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!, minutes: 60)
    block.outcome = outcome
    block.focusedMinutes = ran
    return block
}
let week = [at(2, 9, .full), at(3, 9, .minimum, ran: 20), at(4, 9), at(4, 20), at(8, 9, .full), at(9, 9, .full), at(1, 9, .full)]
let stats = weekStats(week, containing: one, now: one, calendar: iso)
assert(stats == WeekStats(planned: 5, full: 2, minimum: 1, missed: 1, focusMinutes: 60 + 20 + 60), "Mon–Sun only: \(stats)")
assert(stats.done == 3)

// MK2: streak
assert(streak(week, today: one, calendar: iso) == 3, "Sun 1, Mon 2, Tue 3 done; today still open: \(streak(week, today: one, calendar: iso))")
assert(streak([at(1, 9, .full), at(2, 9), at(3, 9, .full)], today: one, calendar: iso) == 1, "a planned day with nothing done breaks it")
assert(streak([at(1, 9, .full), at(3, 9, .full)], today: one, calendar: iso) == 2, "a day with nothing planned doesn't")
assert(streak([at(4, 9, .full), at(3, 9, .full)], today: one, calendar: iso) == 2, "today counts once it's done")
assert(streak([], today: one, calendar: iso) == 0)

// MK2: reminders — at the window's start and at "start by", only for blocks still ahead and not done
let planned = reminders(for: [w, fullW, at(4, 20)], now: one.addingTimeInterval(-600))
assert(planned.map(\.date) == [one, w.startBy, at(4, 20).start], "open, last call, then the evening block: \(planned.map(\.date))")
assert(planned.allSatisfy { $0.id.hasPrefix("remind-") } && Set(planned.map(\.id)).count == 3)
assert(reminders(for: [w], now: one.addingTimeInterval(60)).map(\.date) == [w.startBy], "already open → only the last call")
assert(reminders(for: [w], now: w.startBy).isEmpty && reminders(for: [w], now: one.addingTimeInterval(-600), skipping: w.id).isEmpty)
assert(reminders(for: (0..<50).map { _ in w }, now: noon).count == 40, "capped under iOS's limit of 64")

// MK2: one broken block doesn't empty the calendar
Store.defaults.set(#"[{"title":"broken"},{"id":"\#(UUID().uuidString)","title":"Fine","start":0,"minutes":30,"fullTask":"","minTask":""}]"#.data(using: .utf8)!, forKey: "blocks")
assert(Store.blocks.map(\.title) == ["Fine"], "the readable block survives: \(Store.blocks.map(\.title))")
Store.defaults.removeObject(forKey: "blocks")

print("✓ checks passed")
