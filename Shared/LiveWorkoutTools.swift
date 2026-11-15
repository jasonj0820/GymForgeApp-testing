import Foundation

// MARK: - MK24 live workout: machine taken, reorder what's left, finish time

public extension ActiveWorkoutState {
    /// Superset groups in order, as index ranges ([0], [1, 2], [3]…).
    var groups: [[Int]] {
        var out: [[Int]] = []
        var cursor = 0
        while cursor < routine.exercises.count {
            let group = supersetGroup(of: cursor)
            out.append(group)
            cursor = (group.last ?? cursor) + 1
        }
        return out
    }

    private func groupFinished(_ group: [Int]) -> Bool {
        group.allSatisfy { isFinished(routine.exercises[$0]) }
    }

    /// "Machine taken": the current exercise (its whole superset) moves behind the next one you haven't done,
    /// and that one comes up now. false when there's nothing else left to do first.
    @discardableResult
    mutating func machineTaken() -> Bool {
        let all = groups
        guard let current = all.firstIndex(where: { $0.contains(exerciseIndex) }) else { return false }
        guard let next = all.indices.first(where: { $0 > current && !groupFinished(all[$0]) }) else {
            // Nothing unfinished after it: go back to one earlier on (jumped past), if there is one.
            guard let earlier = all.indices.first(where: { $0 < current && !groupFinished(all[$0]) }),
                  let first = all[earlier].first else { return false }
            jump(toExercise: first)
            return true
        }
        let nextID = all[next].first.map { routine.exercises[$0].id }
        var order = Array(all.indices)
        order.remove(at: current)
        order.insert(current, at: (order.firstIndex(of: next) ?? order.count - 1) + 1)
        apply(groupOrder: order.map { all[$0] })
        moveTo(itemID: routine.exercises.firstIndex { $0.id == nextID })
        return true
    }

    /// Reorders the exercises not finished yet (by the id of each superset's first exercise). Finished ones keep
    /// their place at the front. Stays on the current exercise if it's half done, otherwise goes to the new first.
    mutating func reorderRemaining(_ firstIDs: [UUID]) {
        let all = groups
        let done = all.filter { groupFinished($0) }
        var left = all.filter { !groupFinished($0) }
        left.sort { a, b in
            let ia = firstIDs.firstIndex(of: routine.exercises[a[0]].id) ?? Int.max
            let ib = firstIDs.firstIndex(of: routine.exercises[b[0]].id) ?? Int.max
            return ia < ib
        }
        let oldIDs = routine.exercises.map(\.id)
        let currentID = currentItem?.id
        let halfDone = currentItem.map { !sets(for: $0).isEmpty && !isFinished($0) } ?? false
        apply(groupOrder: done + left)
        if halfDone, let currentID, let index = routine.exercises.firstIndex(where: { $0.id == currentID }) {
            exerciseIndex = index
        } else if let first = left.first?.first {
            let id = oldIDs[first]
            moveTo(itemID: routine.exercises.firstIndex { $0.id == id })
        }
    }

    // Helpers ------------------------------------------------------------------------------------------------

    private mutating func apply(groupOrder: [[Int]]) {
        let old = routine.exercises
        var items = groupOrder.flatMap { $0.map { old[$0] } }
        for i in items.indices { items[i].order = i }
        routine.exercises = items
        revision += 1
    }

    private mutating func moveTo(itemID index: Int?) {
        guard let index else { return }
        exerciseIndex = index
        setIndex = sets(for: routine.exercises[index]).count
    }

    /// Sets still to do (skipped exercises and optional cardio don't count).
    var setsLeft: Int {
        routine.exercises.filter { !$0.exercise.isCardio && !isSkipped($0) }
            .reduce(0) { $0 + max(0, $1.exercise.defaultSets - sets(for: $1).count) }
    }
}

public enum FinishEstimate {
    /// Seconds per set, rest included: this session's pace once 3 sets are in, otherwise the last time you did
    /// this routine, otherwise 2½ minutes. Kept between 1 and 6 minutes.
    public static func secondsPerSet(elapsed: TimeInterval, setsDone: Int, previous: (duration: TimeInterval, sets: Int)?) -> Double {
        let pace: Double
        if setsDone >= 3 {
            pace = elapsed / Double(setsDone)
        } else if let previous, previous.sets > 0 {
            pace = previous.duration / Double(previous.sets)
        } else {
            pace = 150
        }
        return min(max(pace, 60), 360)
    }

