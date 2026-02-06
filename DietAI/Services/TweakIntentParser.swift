import Foundation

// MARK: - Tweak Intent Parser
/// Parses natural language prompts into structured TweakIntent objects
struct TweakIntentParser {

    // MARK: - Day Keywords
    private static let dayKeywords: [(keyword: String, dayName: String)] = [
        ("monday", "Monday"),
        ("tuesday", "Tuesday"),
        ("wednesday", "Wednesday"),
        ("thursday", "Thursday"),
        ("friday", "Friday"),
        ("saturday", "Saturday"),
        ("sunday", "Sunday"),
        ("mon", "Monday"),
        ("tue", "Tuesday"),
        ("wed", "Wednesday"),
        ("thu", "Thursday"),
        ("fri", "Friday"),
        ("sat", "Saturday"),
        ("sun", "Sunday")
    ]

    // MARK: - Meal Type Keywords
    private static let mealTypeKeywords: [(keyword: String, type: MealType)] = [
        ("breakfast", .breakfast),
        ("breakfasts", .breakfast),
        ("brunch", .brunch),
        ("brunches", .brunch),
        ("mid-morning", .brunch),
        ("late breakfast", .brunch),
        ("lunch", .lunch),
        ("lunches", .lunch),
        ("dinner", .dinner),
        ("dinners", .dinner),
        ("snack", .snack),
        ("snacks", .snack)
    ]

    // MARK: - Dietary Restriction Keywords
    private static let restrictionKeywords: [String] = [
        "vegetarian",
        "vegan",
        "gluten-free",
        "gluten free",
        "dairy-free",
        "dairy free",
        "low-carb",
        "low carb",
        "keto",
        "high-protein",
        "high protein"
    ]

    // MARK: - Action Keywords
    private static let replaceKeywords = ["change", "replace", "swap", "different", "new", "don't like", "dont like", "hate", "dislike"]
    private static let lighterKeywords = ["lighter", "less calories", "fewer calories", "lower calorie", "smaller", "diet"]
    private static let heavierKeywords = ["heavier", "more calories", "higher calorie", "bigger", "larger", "more food"]
    private static let quickPrepKeywords = ["quick", "fast", "easy", "simple", "15 minute", "15 min", "under 15", "no cook"]
    private static let moreProteinKeywords = ["more protein", "higher protein", "protein rich", "high protein"]
    private static let lessProteinKeywords = ["less protein", "lower protein"]
    private static let moreCarbsKeywords = ["more carbs", "higher carbs", "more carbohydrates"]
    private static let lessCarbsKeywords = ["less carbs", "lower carbs", "fewer carbs", "low carb"]
    private static let moreFatKeywords = ["more fat", "higher fat", "fattier"]
    private static let lessFatKeywords = ["less fat", "lower fat", "leaner"]
    private static let removeKeywords = ["remove", "no ", "without", "exclude", "skip", "avoid"]

    // MARK: - Common Ingredients to Detect
    private static let commonIngredients = [
        "chicken", "beef", "pork", "fish", "salmon", "tuna", "shrimp", "turkey", "tofu", "eggs", "egg",
        "milk", "cheese", "yogurt", "butter", "cream",
        "rice", "pasta", "bread", "quinoa", "oats", "oatmeal",
        "broccoli", "spinach", "kale", "lettuce", "tomato", "onion", "garlic", "pepper", "mushroom",
        "apple", "banana", "orange", "berry", "berries", "avocado",
        "nuts", "almonds", "peanuts", "cashews",
        "seafood", "shellfish", "meat", "red meat"
    ]

    // MARK: - Parse Intent
    /// Parse a natural language prompt into a TweakIntent
    static func parse(_ prompt: String, plan: DietPlan) -> TweakIntent? {
        let lowered = prompt.lowercased()

        // 1. Determine scope
        let scope = parseScope(lowered, plan: plan)

        // 2. Determine action
        let action = parseAction(lowered)

        guard let scope = scope, let action = action else {
            return nil
        }

        return TweakIntent(scope: scope, action: action, originalPrompt: prompt)
    }

