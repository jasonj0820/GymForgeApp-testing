import Foundation

/// MK24 (G1): the food log behind protein and calories, saved meals, recipes, meal prep and barcode lookups.
/// Every entry also adds to the day's protein / calorie totals, so everything that already reads those keeps working.
extension PhoneAppStore {
    func logFood(_ entry: FoodEntry) {
        extras.foodLog.append(entry)
        extras.foodLog.removeAll { $0.date < Date.now.addingTimeInterval(-400 * 86_400) }
        if entry.proteinG > 0 { addProtein(entry.proteinG) } else { saveExtras() }
        if let kcal = entry.calories, kcal > 0 { addCalories(kcal) }
    }

    func deleteFood(_ entry: FoodEntry) {
        extras.foodLog.removeAll { $0.id == entry.id }
        if Calendar.current.isDateInToday(entry.date) {
            if entry.proteinG > 0 { addProtein(-entry.proteinG) } else { saveExtras() }
            if let kcal = entry.calories, kcal > 0 { addCalories(-kcal) }
        } else {
            saveExtras()
        }
    }

    func moveFood(_ entry: FoodEntry, to meal: Meal) {
        guard let index = extras.foodLog.firstIndex(where: { $0.id == entry.id }) else { return }
        extras.foodLog[index].meal = meal
        saveExtras()
    }

    var foodToday: [FoodEntry] { extras.foodLog.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date } }

    /// Protein per meal today (logged foods only; quick +10 g taps aren't tied to a meal).
    var proteinByMeal: [(meal: Meal, grams: Double)] {
        let today = foodToday
        return Meal.allCases.map { meal in (meal, today.filter { $0.meal == meal }.reduce(0) { $0 + $1.proteinG }) }
    }

    /// Foods eaten in the last 30 days, newest first, one per name.
    var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        return extras.foodLog.filter { $0.date > Date.now.addingTimeInterval(-30 * 86_400) }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.name.lowercased()).inserted }
            .prefix(15).map { $0 }
    }

    func saveMeal(_ meal: SavedMeal) {
        extras.savedMeals.removeAll { $0.id == meal.id || (meal.barcode != nil && $0.barcode == meal.barcode) }
        extras.savedMeals.append(meal)
        extras.savedMeals.sort { $0.name.lowercased() < $1.name.lowercased() }
        saveExtras()
    }

    func deleteSavedMeal(_ id: UUID) {
        extras.savedMeals.removeAll { $0.id == id }
        saveExtras()
    }

    // MARK: Recipes and meal prep (95, 96)

    func saveRecipe(_ recipe: Recipe) {
        if let index = extras.recipes.firstIndex(where: { $0.id == recipe.id }) {
            extras.recipes[index] = recipe
        } else {
            extras.recipes.append(recipe)
        }
        saveExtras()
    }

    func deleteRecipe(_ id: UUID) {
        extras.recipes.removeAll { $0.id == id }
        extras.prepPlan.removeAll { $0.recipeID == id }
        saveExtras()
    }

    func batches(of recipe: Recipe) -> Int { extras.prepPlan.first { $0.recipeID == recipe.id }?.batches ?? 0 }

    func setPrep(_ recipe: Recipe, batches: Int) {
        extras.prepPlan.removeAll { $0.recipeID == recipe.id }
        if batches > 0 { extras.prepPlan.append(PrepItem(recipeID: recipe.id, batches: batches)) }
        saveExtras()
    }

    var shoppingList: [ShoppingLine] { ShoppingList.make(extras.prepPlan, recipes: extras.recipes) }

    // MARK: Barcodes (97)

    /// A product from a barcode: saved ones first, then Open Food Facts (needs the internet).
    func lookupBarcode(_ code: String) async -> BarcodeProduct? {
        if let saved = extras.savedMeals.first(where: { $0.barcode == code }) {
            return BarcodeProduct(code: code, name: saved.name, proteinPerServe: saved.proteinG, kcalPerServe: saved.calories,
                                  proteinPer100: nil, kcalPer100: nil, servingGrams: nil)
        }
        return await OpenFoodFacts.product(code)
    }
}

struct BarcodeProduct: Equatable {
    var code: String
    var name: String
    var proteinPerServe: Double?
    var kcalPerServe: Double?
    var proteinPer100: Double?
    var kcalPer100: Double?
    var servingGrams: Double?
}

enum OpenFoodFacts {
    static func product(_ code: String) async -> BarcodeProduct? {
        guard !Demo.isOn, code.allSatisfy(\.isNumber),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_quantity") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Splitday/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1, let product = json["product"] as? [String: Any] else { return nil }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            if let value = nutriments[key] as? Double { return value }
            if let value = nutriments[key] as? Int { return Double(value) }
            if let text = nutriments[key] as? String { return Double(text) }
            return nil
        }
        let brand = (product["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        let name = [brand, product["product_name"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let serving = (product["serving_quantity"] as? Double) ?? (product["serving_quantity"] as? String).flatMap(Double.init)
        return BarcodeProduct(code: code, name: name.isEmpty ? "Scanned food" : name,
                              proteinPerServe: number("proteins_serving"), kcalPerServe: number("energy-kcal_serving"),
                              proteinPer100: number("proteins_100g"), kcalPer100: number("energy-kcal_100g"),
                              servingGrams: serving)
    }
}
