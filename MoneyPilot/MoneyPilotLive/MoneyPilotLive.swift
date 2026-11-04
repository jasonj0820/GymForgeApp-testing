import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let mint = Color(red: 0.36, green: 0.92, blue: 0.83)
private let ink = Color(red: 0.035, green: 0.065, blue: 0.09)

@main struct MoneyPilotLiveBundle: WidgetBundle {
    var body: some Widget {
        MoneyLiveActivity()
        ShoppingWidget()
    }
}
struct MoneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MoneyActivityAttributes.self) { context in
            Group {
                if let status = context.state.status, !context.isStale { StatusLiveView(text: status) }
                else if let step = context.state.currentTransfer { TransferLiveView(state: context.state, step: step) }
                else if context.state.payKind != nil { PayLiveView(state: context.state) } else { LockScreenView(state: context.state) }
            }
                .activityBackgroundTint(ink.opacity(0.92))
                .activitySystemActionForegroundColor(mint)
        } dynamicIsland: { context in
            let s = context.state
            if let status = s.status, !context.isStale { return statusIsland(status) } // Stale = MoneyPilot was paused mid sign-in.
            if let step = s.currentTransfer { return transferIsland(s, step) }
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spare money").font(.caption2).foregroundStyle(.secondary)
                        Text(wholeDollars(s.spare)).font(.title2.bold()).foregroundStyle(mint).contentTransition(.numericText())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Takeaway left").font(.caption2).foregroundStyle(.secondary)
                        Text(wholeDollars(s.takeawayLeft)).font(.headline)
                        Text("\(s.daysLeft) day\(s.daysLeft == 1 ? "" : "s") left").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.payKind != nil { PaySplitText(state: s) } else { VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: min(1, s.weekUsed)).tint(s.weekUsed > 0.9 ? .orange : mint)
                        NextChargeText(state: s)
                    } }
                }
            } compactLeading: {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(mint)
            } compactTrailing: {
                Text(s.payKind == nil ? wholeDollars(s.spare) : s.paySavings.map { "Save \(wholeDollars($0))" } ?? "Pay?").font(.caption.bold()).foregroundStyle(mint).monospacedDigit()
            } minimal: {
                Gauge(value: min(1, s.weekUsed)) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(mint)
            }
        }
    }
}
struct LockScreenView: View {
    let state: MoneyActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 16) {
            Gauge(value: min(1, state.weekUsed)) { Text("Week") } currentValueLabel: { Text("\(Int(min(1, state.weekUsed) * 100))%") }
                .gaugeStyle(.accessoryCircularCapacity).tint(state.weekUsed > 0.9 ? .orange : mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("SPARE MONEY").font(.caption2.bold()).foregroundStyle(mint)
                Text(wholeDollars(state.spare)).font(.system(size: 30, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text("Takeaway \(wholeDollars(state.takeawayLeft)) left · \(state.daysLeft) day\(state.daysLeft == 1 ? "" : "s") to go").font(.caption).foregroundStyle(.secondary)
                NextChargeText(state: state)
            }
            Spacer(minLength: 0)
        }
        .padding(16).foregroundStyle(.white)
    }
}
struct NextChargeText: View {
    let state: MoneyActivityAttributes.ContentState
    var body: some View {
        if let name = state.nextName, let amount = state.nextAmount, let date = state.nextDate {
            Text("Next: \(name) \(wholeDollars(amount)) · \(date.formatted(.dateTime.weekday(.abbreviated).day()))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

// MARK: Home Screen and Lock Screen widget
struct ShoppingEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot? }
struct ShoppingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShoppingEntry { ShoppingEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (ShoppingEntry) -> Void) {
        completion(ShoppingEntry(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshot.load() ?? .preview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShoppingEntry>) -> Void) {
        // The app reloads the widget whenever its numbers change; the hourly refresh keeps "updated" current.
        completion(Timeline(entries: [ShoppingEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .after(Date().addingTimeInterval(3_600))))
    }
}
struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShoppingMoney", provider: ShoppingProvider()) { entry in
            ShoppingWidgetView(entry: entry).containerBackground(ink, for: .widget)
        }
        .configurationDisplayName("Spare money")
        .description("What you can spend on shopping right now, after savings, bills and Afterpay.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
struct ShoppingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShoppingEntry
    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryInline:
                Text("Shopping \(wholeDollars(s.shoppingLeft)) left")
            case .accessoryCircular:
                Gauge(value: max(0, 1 - min(1, s.shoppingUsed))) { Image(systemName: "bag.fill") } currentValueLabel: { Text(shortDollars(s.shoppingLeft)) }
                    .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Shopping", systemImage: "bag.fill").font(.caption2.bold())
                    Text(wholeDollars(s.shoppingLeft)).font(.title3.bold()).widgetAccentable()
                    ProgressView(value: min(1, max(0, s.shoppingUsed)))
                }
            case .systemMedium:
                HStack(spacing: 18) {
                    shopping(s)
                    Divider().overlay(Color.white.opacity(0.15))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TAKEAWAY LEFT").font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(wholeDollars(s.takeawayLeft)).font(.title2.bold())
                        Text("\(s.daysLeft) day\(s.daysLeft == 1 ? "" : "s") left in the \(s.period ?? "week")").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        updated(s)
                    }
                }.foregroundStyle(.white)
            default:
                VStack(alignment: .leading, spacing: 0) { shopping(s); Spacer(minLength: 0); updated(s) }.foregroundStyle(.white)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "bag.fill").foregroundStyle(mint)
                Text("Open MoneyPilot to show your shopping money.").font(.caption)
            }.foregroundStyle(.white)
        }
    }
    private func shopping(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("SPARE MONEY", systemImage: "bag.fill").font(.caption2.bold()).foregroundStyle(mint)
            Text(wholeDollars(s.shoppingLeft)).font(.system(size: 30, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                .contentTransition(.numericText())
            ProgressView(value: min(1, max(0, s.shoppingUsed))).tint(s.shoppingUsed >= 0.9 ? .orange : mint)
            if s.shoppingLimit > 0 { Text("\(wholeDollars(s.shoppingLimit)) shopping limit").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func updated(_ s: WidgetSnapshot) -> some View {
        Text("Updated \(s.updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 9)).foregroundStyle(.secondary)
    }
}
/// Compact amount for the small round Lock Screen widget, e.g. $84 or $1.2k.
func shortDollars(_ cents: Int64) -> String {
    let dollars = Double(cents) / 100
    return dollars >= 1_000 ? "$\((dollars / 1_000).formatted(.number.precision(.fractionLength(1))))k" : "$\(Int(dollars))"
}

// MARK: Payday on the Lock Screen
struct PayLiveView: View {
    let state: MoneyActivityAttributes.ContentState
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: state.payAmount == nil ? "banknote" : "checkmark.seal.fill").font(.title).foregroundStyle(mint)
            VStack(alignment: .leading, spacing: 4) {
                Text((state.payKind ?? "Payday").uppercased()).font(.caption2.bold()).foregroundStyle(mint)
                if let amount = state.payAmount {
                    Text(wholeDollars(amount)).font(.system(size: 26, weight: .bold, design: .rounded))
                }
                PaySplitText(state: state)
            }
            Spacer(minLength: 0)
        }.padding(16).foregroundStyle(.white)
    }
}
struct PaySplitText: View {
    let state: MoneyActivityAttributes.ContentState
    var body: some View {
        if let save = state.paySavings, let invest = state.payInvest, let spend = state.paySpend {
            VStack(alignment: .leading, spacing: 2) {
                Text("Move \(wholeDollars(save)) to savings").font(.subheadline.bold())
                Text("Move \(wholeDollars(invest)) to investing").font(.subheadline.bold())
                Text("\(wholeDollars(spend)) is yours to spend").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Open MoneyPilot and enter what you received to see where it goes.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Signing in to PocketSmith
struct StatusLiveView: View {
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "building.columns.fill").font(.title2).foregroundStyle(mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("POCKETSMITH").font(.caption2.bold()).foregroundStyle(mint)
                Text(text).font(.headline)
            }
            Spacer(minLength: 0)
        }.padding(16).foregroundStyle(.white)
    }
}
func statusIsland(_ text: String) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) { Label(text, systemImage: "building.columns.fill").font(.headline).foregroundStyle(mint) }
    } compactLeading: {
        Image(systemName: "building.columns.fill").foregroundStyle(mint)
    } compactTrailing: {
        Text(text).font(.caption.bold()).foregroundStyle(mint).lineLimit(1).frame(maxWidth: 90)
    } minimal: {
        Image(systemName: "building.columns.fill").foregroundStyle(mint)
    }
}

