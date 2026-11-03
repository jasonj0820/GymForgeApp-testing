import SwiftUI

/// Program blocks: e.g. 6 weeks hypertrophy → 4 weeks strength → 1 week deload, repeating.
/// Rep ranges shift automatically each block; history keeps what you actually did.
struct ProgramSettingsView: View {
    @EnvironmentObject private var store: PhoneAppStore

    private var plan: ProgramPlan? { store.profile.program }

    var body: some View {
        Form {
            Section {
                Button("Off") { setPlan(nil) }
                    .foregroundStyle(plan == nil ? Color.accentColor : Color.primary)
                ForEach(ProgramPlan.templates, id: \.name) { template in
                    Button {
                        var copy = template
                        copy.startDate = Calendar.current.startOfDay(for: .now)
                        copy.blocks = template.blocks.map { ProgramBlock(phase: $0.phase, weeks: $0.weeks) }
                        setPlan(copy)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).foregroundStyle(.primary)
                            Text(template.blocks.map { "\($0.weeks)w \($0.phase.title.lowercased())" }.joined(separator: " → "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Choose a program")
            } footer: {
                Text("Choosing a program starts it today.")
            }

            if let plan {
                if let position = plan.position(at: .now) {
                    Section("Now") {
                        LabeledContent("Block", value: position.block.phase.title)
                        LabeledContent("Week", value: "\(position.week) of \(position.block.weeks)")
                        LabeledContent("Block ends", value: position.blockEnds.formatted(date: .abbreviated, time: .omitted))
                        Text(position.block.phase.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Name", text: planBinding(\.name))
                    DatePicker("Start date", selection: planBinding(\.startDate), displayedComponents: .date)
                    Toggle("Repeat when finished", isOn: planBinding(\.repeats))
                } header: {
                    Text("Plan")
                }

                Section {
                    ForEach(plan.blocks.indices, id: \.self) { index in
                        HStack {
                            Picker("", selection: blockBinding(index, \.phase)) {
                                ForEach(ProgramPhase.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            Spacer()
                            Stepper("\(plan.blocks[index].weeks) wk", value: blockBinding(index, \.weeks), in: 1...16)
                                .fixedSize()
                        }
                    }
                    .onDelete { offsets in
                        updatePlan { $0.blocks.remove(atOffsets: offsets) }
                    }
                    Button("Add block", systemImage: "plus") {
                        updatePlan { $0.blocks.append(ProgramBlock(phase: .hypertrophy, weeks: 4)) }
                    }
                } header: {
                    Text("Blocks")
                } footer: {
                    Text(ProgramPhase.allCases.map { "\($0.title): \($0.summary)" }.joined(separator: "\n"))
                }
            }
        }
        .navigationTitle("Program blocks")
    }

    private func setPlan(_ newPlan: ProgramPlan?) {
        var profile = store.profile
        profile.program = newPlan
        store.setProfile(profile)
    }

    private func updatePlan(_ change: (inout ProgramPlan) -> Void) {
        guard var current = plan else { return }
        change(&current)
        setPlan(current.blocks.isEmpty ? nil : current)
    }

    private func planBinding<Value>(_ keyPath: WritableKeyPath<ProgramPlan, Value>) -> Binding<Value> {
        Binding(
            get: { (store.profile.program ?? ProgramPlan.templates[0])[keyPath: keyPath] },
            set: { value in updatePlan { $0[keyPath: keyPath] = value } }
        )
    }

    private func blockBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<ProgramBlock, Value>) -> Binding<Value> {
        Binding(
            get: {
                let blocks = store.profile.program?.blocks ?? []
                let block = index < blocks.count ? blocks[index] : ProgramBlock(phase: .hypertrophy, weeks: 4)
                return block[keyPath: keyPath]
            },
            set: { value in
                updatePlan { plan in
                    guard index < plan.blocks.count else { return }
                    plan.blocks[index][keyPath: keyPath] = value
                }
            }
        )
    }
}
