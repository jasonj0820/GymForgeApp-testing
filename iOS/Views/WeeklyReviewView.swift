import SwiftUI

/// Sunday-night review: sessions vs goal, plan vs done, sets per muscle (direct + half for secondary
/// work), your priority muscles, and follow-up on coaching you accepted.
struct WeeklyReviewView: View {
    @EnvironmentObject private var store: PhoneAppStore
    /// 0 = the week being reviewed (this week on Sunday, otherwise last week); −1 = the one before.
    @State private var offset = 0

    var body: some View {
        let start = store.reviewWeekStart(offset: offset)
        let review = store.weeklyReview(weekStart: start)
        List {
            Section {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                    Text(weekTitle(review)).font(.headline)
                    Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.borderless)
                        .disabled(offset >= 0)
                }
                LabeledContent("Sessions", value: "\(review.sessions) / \(review.goal)")
                if review.excusedDays > 0 {
                    LabeledContent("Sick / travel days", value: "\(review.excusedDays) (goal lowered)")
                }
                if review.planned > 0 {
                    LabeledContent("Planned workouts done", value: "\(review.plannedDone) / \(review.planned)")
                }
                LabeledContent("PRs", value: "\(review.prs)")
            } footer: {
                Text(verdict(review))
            }

            Section {
                ForEach(review.muscles) { muscle in
                    muscleRow(muscle, isPriority: review.priorities.contains(muscle.id))
                }
            } header: {
                Text("Sets per muscle")
            } footer: {
                Text("Direct sets count fully; secondary work (e.g. triceps on bench press) counts as half a set. Targets: 10–20 for big muscles, 6–14 for arms. Tap the star to make a muscle a priority.")
            }

            if !review.priorities.isEmpty {
                Section("Priorities") {
                    ForEach(review.priorities, id: \.self) { muscle in
                        if let week = review.muscles.first(where: { $0.id == muscle }) {
                            let enough = week.effective >= (week.low + week.high) / 2
                            Label(enough
                                  ? "\(muscle.title): \(format(week.effective)) sets — getting the extra work."
                                  : "\(muscle.title): \(format(week.effective)) sets — a priority needs about \(format((week.low + week.high) / 2))+. Add 2–4 sets next week.",
                                  systemImage: enough ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(enough ? Color.green : Color.orange)
                                .font(.subheadline)
                        }
                    }
                }
            }

            if offset == 0 {
                let proposals = Array(store.coachProposals.prefix(3))
                if !proposals.isEmpty {
                    Section {
                        ForEach(proposals) { ProposalRow(proposal: $0) }
                    } header: {
                        Text("Suggested for next week")
                    }
                }
            }

            Section {
                if review.followUps.isEmpty {
                    Text("Nothing accepted yet. Tap \"I'll do this\" on a coaching tip (plateaus, weak points, deload) and it's followed up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(review.followUps) { follow in
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = follow.suggestion.exerciseName {
                            Text(name).font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        Text(follow.suggestion.text).font(.subheadline)
                        Label(follow.status, systemImage: follow.done ? "checkmark.circle.fill" : "clock")
                            .font(.caption)
                            .foregroundStyle(follow.done ? Color.green : Color.orange)
                    }
                    .swipeActions {
                        Button("Done with it") { store.resolveSuggestion(follow.suggestion.id) }
                            .tint(.green)
                    }
                }
            } header: {
                Text("Coaching you accepted")
            } footer: {
                if !review.followUps.isEmpty { Text("Swipe left when you're done with one.") }
            }

            Section {
                NavigationLink {
                    WeekPlanView(nextWeek: Calendar.current.component(.weekday, from: .now) == 1)
                } label: {
                    Label("Plan your week", systemImage: "calendar.badge.plus")
                }
            } footer: {
                Text("Plan rest days ahead and Sergeant Cluck stays calm on them.")
            }
        }
        .navigationTitle("Weekly review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func muscleRow(_ muscle: MuscleWeek, isPriority: Bool) -> some View {
        let color: Color = muscle.effective < muscle.low ? .orange : (muscle.effective > muscle.high ? .purple : .green)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    store.togglePriorityMuscle(muscle.id)
                } label: {
                    Image(systemName: isPriority ? "star.fill" : "star")
                        .foregroundStyle(isPriority ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                Text(muscle.id.title).font(.subheadline.bold())
                Spacer()
                Text("\(format(muscle.direct)) direct" + (muscle.secondary > 0 ? " + \(format(muscle.secondary / 2)) secondary" : ""))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(muscle.status)
                    .font(.caption.bold())
                    .foregroundStyle(color)
            }
            SwiftUI.ProgressView(value: min(muscle.effective, muscle.high), total: muscle.high)
                .tint(color)
        }
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func weekTitle(_ review: PhoneAppStore.WeeklyReview) -> String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: review.weekEnd) ?? review.weekEnd
        return review.weekStart.formatted(.dateTime.day().month()) + " – " + end.formatted(.dateTime.day().month())
    }

    private func verdict(_ review: PhoneAppStore.WeeklyReview) -> String {
        let low = review.muscles.filter { $0.effective < $0.low && $0.id != .calves && $0.id != .core }.map(\.id.title)
        var parts: [String] = []
        if review.goal > 0 {
            parts.append(review.sessions >= review.goal ? "Goal hit." : "\(review.goal - review.sessions) session\(review.goal - review.sessions == 1 ? "" : "s") short of the goal.")
        }
        if !low.isEmpty { parts.append("Under target: " + low.joined(separator: ", ") + ".") }
        if review.prs > 0 { parts.append("\(review.prs) PR\(review.prs == 1 ? "" : "s") — nice.") }
        return parts.joined(separator: " ")
    }
}
