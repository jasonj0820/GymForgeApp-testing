import SwiftUI
import WidgetKit

@main
struct DuctileWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        BlockLiveActivity()
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let blocks: [Block]
    let active: ActiveTimer?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, blocks: [Block(title: "Steel design", start: .now, minutes: 90)], active: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let today = dayBlocks(Store.blocks, on: now)
        // Redraw when each block starts or ends and when the timer runs out, so "now" moves along.
        let changes = (today.flatMap { [$0.start, $0.end] } + [Store.active?.ends].compactMap { $0 })
            .filter { $0 > now }.sorted()
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        completion(Timeline(entries: ([now] + changes).map(entry(at:)), policy: .after(midnight)))
    }

    private func entry(at date: Date) -> Entry {
        Entry(date: date, blocks: dayBlocks(Store.blocks, on: date), active: Store.active)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: Provider()) { TodayView(entry: $0) }
            .configurationDisplayName("Today's blocks")
            .description("Tap a block to start its timer and Focus.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if let timer = running {
                    Group {
                        if timer.isPaused { Text("Paused") }
                        else { Text(timerInterval: entry.date...timer.ends, countsDown: true) }
                    }
                    .font(.caption.bold().monospacedDigit()).foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
                }
            }
            if shown.isEmpty {
                Spacer()
                Text(entry.blocks.isEmpty ? "No blocks today" : "All done today ✓")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(shown) { block in
                Link(destination: Links.start(block.id)) { row(block) }
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        // Small widgets can't hold per-row links, so the whole widget starts the next block.
        .widgetURL(family == .systemSmall ? shown.first.map { Links.start($0.id) } : nil)
    }

    private var running: ActiveTimer? {
        entry.active.flatMap { $0.isPaused || $0.ends > entry.date ? $0 : nil }
    }

    /// Unfinished blocks (missed ones stay, so you can still do the minimum).
    private var shown: [Block] {
        let limit = switch family { case .systemSmall: 2; case .systemLarge: 7; default: 3 }
        return Array(entry.blocks.filter { $0.outcome == nil }.prefix(limit))
    }

    private func row(_ block: Block) -> some View {
        let isRunning = running?.blockID == block.id
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(isRunning ? Color.orange : .accentColor).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title).font(.subheadline.bold()).lineLimit(1)
                Text("\(block.start.formatted(date: .omitted, time: .shortened)) · \(block.minutes) min")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                Image(systemName: isRunning ? "timer" : "play.circle.fill")
                    .foregroundStyle(isRunning ? Color.orange : .accentColor)
            }
        }
        .padding(6)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
