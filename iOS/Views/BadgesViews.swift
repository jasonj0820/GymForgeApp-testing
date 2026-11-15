import SwiftUI
import UserNotifications

// MARK: - MK24 (150): milestone badges

extension PhoneAppStore {
    var milestoneTotals: Milestones.Totals {
        let training = workoutLogs.filter(\.countsAsTraining)
        let current = consistency.streakWeeks
        let best = max(UserDefaults.standard.integer(forKey: "streak.best"), current)
        if best > UserDefaults.standard.integer(forKey: "streak.best") { UserDefaults.standard.set(best, forKey: "streak.best") }
        let steps = dayfold?.snapshot.completions.values.filter { $0.done && $0.skipped != true }.count ?? 0
        return Milestones.Totals(sessions: training.count, bestStreakWeeks: best, prs: training.reduce(0) { $0 + $1.prCount },
                                 volumeTonnes: training.reduce(0) { $0 + $1.totalVolumeKg } / 1000, routineSteps: steps,
                                 proteinDaysInARow: Milestones.proteinRun(extras.nutrition, target: proteinTargetG ?? 0))
    }

    var badges: [Badge] { Milestones.badges(milestoneTotals) }
}

struct BadgesView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage("streak.freezes") private var freezes = true

    var body: some View {
        let badges = store.badges
        let stats = store.consistency
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // MK24 (151)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $freezes) { Label("Streak freezes", systemImage: "snowflake") }
                    Text("Every 4 weeks in a row on goal earns a freeze (2 at most). A missed week uses one instead of ending your streak."
                         + (freezes ? " In the bank: \(stats.freezesBanked). Used so far: \(stats.freezesUsed)." : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .card()
                Text("\(badges.filter(\.earned).count) of \(badges.count) earned").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(badges) { badge in
                        VStack(spacing: 6) {
                            Image(systemName: badge.icon)
                                .font(.title)
                                .foregroundStyle(badge.earned ? Color.orange : Color.secondary.opacity(0.5))
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(badge.earned ? Color.orange.opacity(0.15) : Color.gray.opacity(0.08)))
                            Text(badge.title).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2)
                            if badge.earned {
                                Text(badge.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            } else {
                                SwiftUI.ProgressView(value: badge.progress).tint(.orange)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .opacity(badge.earned ? 1 : 0.7)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Badges")
    }
}

// MARK: - MK24 (153): Sergeant Cluck notices your protein and routine streaks (and new badges)

@MainActor
enum CluckPraise {
    static let milestones = [3, 7, 14, 30, 60, 100]
    static let lineKey = "praise.line", lineDayKey = "praise.day"

    /// Today's line for the Today card, if he said something today.
    static var todayLine: String? {
        guard let day = UserDefaults.standard.object(forKey: lineDayKey) as? Date, Calendar.current.isDateInToday(day) else { return nil }
        return UserDefaults.standard.string(forKey: lineKey)
    }

    static func check(store: PhoneAppStore) {
        guard !Demo.isOn else { return }
        var lines: [String] = []
        let protein = Milestones.proteinRun(store.extras.nutrition, target: store.proteinTargetG ?? 0)
        if milestones.contains(protein), once("protein", protein) {
            lines.append(protein >= 14 ? "\(protein) days straight on protein. I've stopped checking. Almost."
                         : "\(protein) days in a row on protein. Sergeant Cluck nods. Once.")
        }
        let routine = routineRun(store)
        if milestones.contains(routine), once("routine", routine) {
            lines.append(routine >= 14 ? "\(routine) days of the whole routine. That's not a streak, that's who you are now."
                         : "\(routine) days, every routine step. Carry on, soldier.")
        }
        // New badges (silently remembered on first run, so you don't get the back catalogue).
        let earned = Set(store.badges.filter(\.earned).map(\.id))
        let seenKey = "badges.seen"
        if let seen = UserDefaults.standard.stringArray(forKey: seenKey).map(Set.init) {
            if let newest = store.badges.last(where: { $0.earned && !seen.contains($0.id) }) {
                lines.append("New badge: \(newest.title). Don't let it go to your head.")
            }
        }
        UserDefaults.standard.set(Array(earned), forKey: seenKey)
        guard let line = lines.first else { return }
        UserDefaults.standard.set(line, forKey: lineKey)
        UserDefaults.standard.set(Date(), forKey: lineDayKey)
        let content = UNMutableNotificationContent()
        content.title = "🪖 Sergeant Cluck"
        content.body = lines.joined(separator: " ")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "gymforge.praise.\(UUID().uuidString)", content: content,
                                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
    }

    /// True the first time this run length is reached (a new run of the same length later counts again).
    private static func once(_ kind: String, _ value: Int) -> Bool {
        let key = "praise.\(kind)"
        let stamp = "\(value)|\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)"
        guard UserDefaults.standard.string(forKey: key)?.hasPrefix("\(value)|") != true else { return false }
        UserDefaults.standard.set(stamp, forKey: key)
        return true
    }

    /// Days in a row (up to yesterday, plus today once it's all done) with every due step ticked.
    static func routineRun(_ store: PhoneAppStore) -> Int {
        guard let dayfold = store.dayfold else { return 0 }
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        let today = dayfold.stats(from: day, to: day.addingTimeInterval(86_400))
        var run = today.due > 0 && today.done == today.due ? 1 : 0
        for _ in 0..<120 {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            let stats = dayfold.stats(from: day, to: cal.date(byAdding: .day, value: 1, to: day) ?? day)
            if stats.due == 0 { if dayfold.isPaused(day) { continue } else { break } }
            guard stats.done == stats.due else { break }
            run += 1
        }
        return run
    }
}

struct CluckPraiseCard: View {
    var body: some View {
        if let line = CluckPraise.todayLine {
            Label(line, systemImage: "medal.fill")
                .font(.subheadline)
                .card()
        }
    }
}
