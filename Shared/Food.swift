import Foundation

// MARK: - MK24 (G1/G2): food log, saved meals, recipes, meal prep, water, caffeine, day tags, goal weight

public enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    /// From the time eaten: before 10:30 breakfast, before 15:00 lunch, 17:00–21:00 dinner, otherwise a snack.
    public static func at(_ date: Date, calendar: Calendar = .current) -> Meal {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        switch minutes {
        case ..<630: return .breakfast
        case ..<900: return .lunch
        case 1020..<1260: return .dinner
        default: return .snack
        }
    }
}

public struct FoodEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var name: String
    public var proteinG: Double
    public var calories: Double?
    public var meal: Meal
    public init(id: UUID = UUID(), date: Date = .now, name: String, proteinG: Double, calories: Double?, meal: Meal? = nil) {
        self.id = id
        self.date = date
        self.name = name
        self.proteinG = proteinG
        self.calories = calories
        self.meal = meal ?? Meal.at(date)
    }
}

public struct SavedMeal: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var proteinG: Double
    public var calories: Double?
    public var barcode: String?
    public init(id: UUID = UUID(), name: String, proteinG: Double, calories: Double?, barcode: String? = nil) {
        self.id = id
        self.name = name
        self.proteinG = proteinG
        self.calories = calories
        self.barcode = barcode
    }
}

public struct Ingredient: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Free text for the shopping list ("500 g", "2 tins").
    public var amount: String
    public var proteinG: Double
    public var calories: Double
    public var cost: Double
    public init(id: UUID = UUID(), name: String, amount: String = "", proteinG: Double = 0, calories: Double = 0, cost: Double = 0) {
        self.id = id
        self.name = name
        self.amount = amount
        self.proteinG = proteinG
        self.calories = calories
        self.cost = cost
    }
}

public struct Recipe: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var servings: Int
    public var ingredients: [Ingredient]
    public var notes: String
    public init(id: UUID = UUID(), name: String, servings: Int = 4, ingredients: [Ingredient] = [], notes: String = "") {
        self.id = id
        self.name = name
        self.servings = servings
        self.ingredients = ingredients
        self.notes = notes
    }

    private var serves: Double { Double(max(servings, 1)) }
    public var proteinPerServe: Double { ingredients.reduce(0) { $0 + $1.proteinG } / serves }
    public var caloriesPerServe: Double { ingredients.reduce(0) { $0 + $1.calories } / serves }
    public var costPerServe: Double { ingredients.reduce(0) { $0 + $1.cost } / serves }
}

/// A recipe in this week's meal prep, made `batches` times.
public struct PrepItem: Codable, Equatable, Identifiable {
    public var recipeID: UUID
    public var batches: Int
    public var id: UUID { recipeID }
    public init(recipeID: UUID, batches: Int = 1) {
        self.recipeID = recipeID
        self.batches = batches
    }
}

public struct ShoppingLine: Equatable, Identifiable {
    public var name: String
    public var amounts: [String]
    public var id: String { name.lowercased() }
}

public enum ShoppingList {
    /// Everything this week's prep needs, one line per ingredient (same name = one line), A–Z.
    public static func make(_ plan: [PrepItem], recipes: [Recipe]) -> [ShoppingLine] {
        var lines: [String: ShoppingLine] = [:]
        for item in plan {
            guard let recipe = recipes.first(where: { $0.id == item.recipeID }) else { continue }
            for ingredient in recipe.ingredients {
                let key = ingredient.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !key.isEmpty else { continue }
                var line = lines[key] ?? ShoppingLine(name: ingredient.name.trimmingCharacters(in: .whitespaces), amounts: [])
                let amount = ingredient.amount.trimmingCharacters(in: .whitespaces)
                if !amount.isEmpty { line.amounts += Array(repeating: amount, count: max(item.batches, 1)) }
                lines[key] = line
            }
        }
        return lines.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Adds up amounts with the same unit ("500 g" + "250 g" → "750 g"); anything else is listed as is.
    public static func total(_ amounts: [String]) -> String {
        var sums: [String: Double] = [:]
        var order: [String] = []
        var other: [String] = []
        for amount in amounts {
            let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
            if let value = Double(parts.first?.replacingOccurrences(of: ",", with: ".") ?? "") {
                let unit = parts.count > 1 ? parts[1] : ""
                if sums[unit] == nil { order.append(unit) }
                sums[unit, default: 0] += value
            } else {
                other.append(amount)
            }
        }
        let summed = order.map { unit in (GFNumber.text(sums[unit] ?? 0) + (unit.isEmpty ? "" : " " + unit)) }
        return (summed + other).joined(separator: " + ")
    }
}

public struct CaffeineEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var mg: Int
    public init(id: UUID = UUID(), date: Date = .now, mg: Int) {
        self.id = id
        self.date = date
        self.mg = mg
    }
}

