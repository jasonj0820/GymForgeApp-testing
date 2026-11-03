import Foundation

// MK16 + MK19.3: Expanded motivational quotes library for the Splitday widget and daily notifications.
enum QuoteTopic: String, CaseIterable, Codable, Identifiable {
    case discipline, gym, basketball, legends, stoic, career, confidence, lettingGo, wisdom, rest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discipline: "Discipline & execution"
        case .gym: "Gym & training"
        case .basketball: "Basketball & court"
        case .legends: "Legends (Goggins, Kobe, Tate…)"
        case .stoic: "Stoic & anti-overthinking"
        case .career: "Study, career & success"
        case .confidence: "Confidence & mental toughness"
        case .lettingGo: "Relationships & letting go"
        case .wisdom: "Perspective & life wisdom"
        case .rest: "Rest & recovery"
        }
    }
}

struct Quote: Equatable {
    let text: String
    var author: String? = nil
    let topic: QuoteTopic
    var tough = false
}

enum QuoteLibrary {
    private static func q(_ topic: QuoteTopic, _ lines: [String], tough: Bool = false) -> [Quote] {
        lines.map { Quote(text: $0, topic: topic, tough: tough) }
    }
    private static func qa(_ topic: QuoteTopic, _ pairs: [(String, String)], tough: Bool = false) -> [Quote] {
        pairs.map { Quote(text: $0.0, author: $0.1, topic: topic, tough: tough) }
    }

    private static let classics: [Quote] = [
        Quote(text: "While we are postponing, life speeds by.", author: "Seneca", topic: .discipline),
        Quote(text: "A journey of a thousand miles begins with a single step.", author: "Lao Tzu", topic: .discipline),
        Quote(text: "No man is free who is not master of himself.", author: "Epictetus", topic: .stoic),
        Quote(text: "We suffer more often in imagination than in reality.", author: "Seneca", topic: .stoic),
        Quote(text: "Very little is needed to make a happy life.", author: "Marcus Aurelius", topic: .rest),
        Quote(text: "First say to yourself what you would be; and then do what you have to do.", author: "Epictetus", topic: .career),
        Quote(text: "You have power over your mind — not outside events. Realize this, and you will find strength.", author: "Marcus Aurelius", topic: .stoic),
        Quote(text: "Waste no more time arguing about what a good man should be. Be one.", author: "Marcus Aurelius", topic: .discipline),
        Quote(text: "If it is not right, do not do it; if it is not true, do not say it.", author: "Marcus Aurelius", topic: .wisdom),
        Quote(text: "He who fears death will never do anything worthy of a man who is alive.", author: "Seneca", topic: .confidence),
        Quote(text: "How long are you going to wait before you demand the best for yourself?", author: "Epictetus", topic: .discipline, tough: true),
        Quote(text: "It is not because things are difficult that we do not dare; it is because we do not dare that they are difficult.", author: "Seneca", topic: .confidence)
    ]

