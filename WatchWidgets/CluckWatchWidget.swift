import SwiftUI
import WidgetKit

/// Sergeant Cluck on the Watch face. The iPhone sends his snapshot to the Watch app, which saves it
/// in the shared App Group; the timeline turns him angry at 5:10pm on its own.
struct CluckWatchEntry: TimelineEntry {
    let date: Date
    let state: CluckState?
}

struct CluckWatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> CluckWatchEntry {
        CluckWatchEntry(date: .now, state: CluckState(mood: .furious, goal: 5, done: 1, remaining: 4, daysLeft: 4,
                                                      spare: 0, trainedToday: false, snoozedToday: false, snoozeAvailable: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (CluckWatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, CluckStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CluckWatchEntry>) -> Void) {
        let snapshot = CluckStore.load()
        let cal = Calendar.current
        let now = Date()
        var dates: [Date] = [now]
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            if offset > 0 { dates.append(day) }
            for stage in CluckEngine.stages {
                if let time = cal.date(bySettingHour: stage.hour, minute: stage.minute, second: 0, of: day), time > now {
                    dates.append(time)
                }
            }
        }
        let refresh = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(6 * 3600)
        dates += CluckEngine.sleepTimes(snapshot, now: now)
        completion(Timeline(entries: dates.sorted().map { entry(at: $0, snapshot) }, policy: .after(refresh)))
    }

    private func entry(at date: Date, _ snapshot: CluckSnapshot?) -> CluckWatchEntry {
        guard let snapshot, snapshot.enabled else { return CluckWatchEntry(date: date, state: nil) }
        return CluckWatchEntry(date: date, state: CluckEngine.evaluate(snapshot, at: date))
    }
}

struct CluckWatchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CluckWatchEntry

    private var mood: CluckMood { entry.state?.mood ?? .chill }

    private var shortText: String {
        guard let s = entry.state else { return "Open GymForge" }
        return s.remaining == 0 ? "Done" : "\(s.remaining) left · \(s.daysLeft)d"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    CluckView(mood: mood).frame(width: 30, height: 30)
                    if let s = entry.state, s.remaining > 0 {
                        Text("\(s.remaining)/\(s.daysLeft)").font(.system(size: 10, weight: .heavy))
                    }
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            CluckView(mood: mood)
                .widgetLabel(shortText)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text("🪖 " + shortText)
                .containerBackground(for: .widget) { Color.clear }
        default:
            HStack(spacing: 6) {
                CluckView(mood: mood).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shortText).font(.headline).widgetAccentable()
                    Text(entry.state.map { CluckEngine.line($0, at: entry.date) } ?? "Open GymForge on your iPhone.")
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        }
    }
}

@main
struct CluckWatchWidgets: WidgetBundle {
    var body: some Widget {
        CluckWatchWidget()
    }
}

struct CluckWatchWidget: Widget {
    static let kind = "SergeantCluckWatch"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CluckWatchProvider()) { entry in
            CluckWatchWidgetView(entry: entry)
        }
        .configurationDisplayName("Sergeant Cluck")
        .description("Weekly gym quota — angry at 5:10pm if you're running out of rest days.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
