import SwiftUI
import WidgetKit

/// Sergeant Cluck on the Home Screen and Lock Screen. The timeline is planned ahead,
/// so he turns angry at 5:10pm by himself even if the app hasn't been opened.
struct CluckEntry: TimelineEntry {
    let date: Date
    let state: CluckState?
    let line: String
}

struct CluckProvider: TimelineProvider {
    func placeholder(in context: Context) -> CluckEntry {
        CluckEntry(date: .now, state: Self.sample, line: "4 sessions. 4 days. ZERO rest days. GET. UP.")
    }

    func getSnapshot(in context: Context, completion: @escaping (CluckEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, snapshot: CluckStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CluckEntry>) -> Void) {
        let snapshot = CluckStore.load()
        let cal = Calendar.current
        let now = Date()
        var dates: [Date] = [now]
        // Today and the next two days: midnight, 5:10pm (anger), 7:00pm, 8:30pm.
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            if offset > 0 { dates.append(day) }
            for stage in CluckEngine.stages {
                if let time = cal.date(bySettingHour: stage.hour, minute: stage.minute, second: 0, of: day), time > now {
                    dates.append(time)
                }
            }
        }
        dates += CluckEngine.sleepTimes(snapshot, now: now)
        let entries = dates.sorted().map { entry(at: $0, snapshot: snapshot) }
        let refresh = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry(at date: Date, snapshot: CluckSnapshot?) -> CluckEntry {
        guard let snapshot, snapshot.enabled else {
            return CluckEntry(date: date, state: nil,
                              line: snapshot == nil ? "Open GymForge once so I can see your week." : "Sergeant Cluck is off duty (Settings).")
        }
        let state = CluckEngine.evaluate(snapshot, at: date)
        return CluckEntry(date: date, state: state, line: CluckEngine.line(state, at: date))
    }

    static let sample = CluckState(mood: .furious, goal: 5, done: 1, remaining: 4, daysLeft: 4, spare: 0,
                                   trainedToday: false, snoozedToday: false, snoozeAvailable: true)
}

struct CluckWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CluckEntry

    private var mood: CluckMood { entry.state?.mood ?? .chill }

    private var countText: String {
        guard let s = entry.state else { return "" }
        if s.remaining == 0 { return "\(s.done)/\(s.goal) done" }
        return "\(s.remaining) left · \(s.daysLeft)d"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    CluckView(mood: mood).frame(width: 34, height: 34)
                    if let s = entry.state, s.remaining > 0 {
                        Text("\(s.remaining)/\(s.daysLeft)").font(.system(size: 11, weight: .heavy))
                    }
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                CluckView(mood: mood).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countText).font(.headline).widgetAccentable()
                    Text(entry.line).font(.caption2).lineLimit(2)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text("🪖 " + (entry.state.map { $0.remaining == 0 ? "Quota met" : "\($0.remaining) left, \($0.daysLeft) days" } ?? "Sergeant Cluck"))
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            HStack(spacing: 12) {
                CluckView(mood: mood)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERGEANT CLUCK").font(.caption2.bold()).foregroundStyle(.secondary)
                    Text(countText).font(.title2.weight(.heavy))
                    Text(entry.line).font(.subheadline).lineLimit(3).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { mood.tint.opacity(0.25) }
        default:
            VStack(spacing: 4) {
                CluckView(mood: mood)
                Text(countText).font(.headline.weight(.heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Text(mood.title).font(.caption2.bold()).foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { mood.tint.opacity(0.25) }
        }
    }
}

struct CluckWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CluckStore.widgetKind, provider: CluckProvider()) { entry in
            CluckWidgetView(entry: entry)
        }
        .configurationDisplayName("Sergeant Cluck")
        .description("Your weekly gym quota. He gets angry at 5:10pm if you're running out of rest days.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
