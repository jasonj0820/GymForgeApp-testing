import SwiftUI

/// Tonight's before-bed checklist: Dayfold's "Before bed" tasks, plus packing your bag when a session is planned tomorrow.
struct WindDownView: View {
    @EnvironmentObject var dayfold: DayfoldStore
    @EnvironmentObject var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let rows = dayfold.bedtimeRows(now: context.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(DayfoldPalette.lavender)
                        Text("Close the day.\nRest easy.").font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
                        if let bed = store.tonightsBedtime(now: context.date) {
                            Text("Lights out \(bed.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                        }
                        if store.bedtimeStreak > 0 {
                            Label("In bed on time · \(store.bedtimeStreak) night\(store.bedtimeStreak == 1 ? "" : "s") running", systemImage: "flame.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                        }
                        if !rows.isEmpty {
                            ProgressView(value: Double(rows.filter(\.done).count), total: Double(rows.count))
                                .tint(DayfoldPalette.lavender).accessibilityLabel("Checklist progress")
                        }
                        ForEach(rows) { row in
                            TaskRow(row: row, color: DayfoldPalette.lavender) { dayfold.setDone(row, done: !row.done) }
                        }
                        if rows.isEmpty {
                            Text("Nothing on your before-bed list. Turn on \"Before bed\" for any step in Dayfold → Routines.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            store.goingToBed()
                            dismiss()
                        } label: {
                            Label("I'm going to bed", systemImage: "bed.double.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(.indigo).padding(.top, 8)
                        Text("Finishing the list during wind-down does the same: the card goes, Sergeant Cluck stops, and your Sleep Focus shortcut runs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .background(DayfoldPalette.background)
            }
            .navigationTitle("Before bed").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
