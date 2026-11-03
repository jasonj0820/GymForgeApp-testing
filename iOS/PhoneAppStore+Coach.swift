import Foundation

/// MK9.1: the coach's suggestions (accept / not now), training focus and the routine builder.
extension PhoneAppStore {
    private var activeDeclines: Set<String> {
        let cutoff = Date.now.addingTimeInterval(-28 * 86_400)
        return Set(extras.declinedProposals.filter { $0.value > cutoff }.map(\.key))
    }

    /// Suggested changes, most important first (nothing is changed until you accept).
    var coachProposals: [CoachProposal] {
        let context = CoachInputs(priorities: extras.priorityMuscles, readinessLow: readiness?.level == .low,
                                   declined: activeDeclines, nutritionPhase: nutritionPhase,
                                   painFlags: extras.painFlags, dayPlans: extras.dayPlans, cardio: cardioSessions)
        let all = CoachBrain.proposals(routines: routines, logs: workoutLogs, profile: profile, context: context)
        let deloading = profile.isDeloadActive()
        // After a volume change is accepted, give it 3 weeks to show before suggesting more for that muscle.
        let volumeCutoff = Date.now.addingTimeInterval(-21 * 86_400)
        // Block ramps are weekly by design.
        let rampCutoff = Date.now.addingTimeInterval(-6 * 86_400)
        return all.filter { proposal in
            switch proposal.change {
            case .deload:
                return !deloading
            case .sets, .addExercise:
                if deloading { return false }
                if proposal.id.hasPrefix("pain-") { return true }
                if let muscle = proposal.muscle, let changed = extras.declinedProposals["volume-\(muscle.rawValue)"],
                   changed > (proposal.id.hasPrefix("ramp-") ? rampCutoff : volumeCutoff) {
                    return false
                }
                return true
            default:
                return true
            }
        }
    }

    var routineAudit: [CoachProposal] {
        let declined = activeDeclines
        return CoachBrain.audit(routines: routines, profile: profile, logs: workoutLogs)
            .filter { !declined.contains($0.id) }
    }

    var muscleStatus: [MuscleStatus] {
        CoachBrain.status(routines: routines, logs: workoutLogs)
    }

    func declineProposal(_ proposal: CoachProposal) {
        extras.declinedProposals[proposal.id] = .now
        // Forget very old declines.
        let cutoff = Date.now.addingTimeInterval(-60 * 86_400)
        extras.declinedProposals = extras.declinedProposals.filter { $0.value > cutoff }
        saveExtras()
    }