public enum DayTagKind: String, Codable, CaseIterable, Identifiable {
    case bigNight
    public var id: String { rawValue }
    public var title: String { "Big night out" }
}

public struct DayTag: Codable, Equatable {
    public var date: Date
    public var kind: DayTagKind
    public init(date: Date, kind: DayTagKind) {
        self.date = date
        self.kind = kind
    }
}

public struct GoalWeight: Codable, Equatable {
    public var kg: Double
    public var by: Date?
    /// MK24.2: your weight when the goal was set, so going past the goal counts as reaching it.
    public var startKg: Double?
    public init(kg: Double, by: Date?, startKg: Double? = nil) {
        self.kg = kg
        self.by = by
        self.startKg = startKg
    }
}

// MARK: - Reading a nutrition label (98)

public enum LabelParser {
    public struct Result: Equatable {
        public var proteinPerServe: Double?
        public var proteinPer100: Double?
        public var kcalPerServe: Double?
        public var kcalPer100: Double?
        public var servingGrams: Double?
    }

    static func numbers(in line: String) -> [Double] {
        var out: [Double] = []
        var current = ""
        // "1,620" is a thousands separator, "4,2" a decimal comma.
        let text = line.replacingOccurrences(of: #"(\d),(\d{3})(?!\d)"#, with: "$1$2", options: .regularExpression)
        for c in text + " " {
            if c.isNumber || ((c == "." || c == ",") && !current.isEmpty) {
                current.append(c == "," ? "." : c)
            } else {
                if let v = Double(current.trimmingCharacters(in: CharacterSet(charactersIn: "."))) { out.append(v) }
                current = ""
            }
        }
        return out
    }

    /// Lines as OCR reads them (Australian panels: "Per serve" then "Per 100 g" columns; energy usually in kJ).
    public static func parse(_ lines: [String]) -> Result {
        var result = Result()
        for raw in lines {
            let line = raw.lowercased()
            let values = numbers(in: line)
            if line.contains("serving size") || line.contains("serve size") {
                result.servingGrams = values.first
            } else if line.contains("protein"), result.proteinPerServe == nil, !values.isEmpty {
                result.proteinPerServe = values[0]
                result.proteinPer100 = values.count > 1 ? values[1] : nil
            } else if line.contains("energy") || line.contains("calories"), result.kcalPerServe == nil, !values.isEmpty {
                let isKJ = line.contains("kj") && !line.contains("kcal")
                let factor = isKJ ? 1 / 4.184 : 1
                // "Energy 1250kJ (299 Cal) 1560kJ (373 Cal)": kcal in brackets win when present.
                if line.contains("cal"), line.contains("kj") {
                    let kcal = values.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
                    result.kcalPerServe = kcal.first
                    result.kcalPer100 = kcal.count > 1 ? kcal[1] : nil
                } else {
                    result.kcalPerServe = (values[0] * factor).rounded()
                    result.kcalPer100 = values.count > 1 ? (values[1] * factor).rounded() : nil
                }
            }
        }
        return result
    }
}

// MARK: - "Two eggs and toast" (99)

public enum FoodEstimate {
    public struct Item: Equatable {
        public var name: String
        public var proteinG: Double
        public var calories: Double
        public init(name: String, proteinG: Double, calories: Double) {
            self.name = name
            self.proteinG = proteinG
            self.calories = calories
        }
    }

