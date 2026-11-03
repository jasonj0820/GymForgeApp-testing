import XCTest
@testable import DayfoldCore

final class ScheduleTests: XCTestCase {
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Australia/Brisbane")!
        return result
    }
    func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }
    func task(_ days: Set<Int> = [1], retry: Int = 1, kind: RoutineKind = .weekly) -> RoutineTask {
        RoutineTask(title: "Test", routine: kind, weekdays: days, retryDays: retry, createdAt: date("2026-10-10 12:00"))
    }
    func row(_ task: RoutineTask, _ when: String, _ records: [String: DayfoldCompletion] = [:]) -> TaskOccurrence? {
        ScheduleEngine.occurrence(task, on: date(when), completions: records, calendar: calendar)
    }
    func completed(_ task: RoutineTask, due: String, at: String, done: Bool = true) -> DayfoldCompletion {
        let occurrence = date(due)
        let key = ScheduleEngine.key(task.id, occurrence, calendar: calendar)
        return DayfoldCompletion(id: key, taskID: task.id, occurrence: occurrence, done: done, changedAt: date(at))
    }
    func testSundayTaskNotDueBeforeFirstSunday() {
        XCTAssertNil(row(task(), "2026-10-10 12:00"))
    }
    func testSundayAppearsAndMondayCarriesSameOccurrence() {
        let task = task()
        let sunday = row(task, "2026-10-11 07:00")!
        let monday = row(task, "2026-10-12 07:00")!
        XCTAssertEqual(sunday.due, monday.due)
        XCTAssertFalse(sunday.overdue)
        XCTAssertTrue(monday.overdue)
        XCTAssertTrue(monday.retryToday)
    }
    func testTuesdayCompletionKeepsNextSunday() {
        let task = task()
        let completion = completed(task, due: "2026-10-11 00:00", at: "2026-10-13 07:00")
        let records = [completion.id: completion]
        XCTAssertTrue(row(task, "2026-10-14 07:00", records)!.done)
        let next = row(task, "2026-10-18 07:00", records)!
        XCTAssertFalse(next.done)
        XCTAssertEqual(next.due, date("2026-10-18 00:00"))
    }
    func testTwoDayRetry() {
        let task = task(retry: 2)
        XCTAssertTrue(row(task, "2026-10-11 07:00")!.retryToday)
        XCTAssertFalse(row(task, "2026-10-12 07:00")!.retryToday)
        XCTAssertTrue(row(task, "2026-10-13 07:00")!.retryToday)
    }
    func testMultipleMissedWeeksBecomeOneLatestOccurrence() {
        let task = task()
        let state = DayfoldSnapshot(configuration: DayfoldConfiguration(tasks: [task], routines: []))
        let rows = ScheduleEngine.rows(state, kind: .weekly, now: date("2026-11-02 07:00"), calendar: calendar)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.due, date("2026-11-01 00:00"))
    }
    func testDailyCompletionReturnsTomorrow() {
        let task = task(Set(1...7), kind: .daily)
        let completion = completed(task, due: "2026-10-11 00:00", at: "2026-10-11 22:00")
        XCTAssertTrue(row(task, "2026-10-11 22:00", [completion.id: completion])!.done)
        XCTAssertFalse(row(task, "2026-10-12 22:00", [completion.id: completion])!.done)
    }
    func testPausedAndEmptyScheduleAreHidden() {
        var task = task()
        task.enabled = false
        XCTAssertNil(row(task, "2026-10-11 07:00"))
        task.enabled = true; task.weekdays = []
        XCTAssertNil(row(task, "2026-10-11 07:00"))
    }
    func testUndoPropagatesAndStaleSyncCannotEraseIt() {
        let task = task()
        let done = completed(task, due: "2026-10-11 00:00", at: "2026-10-11 07:00")
        let undo = completed(task, due: "2026-10-11 00:00", at: "2026-10-11 07:01", done: false)
        let merged = ScheduleEngine.merge([done.id: done], [undo.id: undo])
        XCTAssertFalse(merged[done.id]!.done)
        XCTAssertEqual(ScheduleEngine.merge(merged, [done.id: done]), merged)
    }
    func testMergingIndependentOfflineCheckoffsPreservesBoth() {
        let taskA = task(); let taskB = task()
        let a = completed(taskA, due: "2026-10-11 00:00", at: "2026-10-11 07:00")
        let b = completed(taskB, due: "2026-10-11 00:00", at: "2026-10-11 07:02")
        XCTAssertEqual(ScheduleEngine.merge([a.id: a], [b.id: b]).count, 2)
    }
    func testSelectedWeekdaysAndStableOrder() {
        var a = task([2, 4, 6]); a.order = 1
        var b = task([2, 4, 6]); b.order = 0
        let state = DayfoldSnapshot(configuration: DayfoldConfiguration(tasks: [a, b], routines: []))
        let rows = ScheduleEngine.rows(state, kind: .weekly, now: date("2026-10-14 07:00"), calendar: calendar)
        XCTAssertEqual(rows.map(\.task.id), [b.id, a.id])
        XCTAssertEqual(rows[0].due, date("2026-10-14 00:00"))
    }
    func testCalendarDayRetryAcrossDST() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 7))! }
        let task = RoutineTask(title: "DST", routine: .weekly, weekdays: [7], retryDays: 2, createdAt: d(3))
        XCTAssertFalse(ScheduleEngine.occurrence(task, on: d(4), completions: [:], calendar: cal)!.retryToday)
        XCTAssertTrue(ScheduleEngine.occurrence(task, on: d(5), completions: [:], calendar: cal)!.retryToday)
    }
    func monthly(_ day: Int, month: Int = 1, kind: RoutineKind = .monthly, retry: Int = 1) -> RoutineTask {
        RoutineTask(title: "M", routine: kind, monthDay: day, month: month, retryDays: retry, createdAt: date("2026-01-01 12:00"))
    }
    func testMonthlyDueOnDayAndCarriedUntilNext() {
        let task = monthly(15)
        XCTAssertEqual(row(task, "2026-10-14 08:00")!.due, date("2026-09-15 00:00"))
        let due = row(task, "2026-10-15 08:00")!
        XCTAssertEqual(due.due, date("2026-10-15 00:00"))
        XCTAssertFalse(due.overdue)
        XCTAssertTrue(row(task, "2026-10-20 08:00")!.overdue)
    }
    func testMonthly31stClampsToShortMonths() {
        let task = monthly(31)
        XCTAssertEqual(row(task, "2026-02-28 08:00")!.due, date("2026-02-28 00:00"))
        XCTAssertEqual(row(task, "2026-04-30 08:00")!.due, date("2026-04-30 00:00"))
        XCTAssertEqual(row(task, "2026-05-30 08:00")!.due, date("2026-04-30 00:00"))
        XCTAssertEqual(row(task, "2026-03-01 08:00")!.due, date("2026-02-28 00:00"))
    }
    func testMonthlyNotDueBeforeFirstDateAfterCreation() {
        var task = monthly(5)
        task.createdAt = date("2026-10-10 12:00")
        XCTAssertNil(row(task, "2026-10-20 08:00"))
        XCTAssertNotNil(row(task, "2026-11-05 08:00"))
    }
    func testYearlyLatestOccurrenceAndLeapDay() {
        let task = monthly(29, month: 2, kind: .yearly)
        XCTAssertNil(row(task, "2026-02-27 08:00"))
        XCTAssertEqual(row(task, "2026-10-21 08:00")!.due, date("2026-02-28 00:00"))
        XCTAssertEqual(row(task, "2028-03-01 08:00")!.due, date("2028-02-29 00:00"))
    }
    func testDailyIgnoresWeekdays() {
        var task = task(Set(1...7), kind: .daily)
        task.weekdays = []
        XCTAssertEqual(row(task, "2026-10-14 08:00")!.due, date("2026-10-14 00:00"))
    }
    func testLegacyV1FileDecodes() throws {
        let id = UUID()
        let json = """
        {"configuration":{"revision":0,"tasks":[
          {"id":"\(id.uuidString)","title":"Weigh","routine":"morning","weekdays":[1],"retryDays":1,"order":0,"createdAt":0,"enabled":true},
          {"id":"\(UUID().uuidString)","title":"Skin","routine":"bedtime","weekdays":[1,2,3,4,5,6,7],"retryDays":1,"order":0,"createdAt":0,"enabled":true}],
         "routines":[{"kind":"morning","remindersEnabled":true,"hour":7,"minute":0,"weekdayMinutes":{}}]},
         "completions":{}}
        """
        let snap = try JSONDecoder().decode(DayfoldSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.configuration.tasks.map(\.routine), [.weekly, .daily])
        XCTAssertEqual(snap.configuration.routines.first?.kind, .daily)
        let again = try JSONDecoder().decode(DayfoldSnapshot.self, from: JSONEncoder().encode(snap))
        XCTAssertEqual(again.configuration, snap.configuration)
    }
    func testStarterIncludesJawRoutine() {
        let tasks = DayfoldConfiguration.initial().tasks
        XCTAssertEqual(tasks.filter { $0.title.hasPrefix("Jaw") }.count, 4)
        XCTAssertEqual(Set(DayfoldConfiguration.initial().routines.map(\.kind)), Set(RoutineKind.allCases))
    }
    func testFollowUpsStopAt9pm() {
        XCTAssertEqual(ScheduleEngine.followUps(after: date("2026-10-26 08:00"), calendar: calendar),
                       [date("2026-10-26 09:00"), date("2026-10-26 11:00")])
        XCTAssertEqual(ScheduleEngine.followUps(after: date("2026-10-26 19:00"), calendar: calendar), [date("2026-10-26 20:00")])
        XCTAssertTrue(ScheduleEngine.followUps(after: date("2026-10-26 21:30"), calendar: calendar).isEmpty)
    }
    func testAbsOncePerWeekOnRestDay() {
        let tue = date("2026-10-27 09:00")
        XCTAssertNil(ScheduleEngine.absTask(completions: [:], restDay: false, now: tue, calendar: calendar))
        let shown = ScheduleEngine.absTask(completions: [:], restDay: true, now: tue, calendar: calendar)!
        XCTAssertNotNil(ScheduleEngine.occurrence(shown, on: tue, completions: [:], calendar: calendar))
        // Done on Tuesday: still listed (as done) on Thursday even though it's a gym day; gone next week.
        let key = ScheduleEngine.key(RoutineTask.absID, date("2026-10-27 00:00"), calendar: calendar)
        let done = [key: DayfoldCompletion(id: key, taskID: RoutineTask.absID, occurrence: date("2026-10-27 00:00"), done: true, changedAt: tue)]
        let thu = date("2026-10-29 09:00")
        let kept = ScheduleEngine.absTask(completions: done, restDay: false, now: thu, calendar: calendar)!
        XCTAssertTrue(ScheduleEngine.occurrence(kept, on: thu, completions: done, calendar: calendar)!.done)
        XCTAssertNil(ScheduleEngine.absTask(completions: done, restDay: false, now: date("2026-11-03 09:00"), calendar: calendar))
    }
}
