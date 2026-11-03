import SwiftUI

/// A year of training at a glance: one square per day, coloured by the session's code
/// (CH / B / U / L / CA), grey for marked rest days.
struct YearHeatmapView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var selected: Date?

    static func color(for code: String) -> Color {
        switch code.prefix(2) {
        case "CH": return .red
        case "B", "B+": return .blue
        case "U", "U+": return .purple
        case "L", "L+": return .green
        case "CA": return .orange
        default: return .teal
        }
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }

    var body: some View {
        let cal = calendar
        let today = cal.startOfDay(for: .now)
        let weeks = 53
        let thisMonday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today) ?? today
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisMonday) ?? today
        let byDay = Dictionary(grouping: store.workoutLogs.filter { $0.startedAt >= start }) { cal.startOfDay(for: $0.startedAt) }
        let rest = Set(store.extras.restDays.map { cal.startOfDay(for: $0) })
        let total = byDay.keys.count

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 12 months").font(.headline)
                Spacer()
                Text("\(total) training days").font(.subheadline).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(0..<weeks, id: \.self) { week in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { weekday in
                                    let day = cal.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                                    cell(day: day, logs: byDay[day] ?? [], rest: rest.contains(day), future: day > today)
                                }
                            }
                            .id(week)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(weeks - 1, anchor: .trailing) }
            }
            if let selected {
                let logs = byDay[selected] ?? []
                let detail: String = logs.isEmpty
                    ? (rest.contains(selected) ? "rest day" : "no training")
                    : logs.map(\.routineName).joined(separator: ", ")
                Text(selected.formatted(date: .abbreviated, time: .omitted) + ": " + detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            legend
            splitBalance(byDay.values.flatMap { $0 })
        }
        .card()
    }

    @ViewBuilder
    private func cell(day: Date, logs: [WorkoutLog], rest: Bool, future: Bool) -> some View {
        let code = logs.isEmpty ? "" : GymWeekRow.label(for: logs)
        RoundedRectangle(cornerRadius: 3)
            .fill(future ? Color.clear : (logs.isEmpty ? (rest ? Color.gray.opacity(0.45) : Color.secondary.opacity(0.12)) : Self.color(for: code)))
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(selected == day ? Color.primary : Color.clear, lineWidth: 1.5))
            .onTapGesture { if !future { selected = selected == day ? nil : day } }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(["CH", "B", "U", "L", "CA"], id: \.self) { code in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Self.color(for: code)).frame(width: 10, height: 10)
                    Text(code).font(.caption2.bold())
                }
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.45)).frame(width: 10, height: 10)
                Text("Rest").font(.caption2.bold())
            }
        }
    }

    /// How many sessions of each type over the year — shows if one day keeps getting skipped.
    private func splitBalance(_ logs: [WorkoutLog]) -> some View {
        let counts = Dictionary(grouping: logs) { GymWeekRow.code(for: $0) }.mapValues(\.count)
        let ordered = ["CH", "B", "U", "L", "CA"].filter { counts[$0] != nil } + counts.keys.filter { !["CH", "B", "U", "L", "CA"].contains($0) }.sorted()
        return HStack(spacing: 12) {
            ForEach(ordered, id: \.self) { code in
                VStack(spacing: 2) {
                    Text("\(counts[code] ?? 0)").font(.subheadline.bold().monospacedDigit())
                    Text(code).font(.caption2).foregroundStyle(Self.color(for: code))
                }
            }
        }
    }
}
