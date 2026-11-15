import AppIntents
import CoreLocation
import SwiftUI
import Foundation
import UserNotifications
import WidgetKit

// MARK: - MK24 (H): the routine beyond the list — widget, per-step reminders, "when I get home",
// ticking from a notification or Siri.

extension PhoneAppStore {
    /// Today's row for a step (the one still open, if it carries over).
    func todayRow(taskID: UUID, now: Date = .now) -> TaskOccurrence? {
        guard let dayfold else { return nil }
        return RoutineKind.allCases.flatMap { dayfold.rows($0, now: now) }.first { $0.task.id == taskID && ($0.retryToday || $0.done) }
    }

    /// From the widget, a notification or Siri.
    @discardableResult
    func tickRoutineStep(_ taskID: UUID) -> String? {
        guard let dayfold, let row = todayRow(taskID: taskID), !row.done else { return nil }
        dayfold.setDone(row, done: true)
        return row.task.title
    }
}

extension RoutineWidgetFeed {
    @MainActor
    static func publish(store: PhoneAppStore, now: Date = .now) {
        guard let dayfold = store.dayfold else { return }
        let rows = RoutineKind.allCases.flatMap { dayfold.rows($0, now: now) }.filter { $0.retryToday || $0.done }
        let ordered = RoutineOrder.nextUp(rows, now: now) + rows.filter(\.done)
        save(RoutineWidgetFeed(day: now, items: ordered.map { Item(id: $0.id, taskID: $0.task.id, title: $0.task.title, done: $0.done) }))
    }
}

// MARK: Per-step reminders (115), "when I get home" (116), ticking from the notification (117)

@MainActor
enum RoutineStepReminders {
    nonisolated static let prefix = "dayfold.step."
    nonisolated static let homeID = "dayfold.home"
    nonisolated static let stepCategory = "dayfold.step"
    nonisolated static let routineCategory = "dayfold.routine"
    nonisolated static let doneAction = "dayfold.done"
    nonisolated static let doneAllAction = "dayfold.doneAll"
    nonisolated static let cap = 6

    /// Adds the Done buttons to routine notifications (called once at launch, next to Sergeant Cluck's).
    static func registerCategories() {
        let one = UNNotificationCategory(identifier: stepCategory,
                                         actions: [UNNotificationAction(identifier: doneAction, title: "Done", options: [])],
                                         intentIdentifiers: [], options: [])
        let all = UNNotificationCategory(identifier: routineCategory,
                                         actions: [UNNotificationAction(identifier: doneAllAction, title: "All done", options: [])],
                                         intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var set = existing.filter { $0.identifier != stepCategory && $0.identifier != routineCategory }
            set.insert(one)
            set.insert(all)
            UNUserNotificationCenter.current().setNotificationCategories(set)
        }
    }

    /// Done / All done tapped on a routine notification. true if it was one of ours.
    static func handle(_ response: UNNotificationResponse, store: PhoneAppStore) -> Bool {
        let info = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case doneAction:
            if let raw = info["taskID"] as? String, let id = UUID(uuidString: raw) { store.tickRoutineStep(id) }
            return true
        case doneAllAction:
            for raw in info["taskIDs"] as? [String] ?? [] { if let id = UUID(uuidString: raw) { store.tickRoutineStep(id) } }
            return true
        default:
            return false
        }
    }

    static func reschedule(store: PhoneAppStore, now: Date = .now) {
        guard !Demo.isOn, let dayfold = store.dayfold else { return }
        let snapshot = dayfold.snapshot
        let calendar = Calendar.current
        var requests: [UNNotificationRequest] = []
        // Steps with their own time, next 3 days, while not done (and not on a sick / travel day).
        for offset in 0..<3 where requests.count < cap {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)), !dayfold.isPaused(day) else { continue }
            for task in snapshot.configuration.tasks where task.enabled && requests.count < cap {
                guard let minutes = task.reminderMinutes,
                      let fire = calendar.date(byAdding: .minute, value: minutes, to: day), fire > now,
                      let row = ScheduleEngine.occurrence(task, on: day, completions: snapshot.completions, calendar: calendar),
                      !row.done, row.retryToday else { continue }
                let content = UNMutableNotificationContent()
                content.title = task.title
                content.body = task.timerMinutes.map { "\($0) minutes. Tap Done when it's done." } ?? "Tap Done when it's done."
                content.sound = .default
                content.categoryIdentifier = stepCategory
                content.threadIdentifier = "dayfold.step"
                content.userInfo = ["taskID": task.id.uuidString, "routine": task.routine.rawValue]
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                requests.append(UNNotificationRequest(identifier: "\(prefix)\(task.id.uuidString).\(offset)", content: content,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
        // "When I get home": one notification each time you arrive, listing today's home steps.
        let home = snapshot.configuration.tasks.filter { $0.enabled && $0.atHome }
        if let place = HomePlace.coordinate, !home.isEmpty {
            let open = home.filter { task in
                ScheduleEngine.occurrence(task, on: now, completions: snapshot.completions, calendar: calendar).map { !$0.done && $0.retryToday } ?? false
            }
            if !open.isEmpty {
                let content = UNMutableNotificationContent()
                content.title = "Home: \(open.count) step\(open.count == 1 ? "" : "s")"
                content.body = open.map(\.title).joined(separator: "\n")
                content.sound = .default
                content.categoryIdentifier = routineCategory
                content.userInfo = ["taskIDs": open.map(\.id.uuidString), "routine": "daily"]
                let region = CLCircularRegion(center: place, radius: 120, identifier: homeID)
                region.notifyOnEntry = true
                region.notifyOnExit = false
                requests.append(UNNotificationRequest(identifier: homeID, content: content,
                                                      trigger: UNLocationNotificationTrigger(region: region, repeats: false)))
            }
        }
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) || $0 == homeID }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            for request in requests { try? await center.add(request) }
        }
    }
}

