import Foundation
import Combine
import UserNotifications

extension Notification.Name {
    /// A Dayfold reminder was tapped (posted by GymForge's notification delegate); object = RoutineKind raw value.
    static let dayfoldOpenRoutine = Notification.Name("dayfold.openRoutine")
}

/// Dayfold's reminders. GymForge's PhoneAppDelegate stays the notification delegate and forwards taps here.
final class DayfoldNotifications: ObservableObject {
    static let prefix = "dayfold."
    // iOS keeps 64 pending notifications per app; GymForge uses ~35 (wind-down, nags, Cluck, review) + 6 protein + 4 wake-up + 6 quotes.
    static let cap = 10
    @Published var permission = "Not enabled"
    @Published var problem: String?
    @Published var openedRoutine: RoutineKind?
    private var schedulingTask: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .dayfoldOpenRoutine, object: nil, queue: .main) { [weak self] note in
            self?.openedRoutine = (note.object as? String).flatMap(RoutineKind.init(rawValue:))
        }
        refreshPermission()
    }
    func requestPermission() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            refreshPermission()
        } catch {
            await MainActor.run { self.problem = error.localizedDescription }
        }
    }
    func refreshPermission() {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self.permission = "Enabled"
                case .denied: self.permission = "Blocked — enable in iPhone Settings"
                default: self.permission = "Not enabled"
                }
            }
        }
    }
    func rebuild(_ snapshot: DayfoldSnapshot) {
        schedulingTask?.cancel()
        let generation = UUID().uuidString
        schedulingTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            // Only Dayfold's own requests: GymForge's reminders live in the same app.
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
            let authorization = await center.notificationSettings()
            guard !Task.isCancelled else { return }
            guard [.authorized, .provisional, .ephemeral].contains(authorization.authorizationStatus) else { return }
            let calendar = Calendar.current
            let now = Date()
            var failure: String?
            var count = 0
            // Earliest days first; rebuilt on edits, completions, sync and app activation.
            for offset in 0..<28 where count < Self.cap {
                guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
                for settings in snapshot.configuration.routines where settings.remindersEnabled && count < Self.cap {
                    if Task.isCancelled { return }
                    let time = settings.time(for: calendar.component(.weekday, from: date))
                    guard let fire = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date), fire > now else { continue }
                    let due = ScheduleEngine.rows(snapshot, kind: settings.kind, now: fire).filter { !$0.done && $0.retryToday }.map(\.task.title)
                    guard !due.isEmpty else { continue }
                    // MK14: today and tomorrow also get follow-ups while something's still undone.
                    let chasers = offset < 2 ? ScheduleEngine.followUps(after: fire, calendar: calendar) : []
                    for (index, time) in ([fire] + chasers).enumerated() where count < Self.cap {
                        count += 1
                        let content = UNMutableNotificationContent()
                        content.title = index == 0 ? "\(settings.kind.title) · \(due.count) due" : "🪖 Still not done · \(settings.kind.title)"
                        content.body = due.joined(separator: "\n")
                        content.sound = .default
                        content.interruptionLevel = .active
                        content.threadIdentifier = Self.prefix + settings.kind.rawValue
                        content.userInfo = ["routine": settings.kind.rawValue]
                        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time)
                        let identifier = "\(Self.prefix)\(generation)-\(settings.kind.rawValue)-\(offset)-\(index)"
                        let request = UNNotificationRequest(identifier: identifier, content: content,
                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                        do { try await center.add(request) }
                        catch { failure = error.localizedDescription }
                        if Task.isCancelled {
                            center.removePendingNotificationRequests(withIdentifiers: [identifier])
                            return
                        }
                    }
                }
            }
            problem = failure
        }
    }
}
