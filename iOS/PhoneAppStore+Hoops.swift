import Foundation

/// MK24 (I): basketball extras and sleep debt.
extension PhoneAppStore {
    func updateHoops(_ change: (inout Hoops) -> Void) {
        change(&extras.hoops)
        saveExtras()
    }

    func addShot(_ shot: Shot) { updateHoops { $0.shots.append(shot) } }
    func undoShot() { updateHoops { if !$0.shots.isEmpty { $0.shots.removeLast() } } }
    func logDrill(_ log: DrillLog) { updateHoops { $0.drillLogs.append(log) } }
    func addDrill(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        updateHoops { $0.drills.append(Drill(name: clean)) }
    }
    func deleteDrillLog(_ id: UUID) { updateHoops { $0.drillLogs.removeAll { $0.id == id } } }
    func addJump(_ entry: JumpEntry) { updateHoops { $0.jumps.append(entry); $0.jumps.sort { $0.date < $1.date } } }
    func deleteJump(_ id: UUID) { updateHoops { $0.jumps.removeAll { $0.id == id } } }
    func saveGame(_ game: GameStats) {
        updateHoops { hoops in
            if let index = hoops.games.firstIndex(where: { $0.id == game.id }) { hoops.games[index] = game } else { hoops.games.append(game) }
            hoops.games.sort { $0.date > $1.date }
        }
    }
    func deleteGame(_ id: UUID) { updateHoops { $0.games.removeAll { $0.id == id } } }

    // MARK: Sleep (128)

    /// Health's nights, plus the hours from your morning check-ins on nights Health doesn't have.
    var sleepNightsAll: [SleepNight] {
        let cal = Calendar.current
        var nights = healthKit.sleep
        for check in extras.checkIns where !nights.contains(where: { cal.isDate($0.date, inSameDayAs: check.date) }) {
            nights.append(SleepNight(date: check.date, hoursAsleep: check.sleepHours))
        }
        return nights.sorted { $0.date < $1.date }
    }

    var sleepNeed: Double { SleepMath.need(profile.sleepSchedule) }
}
