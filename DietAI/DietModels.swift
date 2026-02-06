import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums
enum MealType: String, Codable, CaseIterable {
    case breakfast = "Breakfast"
    case brunch = "Brunch"
    case lunch = "Lunch"
    case snack = "Snack"
    case dinner = "Dinner"

    /// Sort order for meal types within a day
    var sortOrder: Int {
        switch self {
        case .breakfast: return 0
        case .brunch: return 1
        case .lunch: return 2
        case .snack: return 3
        case .dinner: return 4
        }
    }

    /// SF Symbol icon for each meal type
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .brunch: return "sun.and.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "carrot.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    /// Display color for each meal type
    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .brunch: return Color(red: 0.95, green: 0.75, blue: 0.3)
        case .lunch: return .green
        case .snack: return .mint
        case .dinner: return .indigo
        }
    }
}

enum GoalType: String, Codable, CaseIterable {
    case weightLoss = "Weight Loss"
    case muscleGain = "Muscle Gain"
    case maintenance = "Maintenance"
    case keto = "Keto"
}

enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly Active"
    case moderatelyActive = "Moderately Active"
    case veryActive = "Very Active"
    case extraActive = "Extra Active"

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extraActive: return 1.9
        }
    }
}

// MARK: - Ingredient Model
/// Structured ingredient with separate name and quantity
struct MealIngredient: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String      // e.g., "Avocado", "Chicken breast"
    var quantity: String  // e.g., "1/2", "2 cups", "200g"

    init(name: String, quantity: String = "") {
        self.name = name
        self.quantity = quantity
    }

    /// Display string combining quantity and name
    var displayString: String {
        quantity.isEmpty ? name : "\(quantity) \(name)"
    }

    /// Create from legacy string format (e.g., "2 cups spinach")
    static func fromLegacyString(_ string: String) -> MealIngredient {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        // Common units to look for
        let units = ["tbsp", "tsp", "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs",
                     "pound", "pounds", "g", "gram", "grams", "kg", "ml", "liter", "liters",
                     "slice", "slices", "piece", "pieces", "clove", "cloves", "can", "cans",
                     "bunch", "bunches", "head", "heads", "stalk", "stalks", "sprig", "sprigs",
                     "medium", "large", "small"]

        // Regex to match quantity at start: number (including fractions) + optional unit
        let pattern = #"^(\d+(?:\s*/\s*\d+|\.\d+)?(?:\s+\d+/\d+)?)\s*([a-zA-Z]+)?\s*(.+)$"#

        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) {

            let numberRange = Range(match.range(at: 1), in: trimmed)
            let unitRange = Range(match.range(at: 2), in: trimmed)
            let restRange = Range(match.range(at: 3), in: trimmed)

            if let numRange = numberRange, let restR = restRange {
                let number = String(trimmed[numRange])
                var unit = ""
                var baseName = String(trimmed[restR]).trimmingCharacters(in: .whitespaces)

                if let uRange = unitRange {
                    let potentialUnit = String(trimmed[uRange]).lowercased()
                    if units.contains(potentialUnit) {
                        unit = potentialUnit
                    } else {
                        // Not a unit, it's part of the base name
                        baseName = String(trimmed[uRange]) + " " + baseName
                    }
                }

                let quantity = unit.isEmpty ? number : "\(number) \(unit)"
                let name = baseName.isEmpty ? trimmed : baseName
                return MealIngredient(name: name, quantity: quantity)
            }
        }

        // No quantity found, return whole string as name
        return MealIngredient(name: trimmed, quantity: "")
    }
}

// MARK: - SwiftData Models

@Model
final class DietPlan {
    var id: UUID
    var name: String
    var createdAt: Date
    var goal: String
    var dailyCaloriesTarget: Int

    // NEW: Plan preferences
    var maxPrepTimeMinutes: Int
    var difficultyPreference: String
    var budgetLevel: String
    var batchCookingEnabled: Bool
    var userNotes: String?

    // Selected meal types for this plan (CSV format)
    var selectedMealTypesRaw: String = "Breakfast,Brunch,Lunch,Snack,Dinner"

    @Relationship(deleteRule: .cascade) var days: [DailyPlan] = []

    init(
        name: String,
        goal: GoalType,
        calories: Int,
        maxPrepTimeMinutes: Int = 30,
        difficultyPreference: MealDifficulty = .easy,
        budgetLevel: BudgetLevel = .moderate,
        batchCookingEnabled: Bool = false,
        userNotes: String? = nil,
        selectedMealTypes: Set<MealType> = Set(MealType.allCases)
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.goal = goal.rawValue
        self.dailyCaloriesTarget = calories
        self.maxPrepTimeMinutes = maxPrepTimeMinutes
        self.difficultyPreference = difficultyPreference.rawValue
        self.budgetLevel = budgetLevel.rawValue
        self.batchCookingEnabled = batchCookingEnabled
        self.userNotes = userNotes
        self.selectedMealTypesRaw = selectedMealTypes
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.rawValue }
            .joined(separator: ",")
    }

    var difficulty: MealDifficulty {
        MealDifficulty(rawValue: difficultyPreference) ?? .easy
    }

    var budget: BudgetLevel {
        BudgetLevel(rawValue: budgetLevel) ?? .moderate
    }

    /// Selected meal types for this plan
    var selectedMealTypes: Set<MealType> {
        get {
            Set(selectedMealTypesRaw.split(separator: ",")
                .compactMap { MealType(rawValue: String($0)) })
        }
        set {
            selectedMealTypesRaw = newValue
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { $0.rawValue }
                .joined(separator: ",")
        }
    }

    var goalType: GoalType {
        GoalType(rawValue: goal) ?? .maintenance
    }
}

