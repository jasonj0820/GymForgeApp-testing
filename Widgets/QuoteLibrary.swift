import Foundation

// MK16: motivational quotes for the Splitday widget and 3 notifications a day.
// Compiled into the iPhone app AND the widget extension, so it only uses Foundation types.

enum QuoteTopic: String, CaseIterable, Codable, Identifiable {
    case discipline, gym, lettingGo, stoic, career, confidence, rest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discipline: "Discipline"
        case .gym: "Gym & training"
        case .lettingGo: "Letting go"
        case .stoic: "Stoic"
        case .career: "Study & career"
        case .confidence: "Confidence"
        case .rest: "Rest & recovery"
        }
    }
}

struct Quote: Equatable {
    let text: String
    var author: String? = nil
    let topic: QuoteTopic
    /// Sergeant Cluck's register; only shown with the Tough tone on.
    var tough = false
}

enum QuoteLibrary {
    private static func q(_ topic: QuoteTopic, _ lines: [String], tough: Bool = false) -> [Quote] {
        lines.map { Quote(text: $0, topic: topic, tough: tough) }
    }

    // Classics are public-domain translations (Seneca: Gummere; Epictetus and Marcus Aurelius: Long). The rest are original.
    private static let classics: [Quote] = [
        Quote(text: "While we are postponing, life speeds by.", author: "Seneca", topic: .discipline),
        Quote(text: "A journey of a thousand miles begins with a single step.", author: "Lao Tzu", topic: .discipline),
        Quote(text: "No man is free who is not master of himself.", author: "Epictetus", topic: .stoic),
        Quote(text: "We are more often frightened than hurt; and we suffer more from imagination than from reality.", author: "Seneca", topic: .stoic),
        Quote(text: "Very little is needed to make a happy life.", author: "Marcus Aurelius", topic: .rest),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus", topic: .career),
    ]

    static let all: [Quote] = {
        var list = classics
        list += q(.discipline, ["Motivation starts the day. Discipline finishes it.",
                          "You don't need to feel like it. You need to start.",
                          "Small promises kept to yourself are how trust in yourself is built.",
                          "The routine is the reward. Show up again tomorrow.",
                          "Do the boring thing well, every day. That's the secret nobody sells."])
        list += q(.discipline, ["Nobody is coming to do it for you. Move.",
                          "You said you would. So do it.",
                          "Comfort is the enemy you invite in. Kick it out."], tough: true)
        list += q(.gym, ["Strength is built on the days you'd rather skip.",
                   "One more good set is how a year of progress happens.",
                   "Train for the person you'll be in five years.",
                   "Progress is slow until it isn't. Keep logging.",
                   "The bar doesn't care about your mood. Neither should you."])
        list += q(.gym, ["The weights are waiting. They've been waiting all day.",
                   "You don't get the body by thinking about the gym.",
                   "Skip today and you're explaining it to me tomorrow."], tough: true)
        list += q(.lettingGo, ["If they're gone, let the space be filled with your own growth.",
                         "You can miss someone and still choose to move forward.",
                         "Closure is something you give yourself.",
                         "Don't shrink to fit somewhere you've outgrown.",
                         "The right people will never make you beg to be chosen."])
        list += q(.lettingGo, ["Stop checking. Start training.",
                         "They're not thinking about you right now. Think about your goals.",
                         "Heartbreak is fuel. Use all of it."], tough: true)
        list += q(.stoic, ["You control your effort and your answer. Leave the rest.",
                     "What you can't change is not yours to carry.",
                     "Meet the day as it comes, not as you feared it would.",
                     "Judge the action, not the outcome."])
        list += q(.stoic, ["Complaining is a set with no reps. Get to work.",
                     "Hard day? Good. That's the training."], tough: true)
        list += q(.career, ["Understanding fades. Practice is what makes it stick.",
                      "Every calculation you check now is one you'll trust in an interview.",
                      "Be the engineer people call because you're careful.",
                      "Learn it like you'll have to teach it tomorrow.",
                      "Great careers are many ordinary days done properly."])
        list += q(.career, ["The exam doesn't care how tired you are.",
                      "One hour of real focus beats four hours of pretending."], tough: true)
        list += q(.confidence, ["You've done hard things before. This is another one.",
                          "Walk in like you belong. Then earn it.",
                          "Your past wins are proof, not luck.",
                          "Speak slowly. People lean in to calm voices."])
        list += q(.confidence, ["Stop waiting to feel ready. Ready is a decision.",
                          "Nobody remembers your nerves. They remember whether you showed up."], tough: true)
        list += q(.rest, ["Recovery is part of the program, not a break from it.",
                    "Sleep is where the gains are banked.",
                    "Rest without guilt. You'll train better tomorrow.",
                    "A calm evening is a strong morning."])
        list += q(.rest, ["Phone down. Lights out. Muscles grow in the dark.",
                    "Rest days are for resting, not for scrolling until 1 am."], tough: true)
        return list
    }()
}

