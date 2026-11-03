import SwiftUI

enum DayfoldPalette {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.13, blue: 0.14)
    static let accent = Color(red: 0.77, green: 0.90, blue: 0.57)
    static let lavender = Color(red: 0.76, green: 0.73, blue: 0.96)
    static func color(_ kind: RoutineKind) -> Color {
        switch kind {
        case .daily: accent
        case .weekly: Color(red: 0.55, green: 0.82, blue: 0.95)
        case .monthly: lavender
        case .yearly: Color(red: 0.98, green: 0.78, blue: 0.55)
        }
    }
}

struct DayfoldRootView: View {
    @EnvironmentObject var store: DayfoldStore
    @State private var tab = 0
    @State private var opened: RoutineKind?
    var body: some View {
        TabView(selection: $tab) {
            // Hosted by GymForge (GymForgeApp switches between the two halves).
            DayfoldHomeView().tabItem { Label("Today", systemImage: "circle.grid.2x2.fill") }.tag(0)
            DayfoldManageView().tabItem { Label("Routines", systemImage: "checklist") }.tag(1)
            DayfoldSettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .sheet(item: $opened) { kind in NavigationStack { DayfoldRoutineView(kind: kind) } }
        .onReceive(store.notifications.$openedRoutine) { value in
            if let value { opened = value; store.notifications.openedRoutine = nil }
        }
        .alert("Something needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct DayfoldHomeView: View {
    @EnvironmentObject var store: DayfoldStore
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let due = RoutineKind.allCases.flatMap { store.rows($0, now: context.date).filter { !$0.done && $0.retryToday } }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Label("DAYFOLD", systemImage: "circle.lefthalf.filled").font(.caption.weight(.bold)).tracking(3)
                            Spacer()
                            Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.caption).foregroundStyle(.secondary)
                            Button { AppLink.open(URL(string: "gymforge://gym")!) } label: {
                                Label("GymForge", systemImage: "dumbbell.fill").font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.orange)
                        }
                        Text(due.isEmpty ? "All clear." : "\(due.count) due\ntoday.")
                            .font(.system(size: 40, weight: .semibold, design: .rounded)).tracking(-1.5)
                        if due.isEmpty {
                            Text("Nothing due right now. Tasks come back when they're next scheduled.")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.top, -10)
                        }
                        Button { AppLink.open(URL(string: "gymforge://wakeup")!) } label: {
                            Label("Wake-up checklist", systemImage: "sun.horizon.fill")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16).background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).foregroundStyle(DayfoldPalette.accent)
                        Button { AppLink.open(URL(string: "gymforge://winddown")!) } label: {
                            Label("Before-bed checklist", systemImage: "moon.stars.fill")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16).background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).foregroundStyle(DayfoldPalette.lavender)
                        if !store.snapshot.configuration.routines.contains(where: \.remindersEnabled) {
                            Label("Reminders are off, so nothing will chase you. Turn them on in Settings → Reminders.", systemImage: "bell.slash")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        ForEach(due) { row in
                            TaskRow(row: row, color: DayfoldPalette.color(row.task.routine)) { store.setDone(row, done: true) }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(RoutineKind.allCases) { kind in
                                NavigationLink { DayfoldRoutineView(kind: kind) } label: {
                                    RoutineTile(kind: kind, rows: store.rows(kind, now: context.date))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 6)
                    }.padding(24).frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                }.background(DayfoldPalette.background)
            }.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct RoutineTile: View {
    let kind: RoutineKind
    let rows: [TaskOccurrence]
    var body: some View {
        let pending = rows.filter { !$0.done && $0.retryToday }.count
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.symbol).font(.title3).foregroundStyle(DayfoldPalette.color(kind))
            Text(kind.title).font(.headline)
            Text(pending == 0 ? "Clear" : "\(pending) to do")
                .font(.caption.weight(.semibold)).foregroundStyle(pending == 0 ? .secondary : DayfoldPalette.color(kind))
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityElement(children: .combine)
    }
}

struct DayfoldRoutineView: View {
    @EnvironmentObject var store: DayfoldStore
    let kind: RoutineKind
    @State private var showCompleted = false
    @State private var showWaiting = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let rows = store.rows(kind, now: context.date)
            let pending = rows.filter { !$0.done && $0.retryToday }
            let completed = rows.filter { $0.done }
            let waiting = rows.filter { !$0.done && !$0.retryToday }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: kind.symbol).font(.largeTitle).foregroundStyle(DayfoldPalette.color(kind))
                    Text(kind.greeting).font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
                    Text(pending.isEmpty ? "Nothing left for now." : "\(pending.count) small \(pending.count == 1 ? "step" : "steps") for you.")
                        .foregroundStyle(.secondary)
                    if !rows.isEmpty {
                        ProgressView(value: Double(completed.count), total: Double(rows.count))
                            .tint(DayfoldPalette.color(kind)).accessibilityLabel("Routine progress")
                    }
                    if pending.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(DayfoldPalette.color(kind))
                            Text("You're clear for now").font(.headline)
                            Text("Your tasks return when they're next due.").font(.footnote).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                    ForEach(pending) { row in TaskRow(row: row, color: DayfoldPalette.color(kind)) { store.setDone(row, done: true) } }
                    if !waiting.isEmpty {
                        DisclosureGroup("Waiting for next retry · \(waiting.count)", isExpanded: $showWaiting) {
                            ForEach(waiting) { row in TaskRow(row: row, color: DayfoldPalette.color(kind)) { store.setDone(row, done: true) } }
                        }.font(.subheadline).tint(.secondary)
                    }
                    if !completed.isEmpty {
                        DisclosureGroup("Completed · \(completed.count)", isExpanded: $showCompleted) {
                            ForEach(completed) { row in TaskRow(row: row, color: DayfoldPalette.color(kind)) { store.setDone(row, done: false) } }
                        }.font(.subheadline).tint(.secondary)
                    }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(DayfoldPalette.background)
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct TaskRow: View {
    let row: TaskOccurrence
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(row.done ? color : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.task.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                        .strikethrough(row.done).multilineTextAlignment(.leading)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).padding(.top, 4)
            .accessibilityLabel("\(row.task.title), \(row.done ? "completed, tap to undo" : "tap to complete")")
    }
    private var subtitle: String {
        if row.done, let date = row.completedAt { return "Done \(date.formatted(date: .abbreviated, time: .shortened)) · tap to undo" }
        if !row.retryToday { return "Still pending · retries every \(row.task.retryDays) days" }
        if row.overdue { return "Carried forward · due \(row.due.formatted(date: .abbreviated, time: .omitted))" }
        return row.task.scheduleLabel
    }
}