    public static func finish(now: Date, setsLeft: Int, secondsPerSet: Double) -> Date {
        now.addingTimeInterval(Double(setsLeft) * secondsPerSet)
    }
}

// MARK: - Say the set

/// MK24: "80 for 10", "80 kilos 10 reps", "10 reps", "body weight 12", "one hundred and two point five for eight".
public enum SpokenSet {
    public struct Parsed: Equatable {
        public var weightKg: Double?
        public var reps: Int?
        public var bodyweight: Bool
        public init(weightKg: Double?, reps: Int?, bodyweight: Bool = false) {
            self.weightKg = weightKg
            self.reps = reps
            self.bodyweight = bodyweight
        }
    }

    private static let small: [String: Double] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static let synonyms: [String: String] = [
        "kgs": "kg", "kilograms": "kg", "kilogram": "kg", "kilos": "kg", "kilo": "kg", "k": "kg",
        "x": "for", "by": "for", "at": "for", "times": "for", "rep": "reps", "bodyweight": "bw",
    ]

    /// Words → digits ("one hundred and two point five" → "102.5"), units tidied ("80kg" → "80 kg").
    public static func normalise(_ text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for c in text.lowercased() {
            if let p = previous, (p.isNumber && c.isLetter) || (p.isLetter && c.isNumber) { spaced.append(" ") }
            spaced.append(c.isLetter || c.isNumber || c == "." ? c : " ")
            previous = c
        }
        let words = spaced.split(separator: " ").map { word -> String in
            var w = String(word)
            while w.hasSuffix(".") { w.removeLast() }
            while w.hasPrefix(".") { w.removeFirst() }
            return synonyms[w] ?? w
        }.filter { !$0.isEmpty }
        var out: [String] = []
        var number: Double?
        var decimal: String?
        func flush() {
            if let n = number {
                out.append(decimal.map { $0.isEmpty ? GFNumber.text(n) : GFNumber.text(n) + "." + $0 } ?? GFNumber.text(n))
            }
            number = nil
            decimal = nil
        }
        for (i, w) in words.enumerated() {
            if decimal != nil, let digit = small[w], digit < 10 {
                decimal! += String(Int(digit))
            } else if let value = small[w] {
                if let n = number, decimal == nil,
                   (n >= 100 && n.truncatingRemainder(dividingBy: 100) == 0) || (n >= 20 && n < 100 && n.truncatingRemainder(dividingBy: 10) == 0 && value < 10) {
                    number = n + value
                } else {
                    flush()
                    number = value
                }
            } else if w == "hundred" {
                number = (number ?? 1) * 100
            } else if w == "and", number != nil, i + 1 < words.count, small[words[i + 1]] != nil {
                continue   // "one hundred and two"
            } else if w == "point", number != nil, decimal == nil {
                decimal = ""
            } else if let value = Double(w) {
                if decimal != nil, w.allSatisfy(\.isNumber) { decimal! += w } else { flush(); number = value }
            } else {
                flush()
                out.append(w)
            }
        }
        flush()
        return out
    }

    public static func parse(_ text: String) -> Parsed? {
        let tokens = normalise(text)
        let bodyweight = tokens.contains("bw") || text.lowercased().contains("body weight")
        var numbers: [(value: Double, next: String?)] = []
        for (i, t) in tokens.enumerated() {
            if let v = Double(t) { numbers.append((v, i + 1 < tokens.count ? tokens[i + 1] : nil)) }
        }
        guard !numbers.isEmpty else { return nil }
        if numbers.count == 1 {
            let n = numbers[0]
            if n.next == "kg" { return Parsed(weightKg: n.value, reps: nil) }
            // A lone whole number is reps ("10", "10 reps", "body weight 12").
            guard n.value == n.value.rounded(), n.value <= 100 else { return Parsed(weightKg: n.value, reps: nil) }
            return Parsed(weightKg: bodyweight ? 0 : nil, reps: Int(n.value), bodyweight: bodyweight)
        }
        // Two numbers: weight then reps, unless they said "reps" after the first ("10 reps at 80").
        var weight = numbers[0].value
        var reps = numbers[1].value
        if numbers[0].next == "reps" || numbers[1].next == "kg" { swap(&weight, &reps) }
        guard reps == reps.rounded(), reps > 0, reps <= 100 else { return nil }
        return Parsed(weightKg: weight, reps: Int(reps), bodyweight: bodyweight)
    }
}

/// Whole numbers without ".0".
public enum GFNumber {
    public static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
