import Foundation

/// Built-in technique cues, matched by exercise name (then by muscle group).
/// Your own cues (Exercise editor → Form cues) replace these for that exercise.
enum FormCues {
    static func cues(for exercise: ExerciseDefinition) -> [String] {
        if let custom = exercise.formCues, !custom.isEmpty { return custom }
        return builtIn(for: exercise)
    }

    static func builtIn(for exercise: ExerciseDefinition) -> [String] {
        let name = exercise.name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { name.contains($0) } }

        // Order matters: more specific names first.
        if exercise.isCardio {
            if has("treadmill", "run", "jog") && !has("crunch") {
                return ["Warm up 3–5 min easy first.",
                        "Short, quick steps, land under your hips.",
                        "Keep most of it at a pace where you could still talk."]
            }
            if has("bike", "cycle", "spin") {
                return ["Seat so your knee is slightly bent at the bottom.",
                        "Smooth circles, steady cadence.",
                        "Build the effort over the session."]
            }
            if has("row erg", "rower", "rowing machine") {
                return ["Legs, then back, then arms — reverse on the way in.",
                        "Drive with the legs; most of the power is there.",
                        "Steady rhythm over sprinting the first minute."]
            }
            return ["Warm up first.", "Mostly conversational pace.", "Finish a little harder than you started."]
        }

