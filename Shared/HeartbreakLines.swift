import Foundation

/// Original breakup-fuel lines for the "Heartbreak" coach style:
/// they use the hurt as fuel without telling you you're worthless.
public enum HeartbreakLines {
    public static let lines: [String] = [
        "She left. The bar stayed. Pick it up.",
        "That's what she left you: time. Spend it here.",
        "You can't change how it ended. You can change who walks out of this gym.",
        "Missing her won't add a rep. This set will.",
        "Let it hurt. Then let it lift.",
        "Don't text her. Do another set.",
        "Every rep is a version of you she never met.",
        "Pain is fuel. Burn it on this set.",
        "Closure isn't coming. Strength is — if you earn it.",
        "Turn the empty evenings into full workouts.",
        "You gave your best to someone else. Give it to yourself now.",
        "Her silence is loud. Make the plates louder.",
        "Revenge is irrelevant. The glow-up isn't.",
        "Heartbreak builds two kinds of men. Be the one still lifting.",
        "You lost her. Don't lose yourself too.",
        "The hurt is real. So is this weight. Move it.",
        "Cry later if you need to. Lift now.",
        "She's not thinking about you right now. Think about the next rep.",
        "Your worth was never hers to decide.",
        "Make your comeback so quiet the results do the talking.",
        "Rebuild yourself rep by rep, day by day.",
        "Some chapters end so better ones get written. Write it here.",
        "She closed the door. You build the house.",
        "The best answer to rejection is relentless self-improvement.",
        "Lonely nights, heavy sets. That's the trade.",
        "Use the anger. Don't let it use you.",
        "Scroll her profile less. Lift more.",
        "She remembers who you were. Show the world who you're becoming.",
        "Nobody claps for the work in the dark. Do it anyway.",
        "Heal like a warrior: quietly, every single day.",
        "A broken heart still pumps blood. Use it.",
        "The pain of losing her fades. Strength stays.",
        "You can't control who stays. You control who you become.",
        "Stop replaying the past. Start repping the future.",
        "Every set is one less thought about her.",
        "Build a life you don't need to escape from.",
        "Hurt people quit. Healing people lift. Lift.",
        "Pour the heartbreak into the barbell. It can take it.",
        "She chose to leave. You choose to grow.",
        "Some day she'll see you and wonder. Don't do it for that — do it for you.",
        "You weren't too much. You were for the wrong person. Get stronger for the right life.",
        "Regret is hers to carry. Your job is this set.",
        "The man she left isn't the man finishing this workout.",
        "Fall apart in private. Rebuild in public.",
        "Distance from her. Closeness to your goals.",
        "Your heart got heavy. Make your lifts heavier.",
        "Breakups end relationships, not ambitions.",
        "Stop waiting for an apology. Start earning respect — yours.",
        "If she's the reason you started, let you be the reason you finish.",
        "Today you don't miss her. Today you miss nothing — not a single set.",
        // Brutal: the gut punch first, then the turn.
        "She was never attracted to you. Fine. Build a man you're proud to be.",
        "You weren't good enough for her. Get good enough for yourself — starting with this set.",
        "She didn't choose you. Make the mirror choose you.",
        "You weren't her first choice. Be your own first priority.",
        "She moved on fast. Move this weight faster.",
        "She's happier without you. Get happier without her.",
        "You were replaceable to her. Make yourself undeniable.",
        "She saw your potential and left anyway. Turn potential into proof.",
        "She found someone better. So become better — for you, not her.",
        "You begged. She left. Never beg again. Lift.",
        "You weren't worth her time. Make your time worth something.",
        "She laughed about you with her friends. Give them nothing to laugh at.",
        "You were an option. Become the standard.",
        "She never missed you. Never miss a set.",
        "You weren't enough then. That was then. Rep.",
        "She said you'd never change. Prove it wrong one rep at a time.",
        "She outgrew you. Now outgrow who you were.",
        "You were the backup plan. Be your own main plan.",
        "She left you with nothing. Nothing is a clean start.",
        "She didn't fight for you. Fight for yourself — this set.",
        "You weren't her type. Become your own kind of strong.",
        "Nobody's coming to tell you you're enough. Earn it from yourself.",
        "She saw the weak version. Nobody sees him again.",
        "You were easy to leave. Become impossible to ignore.",
        "She settled for someone else. Don't settle for one rep less.",

        // MK8.8 — longer, reflective lines
        "I used to finish a set and check if she’d replied. Tonight, I’m putting the phone away. For one hour, I’m showing up for someone who needs me: myself.",
        "The hardest rep is going home knowing she still won’t text. Train anyway. Eat anyway. Sleep anyway. There’s a life waiting for you beyond wanting her.",
        "She may never meet the man I’m becoming. That hurts. But he still deserves the chance to exist.",
        "I spent months looking for signs she wanted me. Now I’m keeping a record of something I can actually build: another rep, another session, another promise kept.",
        "I wanted her to see something special in me. Some nights, I still do. But I’m learning to finish the workout even when nobody’s watching.",
        "No physique can guarantee she’ll choose me. I’m training to stop letting that unanswered question decide how I live.",
        "I can’t lift enough to change her answer. I can show up enough to change what I believe about myself.",
        "Tonight, I miss her. Tomorrow, I might miss her again. Somewhere between those two nights, I’ll have kept one more promise to myself. That’s how I’m starting.",
        "I wanted to be her first choice so badly that I kept accepting whatever attention she had left. I can’t keep putting my own life last.",
        "The hardest part was realising the moments I replayed all night might have been ordinary moments to her. I still have a life to build when the replay stops.",
        "I thought becoming good enough would make her want me. Now I have to become someone I respect, even if she never changes her mind.",
        "I was planning how to win her heart while she was deciding whether to reply. It hurts to admit how much of my life I left waiting beside that phone.",
        "I can work on every weakness I brought into that chase and still never be the person she wants. I have to believe the work is worth doing anyway.",
        "I didn’t get the girl. I don’t get to rewrite that ending. But tomorrow morning, I still get to decide whether I keep the promises I made to myself.",
        "The hardest part is knowing I can become the man I promised her I would be—and she may never be there to meet him.",
        "I kept saying ‘one day’ like love could wait forever. Now I have mornings without her and promises I still owe myself.",
        "I would have done anything to make her stay. Now comes the harder question: will I do the work when she’s no longer here to see it?",
        "I can spend another year wishing she had stayed, or finally stop postponing the life I kept telling her we would have.",
        "Maybe she will never know how much I changed. I have to build a life worth waking up to, even if her name never lights up my phone again.",
        "She left, and I started calling myself ‘not enough.’ But that sentence gives me nowhere to go. ‘I have work to do’ hurts too—and gives me somewhere to start."
    ]

