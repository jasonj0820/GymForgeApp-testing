#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - MK24 (111): today's routine on the Home Screen, with steps you can tick

/// What the app hands the widget: today's open steps (written to the shared App Group).
struct RoutineWidgetFeed: Codable, Equatable {
    struct Item: Codable, Equatable, Identifiable {
        var id: String       // occurrence key
        var taskID: UUID
        var title: String
        var done: Bool
    }
    var day: Date
    var items: [Item]

    static let key = "routine.widget.feed"
    static let kind = "RoutineWidget"

    static func load() -> RoutineWidgetFeed? {
        guard let data = CluckStore.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RoutineWidgetFeed.self, from: data)
    }

    static func save(_ feed: RoutineWidgetFeed) {
        guard load() != feed, let data = try? JSONEncoder().encode(feed) else { return }
        CluckStore.defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// The widget's tick. A LiveActivityIntent, so iOS runs it inside the app (where the routine lives).
struct RoutineTickIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Tick a routine step"
    static var isDiscoverable = false

    @Parameter(title: "Step") var taskID: String

    init() {}
    init(taskID: UUID) { self.taskID = taskID.uuidString }

    func perform() async throws -> some IntentResult {
        await RoutineWidgetControl.tick(taskID)
        return .result()
    }
}

/// Set by the app at launch; does nothing in the widget extension.
@MainActor
enum RoutineWidgetControl {
    static var handler: ((UUID) -> Void)?
    static func tick(_ raw: String) {
        guard let id = UUID(uuidString: raw) else { return }
        handler?(id)
    }
}

struct RoutineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RoutineWidgetFeed.kind, provider: RoutineProvider()) { entry in
            RoutineWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Routine")
        .description("Today's steps. Tick them right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RoutineEntry: TimelineEntry {
    let date: Date
    let feed: RoutineWidgetFeed?
}

struct RoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineEntry {
        RoutineEntry(date: .now, feed: RoutineWidgetFeed(day: .now, items: [
            .init(id: "a", taskID: UUID(), title: "Glass of water", done: true),
            .init(id: "b", taskID: UUID(), title: "Creatine", done: false),
            .init(id: "c", taskID: UUID(), title: "Stretch", done: false)]))
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : RoutineEntry(date: .now, feed: RoutineWidgetFeed.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineEntry>) -> Void) {
        // Again just after midnight, when a new day's steps come due (the app refreshes it sooner on any change).
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [RoutineEntry(date: .now, feed: RoutineWidgetFeed.load())], policy: .after(tomorrow.addingTimeInterval(60))))
    }
}

struct RoutineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineEntry

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemMedium: 4
        default: 9
        }
    }

    var body: some View {
        let today = entry.feed.flatMap { Calendar.current.isDateInToday($0.day) ? $0.items : nil } ?? []
        let open = today.filter { !$0.done }
        let done = today.count - open.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Routine", systemImage: "checklist").font(.caption.bold()).foregroundStyle(.green)
                Spacer()
                if !today.isEmpty { Text("\(done)/\(today.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            if entry.feed == nil {
                Text("Open Splitday once to show your routine here.").font(.caption).foregroundStyle(.secondary)
            } else if open.isEmpty {
                Spacer()
                Label(today.isEmpty ? "Nothing due today" : "All done", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
                Spacer()
            } else {
                ForEach(open.prefix(limit)) { item in
                    Button(intent: RoutineTickIntent(taskID: item.taskID)) {
                        HStack(spacing: 6) {
                            Image(systemName: "circle").foregroundStyle(.green)
                            Text(item.title).font(.caption).lineLimit(1).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if open.count > limit {
                    Text("+\(open.count - limit) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
#endif
