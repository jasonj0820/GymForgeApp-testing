import Foundation

/// Original no-excuses lines for the "Hard Truth" coach style.
/// Shown on the Lock Screen / Dynamic Island during workouts and on the Watch rest screen.
public enum HardTruthLines {
    public static let lines: [String] = [
        "Discipline is doing it when you don't feel like it.",
        "Nobody is coming to save you. Good. Save yourself.",
        "Your comfort zone is a nice place. Nothing grows there.",
        "You don't get the body you want. You get the body you earn.",
        "Motivation leaves. Discipline stays. Be the one who stays.",
        "Every rep you skip is a promise to yourself you broke.",
        "Tired is a feeling. Done is a decision.",
        "The version of you that quits is still in there. Starve him.",
        "Pain of discipline weighs ounces. Pain of regret weighs tons.",
        "You said you wanted it. Prove it on this set.",
        "Average is crowded. Do the rep they won't.",
        "The bar doesn't care how your day went. Lift it anyway.",
        "Hard choices, easy life. Easy choices, hard life.",
        "Stop negotiating with yourself. Do the set.",
        "One more rep is where the change actually happens.",
        "You're not tired. You're uncomfortable. Learn the difference.",
        "Nobody remembers the workouts you skipped — except your body.",
        "Weak days still count if you show up.",
        "Excuses are just lies you tell yourself in a calm voice.",
        "The weight is honest. Be as honest as the weight.",
        "You can be sore tomorrow or sorry tomorrow. Pick.",
        "Respect is built in the sets no one sees.",
        "Your future self is watching. Don't embarrass him.",
        "If it was easy, everyone would look like this.",
        "Rest is earned. Get back under the bar.",
        "Consistency beats intensity. Today, bring both.",
        "You're one set closer than you were a minute ago.",
        "Fear of the weight ends the moment you lift it.",
        "Your mind quits long before your body does. Override it.",
        "Win the set. Then win the next one.",
        "Champions are made on ordinary Tuesdays like this.",
        "Do what you said you would do. That's the whole secret.",
        "Show up, shut up, lift.",
        "Feelings are visitors. Let them come and go. Keep lifting.",
        "Being broke, weak or lazy is a habit. So is winning.",
        "The last rep is the only one that changes you.",
        "Nobody owes you results. Go take them.",
        "Your goals don't care about your mood.",
        "Strong people aren't born. They're forged — one set at a time.",
        "Finish what you started. Every time."
    ]

    /// A stable line for a given step of the workout, so it changes every set but not every second.
    public static func line(seed: Int) -> String {
        lines[((seed % lines.count) + lines.count) % lines.count]
    }

    /// Same line on iPhone and Watch for the same workout and set count.
    public static func line(workout: UUID, step: Int) -> String {
        let base = workout.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return line(seed: base + step)
    }
}