        if has("incline") && has("press", "bench") {
            return ["Bench at 30–45°, not steeper — steeper turns it into a shoulder press.",
                    "Shoulder blades pinned back and down the whole set.",
                    "Lower to the upper chest, elbows about 45–60° from your body."]
        }
        if has("decline") {
            return ["Feet locked in, shoulder blades pinned.",
                    "Lower to the lower chest under control.",
                    "Press up and slightly back toward your face."]
        }
        if has("bench") {
            return ["Shoulder blades squeezed together and down; keep a small arch.",
                    "Feet planted, drive through the floor.",
                    "Touch the lower chest with elbows ~45° — no bouncing."]
        }
        if has("chest press", "machine press") {
            return ["Seat height so the handles line up with mid-chest.",
                    "Keep your back and shoulder blades against the pad.",
                    "Slow 2–3 s on the way back; don't let the stack touch between reps."]
        }
        if has("dumbbell press", "db press") && !has("shoulder", "overhead") {
            return ["Dumbbells at chest level, wrists stacked over elbows.",
                    "Lower until you feel a deep chest stretch, then press up and slightly in.",
                    "Don't clank the bells together at the top — keep tension."]
        }
        if has("fly", "flye", "pec deck", "crossover") {
            return ["Soft, fixed bend in the elbows — it's a hug, not a press.",
                    "Stretch wide under control, then squeeze the chest to bring hands together.",
                    "Pause a second at the squeeze."]
        }
        if has("push-up", "push up", "pushup") {
            return ["Body in one straight line — squeeze glutes and abs.",
                    "Hands just wider than shoulders, elbows ~45°.",
                    "Chest touches the floor every rep."]
        }
        if has("dip") {
            return ["Lean forward slightly for chest, stay upright for triceps.",
                    "Lower until upper arms are about parallel — not deeper if shoulders complain.",
                    "Shoulders down away from your ears."]
        }
        if has("rdl", "romanian", "stiff leg", "stiff-leg") {
            return ["Push your hips back; knees stay soft but barely move.",
                    "Bar or dumbbells slide down your thighs, back flat.",
                    "Stop when hamstrings are fully stretched, then drive hips forward."]
        }
        if has("deadlift") {
            return ["Bar over mid-foot, shins close.",
                    "Brace hard, chest up, pull the slack out before lifting.",
                    "Push the floor away; hips and shoulders rise together."]
        }
        if has("pulldown", "pull-down", "pull down") {
            return ["Lean back slightly, chest up to the bar.",
                    "Start by pulling your shoulder blades down, then drive elbows to your ribs.",
                    "Control the bar up to a full stretch."]
        }
        if has("pull-up", "pull up", "pullup", "chin-up", "chin up", "chinup") {
            return ["Start from a dead hang with shoulders engaged.",
                    "Drive elbows down toward your hips; chin clears the bar.",
                    "Lower all the way, no kipping."]
        }
        if has("row") {
            return ["Flat back, chest up — don't round to reach.",
                    "Pull elbows back toward your hips, squeeze the shoulder blades.",
                    "Pause at the top, lower under control; don't jerk with the lower back."]
        }
        if has("face pull") {
            return ["Rope at face height, pull toward your forehead.",
                    "Elbows high, rotate so hands finish by your ears.",
                    "Light weight, slow and controlled."]
        }
        if has("rear delt", "reverse fly", "reverse pec") {
            return ["Lead with the elbows, arms slightly bent.",
                    "Squeeze the back of the shoulders, not the traps.",
                    "Light weight — momentum steals this one."]
        }
        if has("shrug") {
            return ["Straight up toward your ears, no rolling.",
                    "Hold the top for a second.",
                    "Arms stay straight — it's not a curl."]
        }
        if has("front squat") {
            return ["Elbows high so the bar sits on your shoulders.",
                    "Stay upright; knees travel forward over the toes.",
                    "Brace before each rep."]
        }
        if has("hack squat") {
            return ["Feet mid-platform, shoulder width.",
                    "Go deep under control — knees over toes is fine.",
                    "Drive through the whole foot, don't lock out hard."]
        }
        if has("squat") && !has("split") {
            return ["Brace your core before each rep, chest up.",
                    "Knees track over your toes; sit between your hips.",
                    "Hit at least parallel, then drive up through mid-foot."]
        }
        if has("leg press") {
            return ["Lower back stays on the pad — stop before it lifts.",
                    "Feet shoulder width, knees track over toes.",
                    "Don't lock the knees at the top."]
        }
        if has("split squat", "lunge", "bulgarian") {
            return ["Long enough stance that the front heel stays down.",
                    "Drop the back knee straight down, torso tall.",
                    "Drive through the front heel."]
        }
        if has("leg extension") {
            return ["Line the knee up with the machine's pivot.",
                    "Squeeze the quads hard at the top for a second.",
                    "Lower slowly — 2–3 s."]
        }
        if has("leg curl", "hamstring curl") {
            return ["Hips pressed into the pad, don't let them lift.",
                    "Curl all the way, squeeze the hamstrings.",
                    "Slow negative."]
        }
        if has("hip thrust", "glute bridge") {
            return ["Upper back on the bench edge, chin tucked.",
                    "Drive through the heels to a flat top — no overarching.",
                    "Pause and squeeze the glutes at the top."]
        }
        if has("calf") {
            return ["Full stretch at the bottom, pause a second.",
                    "Rise all the way onto your toes.",
                    "No bouncing — slow reps."]
        }
        if has("overhead press", "shoulder press", "military", "ohp", "arnold") {
            return ["Glutes and abs tight so your lower back doesn't arch.",
                    "Press straight up, head moves through at the top.",
                    "Lower to chin/upper-chest level under control."]
        }
        if has("lateral raise", "side raise") {
            return ["Lead with the elbows, slight bend in the arms.",
                    "Raise to shoulder height, not higher.",
                    "Slow lowering; no swinging."]
        }
        if has("front raise") {
            return ["Raise to eye level, arms slightly bent.",
                    "Torso still — no leaning back.",
                    "Control the way down."]
        }
        if has("hammer") {
            return ["Thumbs up, elbows pinned to your sides.",
                    "Curl without swinging the shoulders.",
                    "Lower all the way."]
        }
        if has("curl") {
            return ["Elbows stay by your sides; only the forearms move.",
                    "Squeeze at the top, lower over 2–3 s.",
                    "Full stretch at the bottom — no half reps."]
        }
        if has("pushdown", "push-down", "pressdown") {
            return ["Elbows pinned to your sides.",
                    "Lock out fully and squeeze the triceps.",
                    "Let the forearms come up only to about parallel."]
        }
        if has("skull", "overhead extension", "french press", "tricep extension", "triceps extension") {
            return ["Upper arms stay still and close together.",
                    "Lower behind the head for a deep stretch.",
                    "Extend fully; control the weight down."]
        }
        if has("plank") {
            return ["Straight line from head to heels.",
                    "Squeeze glutes and pull ribs down.",
                    "Breathe — don't hold your breath."]
        }
        if has("crunch", "sit-up", "situp", "ab ", "abs", "leg raise", "hanging") {
            return ["Curl the ribs toward the hips; don't yank on your neck.",
                    "Exhale hard at the top.",
                    "Slow on the way down."]
        }
        switch exercise.category {
        case .chest: return ["Shoulder blades back and down.", "Control the lowering, full range.", "Squeeze the chest at the top."]
        case .back: return ["Chest up, back flat.", "Pull with the elbows, not the hands.", "Pause and squeeze each rep."]
        case .shoulders: return ["Core tight, no arching.", "Smooth, controlled reps.", "Stop just short of pain — shoulders don't like grinding."]
        case .biceps: return ["Elbows still.", "Squeeze at the top.", "Slow negative."]
        case .triceps: return ["Upper arms still.", "Lock out fully.", "Control the stretch."]
        case .legs: return ["Brace before each rep.", "Knees track over toes.", "Full range you can control."]
        case .calves: return ["Full stretch, pause at the bottom.", "All the way up.", "No bouncing."]
        case .core: return ["Ribs down, breathe out on effort.", "Slow and controlled.", "Quality over reps."]
        case .cardio: return ["Warm up first.", "Mostly conversational pace.", "Finish a little harder than you started."]
        case .other: return ["Controlled reps, full range.", "Leave 1–2 reps in the tank on the first set."]
        }
    }
}
