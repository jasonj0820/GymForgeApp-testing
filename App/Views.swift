import SwiftUI

// MARK: - Calendar

struct CalendarView: View {
    @EnvironmentObject var model: Model
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editing: Block?
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            // Redrawn each minute so "Now" and "Missed" move along while the app sits open.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(now: context.date)
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !Calendar.current.isDateInToday(day) {
                        Button("Today") { day = Calendar.current.startOfDay(for: .now) }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Remind me when a block opens", isOn: $model.remind)
                        Toggle("Turn Focus on with a block", isOn: $model.useFocus)
                        Button("Focus setup", systemImage: "moon") { showSetup = true }
                        Section("Widget storage") {
                            Text(SharedGroup.status)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Settings")
                    Button {
                        editing = Block(title: "", start: newStart, minutes: 150, focusMinutes: 120)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New block")
                }
            }
            .sheet(item: $editing) { BlockEditor(block: $0).environmentObject(model) }
            .sheet(isPresented: $showSetup) { FocusSetupView().environmentObject(model) }
            .fullScreenCover(isPresented: .constant(model.active != nil)) { TimerView().environmentObject(model) }
        }
    }

    private func content(now: Date) -> some View {
        let blocks = dayBlocks(model.blocks, on: day)
        let isToday = Calendar.current.isDate(day, inSameDayAs: now)
        return VStack(spacing: 0) {
            WeekStrip(day: $day, blocks: model.blocks, now: now)
            List {
                Section {
                    WeekSummary(stats: weekStats(model.blocks, containing: day, now: now), streak: streak(model.blocks, today: now))
                }
                if blocks.isEmpty {
                    Section { emptyDay }
                } else {
                    Section {
                        ForEach(blocks) { block in
                            row(block, now: now, canStart: isToday && block.outcome == nil && model.active == nil)
                        }
                    } footer: {
                        Text("Tap a block to edit it. Swipe right to tick it off without the timer.")
                    }
                }
            }
        }
    }

    private func row(_ block: Block, now: Date, canStart: Bool) -> some View {
        BlockRow(block: block, now: now, onStart: canStart ? { model.start(block) } : nil)
            .contentShape(Rectangle())
            .onTapGesture { editing = block }
            .accessibilityAddTraits(.isButton)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if block.outcome == nil {
                    Button("Full") { model.mark(block, .full) }.tint(.green)
                    Button("Minimum") { model.mark(block, .minimum) }.tint(.orange)
                } else {
                    Button("Untick") { model.mark(block, nil) }.tint(.gray)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive) { model.delete(block) }
                Button("Next week") { model.copy(block, byDays: 7) }.tint(.blue)
            }
            .contextMenu {
                if canStart {
                    Button("Start", systemImage: "play.fill") { model.start(block) }
                }
                if block.outcome == nil {
                    Button("Tick off: full", systemImage: "bolt.fill") { model.mark(block, .full) }
                    Button("Tick off: minimum", systemImage: "leaf.fill") { model.mark(block, .minimum) }
                } else {
                    Button("Untick", systemImage: "arrow.uturn.backward") { model.mark(block, nil) }
                }
                Button("Copy to tomorrow", systemImage: "plus.square.on.square") { model.copy(block, byDays: 1) }
                Button("Copy to next week", systemImage: "calendar.badge.plus") { model.copy(block, byDays: 7) }
                Button("Delete", systemImage: "trash", role: .destructive) { model.delete(block) }
            }
    }

    /// Nothing planned: add one, or lay out the same weekday as last week.
    private var emptyDay: some View {
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: day) ?? day
        let previous = dayBlocks(model.blocks, on: lastWeek)
        return VStack(spacing: 10) {
            Image(systemName: "calendar").font(.largeTitle).foregroundStyle(.secondary)
            Text("Nothing planned").font(.headline)
            Text("Tap + to add a block.").font(.subheadline).foregroundStyle(.secondary)
            if !previous.isEmpty {
                Button("Copy last \(day.formatted(.dateTime.weekday(.wide)))'s \(previous.count) block\(previous.count == 1 ? "" : "s")") {
                    model.copyDay(from: lastWeek, to: day)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// New blocks start after the day's last block (or 9am).
    private var newStart: Date {
        dayBlocks(model.blocks, on: day).last?.end
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}

/// The week at a glance: focus time, blocks done, minimums, streak.
struct WeekSummary: View {
    let stats: WeekStats
    let streak: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tile(durationText(stats.focusMinutes), "focused")
            tile("\(stats.done) of \(stats.planned)", "blocks done")
            tile("\(stats.minimum)", stats.minimum == 1 ? "minimum" : "minimums")
            tile("\(streak)", streak == 1 ? "day streak" : "days streak")
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeekStrip: View {
    @Binding var day: Date
    let blocks: [Block]
    let now: Date

    private var week: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").padding(8) }
                .accessibilityLabel("Previous week")
            ForEach(week, id: \.self) { d in
                let selected = Calendar.current.isDate(d, inSameDayAs: day)
                VStack(spacing: 4) {
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    Text(d.formatted(.dateTime.day()))
                        .font(.callout.weight(selected ? .bold : .regular))
                        .frame(width: 34, height: 34)
                        .background(selected ? Color.accentColor : .clear, in: Circle())
                        .foregroundStyle(selected ? Color.white : Calendar.current.isDateInToday(d) ? Color.accentColor : .primary)
                    Circle().fill(dot(d)).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { day = d }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right").padding(8) }
                .accessibilityLabel("Next week")
        }
        .padding(.vertical, 8)
    }

    /// Green = everything ticked off, red = something missed, grey = still to do, none = nothing planned.
    private func dot(_ d: Date) -> Color {
        let planned = dayBlocks(blocks, on: d)
        if planned.isEmpty { return .clear }
        if planned.allSatisfy({ $0.outcome != nil }) { return .green }
        if planned.contains(where: { $0.isMissed(at: now) }) { return .red }
        return .secondary
    }

    private func shift(_ days: Int) { day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day }
}

struct BlockRow: View {
    let block: Block
    let now: Date
    /// nil = can't be started from here (done, another day, or a timer is already running).
    let onStart: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(block.start, style: .time).font(.subheadline.monospacedDigit())
                Text(block.end, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.headline).strikethrough(block.outcome != nil)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if !block.fullTask.isEmpty { Label(block.fullTask, systemImage: "bolt.fill").font(.caption) }
                if !block.minTask.isEmpty {
                    Label(block.minTask, systemImage: "leaf.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let badge {
                    Text(badge).font(.caption.bold()).foregroundStyle(color)
                }
                if let onStart {
                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        if block.outcome != nil, let ran = block.focusedMinutes {
            return "\(durationText(ran)) focused of \(durationText(block.focus))"
        }
        if block.startBy > block.start {
            return "\(durationText(block.focus)) focus · start by \(block.startBy.formatted(date: .omitted, time: .shortened))"
        }
        return "\(durationText(block.focus)) focus"
    }

    private var badge: String? {
        switch block.outcome {
        case .full?: return "Full"
        case .minimum?: return "Min"
        case nil: return block.isMissed(at: now) ? "Missed" : (block.isOpen(at: now) ? "Now" : nil)
        }
    }

    private var color: Color {
        switch block.outcome {
        case .full?: return .green
        case .minimum?: return .orange
        case nil: return block.isMissed(at: now) ? .red : .accentColor
        }
    }
}

// MARK: - Editor

struct BlockEditor: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State var block: Block

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject, e.g. Steel design", text: $block.title)
                Section {
                    DatePicker("From", selection: $block.start)
                    DatePicker("Until", selection: windowEnd, in: block.start.addingTimeInterval(15 * 60)...,
                               displayedComponents: .hourAndMinute)
                    Stepper("Focus: \(durationText(block.focus))", value: focus, in: 15...max(15, block.minutes), step: 15)
                } footer: {
                    Text(block.startBy > block.start
                         ? "Start anytime before \(block.startBy.formatted(date: .omitted, time: .shortened)) and do \(durationText(block.focus)) without stopping."
                         : "The focus fills the whole window, so start on time.")
                }
                Section("Full version (100%)") {
                    TextField("e.g. Timed past paper + marking", text: $block.fullTask, axis: .vertical)
                }
                Section("Minimum version (still counts)") {
                    TextField("e.g. One revision lecture", text: $block.minTask, axis: .vertical)
                }
                if !isNew {
                    Section("Result") {
                        Picker("Ticked off", selection: $block.outcome) {
                            Text("Not yet").tag(Block.Outcome?.none)
                            Text("Full").tag(Block.Outcome?.some(.full))
                            Text("Minimum").tag(Block.Outcome?.some(.minimum))
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        Button("Copy to tomorrow") { model.copy(block, byDays: 1); dismiss() }
                        Button("Copy to next week") { model.copy(block, byDays: 7); dismiss() }
                        Button("Delete block", role: .destructive) { model.delete(block); dismiss() }
                    }
                }
            }
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if block.outcome == nil { block.focusedMinutes = nil }
                        model.save(block)
                        dismiss()
                    }
                    .disabled(block.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    /// Moving "Until" resizes the window; the focus target shrinks with it if it no longer fits.
    private var windowEnd: Binding<Date> {
        Binding(get: { block.end }, set: { block.minutes = max(15, Int($0.timeIntervalSince(block.start) / 60)) })
    }

    private var focus: Binding<Int> {
        Binding(get: { block.focus }, set: { block.focusMinutes = $0 })
    }

    private var isNew: Bool { !model.blocks.contains { $0.id == block.id } }
}

// MARK: - Focus setup

/// The one-time Shortcuts setup, in the app instead of only in the README.
struct FocusSetupView: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Turn Focus on with a block", isOn: $model.useFocus)
                } footer: {
                    Text("Starting a block runs a Shortcut that turns your Focus on until the focus time ends; stopping early runs a second one that turns it off. Off = a block is just a timer and Shortcuts never opens.")
                }
                Section("First, a Focus") {
                    Text("Settings → Focus → make one (e.g. \"Study\") and choose what it silences.")
                }
                Section("Shortcut 1: \(Links.focusOn)") {
                    Text("1. Shortcuts → + → name it exactly \"\(Links.focusOn)\".")
                    Text("2. Add **Adjust Date**: add *Shortcut Input* minutes to *Current Date*.")
                    Text("3. Add **Set Focus**: turn Study on, then change \"Until Turned Off\" to **Until Time** → *Adjusted Date*.")
                    Text("4. In the shortcut's details (ⓘ), let it receive **Text** input.")
                    Button("Test it (1 minute)") { openURL(Links.runShortcut(Links.focusOn, text: "1")) }
                }
                Section("Shortcut 2: \(Links.focusOff)") {
                    Text("1. New shortcut, named exactly \"\(Links.focusOff)\".")
                    Text("2. Add **Set Focus**: turn Study off.")
                    Button("Test it") { openURL(Links.runShortcut(Links.focusOff)) }
                }
                Section {
                    Text("The first run asks to open Shortcuts and to change Focus; allow both. Pausing a block doesn't touch Focus: it still switches off at the original end time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Focus setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Timer

struct TimerView: View {
    @EnvironmentObject var model: Model
    @State private var confirmStop = false

    var body: some View {
        let block = model.blocks.first { $0.id == model.active?.blockID }
        let timer = model.active
        let total = Double(block?.focus ?? 0) * 60
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = timer?.left(at: context.date) ?? 0
            let paused = timer?.isPaused == true
            VStack(spacing: 20) {
                Spacer()
                Text(block?.title ?? "Focus").font(.largeTitle.bold()).multilineTextAlignment(.center)
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: total > 0 ? max(0.001, min(1, 1 - left / total)) : 1)
                        .stroke(left <= 0 ? Color.green : paused ? Color.secondary : Color.accentColor,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    VStack(spacing: 4) {
                        Group {
                            if left <= 0 {
                                Text("Time's up")
                            } else if let timer, !paused {
                                Text(timerInterval: context.date...timer.ends, countsDown: true).monospacedDigit()
                            } else {
                                Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                                    .opacity(0.5)
                            }
                        }
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        Text(caption(block, left: left, paused: paused))
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(28)
                }
                .frame(width: 260, height: 260)
                if left > 0 {
                    Button(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") { model.togglePause() }
                        .buttonStyle(.bordered)
                }
                if let block, !block.fullTask.isEmpty || !block.minTask.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !block.fullTask.isEmpty { Label(block.fullTask, systemImage: "bolt.fill") }
                        if !block.minTask.isEmpty { Label(block.minTask, systemImage: "leaf.fill").foregroundStyle(.secondary) }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer()
                Button { model.finish(.full) } label: { Text("Done: full").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button { model.finish(.minimum) } label: { Text("Done: minimum").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.orange)
                Button("Stop, didn't do it", role: .destructive) { confirmStop = true }
                    .padding(.top, 4)
            }
            .controlSize(.large)
            .padding()
        }
        // One stray tap used to throw the block's timer away.
        .confirmationDialog("Stop without ticking it off?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop the timer", role: .destructive) { model.finish(nil) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("The block stays on your calendar, not done. You can still tick off the minimum later.")
        }
    }

    private func caption(_ block: Block?, left: TimeInterval, paused: Bool) -> String {
        if left <= 0 { return "Tick it off below" }
        if paused { return model.useFocus ? "Paused. Focus still ends at its original time." : "Paused" }
        guard let block else { return "" }
        return "Window closes \(block.end.formatted(date: .omitted, time: .shortened))"
    }
}
