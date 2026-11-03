import SwiftUI

struct RoutinesView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var newRoutineName = ""
    @State private var showingNewRoutine = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Workout history (\(store.workoutLogs.count))", systemImage: "clock.arrow.circlepath")
                }
            }

            Section("Routines") {
                ForEach(store.routines) { routine in
                    NavigationLink {
                        RoutineEditorView(routine: routine)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(routine.name).font(.headline)
                            Text("\(routine.exercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicateRoutine(routine) }
                    }
                }
                .onDelete(perform: store.deleteRoutines)
                .onMove(perform: store.moveRoutines)
            }
        }
        .navigationTitle("Workouts")
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
}
