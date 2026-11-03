import AppIntents
import SwiftUI
import WidgetKit

struct QuoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: QuoteSettings.widgetKind, provider: QuoteProvider()) { entry in
            QuoteWidgetView(entry: entry)
                .containerBackground(for: .widget) { QuoteBackground(topic: entry.quote.topic) }
        }
        .configurationDisplayName("Motivation")
        .description("Rotates fresh quotes every 5 minutes from your chosen topics. Tap ↻ anytime for the next quote.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: Quote
}

struct QuoteProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuoteEntry { QuoteEntry(date: .now, quote: QuoteLibrary.all[0]) }

    func getSnapshot(in context: Context, completion: @escaping (QuoteEntry) -> Void) {
        completion(QuoteEntry(date: .now, quote: QuoteSettings.widgetQuote()))
    }

    /// Generates 48 timeline entries (every 5 minutes for the next 4 hours) for automatic updates.
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuoteEntry>) -> Void) {
        let now = Date.now
        let stepMinutes = 5
        let entries: [QuoteEntry] = (0..<48).map { step in
            let entryDate = now.addingTimeInterval(Double(step * stepMinutes * 60))
            return QuoteEntry(date: entryDate, quote: QuoteSettings.widgetQuote(at: entryDate))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NextQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Next quote"
    func perform() async throws -> some IntentResult {
        QuoteSettings.offset += 1
        WidgetCenter.shared.reloadTimelines(ofKind: QuoteSettings.widgetKind)
        return .result()
    }
}

struct QuoteBackground: View {
    let topic: QuoteTopic
    private var tint: Color {
        switch topic {
        case .gym, .discipline, .basketball: Color(red: 0.45, green: 0.22, blue: 0.08)
        case .legends: Color(red: 0.48, green: 0.14, blue: 0.14)
        case .lettingGo, .confidence: Color(red: 0.30, green: 0.22, blue: 0.45)
        case .stoic, .career, .wisdom: Color(red: 0.20, green: 0.24, blue: 0.30)
        case .rest: Color(red: 0.12, green: 0.18, blue: 0.36)
        }
    }
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.06)
            RadialGradient(colors: [tint.opacity(0.85), .clear], center: .topLeading, startRadius: 10, endRadius: 360)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

struct QuoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuoteEntry

    var body: some View {
        if family == .accessoryRectangular {
            Text(entry.quote.text)
                .font(.system(.caption, design: .serif))
                .minimumScaleFactor(0.7)
        } else {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(entry.quote.text)
                        .font(.system(size: size, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                    if let author = entry.quote.author {
                        Text("— \(author)").font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Button(intent: NextQuoteIntent()) {
                    Image(systemName: "arrow.clockwise").font(.caption2.bold()).foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next quote")
            }
        }
    }

    private var size: CGFloat {
        switch family {
        case .systemSmall: 15
        case .systemLarge: 28
        default: 21
        }
    }
}
