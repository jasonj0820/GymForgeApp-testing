import SwiftUI
import Charts

struct MTStatsView: View {
    @EnvironmentObject private var vault: MTVault
    @State private var month = Date()
    @State private var selectedDay: Date?

    private struct WeekBar: Identifiable {
        let week: Date
        let type: String
        let hours: Double
        var id: String { "\(week.timeIntervalSince1970)-\(type)" }
    }

    private struct DayPoint: Identifiable {
        let day: Date
        let hours: Double
        var id: Date { day }
    }

    var body: some View {
        let sessions = vault.data.sessions
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 7 * 86_400)
        let daysThisWeek = MTStats.daysTrained(sessions, in: week)
        let target = vault.data.settings.targetDaysPerWeek
        let weekTime = sessions.filter { week.contains($0.start) }.reduce(0) { $0 + $1.duration }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    tile("Streak", "\(MTStats.streak(sessions)) days")
                    tile("This week", "\(daysThisWeek) / \(target) days")
                    tile("Time this week", MTStats.formatDuration(weekTime))
                    tile("Consistency", consistencyText(sessions))
                }

                calendarCard(sessions)
                weeklyChart(sessions)
                stretcherChart(sessions)
                pressureCharts(sessions)
                eqChart
                eqVsLoadChart(sessions)
            }
            .padding()
        }
        .navigationTitle("Progress")
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Days trained over the last 4 weeks vs the weekly target.
    private func consistencyText(_ sessions: [MTSession]) -> String {
        let end = Date()
        let start = end.addingTimeInterval(-28 * 86_400)
        let days = MTStats.daysTrained(sessions, in: DateInterval(start: start, end: end))
        let target = max(vault.data.settings.targetDaysPerWeek * 4, 1)
        return "\(Int((min(1, Double(days) / Double(target)) * 100).rounded()))%"
    }

    // MARK: Calendar

    private func calendarCard(_ sessions: [MTSession]) -> some View {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        let minutes = MTStats.minutesByDay(sessions)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    Text(ordered[index]).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(1...dayCount, id: \.self) { day in
                    let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
                    let value = minutes[calendar.startOfDay(for: date)] ?? 0
                    let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    Button {
                        selectedDay = date
                    } label: {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(value == 0 ? Color.gray.opacity(0.15) : Color.indigo.opacity(min(1, 0.35 + value / 240)))
                            .frame(height: 34)
                            .overlay(
                                Text("\(day)")
                                    .font(.caption2)
                                    .foregroundStyle(value == 0 ? Color.secondary : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let day = selectedDay {
                let daySessions = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
                Divider()
                Text(day.formatted(date: .complete, time: .omitted)).font(.subheadline.bold())
                if daySessions.isEmpty {
                    Text("No training").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(daySessions) { session in
                    HStack {
                        Label(session.type.title, systemImage: session.type.symbol)
                        Spacer()
                        Text(MTStats.formatDuration(session.duration)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func shiftMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
        selectedDay = nil
    }

    // MARK: Charts

    private func weeklyChart(_ sessions: [MTSession]) -> some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        var bars: [WeekBar] = []
        for offset in (0..<8).reversed() {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            for type in MTType.allCases {
                let hours = sessions.filter { $0.type == type && $0.start >= start && $0.start < end }
                    .reduce(0) { $0 + $1.duration } / 3600
                bars.append(WeekBar(week: start, type: type.shortTitle, hours: hours))
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Hours per week").font(.headline)
            Chart(bars) { bar in
                BarMark(x: .value("Week", bar.week, unit: .weekOfYear), y: .value("Hours", bar.hours))
                    .foregroundStyle(by: .value("Type", bar.type))
            }
            .frame(height: 220)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private struct LevelBar: Identifiable {
        let day: Date
        let level: String
        let hours: Double
        var id: String { "\(day.timeIntervalSince1970)-\(level)" }
    }

    private struct ValuePoint: Identifiable {
        let id: UUID
        let date: Date
        let series: String
        let value: Double
    }

    private func stretcherChart(_ sessions: [MTSession]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        var totals: [Date: [String: Double]] = [:]
        for session in sessions where session.type == .allDayStretcher && session.start >= start {
            let day = calendar.startOfDay(for: session.start)
            totals[day, default: [:]][session.level?.title ?? "Not set", default: 0] += session.duration / 3600
        }
        if let running = vault.data.stretcherStartedAt {
            let level = vault.data.stretcherLevel?.title ?? "Not set"
            totals[today, default: [:]][level, default: 0] += Date().timeIntervalSince(max(running, today)) / 3600
        }
        let bars: [LevelBar] = totals.flatMap { entry in
            entry.value.map { LevelBar(day: entry.key, level: $0.key, hours: $0.value) }
        }
        let average = totals.values.map { $0.values.reduce(0, +) }.reduce(0, +) / 30
        var levelHours: [String: Double] = [:]
        for bar in bars { levelHours[bar.level, default: 0] += bar.hours }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Phallosan wear — last 30 days").font(.headline)
            Chart(bars) { bar in
                BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Hours", bar.hours))
                    .foregroundStyle(by: .value("Level", bar.level))
            }
            .chartForegroundStyleScale([
                "Green": MTLevel.green.color, "High Green": MTLevel.highGreen.color,
                "Yellow": MTLevel.yellow.color, "Red": MTLevel.red.color, "Not set": Color.gray
            ])
            .frame(height: 200)
            Text(String(format: "Average %.1f h/day", average)).font(.caption).foregroundStyle(.secondary)
            ForEach(MTLevel.allCases) { level in
                if let hours = levelHours[level.title], hours > 0 {
                    HStack {
                        Circle().fill(level.color).frame(width: 10, height: 10)
                        Text(level.title)
                        Spacer()
                        Text(String(format: "%.1f h", hours)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func pressureCharts(_ sessions: [MTSession]) -> some View {
        let pressure: [ValuePoint] = sessions.compactMap { session in
            guard session.type.usesPressure, let value = session.pressureInHg else { return nil }
            return ValuePoint(id: session.id, date: session.start, series: session.type.shortTitle, value: value)
        }
        let unit = vault.data.settings.weightUnit
        let tension: [ValuePoint] = sessions.compactMap { session in
            guard session.type.usesTension, let value = session.tensionKg else { return nil }
            return ValuePoint(id: session.id, date: session.start, series: "HTE", value: unit.display(value))
        }
        if !pressure.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pressure (inHg)").font(.headline)
                Chart(pressure) { point in
                    LineMark(x: .value("Date", point.date), y: .value("inHg", point.value))
                        .foregroundStyle(by: .value("Type", point.series))
                    PointMark(x: .value("Date", point.date), y: .value("inHg", point.value))
                        .foregroundStyle(by: .value("Type", point.series))
                }
                .chartForegroundStyleScale(["Pump": Color.indigo, "PAC": Color.yellow])
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        if !tension.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Extender tension (\(unit.rawValue))").font(.headline)
                Chart(tension) { point in
                    LineMark(x: .value("Date", point.date), y: .value(unit.rawValue, point.value))
                    PointMark(x: .value("Date", point.date), y: .value(unit.rawValue, point.value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var eqChart: some View {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: .now) ?? .now
        let checkIns = vault.data.checkInList.filter { $0.day >= start }
        let points: [ValuePoint] = checkIns.compactMap { checkIn in
            checkIn.eq.map { ValuePoint(id: checkIn.id, date: checkIn.day, series: "EQ", value: Double($0)) }
        }
        if !points.isEmpty {
            let wood = checkIns.compactMap(\.morningWood)
            VStack(alignment: .leading, spacing: 8) {
                Text("EQ — last 60 days").font(.headline)
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("EQ", point.value))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("EQ", point.value))
                }
                .chartYScale(domain: 1.0...5.0)
                .frame(height: 160)
                if !wood.isEmpty {
                    Text("Morning wood on \(wood.filter { $0 }.count) of \(wood.count) check-ins")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: EQ vs training load

    private struct DayLoad: Identifiable {
        let day: Date
        let ads: Double      // weighted ADS hours
        let intense: Double  // extender / pump / clamp / PAC hours
        var id: Date { day }
        var total: Double { ads + intense }
    }

    private struct DayEQ: Identifiable {
        let day: Date
        let eq: Double
        var id: Date { day }
    }

    /// Daily training load (bars) above the EQ check-ins (line), same 30 days, plus how EQ
    /// looks the morning after heavy vs light days.
    @ViewBuilder
    private func eqVsLoadChart(_ sessions: [MTSession]) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days: [Date] = (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let loads: [DayLoad] = days.map { day in
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let todays = sessions.filter { $0.start >= day && $0.start < end }
            let ads = todays.filter { $0.type == .allDayStretcher }
                .reduce(0.0) { $0 + $1.duration / 3600 * ($1.level?.weight ?? 1) }
            let intense = todays.filter { $0.type != .allDayStretcher }.reduce(0.0) { $0 + $1.duration / 3600 }
            return DayLoad(day: day, ads: ads, intense: intense)
        }
        let eqs: [DayEQ] = vault.data.checkInList.compactMap { checkIn in
            guard let eq = checkIn.eq, checkIn.day >= (days.first ?? today) else { return nil }
            return DayEQ(day: calendar.startOfDay(for: checkIn.day), eq: Double(eq))
        }
        let domain = (days.first ?? today)...(calendar.date(byAdding: .day, value: 1, to: today) ?? today)

        if !eqs.isEmpty && loads.contains(where: { $0.total > 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("EQ vs training load — 30 days").font(.headline)
                Chart {
                    ForEach(loads) { load in
                        BarMark(x: .value("Day", load.day, unit: .day), y: .value("Hours", load.ads))
                            .foregroundStyle(by: .value("Type", "ADS (weighted h)"))
                        BarMark(x: .value("Day", load.day, unit: .day), y: .value("Hours", load.intense))
                            .foregroundStyle(by: .value("Type", "Extender / pump / PAC (h)"))
                    }
                }
                .chartForegroundStyleScale(["ADS (weighted h)": Color.indigo, "Extender / pump / PAC (h)": Color.orange])
                .chartXScale(domain: domain)
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 130)
                Chart(eqs) { point in
                    LineMark(x: .value("Day", point.day, unit: .day), y: .value("EQ", point.eq))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.pink)
                    PointMark(x: .value("Day", point.day, unit: .day), y: .value("EQ", point.eq))
                        .foregroundStyle(Color.pink)
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 1.0...5.0)
                .frame(height: 110)
                Text(morningAfterText(loads: loads, eqs: eqs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Average EQ the morning after heavier-than-usual days vs lighter days.
    private func morningAfterText(loads: [DayLoad], eqs: [DayEQ]) -> String {
        let calendar = Calendar.current
        var pairs: [(load: Double, eq: Double)] = []
        for point in eqs {
            guard let before = calendar.date(byAdding: .day, value: -1, to: point.day),
                  let load = loads.first(where: { calendar.isDate($0.day, inSameDayAs: before) }) else { continue }
            pairs.append((load.total, point.eq))
        }
        guard pairs.count >= 6 else { return "Check in on more mornings to see how training load affects EQ." }
        let sortedLoads = pairs.map { $0.load }.sorted()
        let median = sortedLoads[sortedLoads.count / 2]
        let heavy = pairs.filter { $0.load > median }.map { $0.eq }
        let light = pairs.filter { $0.load <= median }.map { $0.eq }
        guard !heavy.isEmpty, !light.isEmpty else { return "Load has been very even — nothing to compare yet." }
        let heavyAvg = heavy.reduce(0, +) / Double(heavy.count)
        let lightAvg = light.reduce(0, +) / Double(light.count)
        let base = String(format: "EQ the morning after heavier days: %.1f · after lighter days: %.1f.", heavyAvg, lightAvg)
        if lightAvg - heavyAvg >= 0.4 {
            return base + " Heavy days are costing you EQ — add a rest day or ease the intensity."
        }
        return base + " No sign that training is hurting EQ."
    }
}