@Model
final class DailyPlan {
    var date: Date
    var dayName: String
    
    @Relationship(deleteRule: .cascade) var meals: [Meal] = []
    @Relationship(inverse: \DietPlan.days) var plan: DietPlan?
    
    init(date: Date, dayName: String) {
        self.date = date
        self.dayName = dayName
    }
}

@Model
final class Meal {
    var id: UUID
    var typeRaw: String
    var name: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    // Store ingredients as JSON data for SwiftData compatibility
    var ingredientsData: Data?

    // Prep time and difficulty
    var prepTimeMinutes: Int
    var difficultyRaw: String

    // Cooking instructions
    var cookingInstructions: [String] = []

    // Logging
    var isLogged: Bool
    var loggedAt: Date?

    @Relationship(inverse: \DailyPlan.meals) var day: DailyPlan?

    init(
        type: MealType,
        name: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        ingredients: [MealIngredient] = [],
        prepTimeMinutes: Int = 15,
        difficulty: MealDifficulty = .easy,
        cookingInstructions: [String] = []
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredientsData = try? JSONEncoder().encode(ingredients)
        self.prepTimeMinutes = prepTimeMinutes
        self.difficultyRaw = difficulty.rawValue
        self.cookingInstructions = cookingInstructions
        self.isLogged = false
        self.loggedAt = nil
    }

    // MARK: - Computed Properties

    var type: MealType {
        return MealType(rawValue: typeRaw) ?? .snack
    }

    var difficulty: MealDifficulty {
        return MealDifficulty(rawValue: difficultyRaw) ?? .easy
    }

    /// Structured ingredients with name and quantity
    var ingredients: [MealIngredient] {
        get {
            guard let data = ingredientsData else { return [] }
            return (try? JSONDecoder().decode([MealIngredient].self, from: data)) ?? []
        }
        set {
            ingredientsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Legacy support: Get ingredients as simple strings (for display)
    var ingredientStrings: [String] {
        ingredients.map { $0.displayString }
    }

    /// Set ingredients from legacy string array (for migration/compatibility)
    func setIngredientsFromStrings(_ strings: [String]) {
        self.ingredients = strings.map { MealIngredient.fromLegacyString($0) }
    }

    // Mark meal as logged
    func markAsLogged() {
        self.isLogged = true
        self.loggedAt = Date()
    }

    // Unmark meal
    func unmarkAsLogged() {
        self.isLogged = false
        self.loggedAt = nil
    }
}

// MARK: - Meal Difficulty
enum MealDifficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

// MARK: - Budget Level
enum BudgetLevel: String, Codable, CaseIterable {
    case low = "$"
    case moderate = "$$"
    case high = "$$$"

    var displayName: String {
        switch self {
        case .low: return "Budget-friendly"
        case .moderate: return "Moderate"
        case .high: return "No limit"
        }
    }
}

// MARK: - Ingredient Category
enum IngredientCategory: String, Codable, CaseIterable {
    case protein = "Protein"
    case dairy = "Dairy"
    case vegetables = "Vegetables"
    case fruits = "Fruits"
    case grains = "Grains"
    case spices = "Spices & Seasonings"
    case other = "Other"

    var icon: String {
        switch self {
        case .protein: return "fish.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .vegetables: return "leaf.fill"
        case .fruits: return "apple.logo"
        case .grains: return "wheat.bundle"
        case .spices: return "flame.fill"
        case .other: return "basket.fill"
        }
    }
}

// MARK: - Meal Log Model
@Model
final class MealLog {
    var id: UUID
    var mealName: String
    var mealTypeRaw: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var loggedAt: Date

    // Optional reference to original meal (if logged from a plan)
    @Relationship var originalMeal: Meal?

    init(meal: Meal) {
        self.id = UUID()
        self.mealName = meal.name
        self.mealTypeRaw = meal.typeRaw
        self.calories = meal.calories
        self.protein = meal.protein
        self.carbs = meal.carbs
        self.fat = meal.fat
        self.loggedAt = Date()
        self.originalMeal = meal
    }

    init(
        name: String,
        type: MealType,
        calories: Int,
        protein: Int = 0,
        carbs: Int = 0,
        fat: Int = 0,
        loggedAt: Date = Date()
    ) {
        self.id = UUID()
        self.mealName = name
        self.mealTypeRaw = type.rawValue
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.loggedAt = loggedAt
        self.originalMeal = nil
    }

    var mealType: MealType {
        MealType(rawValue: mealTypeRaw) ?? .snack
    }
}

// MARK: - Shopping List Item Model
@Model
final class ShoppingListItem {
    var id: UUID
    var name: String
    var quantity: String
    var categoryRaw: String
    var estimatedPrice: Double?
    var isPurchased: Bool
    var addedDate: Date

    init(
        name: String,
        quantity: String = "",
        category: IngredientCategory = .other,
        estimatedPrice: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.categoryRaw = category.rawValue
        self.estimatedPrice = estimatedPrice
        self.isPurchased = false
        self.addedDate = Date()
    }

    var category: IngredientCategory {
        IngredientCategory(rawValue: categoryRaw) ?? .other
    }
}
