import SwiftUI

/// MK11.3: Today banner while a break runs (or the comeback week after one).
struct BreakBanner: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        if let active = store.activeBreak {
            HStack(alignment: .top, spacing: 10) {
                CluckView(mood: .empathetic, animated: true).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(active.mode == .full ? "On a break" : "Maintenance mode").font(.headline)
                    Text("\(active.detail) · until \(active.finish.formatted(.dateTime.weekday(.wide).day().month()))"
                         + (active.mode == .maintenance ? " · \(store.consistency.thisWeekCount)/\(GymBreakRules.maintenanceGoal) short sessions this week" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .card()
        } else if store.comebackSuggested {
            Label("Comeback week — start with a light session; your weights come back fast.", systemImage: "arrow.uturn.up")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }
}

/// "Give me a break": a real reason with numbers → Sergeant Cluck pushes back → type BREAK.
struct GiveMeABreakView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason: GymBreak.Reason = .deadlines
    @State private var count = 0
    @State private var detail = ""
    @State private var lastDue = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var step = 0
    @State private var mode: GymBreak.Mode = .maintenance
    @State private var confirmText = ""

    private var refusal: String? { store.breakRefusal(reason: reason, count: count, detail: detail, lastDue: lastDue) }

    var body: some View {
        Form {
            if let active = store.activeBreak {
                activeSection(active)
            } else if step == 0 {
                reasonSection
            } else if step == 1 {
                pushbackSection
            } else {
                confirmSection
            }
        }
        .navigationTitle("Give me a break")
    }

    private func activeSection(_ active: GymBreak) -> some View {
        Section {
            LabeledContent("Why", value: "\(active.reason.title) (\(active.count))")
            LabeledContent("What", value: active.detail)
            LabeledContent("Mode", value: active.mode == .full ? "Full break" : "Maintenance — 2 short sessions a week")
            LabeledContent("Until", value: active.finish.formatted(date: .abbreviated, time: .omitted))
            Button("I'm back — end the break now", role: .destructive) { store.endBreakEarly() }
        } footer: {
            Text("Sergeant Cluck won't nag, your streak is paused, and sessions in this time don't count toward plateaus. After a break of 5+ days you get a light comeback session.")
        }
    }

    private var reasonSection: some View {
        Group {
            Section {
                Picker("Reason", selection: $reason) {
                    ForEach(GymBreak.Reason.allCases) { Text($0.title).tag($0) }
                }
                Stepper("\(reason.question): \(count)", value: $count, in: 0...20)
                TextField("What's due? (e.g. CIVL3390 report, exam)", text: $detail)
                DatePicker("Last one due", selection: $lastDue,
                           in: Date.now...(Calendar.current.date(byAdding: .day, value: GymBreakRules.maxDays, to: .now) ?? .now),
                           displayedComponents: .date)
            } header: {
                Text("What's going on?")
            } footer: {
                Text("Breaks are for genuinely busy stretches: \(GymBreak.Reason.deadlines.minimum)+ assignments or exams, \(GymBreak.Reason.work.minimum)+ long work days, or a move / family emergency. Up to \(GymBreakRules.maxDays) days, once every 6 weeks.")
            }
            Section {
                if let refusal {
                    Label(refusal, systemImage: "hand.raised.fill").foregroundStyle(.orange)
                }
                Button("Continue") { step = 1 }.disabled(refusal != nil)
            }
        }
    }

    private var pushbackSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                CluckView(mood: .suspicious, animated: true).frame(width: 52, height: 52)
                Text("Hold it, recruit. Two 30-minute sessions a week keeps your strength — you lose almost nothing in two weeks. Sure you want out completely?")
                    .font(.subheadline)
            }
            Button {
                mode = .maintenance
                step = 2
            } label: {
                Label("Maintenance mode — 2 short sessions a week", systemImage: "leaf")
            }
            Button {
                mode = .full
                step = 2
            } label: {
                Label("Full break — no gym", systemImage: "pause.circle")
            }
            .tint(.red)
            Button("Never mind, I'll train") { dismiss() }
        }
    }

    private var confirmSection: some View {
        Section {
            Text(mode == .full ? "Full break until \(lastDue.formatted(date: .abbreviated, time: .omitted))." : "Maintenance mode until \(lastDue.formatted(date: .abbreviated, time: .omitted)): goal drops to 2, sessions default to 30 min.")
            TextField("Type \(GymBreakRules.confirmWord) to confirm", text: $confirmText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Start break") {
                store.startBreak(reason: reason, count: count, detail: detail, mode: mode, lastDue: lastDue)
                dismiss()
            }
            .disabled(confirmText.trimmingCharacters(in: .whitespaces).uppercased() != GymBreakRules.confirmWord || refusal != nil)
            Button("Back") { step = 1 }
        } footer: {
            Text("You can end it early any time. The next break is available 6 weeks after this one starts.")
        }
    }
}
