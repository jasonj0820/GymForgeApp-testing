import SwiftUI
import UIKit
import UserNotifications

/// Settings → Notifications: shows whether notifications are allowed, what's scheduled,
/// and sends a test so you can confirm they arrive.
struct NotificationCheckView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.openURL) private var openURL
    @State private var settings: UNNotificationSettings?
    @State private var pending: [UNNotificationRequest] = []
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Permission", value: statusText)
                if let settings {
                    LabeledContent("Banners", value: settings.alertSetting == .enabled ? "On" : "Off")
                    LabeledContent("Lock Screen", value: settings.lockScreenSetting == .enabled ? "On" : "Off")
                    LabeledContent("Sounds", value: settings.soundSetting == .enabled ? "On" : "Off")
                }
                if settings?.authorizationStatus == .denied || settings?.alertSetting == .disabled {
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } else if settings?.authorizationStatus == .notDetermined {
                    Button("Allow notifications") { Task { await store.ensureNotifications(); store.rescheduleReminders(); await refresh() } }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("If a Focus (Sleep, Work, Do Not Disturb) is on, GymForge needs to be an allowed app in that Focus. When your iPhone is locked and you're wearing your Watch, notifications go to the Watch.")
            }

            Section {
                ForEach(groups, id: \.name) { group in
                    LabeledContent(group.name, value: "\(group.count)")
                }
                if let next = nextCluck {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next from Sergeant Cluck").font(.caption).foregroundStyle(.secondary)
                        Text(next.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                        Text(next.title).font(.caption)
                    }
                } else if store.profile.cluckEnabled {
                    Text("No Sergeant Cluck nags planned — he only nags when you're down to 1 or 0 spare rest days.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("\(pending.count) of iOS's 64-notification limit in use").font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Scheduled")
            }

            Section {
                Button("Send a test notification (5 s)") { sendTest() }
                Button("Re-plan all notifications") {
                    Task {
                        await store.ensureNotifications()
                        store.rescheduleReminders()
                        try? await Task.sleep(for: .milliseconds(600))
                        await refresh()
                        message = "Re-planned. \(pending.count) notifications scheduled."
                    }
                }
            } footer: {
                Text("After tapping the test, lock your iPhone or go to the Home Screen — it should arrive in 5 seconds.")
            }
        }
        .navigationTitle("Notifications")
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Notifications", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var statusText: String {
        switch settings?.authorizationStatus {
        case .authorized: return "Allowed"
        case .provisional: return "Delivered quietly"
        case .ephemeral: return "Temporary"
        case .denied: return "Not allowed"
        case .notDetermined: return "Not asked yet"
        default: return "Checking…"
        }
    }

    private struct NotificationGroup { let name: String; let count: Int }

    private var groups: [NotificationGroup] {
        func count(_ prefixes: [String], excluding: [String] = []) -> Int {
            pending.filter { r in prefixes.contains { r.identifier.hasPrefix($0) } && !excluding.contains { r.identifier.hasPrefix($0) } }.count
        }
        let list = [
            NotificationGroup(name: "Sergeant Cluck nags", count: count(["gymforge.cluck."], excluding: ["gymforge.cluck.m.", "gymforge.cluck.r.", "gymforge.cluck.recap"])),
            NotificationGroup(name: "Rest-day nags", count: count(["gymforge.cluck.r."])),
            NotificationGroup(name: "Sunday recap", count: count(["gymforge.cluck.recap"])),
            NotificationGroup(name: "Workout reminders", count: count(["gymforge.reminder"])),
            NotificationGroup(name: "Other", count: pending.count - count(["gymforge.cluck", "gymforge.reminder"]))
        ]
        return list.filter { $0.count > 0 }
    }

    private var nextCluck: (date: Date, title: String)? {
        pending.compactMap { request -> (Date, String)? in
            guard request.identifier.hasPrefix("gymforge.cluck"),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return (date, request.content.title)
        }
        .min { $0.0 < $1.0 }
        .map { (date: $0.0, title: $0.1) }
    }

    private func refresh() async {
        let center = UNUserNotificationCenter.current()
        settings = await center.notificationSettings()
        pending = await center.pendingNotificationRequests()
    }

    private func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "🪖 Sergeant Cluck"
        content.body = "Test received. Now go to the gym."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "gymforge.test", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))) { error in
            DispatchQueue.main.async {
                message = error.map { "Couldn't schedule: \($0.localizedDescription)" }
                    ?? "Sent — lock your phone or go to the Home Screen."
            }
        }
    }
}
