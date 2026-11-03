import SwiftUI
import WatchKit

struct DayfoldWatchHome: View {
    @EnvironmentObject var store: DayfoldStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    if store.snapshot.configuration.tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "iphone.and.arrow.forward").font(.title)
                            Text("Welcome to Dayfold").font(.headline)
                            Text("Open GymForge → Dayfold on your iPhone to sync your routines.").font(.footnote)
                            Button("Try sync") { store.refresh() }
                        }
                    } else {
                        ForEach(RoutineKind.allCases) { kind in
                            NavigationLink { DayfoldWatchRoutine(kind: kind) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(kind.title, systemImage: kind.symbol)
                                        .foregroundStyle([Color.mint, .cyan, .purple, .orange][RoutineKind.allCases.firstIndex(of: kind)!])
                                    let count = store.rows(kind, now: context.date).filter { !$0.done && $0.retryToday }.count
                                    Text(count == 0 ? "All clear" : "\(count) to do").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                        }
                        Text(store.syncStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
        .navigationTitle("Dayfold")
        .onAppear { store.refresh() }
        .alert("Save issue", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}

struct DayfoldWatchRoutine: View {
    @EnvironmentObject var store: DayfoldStore
    let kind: RoutineKind
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let rows = store.rows(kind, now: context.date)
            let pending = rows.filter { !$0.done && $0.retryToday }
            List {
                if pending.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.mint)
                        Text("You're clear").font(.headline)
                        Text("Tasks return when due.").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical)
                }
                ForEach(pending) { row in
                    Button {
                        store.setDone(row, done: true)
                        WKInterfaceDevice.current().play(.success)
                    } label: {
                        HStack {
                            Image(systemName: "circle").foregroundStyle(.mint)
                            VStack(alignment: .leading) {
                                Text(row.task.title)
                                if row.overdue { Text("Carried forward").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                let waiting = rows.filter { !$0.done && !$0.retryToday }
                if !waiting.isEmpty {
                    Section("Waiting for retry") {
                        ForEach(waiting) { row in
                            Button(row.task.title) { store.setDone(row, done: true) }
                        }
                    }
                }
                let done = rows.filter { $0.done }
                if !done.isEmpty {
                    Section("Completed · tap to undo") {
                        ForEach(done) { row in
                            Button { store.setDone(row, done: false) } label: {
                                Label(row.task.title, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }.navigationTitle(kind.title)
    }
}
