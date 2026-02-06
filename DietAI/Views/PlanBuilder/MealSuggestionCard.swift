import SwiftUI

// MARK: - Meal Suggestion Card
struct MealSuggestionCard: View {
    let meal: PlannedMeal
    let targetCalories: Int
    let onAccept: () -> Void
    let onRegenerate: () -> Void
    let onCustomize: () -> Void

    @State private var showIngredients = false

    private var calorieDeviation: Int {
        meal.calories - targetCalories
    }

    private var calorieColor: Color {
        let deviation = abs(calorieDeviation)
        if deviation < 50 { return .green }
        if deviation < 100 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with meal type
            HStack {
                Label(meal.type.rawValue, systemImage: mealTypeIcon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(mealTypeColor.opacity(0.15))
                    .foregroundStyle(mealTypeColor)
                    .cornerRadius(20)

                Spacer()

                Text("AI Suggestion")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()

            Divider()

            // Meal details
            VStack(alignment: .leading, spacing: 16) {
                // Name
                Text(meal.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                // Nutrition grid
                HStack(spacing: 16) {
                    NutritionBadge(
                        value: meal.calories,
                        unit: "kcal",
                        label: "Calories",
                        color: calorieColor
                    )

                    NutritionBadge(
                        value: meal.protein,
                        unit: "g",
                        label: "Protein",
                        color: .red
                    )

                    NutritionBadge(
                        value: meal.carbs,
                        unit: "g",
                        label: "Carbs",
                        color: .blue
                    )

                    NutritionBadge(
                        value: meal.fat,
                        unit: "g",
                        label: "Fat",
                        color: .yellow
                    )
                }

                // Calorie indicator
                if abs(calorieDeviation) >= 50 {
                    HStack(spacing: 6) {
                        Image(systemName: calorieDeviation > 0 ? "arrow.up" : "arrow.down")
                            .font(.caption2)

                        Text("\(abs(calorieDeviation)) kcal \(calorieDeviation > 0 ? "over" : "under") target")
                            .font(.caption)
                    }
                    .foregroundStyle(calorieColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(calorieColor.opacity(0.1))
                    .cornerRadius(8)
                }

                // Ingredients (expandable)
                DisclosureGroup(isExpanded: $showIngredients) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(meal.ingredients) { ingredient in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.name.capitalized)
                                        .font(.subheadline)
                                    if !ingredient.quantity.isEmpty {
                                        Text(ingredient.quantity)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundStyle(.green)
                        Text("\(meal.ingredients.count) Ingredients")
                            .font(.subheadline)
                    }
                }
            }
            .padding()

            Divider()

            // Actions
            HStack(spacing: 12) {
                // Regenerate
                Button(action: onRegenerate) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Different")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .cornerRadius(10)
                }

                // Accept
                Button(action: onAccept) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                        Text("Accept")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private var mealTypeIcon: String {
        meal.type.icon
    }

    private var mealTypeColor: Color {
        meal.type.color
    }
}

// MARK: - Nutrition Badge
struct NutritionBadge: View {
    let value: Int
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("\(value)")
                    .font(.headline)
                    .fontWeight(.bold)

                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Meal Suggestion Service
@MainActor
class MealSuggestionService {
    static let shared = MealSuggestionService()

    private init() {}

    func generateMealSuggestion(
        type: MealType,
        targetCalories: Int,
        goal: GoalType,
        restrictions: [String],
        existingMeals: [PlannedMeal]
    ) async throws -> PlannedMeal {
        return try await generateMealSuggestionWithPreference(
            type: type,
            targetCalories: targetCalories,
            goal: goal,
            restrictions: restrictions,
            existingMeals: existingMeals,
            userPreference: ""
        )
    }

    func generateMealSuggestionWithPreference(
        type: MealType,
        targetCalories: Int,
        goal: GoalType,
        restrictions: [String],
        existingMeals: [PlannedMeal],
        userPreference: String
    ) async throws -> PlannedMeal {
        // Load model on-demand if not already loaded
        await ModelManager.shared.loadModelIfNeeded()

        // Check if MLX model is available
        guard ModelManager.shared.isModelLoaded,
              let container = ModelManager.shared.modelContainer else {
            // Return a smart default based on preference (fallback if model couldn't load)
            return generateDefaultMealWithPreference(type: type, targetCalories: targetCalories, goal: goal, preference: userPreference)
        }

        // Build a focused prompt for single meal generation with user preference
        let prompt = buildMealPromptWithPreference(
            type: type,
            targetCalories: targetCalories,
            goal: goal,
            restrictions: restrictions,
            userPreference: userPreference
        )

        let output = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: 300, temperature: 0.4) // Slightly higher temp for variety

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { (tokens: [Int]) -> GenerateDisposition in
                // Stop early for single meal generation
                if tokens.count > 200 {
                    return .stop
                }
                return .more
            }

            return result.output
        }

        // Parse the response
        return parseMealResponse(output, type: type, targetCalories: targetCalories)
    }

    private func buildMealPrompt(
        type: MealType,
        targetCalories: Int,
        goal: GoalType,
        restrictions: [String]
    ) -> String {
        return buildMealPromptWithPreference(
            type: type,
            targetCalories: targetCalories,
            goal: goal,
            restrictions: restrictions,
            userPreference: ""
        )
    }

    private func buildMealPromptWithPreference(
        type: MealType,
        targetCalories: Int,
        goal: GoalType,
        restrictions: [String],
        userPreference: String
    ) -> String {
        var restrictionText = ""
        if !restrictions.isEmpty {
            restrictionText = "Dietary restrictions: \(restrictions.joined(separator: ", ")). "
        }

        let goalText: String
        switch goal {
        case .weightLoss:
            goalText = "Focus on high protein, low calorie, filling foods."
        case .muscleGain:
            goalText = "Focus on high protein with adequate carbs for muscle building."
        case .maintenance:
            goalText = "Provide balanced macronutrients."
        case .keto:
            goalText = "Focus on high fat, moderate protein, very low carbs (under 20g net carbs)."
        }

        var preferenceText = ""
        if !userPreference.isEmpty {
            preferenceText = "User preference: \(userPreference). "
        }

        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        You are a nutritionist. Generate ONE \(type.rawValue.lowercased()) meal with approximately \(targetCalories) calories.
        \(restrictionText)\(goalText)\(preferenceText)
        Respond with ONLY valid JSON, no markdown. Each ingredient must have name and quantity as separate fields:
        {"name":"Meal Name","calories":300,"protein":20,"carbs":30,"fat":10,"ingredients":[{"name":"chicken breast","quantity":"200g"},{"name":"rice","quantity":"1 cup"},{"name":"olive oil","quantity":"2 tbsp"}]}
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Generate a \(type.rawValue.lowercased()) around \(targetCalories) calories\(userPreference.isEmpty ? "" : " that is \(userPreference)").
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {
        """
    }

    private func parseMealResponse(_ response: String, type: MealType, targetCalories: Int) -> PlannedMeal {
        // Try to parse JSON
        var cleaned = response
        if !cleaned.hasPrefix("{") {
            if let start = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[start...])
            }
        }
        if !cleaned.hasSuffix("}") {
            if let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[...end])
            } else {
                cleaned += "}"
            }
        }

        // Ensure it starts with {
        if !cleaned.hasPrefix("{") {
            cleaned = "{" + cleaned
        }

        if let data = cleaned.data(using: .utf8) {
            // Try structured ingredients first
            if let json = try? JSONDecoder().decode(MealJSON.self, from: data) {
                let structuredIngredients = json.ingredients.map {
                    MealIngredient(name: $0.name, quantity: $0.quantity)
                }
                return PlannedMeal(
                    type: type,
                    name: json.name,
                    calories: json.calories,
                    protein: json.protein,
                    carbs: json.carbs,
                    fat: json.fat,
                    structuredIngredients: structuredIngredients
                )
            }

            // Fallback to legacy string format
            if let json = try? JSONDecoder().decode(MealJSONLegacy.self, from: data) {
                return PlannedMeal(
                    type: type,
                    name: json.name,
                    calories: json.calories,
                    protein: json.protein,
                    carbs: json.carbs,
                    fat: json.fat,
                    ingredients: json.ingredients
                )
            }
        }

        // Fallback to default
        return generateDefaultMeal(type: type, targetCalories: targetCalories, goal: .maintenance)
    }

    private func generateDefaultMeal(type: MealType, targetCalories: Int, goal: GoalType) -> PlannedMeal {
        return generateDefaultMealWithPreference(type: type, targetCalories: targetCalories, goal: goal, preference: "")
    }

    private func generateDefaultMealWithPreference(type: MealType, targetCalories: Int, goal: GoalType, preference: String) -> PlannedMeal {
        // Preference-specific meal options with full macro data (name, ingredients, protein, carbs, fat)
        let highProteinMeals: [MealType: [(String, [String], Int, Int, Int)]] = [
            .breakfast: [
                ("Egg White Omelette with Turkey", ["6 egg whites", "3 slices turkey bacon", "1 cup spinach", "30g feta"], 35, 8, 12),
                ("Protein Pancakes", ["1 scoop protein powder", "1/2 cup oats", "4 egg whites", "100g greek yogurt"], 32, 42, 6),
                ("Greek Yogurt Power Bowl", ["250g greek yogurt", "1/4 cup protein granola", "15 almonds", "1/2 cup berries"], 28, 35, 10)
            ],
            .lunch: [
                ("Grilled Chicken Caesar", ["200g chicken breast", "2 cups romaine", "30g parmesan", "2 tbsp light dressing"], 42, 15, 18),
                ("Tuna Protein Bowl", ["180g tuna steak", "1 cup quinoa", "1/2 cup edamame", "1/4 avocado"], 45, 32, 14),
                ("Turkey & Egg White Wrap", ["150g turkey breast", "4 egg whites", "1 cup spinach", "1 large whole wheat wrap"], 40, 28, 8)
            ],
            .dinner: [
                ("Grilled Salmon with Asparagus", ["200g salmon fillet", "1 cup asparagus", "1 lemon", "1 tbsp olive oil"], 42, 12, 28),
                ("Chicken Breast with Quinoa", ["200g chicken breast", "1 cup quinoa", "1 cup broccoli", "2 cloves garlic"], 45, 35, 8),
                ("Lean Steak with Vegetables", ["180g sirloin steak", "1.5 cups mixed vegetables", "1 medium sweet potato"], 40, 30, 15)
            ],
            .snack: [
                ("Protein Shake", ["1 scoop protein powder", "1 cup almond milk", "1 medium banana", "1 tbsp peanut butter"], 30, 25, 8),
                ("Cottage Cheese & Nuts", ["200g cottage cheese", "15 almonds", "1 tsp honey"], 22, 12, 10),
                ("Hard Boiled Eggs", ["3 large eggs", "pinch salt", "pinch pepper"], 12, 1, 10)
            ]
        ]

        let lowCarbMeals: [MealType: [(String, [String], Int, Int, Int)]] = [
            .breakfast: [
                ("Keto Eggs Benedict", ["eggs", "canadian bacon", "hollandaise", "spinach"], 25, 4, 30),
                ("Avocado Egg Cups", ["avocado", "eggs", "bacon bits", "cheese"], 18, 6, 28),
                ("Smoked Salmon Plate", ["smoked salmon", "cream cheese", "capers", "cucumber"], 22, 5, 24)
            ],
            .lunch: [
                ("Cobb Salad", ["chicken", "bacon", "eggs", "avocado", "blue cheese"], 35, 8, 32),
                ("Lettuce Wrap Tacos", ["ground beef", "lettuce", "cheese", "sour cream", "salsa"], 28, 10, 26),
                ("Zucchini Noodle Carbonara", ["zucchini noodles", "bacon", "egg", "parmesan"], 22, 12, 24)
            ],
            .dinner: [
                ("Grilled Ribeye with Broccoli", ["ribeye steak", "broccoli", "butter", "garlic"], 38, 8, 38),
                ("Baked Chicken Thighs", ["chicken thighs", "green beans", "olive oil", "herbs"], 35, 10, 28),
                ("Shrimp Scampi (No Pasta)", ["shrimp", "garlic", "butter", "zucchini", "parsley"], 32, 8, 24)
            ],
            .snack: [
                ("Cheese & Pepperoni", ["mozzarella", "pepperoni", "olives"], 14, 2, 18),
                ("Celery with Cream Cheese", ["celery", "cream cheese", "everything seasoning"], 4, 4, 14),
                ("Beef Jerky", ["beef jerky"], 20, 3, 2)
            ]
        ]

        let asianMeals: [MealType: [(String, [String], Int, Int, Int)]] = [
            .breakfast: [
                ("Japanese Breakfast Bowl", ["rice", "salmon", "miso soup", "pickled vegetables"], 25, 45, 10),
                ("Congee with Egg", ["rice porridge", "soft boiled egg", "green onions", "ginger"], 12, 42, 6),
                ("Tamagoyaki with Rice", ["eggs", "dashi", "rice", "nori", "pickles"], 18, 40, 12)
            ],
            .lunch: [
                ("Teriyaki Chicken Bowl", ["chicken", "teriyaki sauce", "rice", "broccoli", "sesame"], 35, 48, 12),
                ("Poke Bowl", ["ahi tuna", "sushi rice", "edamame", "cucumber", "avocado"], 32, 45, 14),
                ("Pad Thai", ["rice noodles", "shrimp", "peanuts", "bean sprouts", "lime"], 25, 55, 18)
            ],
            .dinner: [
                ("Korean BBQ Beef", ["bulgogi beef", "rice", "kimchi", "lettuce wraps"], 35, 42, 18),
                ("Thai Basil Chicken", ["chicken", "thai basil", "chili", "garlic", "jasmine rice"], 32, 45, 12),
                ("Salmon Teriyaki", ["salmon", "teriyaki glaze", "bok choy", "rice"], 38, 40, 16)
            ],
            .snack: [
                ("Miso Soup", ["tofu", "wakame", "miso paste", "green onions"], 6, 8, 2),
                ("Seaweed Snack", ["roasted seaweed", "sesame oil"], 2, 4, 4),
                ("Gyoza (Dumplings)", ["pork", "cabbage", "wrapper", "soy sauce"], 12, 24, 8)
            ]
        ]

        let vegetarianMeals: [MealType: [(String, [String], Int, Int, Int)]] = [
            .breakfast: [
                ("Veggie Scramble", ["eggs", "bell peppers", "onions", "mushrooms", "cheese"], 20, 12, 22),
                ("Açaí Bowl", ["açaí puree", "banana", "granola", "berries", "coconut"], 8, 65, 12),
                ("Avocado Toast Deluxe", ["whole grain bread", "avocado", "tomatoes", "feta", "eggs"], 16, 35, 24)
            ],
            .lunch: [
                ("Falafel Bowl", ["falafel", "hummus", "tabbouleh", "cucumber", "tahini"], 16, 52, 22),
                ("Caprese Panini", ["mozzarella", "tomato", "basil", "ciabatta", "pesto"], 20, 40, 20),
                ("Black Bean Buddha Bowl", ["black beans", "quinoa", "roasted vegetables", "avocado"], 18, 62, 18)
            ],
            .dinner: [
                ("Vegetable Stir Fry with Tofu", ["tofu", "broccoli", "bell peppers", "soy sauce", "rice"], 22, 48, 16),
                ("Eggplant Parmesan", ["eggplant", "marinara", "mozzarella", "parmesan", "basil"], 18, 32, 20),
                ("Mushroom Risotto", ["arborio rice", "mushrooms", "parmesan", "white wine", "vegetable broth"], 14, 58, 16)
            ],
            .snack: [
                ("Edamame", ["edamame", "sea salt"], 17, 14, 8),
                ("Hummus with Veggies", ["hummus", "carrots", "cucumber", "bell pepper"], 8, 22, 10),
                ("Caprese Skewers", ["mozzarella balls", "cherry tomatoes", "basil", "balsamic glaze"], 12, 8, 12)
            ]
        ]

        // Default meals with quantities
        let defaultMeals: [MealType: [(String, [String], Int, Int, Int)]] = [
            .breakfast: [
                ("Greek Yogurt Parfait", ["200g greek yogurt", "1/4 cup granola", "1/2 cup mixed berries", "1 tbsp honey"], 15, 45, 8),
                ("Veggie Omelette", ["3 large eggs", "1 cup spinach", "1/2 cup tomatoes", "30g feta cheese"], 22, 8, 18),
                ("Overnight Oats", ["1/2 cup oats", "1 cup almond milk", "1 tbsp chia seeds", "1 medium banana"], 12, 55, 10),
                ("Avocado Toast", ["2 slices whole wheat bread", "1/2 avocado", "2 large eggs", "1/2 cup cherry tomatoes"], 14, 35, 20)
            ],
            .lunch: [
                ("Grilled Chicken Salad", ["150g chicken breast", "2 cups mixed greens", "1/2 cucumber", "2 tbsp olive oil"], 35, 12, 18),
                ("Turkey Wrap", ["120g turkey breast", "1 large whole wheat tortilla", "1 cup lettuce", "2 tbsp hummus"], 28, 35, 12),
                ("Quinoa Buddha Bowl", ["1 cup cooked quinoa", "1/2 cup chickpeas", "1 cup roasted vegetables", "2 tbsp tahini"], 18, 55, 16),
                ("Mediterranean Bowl", ["4 pieces falafel", "3 tbsp hummus", "1/2 cucumber", "1 cup tomatoes", "1 small pita"], 15, 48, 18)
            ],
            .dinner: [
                ("Baked Salmon", ["180g salmon fillet", "1 cup asparagus", "1 lemon", "1 tbsp olive oil"], 38, 10, 22),
                ("Chicken Stir Fry", ["150g chicken breast", "1 cup broccoli", "1/2 cup bell peppers", "1 cup brown rice"], 32, 42, 12),
                ("Lean Beef Tacos", ["150g lean ground beef", "3 corn tortillas", "1 cup lettuce", "1/4 cup salsa"], 28, 35, 16),
                ("Shrimp Pasta", ["150g shrimp", "100g whole wheat pasta", "2 cloves garlic", "1 tbsp olive oil", "1 cup spinach"], 30, 52, 14)
            ],
            .snack: [
                ("Apple with Almond Butter", ["1 medium apple", "2 tbsp almond butter"], 6, 25, 16),
                ("Protein Smoothie", ["1 scoop protein powder", "1 medium banana", "1 cup almond milk", "1 cup spinach"], 25, 30, 5),
                ("Mixed Nuts", ["15 almonds", "5 walnuts", "10 cashews"], 6, 8, 18),
                ("Cottage Cheese & Fruit", ["150g cottage cheese", "1/2 cup pineapple", "1 tsp honey"], 14, 20, 4)
            ]
        ]

        // Select meal based on preference
        let loweredPref = preference.lowercased()
        var selectedMeals: [MealType: [(String, [String], Int, Int, Int)]]

        if loweredPref.contains("protein") || loweredPref.contains("muscle") {
            selectedMeals = highProteinMeals
        } else if loweredPref.contains("low carb") || loweredPref.contains("keto") || loweredPref.contains("carb") {
            selectedMeals = lowCarbMeals
        } else if loweredPref.contains("asian") || loweredPref.contains("japanese") || loweredPref.contains("chinese") || loweredPref.contains("korean") || loweredPref.contains("thai") {
            selectedMeals = asianMeals
        } else if loweredPref.contains("vegetarian") || loweredPref.contains("veggie") || loweredPref.contains("meatless") {
            selectedMeals = vegetarianMeals
        } else {
            selectedMeals = defaultMeals
        }

        let options = selectedMeals[type] ?? selectedMeals[.snack] ?? []

        // Safe fallback if no options available
        guard let selected = options.randomElement() else {
            return PlannedMeal(
                type: type,
                name: "Custom Meal",
                calories: targetCalories,
                protein: Int(Double(targetCalories) * 0.3 / 4),
                carbs: Int(Double(targetCalories) * 0.4 / 4),
                fat: Int(Double(targetCalories) * 0.3 / 9),
                ingredients: ["Your choice of ingredients"]
            )
        }

        // Use provided macros or calculate from calories if needed
        let protein = selected.2
        let carbs = selected.3
        let fat = selected.4

        // Adjust calories based on actual macros
        let actualCalories = (protein * 4) + (carbs * 4) + (fat * 9)
        let finalCalories = abs(actualCalories - targetCalories) < 100 ? actualCalories : targetCalories

        return PlannedMeal(
            type: type,
            name: selected.0,
            calories: finalCalories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            ingredients: selected.1
        )
    }

    struct IngredientJSON: Codable {
        let name: String
        let quantity: String
    }

    struct MealJSON: Codable {
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let ingredients: [IngredientJSON]
    }

    // Fallback for legacy string-based ingredients
    struct MealJSONLegacy: Codable {
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let ingredients: [String]
    }
}

// Need to import MLX for the generate function
import MLX
import MLXLLM
import MLXLMCommon
