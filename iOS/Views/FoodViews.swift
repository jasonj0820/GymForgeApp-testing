import SwiftUI
import Vision
import VisionKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Food today (G1: 94, 100)

/// What you've eaten today by meal, with protein per meal against an even split of your target.
struct FoodTodayCard: View {
    @EnvironmentObject private var store: PhoneAppStore
    @State private var adding = false

    var body: some View {
        let today = store.foodToday
        let perMeal = store.proteinTargetG.map { $0 / 4 }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Food today").font(.headline)
                Spacer()
                Button { adding = true } label: { Label("Add food", systemImage: "plus.circle.fill") }
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 8) {
                ForEach(store.proteinByMeal, id: \.meal) { item in
                    VStack(spacing: 3) {
                        Text("\(Int(item.grams)) g").font(.subheadline.bold().monospacedDigit())
                        SwiftUI.ProgressView(value: min(item.grams / max(perMeal ?? 30, 1), 1))
                            .tint(item.grams >= (perMeal ?? 30) * 0.8 ? .green : .accentColor)
                        Text(item.meal.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let perMeal {
                Text("Protein by meal. About \(Int(perMeal)) g at each of 4 meals spreads your \(Int(perMeal * 4)) g evenly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Meal.allCases) { meal in
                let rows = today.filter { $0.meal == meal }
                if !rows.isEmpty {
                    Text(meal.title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary).padding(.top, 2)
                    ForEach(rows) { entry in
                        HStack {
                            Text(entry.name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(GFFormat.kg(entry.proteinG)) g" + (entry.calories.map { " · \(Int($0)) kcal" } ?? ""))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Menu("Move to") {
                                ForEach(Meal.allCases.filter { $0 != meal }) { other in
                                    Button(other.title) { store.moveFood(entry, to: other) }
                                }
                            }
                            Button(role: .destructive) { store.deleteFood(entry) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            NavigationLink { RecipeBookView() } label: {
                Label("Recipe book & meal prep", systemImage: "book.closed").font(.subheadline)
            }
        }
        .card()
        .sheet(isPresented: $adding) { FoodAddSheet().environmentObject(store) }
    }
}

// MARK: - Adding food

@MainActor
enum FoodAI {
    static var available: Bool { AskCoach.unavailableReason == nil }

    /// Apple's on-device model, when it's there. nil = not available or no answer.
    static func estimate(_ text: String) async -> [FoodEstimate.Item]? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), available {
            let session = LanguageModelSession(instructions: """
            Estimate the protein and calories of each food described, using typical Australian serving sizes \
            unless amounts are given. Answer with one line per food in exactly this form and nothing else:
            food name | protein in grams | calories in kcal
            """)
            if let response = try? await session.respond(to: text) {
                let items = FoodEstimate.parse(response.content)
                return items.isEmpty ? nil : items
            }
        }
        #endif
        return nil
    }
}

struct FoodAddSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var meal = Meal.at(.now)
    @State private var described = ""
    @State private var estimates: [FoodEstimate.Item] = []
    @State private var estimatedByModel = false
    @State private var estimating = false
    @State private var name = ""
    @State private var protein = ""
    @State private var calories = ""
    @State private var saveAsMeal = false
    @State private var scanning = false
    @State private var readingLabel = false
    @State private var product: BarcodeProduct?
    @State private var lookingUp = false
    @State private var notFound: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Meal", selection: $meal) {
                    ForEach(Meal.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("e.g. 200 g chicken, rice and 2 eggs", text: $described, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        Task { await estimate() }
                    } label: {
                        if estimating { HStack { SwiftUI.ProgressView(); Text("Estimating…") } } else { Label("Estimate", systemImage: "wand.and.stars") }
                    }
                    .disabled(described.trimmingCharacters(in: .whitespaces).isEmpty || estimating)
                    ForEach(estimates.indices, id: \.self) { index in
                        let item = estimates[index]
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text("\(GFFormat.kg(item.proteinG)) g · \(Int(item.calories)) kcal").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { estimates.remove(atOffsets: $0) }
                    if !estimates.isEmpty {
                        Button("Add \(estimates.count) food\(estimates.count == 1 ? "" : "s")") {
                            for item in estimates { store.logFood(FoodEntry(name: item.name, proteinG: item.proteinG, calories: item.calories, meal: meal)) }
                            done()
                        }
                        .bold()
                    }
                } header: {
                    Text("Type or say what you ate")
                } footer: {
                    Text(estimates.isEmpty
                         ? (FoodAI.available ? "Estimated on your iPhone by Apple's model. Use the keyboard's mic to say it." : "A rough guess from common foods (Apple's on-device model gives better ones on iOS 26, iPhone 15 Pro or later). Use the keyboard's mic to say it.")
                         : (estimatedByModel ? "Estimates. Swipe one away if it's wrong." : "A rough guess from common foods. Swipe one away if it's wrong."))
                }

                Section("Scan") {
                    Button { scanning = true } label: { Label("Barcode", systemImage: "barcode.viewfinder") }
                        .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                    Button { readingLabel = true } label: { Label("Nutrition label", systemImage: "text.viewfinder") }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    if lookingUp { HStack { SwiftUI.ProgressView(); Text("Looking it up…") } }
                    if let notFound { Text(notFound).font(.footnote).foregroundStyle(.orange) }
                }

                if !store.extras.savedMeals.isEmpty {
                    Section("Saved meals") {
                        ForEach(store.extras.savedMeals) { saved in
                            Button {
                                store.logFood(FoodEntry(name: saved.name, proteinG: saved.proteinG, calories: saved.calories, meal: meal))
                                done()
                            } label: { foodRow(saved.name, saved.proteinG, saved.calories) }
                        }
                        .onDelete { offsets in offsets.map { store.extras.savedMeals[$0].id }.forEach(store.deleteSavedMeal) }
                    }
                }
                if !store.recentFoods.isEmpty {
                    Section("Recent") {
                        ForEach(store.recentFoods) { recent in
                            Button {
                                store.logFood(FoodEntry(name: recent.name, proteinG: recent.proteinG, calories: recent.calories, meal: meal))
                                done()
                            } label: { foodRow(recent.name, recent.proteinG, recent.calories) }
                        }
                    }
                }
                if !store.extras.recipes.isEmpty {
                    Section("A serve from your recipes") {
                        ForEach(store.extras.recipes) { recipe in
                            Button {
                                store.logFood(FoodEntry(name: recipe.name, proteinG: recipe.proteinPerServe.rounded(), calories: recipe.caloriesPerServe.rounded(), meal: meal))
                                done()
                            } label: { foodRow(recipe.name, recipe.proteinPerServe, recipe.caloriesPerServe) }
                        }
                    }
                }

                Section("Type it in") {
                    TextField("Name", text: $name)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                    TextField("Calories (kcal, optional)", text: $calories).keyboardType(.decimalPad)
                    Toggle("Save to my meals", isOn: $saveAsMeal)
                    Button("Add") {
                        let p = number(protein) ?? 0
                        let k = number(calories)
                        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Food" : name.trimmingCharacters(in: .whitespaces)
                        store.logFood(FoodEntry(name: title, proteinG: p, calories: k, meal: meal))
                        if saveAsMeal { store.saveMeal(SavedMeal(name: title, proteinG: p, calories: k)) }
                        done()
                    }
                    .disabled(number(protein) == nil && number(calories) == nil)
                }
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $scanning) {
                BarcodeScanner { code in
                    scanning = false
                    Task { await lookUp(code) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $readingLabel) {
                LabelCamera { result in
                    readingLabel = false
                    if let result {
                        product = BarcodeProduct(code: "", name: "", proteinPerServe: result.proteinPerServe, kcalPerServe: result.kcalPerServe,
                                                 proteinPer100: result.proteinPer100, kcalPer100: result.kcalPer100, servingGrams: result.servingGrams)
                    } else {
                        notFound = "Couldn't read a protein line on that label. Try again closer, with the panel flat and lit."
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(item: Binding(get: { product.map { IdentifiedProduct(product: $0) } }, set: { product = $0?.product })) { wrapped in
                PortionSheet(product: wrapped.product, meal: meal) { done() }
                    .environmentObject(store)
            }
        }
    }

    private struct IdentifiedProduct: Identifiable {
        let product: BarcodeProduct
        var id: String { product.code + product.name + "\(product.proteinPerServe ?? -1)" }
    }

    private func foodRow(_ name: String, _ protein: Double, _ kcal: Double?) -> some View {
        HStack {
            Text(name).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Text("\(GFFormat.kg(protein.rounded())) g" + (kcal.map { " · \(Int($0)) kcal" } ?? "")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }

    private func estimate() async {
        estimating = true
        if let items = await FoodAI.estimate(described) {
            estimates = items
            estimatedByModel = true
        } else {
            estimates = FoodEstimate.guess(described)
            estimatedByModel = false
            if estimates.isEmpty { notFound = "Couldn't guess that one. Type it in below." }
        }
        estimating = false
    }

    private func lookUp(_ code: String) async {
        lookingUp = true
        notFound = nil
        if let found = await store.lookupBarcode(code) {
            product = found
        } else {
            notFound = "No match for \(code) (or no internet). Type it in below and tick Save, and it'll be there next time."
        }
        lookingUp = false
    }

    private func done() {
        Haptics.success()
        dismiss()
    }
}

/// How much you had of a scanned food (serves or grams).
struct PortionSheet: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    let product: BarcodeProduct
    let meal: Meal
    let onAdded: () -> Void
    @State private var name = ""
    @State private var serves = 1.0
    @State private var grams = ""
    @State private var byGrams = false
    @State private var save = true

    private var hasServe: Bool { product.proteinPerServe != nil }
    private var hasPer100: Bool { product.proteinPer100 != nil }

    private var totals: (protein: Double, kcal: Double?) {
        if byGrams || !hasServe, let g = Double(grams.replacingOccurrences(of: ",", with: ".")), let p100 = product.proteinPer100 {
            return (p100 * g / 100, product.kcalPer100.map { $0 * g / 100 })
        }
        return ((product.proteinPerServe ?? 0) * serves, product.kcalPerServe.map { $0 * serves })
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                if hasServe && hasPer100 {
                    Picker("Amount", selection: $byGrams) {
                        Text("Serves").tag(false)
                        Text("Grams").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if hasServe && !byGrams {
                    Stepper("\(GFNumber.text(serves)) serve\(serves == 1 ? "" : "s")" + (product.servingGrams.map { " (\(GFNumber.text($0 * serves)) g)" } ?? ""),
                            value: $serves, in: 0.5...10, step: 0.5)
                } else if hasPer100 {
                    TextField("Grams", text: $grams).keyboardType(.decimalPad)
                }
                Section {
                    LabeledContent("Protein", value: "\(GFFormat.kg(totals.protein.rounded())) g")
                    if let kcal = totals.kcal { LabeledContent("Calories", value: "\(Int(kcal.rounded())) kcal") }
                }
                Toggle("Save to my meals", isOn: $save)
                Button("Add") {
                    let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Food" : name.trimmingCharacters(in: .whitespaces)
                    store.logFood(FoodEntry(name: title, proteinG: totals.protein.rounded(), calories: totals.kcal?.rounded(), meal: meal))
                    if save {
                        // Saved as one serve (or 100 g), keyed to the barcode when there is one.
                        store.saveMeal(SavedMeal(name: title, proteinG: (product.proteinPerServe ?? product.proteinPer100 ?? 0).rounded(),
                                                 calories: (product.kcalPerServe ?? product.kcalPer100)?.rounded(),
                                                 barcode: product.code.isEmpty ? nil : product.code))
                    }
                    dismiss()
                    onAdded()
                }
                .bold()
                .disabled(totals.protein <= 0 && (totals.kcal ?? 0) <= 0)
            }
            .navigationTitle(product.name.isEmpty ? "From the label" : product.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                name = product.name
                byGrams = !hasServe
                if let serving = product.servingGrams, !hasServe { grams = GFNumber.text(serving) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Barcode scanner (97)

struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
                                                qualityLevel: .balanced, recognizesMultipleItems: false,
                                                isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}

// MARK: - Nutrition label (98)

/// The standard camera; the photo is read on the iPhone (Vision) and thrown away.
struct LabelCamera: UIViewControllerRepresentable {
    let onResult: (LabelParser.Result?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onResult: (LabelParser.Result?) -> Void
        init(onResult: @escaping (LabelParser.Result?) -> Void) { self.onResult = onResult }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onResult(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let cg = image.cgImage else { onResult(nil); return }
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            let done = onResult
            DispatchQueue.global(qos: .userInitiated).async {
                let lines = LabelOCR.lines(cg, orientation: orientation)
                let result = LabelParser.parse(lines)
                DispatchQueue.main.async { done(result.proteinPerServe == nil && result.proteinPer100 == nil ? nil : result) }
            }
        }
    }
}

enum LabelOCR {
    /// Text boxes joined into rows (same height on the label), left to right.
    static func lines(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let boxes = (request.results ?? []).compactMap { obs -> (y: CGFloat, x: CGFloat, text: String)? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return (obs.boundingBox.midY, obs.boundingBox.minX, text)
        }
        .sorted { $0.y > $1.y }
        var rows: [[(y: CGFloat, x: CGFloat, text: String)]] = []
        for box in boxes {
            if let last = rows.last?.first, abs(last.y - box.y) < 0.012 {
                rows[rows.count - 1].append(box)
            } else {
                rows.append([box])
            }
        }
        return rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }
}

extension CGImagePropertyOrientation {
    init(_ ui: UIImage.Orientation) {
        switch ui {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Recipe book, meal prep and the shopping list (95, 96)

struct RecipeBookView: View {
    @EnvironmentObject private var store: PhoneAppStore

    var body: some View {
        List {
            if store.extras.recipes.isEmpty {
                Text("Add the meals you batch-cook. Each shows protein, calories and cost per serve, and this week's prep builds your shopping list.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(store.extras.recipes) { recipe in
                    VStack(alignment: .leading, spacing: 6) {
                        NavigationLink { RecipeEditorView(recipe: recipe) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name).font(.headline)
                                Text("Per serve: \(Int(recipe.proteinPerServe.rounded())) g protein · \(Int(recipe.caloriesPerServe.rounded())) kcal"
                                     + (recipe.costPerServe > 0 ? String(format: " · $%.2f", recipe.costPerServe) : "")
                                     + " · makes \(recipe.servings)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Stepper("This week: \(store.batches(of: recipe)) batch\(store.batches(of: recipe) == 1 ? "" : "es")",
                                value: Binding(get: { store.batches(of: recipe) }, set: { store.setPrep(recipe, batches: $0) }), in: 0...6)
                            .font(.subheadline)
                    }
                }
                .onDelete { offsets in offsets.map { store.extras.recipes[$0].id }.forEach(store.deleteRecipe) }
            }
            if !store.extras.prepPlan.isEmpty {
                Section {
                    NavigationLink { ShoppingListView() } label: {
                        Label("Shopping list · \(store.shoppingList.count) item\(store.shoppingList.count == 1 ? "" : "s")", systemImage: "cart")
                    }
                    let plan = store.extras.prepPlan.compactMap { item in store.extras.recipes.first { $0.id == item.recipeID }.map { ($0, item.batches) } }
                    let serves = plan.reduce(0) { $0 + $1.0.servings * $1.1 }
                    let protein = plan.reduce(0.0) { $0 + $1.0.proteinPerServe * Double($1.0.servings * $1.1) }
                    Text("\(serves) serves, \(Int(protein)) g protein in the fridge.").font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("This week's prep")
                }
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            NavigationLink { RecipeEditorView(recipe: Recipe(name: "")) } label: { Image(systemName: "plus") }
        }
    }
}

struct RecipeEditorView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe

    var body: some View {
        Form {
            TextField("Recipe name", text: $recipe.name)
            Stepper("Makes \(recipe.servings) serve\(recipe.servings == 1 ? "" : "s")", value: $recipe.servings, in: 1...30)
            Section {
                ForEach($recipe.ingredients) { $ingredient in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Ingredient", text: $ingredient.name).font(.headline)
                            TextField("Amount", text: $ingredient.amount).multilineTextAlignment(.trailing).frame(maxWidth: 110)
                        }
                        HStack {
                            numberField("Protein g", $ingredient.proteinG)
                            numberField("kcal", $ingredient.calories)
                            numberField("Cost $", $ingredient.cost)
                        }
                        .font(.caption)
                    }
                }
                .onDelete { recipe.ingredients.remove(atOffsets: $0) }
                Button { recipe.ingredients.append(Ingredient(name: "")) } label: { Label("Add ingredient", systemImage: "plus") }
            } header: {
                Text("Ingredients (for the whole batch)")
            } footer: {
                Text("Per serve: \(Int(recipe.proteinPerServe.rounded())) g protein · \(Int(recipe.caloriesPerServe.rounded())) kcal"
                     + (recipe.costPerServe > 0 ? String(format: " · $%.2f", recipe.costPerServe) : "")
                     + ". Amounts like \"500 g\" add up on the shopping list.")
            }
            Section("Notes") {
                TextField("Method, storage…", text: $recipe.notes, axis: .vertical).lineLimit(2...8)
            }
        }
        .navigationTitle(recipe.name.isEmpty ? "New recipe" : recipe.name)
        .toolbar {
            Button("Save") {
                store.saveRecipe(recipe)
                Haptics.success()
                dismiss()
            }
            .disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func numberField(_ title: String, _ value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
    }
}

struct ShoppingListView: View {
    @EnvironmentObject private var store: PhoneAppStore
    @AppStorage("shopping.checked") private var checkedRaw = ""

    var body: some View {
        let lines = store.shoppingList
        let checked = Set(checkedRaw.split(separator: "\n").map(String.init))
        List {
            ForEach(lines) { line in
                Button {
                    var all = checked
                    if all.contains(line.id) { all.remove(line.id) } else { all.insert(line.id) }
                    checkedRaw = all.sorted().joined(separator: "\n")
                    Haptics.tap()
                } label: {
                    HStack {
                        Image(systemName: checked.contains(line.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked.contains(line.id) ? Color.green : Color.secondary)
                        Text(line.name).strikethrough(checked.contains(line.id)).foregroundStyle(.primary)
                        Spacer()
                        Text(ShoppingList.total(line.amounts)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !checked.isEmpty {
                Button("Untick everything") { checkedRaw = "" }
            }
        }
        .navigationTitle("Shopping list")
        .toolbar {
            ShareLink(item: lines.map { "• \($0.name)" + (ShoppingList.total($0.amounts).isEmpty ? "" : " (\(ShoppingList.total($0.amounts)))") }
                .joined(separator: "\n"))
        }
    }
}