    // MARK: - Parse Scope
    private static func parseScope(_ prompt: String, plan: DietPlan) -> TweakScope? {
        // Check for specific day
        for (keyword, dayName) in dayKeywords {
            if prompt.contains(keyword) {
                return .specificDay(dayName: dayName)
            }
        }

        // Check for specific meal type
        for (keyword, type) in mealTypeKeywords {
            if prompt.contains(keyword) {
                return .mealType(type)
            }
        }

        // Check for ingredient-based scope (e.g., "remove salmon", "no chicken")
        if let ingredient = findIngredientInPrompt(prompt) {
            // If it's a "remove" action targeting an ingredient, scope to that ingredient
            if containsAny(prompt, keywords: removeKeywords) {
                return .ingredient(ingredient)
            }
        }

        // Default to all meals for general modifications
        return .allMeals
    }

    // MARK: - Parse Action
    private static func parseAction(_ prompt: String) -> TweakAction? {
        // Check for dietary restrictions first (make X vegetarian, etc.)
        for restriction in restrictionKeywords {
            if prompt.contains(restriction) {
                return .addRestriction(restriction)
            }
        }

        // Check for ingredient removal
        if containsAny(prompt, keywords: removeKeywords) {
            if let ingredient = findIngredientInPrompt(prompt) {
                return .removeIngredient(ingredient)
            }
        }

        // Check for macro adjustments
        if containsAny(prompt, keywords: moreProteinKeywords) {
            return .adjustMacro(.protein, .increase)
        }
        if containsAny(prompt, keywords: lessProteinKeywords) {
            return .adjustMacro(.protein, .decrease)
        }
        if containsAny(prompt, keywords: moreCarbsKeywords) {
            return .adjustMacro(.carbs, .increase)
        }
        if containsAny(prompt, keywords: lessCarbsKeywords) {
            return .adjustMacro(.carbs, .decrease)
        }
        if containsAny(prompt, keywords: moreFatKeywords) {
            return .adjustMacro(.fat, .increase)
        }
        if containsAny(prompt, keywords: lessFatKeywords) {
            return .adjustMacro(.fat, .decrease)
        }

        // Check for calorie adjustments
        if containsAny(prompt, keywords: lighterKeywords) {
            return .adjustCalories(delta: -150)
        }
        if containsAny(prompt, keywords: heavierKeywords) {
            return .adjustCalories(delta: 150)
        }

        // Check for quick prep
        if containsAny(prompt, keywords: quickPrepKeywords) {
            return .quickPrep
        }

        // Check for replace/change keywords
        if containsAny(prompt, keywords: replaceKeywords) {
            return .replace
        }

        // If we have a scope but no clear action, default to replace
        return .replace
    }

    // MARK: - Helper Functions
    private static func containsAny(_ text: String, keywords: [String]) -> Bool {
        for keyword in keywords {
            if text.contains(keyword) {
                return true
            }
        }
        return false
    }

    private static func findIngredientInPrompt(_ prompt: String) -> String? {
        for ingredient in commonIngredients {
            if prompt.contains(ingredient) {
                return ingredient
            }
        }
        return nil
    }

    // MARK: - Get Affected Meals
    /// Given a TweakIntent, return the meals that will be affected
    static func getAffectedMeals(intent: TweakIntent, plan: DietPlan) -> [Meal] {
        var affectedMeals: [Meal] = []

        for day in plan.days {
            for meal in day.meals {
                if shouldIncludeMeal(meal, day: day, scope: intent.scope, action: intent.action) {
                    affectedMeals.append(meal)
                }
            }
        }

        return affectedMeals
    }

    private static func shouldIncludeMeal(_ meal: Meal, day: DailyPlan, scope: TweakScope, action: TweakAction) -> Bool {
        switch scope {
        case .allMeals:
            return true

        case .mealType(let type):
            return meal.type == type

        case .specificDay(let dayName):
            return day.dayName.lowercased() == dayName.lowercased()

        case .ingredient(let ingredient):
            // Check if meal name or ingredients contain the ingredient
            let loweredIngredient = ingredient.lowercased()
            if meal.name.lowercased().contains(loweredIngredient) {
                return true
            }
            for mealIngredient in meal.ingredients {
                if mealIngredient.name.lowercased().contains(loweredIngredient) {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Quick Suggestion Prompts
extension TweakIntentParser {
    /// Predefined quick suggestions for common tweaks
    static let quickSuggestions: [(label: String, prompt: String)] = [
        ("More Protein", "Add more protein to all meals"),
        ("Lighter Meals", "Make all meals lighter"),
        ("Quick Prep", "Replace with quick prep meals under 15 minutes"),
        ("Vegetarian", "Make all meals vegetarian")
    ]
}