    public static func line(workout: UUID, step: Int) -> String {
        let base = workout.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let count = lines.count
        return lines[(((base + step) % count) + count) % count]
    }
}

public extension CoachStyle {
    /// Always returns a line for the workout screen (changes after every set, matches the Lock Screen
    /// for Hard Truth / Heartbreak).
    func workoutLine(workout: UUID, step: Int) -> String {
        if let line = liveLine(workout: workout, step: step) { return line }
        let lines: [String]
        switch self {
        case .pushMe:
            lines = ["Next set. No negotiating.",
                     "You didn't come here to go easy.",
                     "Last rep is the one that counts. Earn it.",
                     "Rest's over when the timer says. Then you go.",
                     "Tired is allowed. Quitting isn't.",
                     "Beat last time. That's the whole job.",
                     "Focus. One set. Right now.",
                     "Nobody remembers the easy sets."]
        case .motivating:
            lines = ["Every set today is building the next version of you.",
                     "You showed up — that's the hardest part done.",
                     "Strong reps, steady breathing. You've got this.",
                     "One more rep than last time is a win.",
                     "Progress is quiet. Keep stacking sets.",
                     "This is how strong people are made — one set at a time.",
                     "Proud of the work. Keep it rolling.",
                     "Finish this one strong."]
        case .analytical:
            lines = ["Quality reps beat junk volume. Control the lowering.",
                     "Full range, consistent tempo — that's what moves the numbers.",
                     "Rest fully on heavy sets; strength output drops when you rush.",
                     "Track it honestly. The data only helps if it's real.",
                     "Progressive overload: one more rep or a little more load.",
                     "Most growth comes from the last 3–5 reps before failure.",
                     "Consistency over weeks beats intensity in one session.",
                     "Log effort accurately — it steers your next session."]
        case .supportive:
            lines = ["Whatever today looks like, you're here. That counts.",
                     "Breathe. You're doing great.",
                     "Listen to your body — good form first.",
                     "Small wins add up. This set is one of them.",
                     "No pressure. Just do your best rep.",
                     "You're stronger than when you started.",
                     "Be proud of showing up today.",
                     "Take your time. Quality over speed."]
        case .hardTruth, .heartbreak:
            lines = ["Next set."]
        }
        let base = workout.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return lines[(((base + step) % lines.count) + lines.count) % lines.count]
    }

    /// Line for the Lock Screen / Watch rest screen, or nil if this style doesn't use them.
    func liveLine(workout: UUID, step: Int) -> String? {
        switch self {
        case .hardTruth: return HardTruthLines.line(workout: workout, step: step)
        case .heartbreak: return HeartbreakLines.line(workout: workout, step: step)
        default: return nil
        }
    }
}
