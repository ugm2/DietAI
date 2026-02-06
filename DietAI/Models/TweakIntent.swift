import Foundation

// MARK: - Tweak Scope
/// Defines which meals in the plan should be modified
enum TweakScope: Equatable {
    case allMeals                           // "Add more protein to all meals"
    case mealType(MealType)                 // "Change all breakfasts"
    case specificDay(dayName: String)       // "Make Wednesday vegetarian"
    case ingredient(String)                 // "Remove all salmon dishes"

    var description: String {
        switch self {
        case .allMeals:
            return "all meals"
        case .mealType(let type):
            return "all \(type.rawValue.lowercased())s"
        case .specificDay(let day):
            return "\(day) meals"
        case .ingredient(let ingredient):
            return "meals with \(ingredient)"
        }
    }
}

// MARK: - Macro Type
enum MacroType: String, CaseIterable {
    case protein = "Protein"
    case carbs = "Carbs"
    case fat = "Fat"
}

// MARK: - Macro Direction
enum MacroDirection {
    case increase
    case decrease

    var description: String {
        switch self {
        case .increase: return "more"
        case .decrease: return "less"
        }
    }
}

// MARK: - Tweak Action
/// Defines what modification to apply to the selected meals
enum TweakAction: Equatable {
    case replace                                    // Full replacement
    case adjustCalories(delta: Int)                 // +/- calories
    case adjustMacro(MacroType, MacroDirection)     // e.g., more protein
    case addRestriction(String)                     // e.g., "vegetarian"
    case removeIngredient(String)                   // e.g., "salmon"
    case quickPrep                                  // Replace with <15 min meals

    var description: String {
        switch self {
        case .replace:
            return "replace with new meals"
        case .adjustCalories(let delta):
            return delta > 0 ? "increase by \(delta) kcal" : "decrease by \(abs(delta)) kcal"
        case .adjustMacro(let macro, let direction):
            return "\(direction.description) \(macro.rawValue.lowercased())"
        case .addRestriction(let restriction):
            return "make \(restriction)"
        case .removeIngredient(let ingredient):
            return "remove \(ingredient)"
        case .quickPrep:
            return "replace with quick meals"
        }
    }

    static func == (lhs: TweakAction, rhs: TweakAction) -> Bool {
        switch (lhs, rhs) {
        case (.replace, .replace):
            return true
        case (.adjustCalories(let a), .adjustCalories(let b)):
            return a == b
        case (.adjustMacro(let m1, let d1), .adjustMacro(let m2, let d2)):
            return m1 == m2 && d1 == d2
        case (.addRestriction(let a), .addRestriction(let b)):
            return a == b
        case (.removeIngredient(let a), .removeIngredient(let b)):
            return a == b
        case (.quickPrep, .quickPrep):
            return true
        default:
            return false
        }
    }
}

// MARK: - Tweak Intent
/// Represents a parsed user request to modify their meal plan
struct TweakIntent {
    let scope: TweakScope
    let action: TweakAction
    let originalPrompt: String

    /// Human-readable description of what will change
    var description: String {
        "Will \(action.description) for \(scope.description)"
    }
}

// MARK: - Meal Change
/// Represents a proposed change to a single meal
struct MealChange: Identifiable {
    let id = UUID()
    let originalMeal: Meal
    let dayName: String
    let newMealName: String
    let newCalories: Int
    let newProtein: Int
    let newCarbs: Int
    let newFat: Int
    let newIngredients: [MealIngredient]
    let newPrepTimeMinutes: Int
    let newDifficulty: MealDifficulty
    let newCookingInstructions: [String]
    var isAccepted: Bool = true

    /// Calorie difference from original
    var calorieDelta: Int {
        newCalories - originalMeal.calories
    }

    /// Create a new Meal from this change
    func toMeal() -> Meal {
        let meal = Meal(
            type: originalMeal.type,
            name: newMealName,
            calories: newCalories,
            protein: newProtein,
            carbs: newCarbs,
            fat: newFat,
            ingredients: newIngredients,
            prepTimeMinutes: newPrepTimeMinutes,
            difficulty: newDifficulty,
            cookingInstructions: newCookingInstructions
        )
        return meal
    }
}

// MARK: - Tweak Phase
/// Tracks the current phase of the tweak process
enum TweakPhase: Equatable {
    case idle
    case parsing
    case generating(progress: Double)
    case preview
    case applying
    case completed
    case error(String)

    static func == (lhs: TweakPhase, rhs: TweakPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.parsing, .parsing): return true
        case (.generating(let a), .generating(let b)): return a == b
        case (.preview, .preview): return true
        case (.applying, .applying): return true
        case (.completed, .completed): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}