// MARK: Transfer now
extension MoneyActivityAttributes.ContentState {
    var currentTransfer: MoneyActivityAttributes.TransferStep? {
        guard let steps = transfers, let i = step, steps.indices.contains(i) else { return nil }
        return steps[i]
    }
}
func transferIsland(_ s: MoneyActivityAttributes.ContentState, _ step: MoneyActivityAttributes.TransferStep) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Transfer").font(.caption2).foregroundStyle(.secondary)
                Text(wholeDollarsAndCents(step.amount)).font(.title2.bold()).foregroundStyle(mint)
            }
        }
        DynamicIslandExpandedRegion(.trailing) {
            Text("\((s.step ?? 0) + 1) of \(s.transfers?.count ?? 1)").font(.caption).foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.bottom) {
            HStack {
                Text("\(step.from) → \(step.to)").font(.headline).lineLimit(1)
                Spacer()
                Button(intent: NextTransferIntent()) { Label("Done", systemImage: "checkmark") }.tint(mint)
            }
        }
    } compactLeading: {
        Image(systemName: "arrow.left.arrow.right").foregroundStyle(mint)
    } compactTrailing: {
        Text(wholeDollarsAndCents(step.amount)).font(.caption.bold()).foregroundStyle(mint).monospacedDigit()
    } minimal: {
        Image(systemName: "arrow.left.arrow.right").foregroundStyle(mint)
    }
}
func wholeDollarsAndCents(_ cents: Int64) -> String { (Double(cents) / 100).formatted(.currency(code: "AUD")) }
struct TransferLiveView: View {
    let state: MoneyActivityAttributes.ContentState
    let step: MoneyActivityAttributes.TransferStep
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSFER \((state.step ?? 0) + 1) OF \(state.transfers?.count ?? 1)").font(.caption2.bold()).foregroundStyle(mint)
                Spacer()
                Text("Amount copied").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(wholeDollarsAndCents(step.amount)).font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button(intent: NextTransferIntent()) { Label("Done", systemImage: "checkmark") }.tint(mint)
            }
            Text("From \(step.from) to \(step.to)").font(.headline)
            if let steps = state.transfers, (state.step ?? 0) + 1 < steps.count {
                Text("Then: " + steps[((state.step ?? 0) + 1)...].map { "\(wholeDollarsAndCents($0.amount)) \($0.from) → \($0.to)" }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(16).foregroundStyle(.white)
    }
}
