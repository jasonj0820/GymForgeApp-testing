import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var model: Model
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editing: Block?

    var body: some View {
        let today = dayBlocks(model.blocks, on: day)
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(day: $day)
                List {
                    ForEach(today) { block in
                        BlockRow(block: block)
                            .contentShape(Rectangle())
                            .onTapGesture { model.start(block) }
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.blocks.removeAll { $0.id == block.id } }
                                Button("Edit") { editing = block }.tint(.blue)
                            }
                    }
                }
                .overlay {
                    if today.isEmpty {
                        ContentUnavailableView("No blocks", systemImage: "calendar",
                                               description: Text("Tap + to plan this day. Tap a block to start it."))
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { editing = Block(title: "", start: newStart, minutes: 90) } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { BlockEditor(block: $0).environmentObject(model) }
            .fullScreenCover(isPresented: .constant(model.active != nil)) { TimerView().environmentObject(model) }
        }
    }

    /// New blocks start after the day's last block (or 9am).
    private var newStart: Date {
        dayBlocks(model.blocks, on: day).last?.end
            ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    }
}

struct WeekStrip: View {
    @Binding var day: Date

    private var week: [Date] {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: day)!.start
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").padding(8) }
            ForEach(week, id: \.self) { d in
                let selected = Calendar.current.isDate(d, inSameDayAs: day)
                VStack(spacing: 4) {
                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    Text(d.formatted(.dateTime.day()))
                        .font(.callout.weight(selected ? .bold : .regular))
                        .frame(width: 34, height: 34)
                        .background(selected ? Color.accentColor : .clear, in: Circle())
                        .foregroundStyle(selected ? Color.white : Calendar.current.isDateInToday(d) ? Color.accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { day = d }
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right").padding(8) }
        }
        .padding(.vertical, 8)
    }

    private func shift(_ days: Int) { day = Calendar.current.date(byAdding: .day, value: days, to: day)! }
}

struct BlockRow: View {
    let block: Block

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(block.start, style: .time).font(.subheadline.monospacedDigit())
                Text("\(block.minutes) min").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 70, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(block.title).font(.headline).strikethrough(block.outcome != nil)
                if !block.fullTask.isEmpty { Label(block.fullTask, systemImage: "bolt.fill").font(.caption) }
                if !block.minTask.isEmpty {
                    Label(block.minTask, systemImage: "leaf.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let outcome = block.outcome {
                Text(outcome == .full ? "Full" : "Min").font(.caption.bold()).foregroundStyle(color)
            }
        }
        .padding(.vertical, 4)
    }

    private var color: Color {
        switch block.outcome {
        case .full?: .green
        case .minimum?: .orange
        case nil: .accentColor
        }
    }
}

struct BlockEditor: View {
    @EnvironmentObject var model: Model
    @Environment(\.dismiss) private var dismiss
    @State var block: Block

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject, e.g. Steel design", text: $block.title)
                DatePicker("Start", selection: $block.start)
                Stepper("Length: \(block.minutes) min", value: $block.minutes, in: 15...240, step: 15)
                Section("Full version (100%)") {
                    TextField("e.g. Timed past paper + marking", text: $block.fullTask)
                }
                Section("Minimum version (still counts)") {
                    TextField("e.g. One revision lecture", text: $block.minTask)
                }
            }
            .navigationTitle(isNew ? "New block" : "Edit block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(block.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var isNew: Bool { !model.blocks.contains { $0.id == block.id } }

    private func save() {
        if let i = model.blocks.firstIndex(where: { $0.id == block.id }) {
            model.blocks[i] = block
        } else {
            model.blocks.append(block)
        }
        dismiss()
    }
}

struct TimerView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        let block = model.blocks.first { $0.id == model.active?.blockID }
        let timer = model.active
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = timer?.left(at: context.date) ?? 0
            VStack(spacing: 20) {
                Spacer()
                Text(block?.title ?? "Focus").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Group {
                    if left <= 0 {
                        Text("Time's up")
                    } else if let timer, !timer.isPaused {
                        Text(timerInterval: context.date...timer.ends, countsDown: true).monospacedDigit()
                    } else {
                        Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                            .opacity(0.5)
                    }
                }
                .font(.system(size: 64, weight: .bold, design: .rounded))
                if left > 0 {
                    Button(timer?.isPaused == true ? "Resume" : "Pause",
                           systemImage: timer?.isPaused == true ? "play.fill" : "pause.fill") { model.togglePause() }
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
                Button("Stop, didn't do it", role: .destructive) { model.finish(nil) }
                    .padding(.top, 4)
            }
            .controlSize(.large)
            .padding()
        }
    }
}