    /// Applies a suggestion to your routine, and remembers it for the weekly review's follow-up.
    func acceptProposal(_ proposal: CoachProposal) {
        var exercise: ExerciseDefinition?
        func update(_ routineID: UUID, _ itemID: UUID, _ change: (inout RoutineExercise) -> Void) {
            guard let r = routines.firstIndex(where: { $0.id == routineID }),
                  let i = routines[r].exercises.firstIndex(where: { $0.id == itemID }) else { return }
            change(&routines[r].exercises[i])
            exercise = routines[r].exercises[i].exercise
        }
        var kind: CoachSuggestion.Kind = .other
        switch proposal.change {
        case .sets(let routineID, let itemID, let to):
            var increased = false
            update(routineID, itemID) { item in
                increased = to > item.exercise.defaultSets
                item.exercise.defaultSets = to
            }
            kind = increased ? .addSet : .other
        case .repRange(let routineID, let itemID, let min, let max):
            update(routineID, itemID) { item in
                item.exercise.repMin = min
                item.exercise.repMax = max
            }
        case .rest(let routineID, let itemID, let seconds):
            update(routineID, itemID) { $0.exercise.restSeconds = seconds }
        case .moveBefore(let routineID, let itemID, let beforeID):
            if let r = routines.firstIndex(where: { $0.id == routineID }),
               let from = routines[r].exercises.firstIndex(where: { $0.id == itemID }),
               let to = routines[r].exercises.firstIndex(where: { $0.id == beforeID }), from > to {
                // Superset links would no longer make sense after reordering.
                let moved = routines[r].exercises.remove(at: from)
                routines[r].exercises.insert(moved, at: to)
                for index in routines[r].exercises.indices {
                    routines[r].exercises[index].order = index
                    routines[r].exercises[index].isSupersetWithNext = false
                }
                exercise = moved.exercise
            }
        case .addExercise(let routineID, let name, let sets):
            if let r = routines.firstIndex(where: { $0.id == routineID }), let info = ExerciseLibrary.profile(named: name) {
                let definition = ExerciseDefinition(name: info.name, category: info.category, repMin: info.repMin, repMax: info.repMax,
                                                    defaultSets: sets, restSeconds: info.restSeconds, weightIncrementKg: info.increment)
                routines[r].exercises.append(RoutineExercise(exercise: definition, order: routines[r].exercises.count))
                exercise = definition
                kind = .addSet
            }
        case .swapExercise(let routineID, let itemID, let name):
            if let info = ExerciseLibrary.profile(named: name) {
                update(routineID, itemID) { item in
                    let old = item.exercise
                    var replacement = ExerciseDefinition(name: info.name, category: info.category, repMin: info.repMin, repMax: info.repMax,
                                                         defaultSets: old.defaultSets, restSeconds: info.restSeconds,
                                                         weightIncrementKg: info.increment)
                    // The old exercise stays one tap away as a swap option.
                    var options = (old.alternatives ?? []).filter { $0.name != info.name }
                    var previous = old
                    previous.alternatives = nil
                    options.insert(previous, at: 0)
                    replacement.alternatives = options
                    item.exercise = replacement
                }
            }
        case .deload:
            startDeloadWeek()
            kind = .deload
        case .info:
            extras.declinedProposals[proposal.id] = .now.addingTimeInterval(60 * 86_400)   // "got it": hide for a good while
            saveExtras()
            return
        }
        if let muscle = proposal.muscle {
            switch proposal.change {
            case .sets, .addExercise: extras.declinedProposals["volume-\(muscle.rawValue)"] = .now
            default: break
            }
        }
        persistAndSync()
        // Follow-up in the weekly review.
        let key = exercise?.historyKey ?? proposal.muscle.map { "muscle:\($0.category.rawValue)" }
        if !extras.suggestions.contains(where: { !$0.resolved && $0.text == proposal.title }) {
            var baselineSets: Double?
            var strength: Double?
            if let exercise {
                let recent = workoutLogs.history(for: exercise).suffix(3).map(\.log)
                if !recent.isEmpty {
                    baselineSets = Double(recent.reduce(0) { $0 + $1.sets.count }) / Double(recent.count)
                    strength = exercise.isAssisted ? recent.compactMap(\.leastAssistanceKg).min() : recent.map(\.estimatedOneRepMaxKg).max()
                }
            }
            extras.suggestions.append(CoachSuggestion(exerciseKey: key, exerciseName: exercise?.name ?? proposal.muscle?.title,
                                                      text: proposal.title, kind: kind,
                                                      baselineStrength: strength, baselineSets: baselineSets))
        }
        saveExtras()
    }

    /// MK10.1: the coach's short brief on a finished workout.
    func brief(for log: WorkoutLog) -> WorkoutBrief {
        let recentReadiness = Calendar.current.isDateInToday(log.startedAt) ? readiness : nil
        return WorkoutBriefBuilder.make(for: log, logs: workoutLogs, style: profile.coachStyle, targetRIR: log.targetRIR,
                                        readiness: recentReadiness, cardio: cardioSessions)
    }

    /// The block that just finished (during the deload and the week after).
    var blockReview: BlockReview? {
        CoachBrain.blockReview(profile: profile, logs: workoutLogs)
    }

    /// Starts a fixed-length coached block today: build weeks, then a deload, repeating.
    func startCoachedBlock(buildWeeks: Int) {
        var updated = profile
        updated.program = ProgramPlan.coachedBlock(focus: profile.focus, buildWeeks: buildWeeks)
        setProfile(updated)
    }

    /// MK15: stop the running block (history stays); then start a fresh one from today.
    func endProgram() {
        var updated = profile
        updated.program = nil
        setProfile(updated)
    }

    func setFocus(_ focus: TrainingFocus) {
        var updated = profile
        updated.focus = focus
        setProfile(updated)
    }

    /// Adds routines from the builder (your existing ones are kept).
    func addBuiltRoutines(_ built: [WorkoutRoutine]) {
        let existing = Set(routines.map(\.name))
        for var routine in built {
            if existing.contains(routine.name) { routine.name += " (new)" }
            routines.append(routine)
        }
        persistAndSync()
    }
}
