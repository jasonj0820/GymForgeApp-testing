import SwiftUI

/// MK15: the wake-up checklist. Dayfold's "Wake-up" steps, creatine (GymForge's tick) and last night's recap.
struct WakeUpView: View {
    @EnvironmentObject var dayfold: DayfoldStore
    @EnvironmentObject var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let rows = dayfold.wakeRows(now: context.date)
                let creatine = store.nutritionToday(context.date).creatine
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sun.horizon.fill").font(.largeTitle).foregroundStyle(DayfoldPalette.accent)
                        Text("Up and at it.").font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
                        if let gym = store.extras.dayPlan(on: context.date), gym.kind == .workout {
                            Label("\(gym.routineName ?? "Gym") today", systemImage: "dumbbell.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        }
                        ProgressView(value: Double(rows.filter(\.done).count + (creatine ? 1 : 0)), total: Double(rows.count + 1))
                            .tint(DayfoldPalette.accent).accessibilityLabel("Checklist progress")
                        Button { store.toggleCreatine() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: creatine ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundStyle(creatine ? DayfoldPalette.accent : .secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Creatine 5 g").font(.body.weight(.medium)).strikethrough(creatine)
                                    Text("Same tick as GymForge's nutrition card").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                .background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                        ForEach(rows) { row in
                            TaskRow(row: row, color: DayfoldPalette.accent) { dayfold.setDone(row, done: !row.done) }
                        }
                        if let recap = store.lastRecap {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(recap.title).font(.headline)
                                Text(recap.text).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DayfoldPalette.card, in: RoundedRectangle(cornerRadius: 18))
                            .padding(.top, 8)
                        }
                        Text("Add or remove steps with the \"Wake-up\" switch in Dayfold → Routines.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .background(DayfoldPalette.background)
            }
            .navigationTitle("Wake-up").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
