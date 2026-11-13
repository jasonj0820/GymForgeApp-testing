import SwiftUI

struct RoutinesView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var newRoutineName = ""
    @State private var showingNewRoutine = false
    @State private var deleting: WorkoutRoutine?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Workout history (\(store.workoutLogs.count))", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                ForEach(store.routines) { routine in
                    let canStart = !routine.exercises.isEmpty && store.activeWorkout == nil
                    NavigationLink {
                        RoutineEditorView(routine: routine)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(routine.name).font(.headline)
                            Text(detail(routine))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // MK22.1: start a workout from here too, not only from Today.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if canStart {
                            Button {
                                Task { await store.startWorkout(routine) }
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .tint(.green)
                        }
                    }
                    .contextMenu {
                        if canStart {
                            Button("Start workout", systemImage: "play.fill") { Task { await store.startWorkout(routine) } }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicateRoutine(routine) }
                    }
                }
                // MK22.1: a swipe used to delete the whole routine on the spot.
                .onDelete { offsets in
                    if let index = offsets.first { deleting = store.routines[index] }
                }
                .onMove(perform: store.moveRoutines)
            } header: {
                Text("Routines")
            } footer: {
                if !store.routines.isEmpty {
                    Text("Tap a routine to edit it. Swipe right (or touch and hold) to start it.")
                }
            }
        }
        .navigationTitle("Workouts")
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { routine in
            Button("Delete \(routine.name)", role: .destructive) {
                if let index = store.routines.firstIndex(where: { $0.id == routine.id }) {
                    store.deleteRoutines(at: IndexSet(integer: index))
                }
            }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("Its exercises and their settings go with it. Workouts you've already logged stay in History.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNewRoutine = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New routine", isPresented: $showingNewRoutine) {
            TextField("e.g. Back Day", text: $newRoutineName)
            Button("Create") {
                let name = newRoutineName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.addRoutine(named: name) }
                newRoutineName = ""
            }
            Button("Cancel", role: .cancel) { newRoutineName = "" }
        }
    }

    /// "6 exercises · last done 3 days ago".
    private func detail(_ routine: WorkoutRoutine) -> String {
        let count = routine.exercises.count
        let last = store.lastDone(routine)
        return "\(count) exercise\(count == 1 ? "" : "s") · "
            + (last > .distantPast ? "last done " + last.formatted(.relative(presentation: .named)) : "not done yet")
    }
}
