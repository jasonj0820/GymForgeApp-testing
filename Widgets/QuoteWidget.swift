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
        WidgetCenter.shared.reloadTimelines(ofKind: MTWidgetStore.kind)   // MK20.6: its quote too
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

/// MK20.2: a frosted, matte "glass" panel behind the quote — a light smoked tint, a soft top sheen
/// and a hairline edge, so the text reads easily without the panel looking glossy or see-through.
struct MatteGlassPanel: View {
    var cornerRadius: CGFloat
    /// MK20.2.1: 30% more see-through than the first version (1.0 = original).
    static let strength = 0.7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let k = Self.strength
        shape
            .fill(.black.opacity(0.26 * k))                       // smoked matte body
            .overlay(shape.fill(.white.opacity(0.06 * k)))          // frost lift, keeps it from looking like a hole
            .overlay(                                           // soft light from the top, fading out — matte, no hard shine
                shape.fill(LinearGradient(colors: [.white.opacity(0.10 * k), .white.opacity(0.0)],
                                          startPoint: .top, endPoint: .center))
            )
            .overlay(                                           // hairline glass edge, brighter on top
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28 * k), .white.opacity(0.06 * k), .white.opacity(0.12 * k)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.25 * k), radius: 8, y: 3)
    }
}

struct QuoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: QuoteEntry

    var body: some View {
        if family == .accessoryRectangular {
            // Lock Screen: the system's frosted backdrop, a bit more see-through, behind the quote.
            Text(entry.quote.text)
                .font(.system(.caption, design: .serif))
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                    ZStack {
                        AccessoryWidgetBackground()
                        shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5)   // hairline glass edge
                    }
                    .clipShape(shape)
                    .opacity(MatteGlassPanel.strength)
                }
        } else {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(entry.quote.text)
                        .font(.system(size: size, weight: .regular, design: .serif))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    if let author = entry.quote.author {
                        Text("— \(author)").font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, panelPadding)
                .padding(.vertical, panelPadding * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    // Full colour only: tinted / clear Home Screens already draw their own glass.
                    if renderingMode == .fullColor { MatteGlassPanel(cornerRadius: cornerRadius) }
                }
                Button(intent: NextQuoteIntent()) {
                    Image(systemName: "arrow.clockwise").font(.caption2.bold()).foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Next quote")
            }
            .padding(family == .systemSmall ? -6 : -4)   // let the panel use a little of the widget margin
        }
    }

    private var size: CGFloat {
        switch family {
        case .systemSmall: 15
        case .systemLarge: 28
        default: 21
        }
    }
    private var panelPadding: CGFloat { family == .systemSmall ? 8 : 14 }
    private var cornerRadius: CGFloat { family == .systemSmall ? 14 : 18 }
}

// MARK: - More Training widget (MK20.6)

/// For StandBy (and the Home Screen): the More Training timer with Pause / Skip / Next while one runs,
/// otherwise the motivation quote.
struct MTTrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MTWidgetStore.kind, provider: MTTrainingProvider()) { entry in
            MTTrainingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    if entry.timer != nil {
                        LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.14), .black],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        QuoteBackground(topic: entry.quote.topic)
                    }
                }
        }
        .configurationDisplayName("More Training")
        .description("Your More Training timer with Pause, Skip and Next while it runs; a motivation quote the rest of the time. Made for StandBy.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MTTrainingEntry: TimelineEntry {
    let date: Date
    let quote: Quote
    /// Set while a timer runs.
    var timer: Running?

    struct Running {
        var step: MTWidgetSnapshot.Step
        var program: String?
        var controls: [MTWidgetSnapshot.Control]
        var needsApp: Bool
    }
}

struct MTTrainingProvider: TimelineProvider {
    func placeholder(in context: Context) -> MTTrainingEntry { MTTrainingEntry(date: .now, quote: QuoteLibrary.all[0]) }

    func getSnapshot(in context: Context, completion: @escaping (MTTrainingEntry) -> Void) {
        completion(entries(now: .now).first ?? MTTrainingEntry(date: .now, quote: QuoteSettings.widgetQuote()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MTTrainingEntry>) -> Void) {
        MTWidgetStore.widgetCheckedIn()
        completion(Timeline(entries: entries(now: .now), policy: .atEnd))
    }

    /// Timer running: one entry per upcoming phase, then quotes after it ends. Otherwise quotes every 5 min.
    private func entries(now: Date) -> [MTTrainingEntry] {
        func quotes(from start: Date, count: Int) -> [MTTrainingEntry] {
            (0..<count).map { i in
                let date = start.addingTimeInterval(Double(i * 5 * 60))
                return MTTrainingEntry(date: date, quote: QuoteSettings.widgetQuote(at: date))
            }
        }
        guard let snapshot = MTWidgetStore.current(now: now), !snapshot.steps.isEmpty,
              snapshot.endsAt.map({ $0 > now }) ?? true else {
            return quotes(from: now, count: 48)
        }
        // The step showing now is the last one that has started.
        let current = snapshot.steps.lastIndex { $0.date <= now } ?? 0
        var result = snapshot.steps[current...].map { step in
            MTTrainingEntry(date: max(step.date, now), quote: QuoteSettings.widgetQuote(at: step.date),
                            timer: .init(step: step, program: snapshot.program, controls: snapshot.controls, needsApp: snapshot.needsApp))
        }
        if let ends = snapshot.endsAt { result += quotes(from: ends, count: 24) }
        return result
    }
}

struct MTTrainingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MTTrainingEntry

    var body: some View {
        if let timer = entry.timer {
            timerView(timer)
                .widgetURL(MTTimerLiveActivity.openURL)
        } else {
            QuoteWidgetView(entry: QuoteEntry(date: entry.date, quote: entry.quote))
        }
    }

    private func timerView(_ timer: MTTrainingEntry.Running) -> some View {
        let state = timer.step.state
        let small = family == .systemSmall
        return VStack(alignment: .leading, spacing: small ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(timer.step.title)
                        .font(small ? .headline : .title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(state.pausedRemaining != nil ? "Paused · \(state.label)" : state.label)
                        .font(.caption)
                        .foregroundStyle(.indigo)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !small, let program = timer.program {
                    Text(program).font(.caption2).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            MTTimerClock(state: state, stale: false)
                .font(.system(size: small ? 38 : 46, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if !small, let next = state.next {
                Text(next).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if timer.needsApp {
                Text("Open the app to control the timer").font(.caption2).foregroundStyle(.orange)
            } else {
                HStack(spacing: small ? 6 : 8) {
                    ForEach(timer.controls, id: \.self) { control in
                        Button(intent: MTWidgetControlIntent(MTWidgetAction(rawValue: control.action) ?? .pause)) {
                            Group {
                                if small {
                                    Image(systemName: control.icon)
                                } else {
                                    Label(control.label, systemImage: control.icon)
                                }
                            }
                            .font(.caption.bold())
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: small ? 30 : 34)
                            .background(.white.opacity(0.14), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(control.label)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
