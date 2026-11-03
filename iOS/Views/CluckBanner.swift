import SwiftUI

/// Sergeant Cluck on Today, above the week row. Re-checks every minute so he turns
/// angry at 5:10pm while the app is open too.
struct CluckBanner: View {
    let snapshot: CluckSnapshot
    let onSnooze: () -> Bool
    @State private var snoozeReply: String?
    @State private var snoozeReplyDay: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let state = CluckEngine.evaluate(snapshot, at: context.date)
            HStack(alignment: .center, spacing: 12) {
                CluckView(mood: state.mood, animated: true)
                    .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Sergeant Cluck").font(.caption.bold())
                        Text(state.mood.title.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(state.mood.tint.opacity(0.3)))
                    }
                    Text(reply(on: context.date) ?? CluckEngine.line(state, at: context.date))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    // MK11: his read on your gym pattern (missed weekdays, gaps, shrinking sessions).
                    if let pattern = state.patternLine, state.mood != .suspicious {
                        Label(pattern, systemImage: "binoculars.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showsSnooze(state) {
                        Button("Not today (1 per week)") {
                            snoozeReply = onSnooze()
                                ? "Fine. Take your day. I'll remember this."
                                : "You already used this week's snooze. Nice try."
                            snoozeReplyDay = context.date
                        }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)
                        .tint(state.mood.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(state.mood.tint.opacity(0.12)))
        }
    }

    /// The snooze reply only shows on the day you snoozed.
    private func reply(on date: Date) -> String? {
        guard let snoozeReply, let day = snoozeReplyDay, Calendar.current.isDate(day, inSameDayAs: date) else { return nil }
        return snoozeReply
    }

    private func showsSnooze(_ state: CluckState) -> Bool {
        state.snoozeAvailable && [.watching, .annoyed, .furious, .doomed, .suspicious].contains(state.mood)
    }
}