    /// Reads the model's answer: one food per line as "name | protein g | kcal".
    public static func parse(_ text: String) -> [Item] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let name = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            guard !name.isEmpty, let protein = LabelParser.numbers(in: parts[1]).first,
                  let kcal = LabelParser.numbers(in: parts[2]).first else { return nil }
            return Item(name: name, proteinG: protein, calories: kcal)
        }
    }

    /// Typical serves, for when Apple's model isn't available. (protein g, kcal) per serve, or per 100 g with grams given.
    static let table: [(words: [String], name: String, serve: (Double, Double), per100: (Double, Double)?)] = [
        (["egg", "eggs"], "Egg", (6.3, 72), nil),
        (["chicken"], "Chicken breast", (31, 165), (31, 165)),
        (["beef", "mince", "steak"], "Beef", (26, 250), (26, 250)),
        (["salmon"], "Salmon", (25, 208), (20, 208)),
        (["tuna"], "Tuna (tin)", (24, 110), (24, 110)),
        (["shake", "whey", "scoop"], "Protein shake", (24, 120), nil),
        (["yoghurt", "yogurt"], "Greek yoghurt", (17, 150), (10, 97)),
        (["milk"], "Milk (glass)", (8.5, 125), (3.4, 50)),
        (["toast", "bread", "slice", "slices"], "Bread (slice)", (3.5, 85), nil),
        (["rice"], "Rice (cup, cooked)", (4.3, 205), (2.7, 130)),
        (["pasta"], "Pasta (cup, cooked)", (8, 220), (5.8, 158)),
        (["oats", "porridge"], "Oats (½ cup)", (5, 150), (13, 389)),
        (["banana", "bananas"], "Banana", (1.3, 105), nil),
        (["apple", "apples"], "Apple", (0.5, 95), nil),
        (["cheese"], "Cheese (slice)", (5, 80), (25, 400)),
        (["tofu"], "Tofu", (15, 145), (15, 145)),
        (["lentils", "beans"], "Lentils / beans (cup)", (18, 230), (9, 116)),
        (["peanut", "butter"], "Peanut butter (tbsp)", (4, 95), nil),
        (["bar"], "Protein bar", (20, 200), nil),
        (["potato", "potatoes"], "Potato", (4, 160), (2, 77)),
    ]

    /// Words between a number and the food ("2 cups of rice"): the number is still the count.
    static let measures: Set<String> = ["cup", "cups", "slice", "slices", "scoop", "scoops", "tin", "tins", "can", "cans",
                                        "serve", "serves", "serving", "servings", "piece", "pieces", "bowl", "bowls",
                                        "glass", "glasses", "tbsp", "tablespoon", "tablespoons"]

    /// A rough guess from a table of common foods: "200g chicken and rice", "3 eggs", "two slices of toast".
    public static func guess(_ text: String) -> [Item] {
        let tokens = SpokenSet.normalise(text)
        var items: [Item] = []
        var used = Set<String>()
        for (index, token) in tokens.enumerated() {
            guard let entry = table.first(where: { $0.words.contains(token) }), !used.contains(entry.name) else { continue }
            used.insert(entry.name)
            // A number just before ("3 eggs", "200 g chicken", "200 grams of chicken", "2 cups of rice").
            var count = 1.0
            var grams: Double?
            var back = index - 1
            if back >= 0, tokens[back] == "of" { back -= 1 }
            if back >= 1, tokens[back] == "g", let n = Double(tokens[back - 1]) {
                grams = n
            } else {
                if back >= 0, measures.contains(tokens[back]) { back -= 1 }
                if back >= 0, let n = Double(tokens[back]) { count = n }
            }
            if let grams, let per100 = entry.per100 {
                items.append(Item(name: "\(entry.name), \(GFNumber.text(grams)) g", proteinG: (per100.0 * grams / 100).rounded(),
                                  calories: (per100.1 * grams / 100).rounded()))
            } else {
                let n = grams == nil && count > 0 && count < 20 ? count : 1
                items.append(Item(name: n == 1 ? entry.name : "\(GFNumber.text(n)) × \(entry.name)",
                                  proteinG: (entry.serve.0 * n).rounded(), calories: (entry.serve.1 * n).rounded()))
            }
        }
        return items
    }
}