/// Where "home" is, for "when I get home" steps. Set once from where you're standing.
@MainActor
enum HomePlace {
    private static let latKey = "home.lat", lonKey = "home.lon"

    static var coordinate: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: latKey), longitude: d.double(forKey: lonKey))
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: latKey)
        UserDefaults.standard.removeObject(forKey: lonKey)
    }

    private static var finder: OneShotLocation?

    /// Asks for location once (while using the app) and saves it as home.
    static func setToHere() async -> Bool {
        let finder = OneShotLocation()
        self.finder = finder
        guard let location = await finder.locate() else { return false }
        UserDefaults.standard.set(location.coordinate.latitude, forKey: latKey)
        UserDefaults.standard.set(location.coordinate.longitude, forKey: lonKey)
        self.finder = nil
        return true
    }
}

@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func locate() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

// MARK: - Siri and Shortcuts (126)

struct RoutineStepEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine step"
    static var defaultQuery = RoutineStepQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct RoutineStepQuery: EntityQuery {
    @MainActor
    private func open() -> [RoutineStepEntity] {
        guard let dayfold = PhoneAppStore.shared.dayfold else { return [] }
        return RoutineKind.allCases.flatMap { dayfold.rows($0) }.filter { $0.retryToday && !$0.done }
            .map { RoutineStepEntity(id: $0.task.id.uuidString, title: $0.task.title) }
    }

    func entities(for identifiers: [String]) async throws -> [RoutineStepEntity] {
        await MainActor.run {
            let all = PhoneAppStore.shared.dayfold?.snapshot.configuration.tasks ?? []
            return all.filter { identifiers.contains($0.id.uuidString) }.map { RoutineStepEntity(id: $0.id.uuidString, title: $0.title) }
        }
    }

    func suggestedEntities() async throws -> [RoutineStepEntity] {
        await MainActor.run { open() }
    }
}

struct TickRoutineStepAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick a routine step"
    static var description = IntentDescription("Marks one of today's routine steps as done in Splitday.")

    @Parameter(title: "Step") var step: RoutineStepEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: step.id) else { return .result(dialog: "That step isn't in your routine.") }
        if let title = PhoneAppStore.shared.tickRoutineStep(id) {
            return .result(dialog: "Done: \(title).")
        }
        return .result(dialog: "\(step.title) is already done today, or isn't due.")
    }
}

// MARK: - Routine in the weekly review and monthly report (123)

struct RoutineStatsBlock: View {
    @EnvironmentObject private var store: PhoneAppStore
    let start: Date
    let end: Date
    let title: String
    var carded = false

    var body: some View {
        if let dayfold = store.dayfold {
            let stats = dayfold.stats(from: start, to: end)
            if stats.due > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: "checklist").font(.headline)
                    let percent = Int((Double(stats.done) / Double(stats.due) * 100).rounded())
                    Text("\(percent)% of steps done (\(stats.done) of \(stats.due))").font(.subheadline.weight(.semibold))
                    SwiftUI.ProgressView(value: Double(stats.done), total: Double(stats.due)).tint(.green)
                    if let weakest = stats.perTask.first, weakest.done < weakest.due {
                        Text("Most missed: \(weakest.title) (\(weakest.done) of \(weakest.due))").font(.caption).foregroundStyle(.secondary)
                    }
                    if let best = stats.perTask.last, best.done == best.due, stats.perTask.count > 1 {
                        Text("Never missed: \(best.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .modifier(OptionalCard(on: carded))
            }
        }
    }
}

struct OptionalCard: ViewModifier {
    let on: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.card() } else { content }
    }
}