    static let all: [Quote] = {
        var list = classics
        list += q(.discipline, [
            "Motivation starts the day. Discipline finishes it.",
            "You don't need to feel like it. You need to start.",
            "Small promises kept to yourself are how self-trust is built.",
            "The routine is the reward. Show up again tomorrow.",
            "Do the boring thing well, every day. That's the secret nobody sells.",
            "Action cures anxiety. Start with fifteen minutes.",
            "Don't wait for the mood. The mood follows the motion.",
            "Self-respect is the receipt of keeping your own word.",
            "Systems beat willpower when you're exhausted.",
            "Win the first hour of the morning and the rest of the day falls in line.",
            "Consistency is doing it on the days when nobody is clapping.",
            "Lower the friction. Open the page. Do one problem."
        ])
        list += q(.discipline, [
            "Nobody is coming to do it for you. Move.",
            "You said you would. So do it.",
            "Comfort is the enemy you invite in. Kick it out.",
            "Stop negotiating with your alarm clock. Get up.",
            "Your excuses sound smart to you and pathetic to everyone else.",
            "You don't lack time. You lack ruthless priorities.",
            "Feelings are irrelevant to the schedule. Execute.",
            "Every time you hit snooze, you vote for the weaker version of yourself.",
            "Stop looking for a shortcut. The grind is the shortcut."
        ], tough: true)

        list += q(.gym, [
            "Strength is built on the days you'd rather skip.",
            "One more good set is how a year of progress happens.",
            "Train for the person you'll be in five years.",
            "Progress is slow until it isn't. Keep logging.",
            "The bar doesn't care about your mood. Neither should you.",
            "Control the eccentric. Own every millimeter of the rep.",
            "Heavy plates don't lie. You either put in the work or you didn't.",
            "A mediocre workout beats a perfect skip every single time.",
            "Respect the warm-up, attack the working sets, earn the recovery.",
            "Progressive overload is just patience measured in kilograms.",
            "Your body adapts to what you demand of it. Demand more."
        ])
        list += q(.gym, [
            "The weights are waiting. They've been waiting all day.",
            "You don't get the body by thinking about the gym.",
            "Skip today and you're explaining it to me tomorrow.",
            "Last two reps are the only ones that actually change you. Don't rack it early.",
            "Soreness is temporary. Being weak is a choice.",
            "Put the phone down between sets. You're here to work, not scroll.",
            "Under the bar, nobody cares about your excuses. Push."
        ], tough: true)

        list += q(.basketball, [
            "Shooters shoot, but winners defend and rebound when their shot isn't falling.",
            "Footwork and balance beat raw athleticism when the fourth quarter gets tight.",
            "Great guards see the floor two passes ahead. Slow your mind down.",
            "Make your free throws when your legs are heavy. That's where games are won.",
            "Protect your ankles, strengthen your base, and own the paint.",
            "Every loose ball is a test of who wants the possession more.",
            "Conditioning is what keeps your jumper wet in the final two minutes.",
            "Play at your own pace. Never let the defender speed you up.",
            "A high basketball IQ turns a good player into an unstoppable teammate.",
            "Box out first, jump second. Fundamentals win possessions."
        ])
        list += q(.basketball, [
            "Don't complain about playing time or touches if you aren't sprinting back on defense.",
            "Tired legs miss short. Get lower on your base and follow through.",
            "Someone out there is working on their handle while you're resting.",
            "If you get beat off the dribble once, shame on them. Twice, you're lazy in your stance.",
            "Dominate your matchup. Take it personal."
        ], tough: true)

        list += qa(.legends, [
            ("Job's not finished.", "Kobe Bryant"),
            ("Rest at the end, not in the middle.", "Kobe Bryant"),
            ("Everything negative — pressure, challenges — is all an opportunity for me to rise.", "Kobe Bryant"),
            ("If you're afraid to fail, then you're probably going to fail.", "Kobe Bryant"),
            ("Once you know what failure feels like, determination chases success.", "Kobe Bryant"),
            ("The moment you give up is the moment you let someone else win.", "Kobe Bryant"),
            ("Suffering is the true test of life.", "David Goggins"),
            ("We don't rise to the level of our expectations, we fall to the level of our training.", "David Goggins"),
            ("Mental toughness is a lifestyle, not a switch you flip when it's convenient.", "David Goggins"),
            ("Discipline equals freedom.", "Jocko Willink"),
            ("Some people want it to happen, some wish it would happen, others make it happen.", "Michael Jordan"),
            ("I've failed over and over and over again in my life. And that is why I succeed.", "Michael Jordan"),
            ("Stress tolerance is the best indicator of a successful person.", "Andrew Tate"),
            ("Your mind must be stronger than your feelings.", "Andrew Tate")
        ])
        list += qa(.legends, [
            ("Nobody cares what you did yesterday. What have you done today to better yourself?", "David Goggins"),
            ("You are in danger of living a life so comfortable and soft, that you will die without ever realizing your true potential.", "David Goggins"),
            ("When you think you're done, you're only at 40% of what your body's capable of doing.", "David Goggins"),
            ("Don't stop when you're tired. Stop when you're done.", "David Goggins"),
            ("They don't know me son!", "David Goggins"),
            ("Do the impossible and you'll never doubt yourself ever again.", "Andrew Tate"),
            ("You can't beat the person who never gives up, and you can't compete with the man who works even when he's depressed.", "Andrew Tate"),
            ("Arrogance breeds complacency. Stay hungry.", "Andrew Tate"),
            ("Friends can hang out another time. Banners hang forever.", "Kobe Bryant"),
            ("Stop feeling sorry for yourself. Find the silver lining and get to work.", "Kobe Bryant"),
            ("Good. More fuel for the fire.", "Jocko Willink")
        ], tough: true)

        list += q(.stoic, [
            "You control your effort and your response. Leave the rest.",
            "What you can't change is not yours to carry.",
            "Meet the day as it comes, not as you feared it would.",
            "Judge the action, not the outcome.",
            "Overthinking is trying to solve tomorrow's problems with tonight's tired brain.",
            "Zoom out. In five years, this moment is a footnote.",
            "Not every thought in your head deserves a seat at the table.",
            "When the system is overloaded, reduce the variables and focus on the next boundary condition.",
            "You don't have to figure out your whole life tonight. Just finish the next hour.",
            "Anxiety is energy without a direction. Give it a task.",
            "Peace comes from accepting uncertainty and preparing anyway."
        ])
        list += q(.stoic, [
            "Complaining is a set with no reps. Get to work.",
            "Hard day? Good. That's the training.",
            "Stop catastrophizing. You survived 100% of your worst days so far.",
            "Your brain is lying to you because it's tired. Shut it down or put it to work.",
            "Staring at the ceiling won't fix the problem. Action will."
        ], tough: true)

        list += q(.career, [
            "Understanding fades. Practice is what makes it stick.",
            "Every calculation you check now is one you'll trust in an interview.",
            "Be the engineer people call because you're careful and reliable.",
            "Learn it like you'll have to teach it tomorrow.",
            "Great careers are many ordinary days done properly.",
            "First principles beat memorization every time.",
            "Done and reviewed beats perfect and unfinished.",
            "Your degree is the floor. Your curiosity and work ethic build the ceiling.",
            "Master the fundamentals so well that complex problems look simple.",
            "Success is rented, and the rent is due every single day.",
            "Twenty minutes of focused revision right now beats three hours of panic tomorrow."
        ])
        list += q(.career, [
            "The exam doesn't care how tired you are.",
            "One hour of real focus beats four hours of pretending.",
            "Close the tabs. Pick up the pen. Solve the problem.",
            "Nobody hands responsibility to someone who cuts corners when they're tired.",
            "Want the top-tier offer? Put in the top-tier hours."
        ], tough: true)

        list += q(.confidence, [
            "You've done hard things before. This is another one.",
            "Walk in like you belong. Then earn it.",
            "Your past wins are proof, not luck.",
            "Speak slowly. People lean in to calm voices.",
            "You didn't lose your edge; you're just carrying a heavier load right now.",
            "Confidence isn't loud. It's the quiet knowledge that you can handle whatever happens.",
            "Pressure is a privilege — it only falls on shoulders that can bear it.",
            "Don't compare your high-load season to someone else's highlight reel.",
            "Trust the man you've built through every setback.",
            "Stand tall. Your posture tells your brain how to feel."
        ])
        list += q(.confidence, [
            "Stop waiting to feel ready. Ready is a decision.",
            "Nobody remembers your nerves. They remember whether you showed up.",
            "Act like the man you want to be until you forget you're acting.",
            "Doubt is a parasite. Starve it with execution.",
            "Never apologize for having high standards for yourself."
        ], tough: true)

        list += q(.lettingGo, [
            "If they're gone, let the space be filled with your own growth.",
            "You can miss someone and still choose to move forward.",
            "Closure is something you give yourself.",
            "Don't shrink to fit somewhere you've outgrown.",
            "The right people will never make you beg to be chosen.",
            "Attraction and respect grow naturally when you are locked into your own mission.",
            "Date from abundance, never from loneliness.",
            "How someone treats you is about them. What you tolerate is about you.",
            "Invest in people who match your effort, not just your words.",
            "Your peace of mind is too expensive to trade for mixed signals."
        ])
        list += q(.lettingGo, [
            "Stop checking. Start training.",
            "They're not thinking about you right now. Think about your goals.",
            "Heartbreak is fuel. Use all of it.",
            "Never chase someone who shows you they're fine without you.",
            "Be your own first priority. Everything else is secondary."
        ], tough: true)

        list += q(.wisdom, [
            "Happiness isn't the absence of problems; it's the ability to deal with them.",
            "Don't measure your 21-year-old chapter with a 17-year-old ruler.",
            "A good life is built on strong health, honest work, and a few people you love.",
            "Gratitude turns what you have into enough while you build what's next.",
            "The days are long, but the years are fast. Be present where your feet are.",
            "Strength without kindness is brittle; resilience with warmth is unbreakable.",
            "Sometimes the most productive thing you can do is forgive yourself for a slow day and start fresh.",
            "You are not a machine. Even steel fatigues without proper design limits.",
            "Enjoy the process of becoming, not just the trophies on the shelf."
        ])
        list += q(.wisdom, [
            "Nobody is coming to write your story. Pick up the pen.",
            "Life doesn't get easier. You just get harder to break.",
            "Stop romanticizing the past. Your best chapter hasn't been built yet."
        ], tough: true)

        list += q(.rest, [
            "Recovery is part of the program, not a break from it.",
            "Sleep is where the gains and memories are banked.",
            "Rest without guilt. You'll train and study better tomorrow.",
            "A calm evening builds a sharp morning.",
            "When you're sick, resting is the most disciplined work you can do.",
            "Drink water, eat your protein, and let your nervous system reset.",
            "Stepping back for one night keeps you in the game for the whole semester."
        ])
        list += q(.rest, [
            "Phone down. Lights out. Muscles grow in the dark.",
            "Rest days are for resting, not for scrolling until 1 am.",
            "If you're sick, go to bed. Half-assing an all-nighter helps nobody."
        ], tough: true)

        return list
    }()
}