/// Which quote shows when: three slots a day (8:00, 13:00, 18:00), walking through your topics in turn.
enum QuotePicker {
    static let slotHours = [8, 13, 18]

    /// A running slot number; before 8 am belongs to the previous evening's slot.
    static func slot(at date: Date, calendar: Calendar = .current) -> Int {
        // Days since a fixed local date (ordinality(of:in:) isn't reliably local-midnight based).
        let origin = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let day = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
        let hour = calendar.component(.hour, from: date)
        let within = slotHours.lastIndex { hour >= $0 } ?? -1
        return day * slotHours.count + within
    }

    /// When the slot after `date` begins.
    static func nextSlotStart(after date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        for offset in 0...1 {
            guard let base = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            for hour in slotHours {
                if let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base), start > date { return start }
            }
        }
        return date.addingTimeInterval(3600)
    }

    /// Topics take turns (discipline, gym, …, then the next line of each), so consecutive quotes differ.
    static func pool(topics: Set<QuoteTopic>, tough: Bool) -> [Quote] {
        let chosen = QuoteTopic.allCases.filter { topics.isEmpty || topics.contains($0) }
        let byTopic = chosen.map { topic in QuoteLibrary.all.filter { $0.topic == topic && (tough || !$0.tough) } }
        let longest = byTopic.map(\.count).max() ?? 0
        return (0..<longest).flatMap { index in byTopic.compactMap { index < $0.count ? $0[index] : nil } }
    }

    static func quote(slot: Int, offset: Int, topics: Set<QuoteTopic>, tough: Bool) -> Quote {
        let list = pool(topics: topics, tough: tough)
        let index = ((slot + offset) % list.count + list.count) % list.count
        return list[index]
    }
}

/// Your choices, shared between the app and the widget through the App Group.
enum QuoteSettings {
    static let widgetKind = "SplitdayQuotes"
    private static var defaults: UserDefaults { CluckStore.defaults }

    static var topics: Set<QuoteTopic> {
        get { Set((defaults.stringArray(forKey: "quotes.topics") ?? QuoteTopic.allCases.map(\.rawValue)).compactMap(QuoteTopic.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue), forKey: "quotes.topics") }
    }
    static var tough: Bool {
        get { defaults.bool(forKey: "quotes.tough") }
        set { defaults.set(newValue, forKey: "quotes.tough") }
    }
    static var notify: Bool {
        get { defaults.object(forKey: "quotes.notify") as? Bool ?? false }   // MK19: off unless you turn it on
        set { defaults.set(newValue, forKey: "quotes.notify") }
    }
    /// Bumped by the widget's "next quote" button.
    static var offset: Int {
        get { defaults.integer(forKey: "quotes.offset") }
        set { defaults.set(newValue, forKey: "quotes.offset") }
    }

    static func current(at date: Date = .now) -> Quote {
        QuotePicker.quote(slot: QuotePicker.slot(at: date), offset: offset, topics: topics, tough: tough)
    }
}
