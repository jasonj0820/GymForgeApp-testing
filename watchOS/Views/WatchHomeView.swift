import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject private var store: WatchAppStore

    var body: some View {
        NavigationStack {
            List {
                if store.routines.isEmpty {
                    Text("Open GymForge on iPhone to sync your routines.")
                        .foregroundStyle(.secondary)
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { store.requestSync() }
                } else {
                    ForEach(store.routines) { routine in
                        Button {
                            Task { await store.beginFromWatch(routine) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(routine.name).font(.headline)
                                Text("\(routine.exercises.count) exercises")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(routine.exercises.isEmpty)
                    }
                }

                Section {
                    NavigationLink {
                        CardioStartView()
                    } label: {
                        Label("Run & basketball", systemImage: "figure.run")
                    }
                    NavigationLink {
                        DayfoldWatchHome()
                    } label: {
                        Label("Routine", systemImage: "checklist")
                    }
                    NavigationLink {
                        WatchSleepView()
                    } label: {
                        Label("Sleep", systemImage: "bed.double.fill")
                    }
                }

                Section {
                    Label(store.phoneReachable ? "iPhone connected" : "iPhone not reachable",
                          systemImage: store.phoneReachable ? "iphone" : "iphone.slash")
                        .foregroundStyle(store.phoneReachable ? Color.green : Color.secondary)
                    if let lastSync = store.lastSync {
                        Text("Synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    }
                    if !store.routines.isEmpty {
                        Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { store.requestSync() }
                    }
                }
                .font(.caption2)
            }
            .navigationTitle("GymForge")
        }
    }
}