enum QuotePicker {
    static let slotHours = [8, 13, 18]

    static func slot(at date: Date, calendar: Calendar = .current) -> Int {
        let origin = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .distantPast
        let day = calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day ?? 0
        let hour = calendar.component(.hour, from: date)
        let within = slotHours.lastIndex { hour >= $0 } ?? -1
        return day * slotHours.count + within
    }

    /// 5-minute slot for the Widget timeline so quotes automatically rotate every 5 minutes.
    static func widgetSlot(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / (5 * 60))
    }

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

    static func pool(topics: Set<QuoteTopic>, tough: Bool) -> [Quote] {
        let chosen = QuoteTopic.allCases.filter { topics.isEmpty || topics.contains($0) }
        let byTopic = chosen.map { topic in QuoteLibrary.all.filter { $0.topic == topic && (tough || !$0.tough) } }
        let longest = byTopic.map(\.count).max() ?? 0
        return (0..<longest).flatMap { index in byTopic.compactMap { index < $0.count ? $0[index] : nil } }
    }

    static func quote(slot: Int, offset: Int, topics: Set<QuoteTopic>, tough: Bool) -> Quote {
        let list = pool(topics: topics, tough: tough)
        guard !list.isEmpty else { return QuoteLibrary.all[0] }
        let index = ((slot + offset) % list.count + list.count) % list.count
        return list[index]
    }
}

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
        get { defaults.object(forKey: "quotes.notify") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "quotes.notify") }
    }
    static var offset: Int {
        get { defaults.integer(forKey: "quotes.offset") }
        set { defaults.set(newValue, forKey: "quotes.offset") }
    }

    static func current(at date: Date = .now) -> Quote {
        QuotePicker.quote(slot: QuotePicker.slot(at: date), offset: offset, topics: topics, tough: tough)
    }

    static func widgetQuote(at date: Date = .now) -> Quote {
        QuotePicker.quote(slot: QuotePicker.widgetSlot(at: date), offset: offset, topics: topics, tough: tough)
    }
}
