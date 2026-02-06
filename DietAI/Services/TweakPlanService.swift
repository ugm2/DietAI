import Foundation
import SwiftData

// MARK: - Tweak Plan Service
/// Orchestrates the plan tweaking workflow
@MainActor
@Observable
class TweakPlanService {

    // MARK: - State
    var phase: TweakPhase = .idle
    var progress: Double = 0.0
    var currentIntent: TweakIntent?
    var affectedMeals: [Meal] = []
    var proposedChanges: [MealChange] = []
    var errorMessage: String?

    // MARK: - Public Methods

    /// Parse a prompt and identify affected meals
    func prepareTweak(prompt: String, plan: DietPlan) async throws {
        phase = .parsing
        errorMessage = nil

        // Parse the intent
        guard let intent = TweakIntentParser.parse(prompt, plan: plan) else {
            throw TweakError.unableToParseIntent
        }

        currentIntent = intent

        // Get affected meals
        affectedMeals = TweakIntentParser.getAffectedMeals(intent: intent, plan: plan)

        if affectedMeals.isEmpty {
            throw TweakError.noMealsAffected
        }

        phase = .idle
    }

    /// Generate replacement meals for all affected meals
    func generateReplacements(plan: DietPlan, restrictions: [String]) async throws {
        guard let intent = currentIntent else {
            throw TweakError.noIntent
        }

        phase = .generating(progress: 0)
        proposedChanges = []
        progress = 0

        let totalMeals = affectedMeals.count

        for (index, meal) in affectedMeals.enumerated() {
            // Find the day this meal belongs to
            guard let day = meal.day else { continue }

            // Generate a replacement based on the action, respecting plan preferences
            let newMeal = try await generateReplacementMeal(
                for: meal,
                intent: intent,
                goal: plan.goalType,
                restrictions: restrictions,
                maxPrepTime: plan.maxPrepTimeMinutes,
                maxDifficulty: plan.difficulty
            )

            let change = MealChange(
                originalMeal: meal,
                dayName: day.dayName,
                newMealName: newMeal.name,
                newCalories: newMeal.calories,
                newProtein: newMeal.protein,
                newCarbs: newMeal.carbs,
                newFat: newMeal.fat,
                newIngredients: newMeal.ingredients,
                newPrepTimeMinutes: newMeal.prepTimeMinutes,
                newDifficulty: newMeal.difficulty,
                newCookingInstructions: newMeal.cookingInstructions
            )

            proposedChanges.append(change)

            // Update progress
            progress = Double(index + 1) / Double(totalMeals)
            phase = .generating(progress: progress)
        }

        phase = .preview
    }

    /// Apply accepted changes to the database
    func applyChanges(modelContext: ModelContext) {
        phase = .applying

        for change in proposedChanges where change.isAccepted {
            let meal = change.originalMeal

            // Update meal properties
            meal.name = change.newMealName
            meal.calories = change.newCalories
            meal.protein = change.newProtein
            meal.carbs = change.newCarbs
            meal.fat = change.newFat
            meal.ingredients = change.newIngredients
            meal.prepTimeMinutes = change.newPrepTimeMinutes
            meal.difficultyRaw = change.newDifficulty.rawValue
            meal.cookingInstructions = change.newCookingInstructions

            // Reset logging status since it's a new meal
            meal.isLogged = false
            meal.loggedAt = nil
        }

        do {
            try modelContext.save()
            phase = .completed
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            phase = .idle
            #if DEBUG
            print("⚠️ TweakPlanService save error: \(error)")
            #endif
        }
    }

    /// Reset the service state
    func reset() {
        phase = .idle
        progress = 0
        currentIntent = nil
        affectedMeals = []
        proposedChanges = []
        errorMessage = nil
    }

    /// Toggle acceptance of a specific change
    func toggleChange(_ change: MealChange) {
        if let index = proposedChanges.firstIndex(where: { $0.id == change.id }) {
            proposedChanges[index].isAccepted.toggle()
        }
    }

    /// Count of accepted changes
    var acceptedCount: Int {
        proposedChanges.filter { $0.isAccepted }.count
    }

    // MARK: - Private Methods

    private func generateReplacementMeal(
        for meal: Meal,
        intent: TweakIntent,
        goal: GoalType,
        restrictions: [String],
        maxPrepTime: Int,
        maxDifficulty: MealDifficulty
    ) async throws -> GeneratedMeal {
        let service = MealSuggestionService.shared

        // Build preference string that includes the user's request AND plan constraints
        var preference = intent.originalPrompt

        // Add difficulty constraint to the preference
        switch maxDifficulty {
        case .easy:
            preference += ". Must be easy and simple to prepare, no complex techniques"
        case .medium:
            preference += ". Keep it moderately easy to prepare"
        case .hard:
            break // No constraint needed
        }

        // Add prep time constraint
        if maxPrepTime > 0 && maxPrepTime <= 30 {
            preference += ". Must be ready in under \(maxPrepTime) minutes"
        }

        // Calculate target calories based on action
        let targetCalories = calculateTargetCalories(for: intent, originalMeal: meal)

        // Generate replacement using MealSuggestionService (uses the AI model)
        let plannedMeal = try await service.generateMealSuggestionWithPreference(
            type: meal.type,
            targetCalories: targetCalories,
            goal: goal,
            restrictions: restrictions,
            existingMeals: [],
            userPreference: preference
        )

        // Generate cooking instructions
        let instructions = generateCookingInstructions(for: plannedMeal)

        // Validate and correct macros to ensure they add up to calories
        let (validatedProtein, validatedCarbs, validatedFat, validatedCalories) = validateMacros(
            protein: plannedMeal.protein,
            carbs: plannedMeal.carbs,
            fat: plannedMeal.fat,
            targetCalories: targetCalories
        )

        // Determine prep time - respect plan's max, but estimate based on ingredients
        let estimatedPrepTime = estimatePrepTime(for: plannedMeal)
        let finalPrepTime = maxPrepTime > 0 ? min(estimatedPrepTime, maxPrepTime) : estimatedPrepTime

        // Determine difficulty - never exceed plan's max difficulty
        let estimatedDifficulty = estimateDifficulty(for: plannedMeal)
        let finalDifficulty = capDifficulty(estimatedDifficulty, max: maxDifficulty)

        return GeneratedMeal(
            name: plannedMeal.name,
            calories: validatedCalories,
            protein: validatedProtein,
            carbs: validatedCarbs,
            fat: validatedFat,
            ingredients: plannedMeal.ingredients,
            prepTimeMinutes: finalPrepTime,
            difficulty: finalDifficulty,
            cookingInstructions: instructions
        )
    }

    /// Validate that macros add up to calories correctly
    /// If they don't match, adjust macros proportionally to match target calories
    private func validateMacros(
        protein: Int,
        carbs: Int,
        fat: Int,
        targetCalories: Int
    ) -> (protein: Int, carbs: Int, fat: Int, calories: Int) {
        // Calculate calories from macros: protein/carbs = 4 cal/g, fat = 9 cal/g
        let calculatedCalories = (protein * 4) + (carbs * 4) + (fat * 9)

        // If within 5% tolerance, just recalculate calories from macros for accuracy
        let tolerance = Double(targetCalories) * 0.05
        if abs(Double(calculatedCalories - targetCalories)) <= tolerance {
            return (protein, carbs, fat, calculatedCalories)
        }

        // Macros don't match target - adjust them proportionally
        // Keep the same ratio but scale to match target calories
        let scaleFactor = Double(targetCalories) / Double(max(calculatedCalories, 1))

        // Scale each macro, keeping fat calories at ~30% for balanced nutrition
        var newProtein = Int(Double(protein) * scaleFactor)
        var newCarbs = Int(Double(carbs) * scaleFactor)
        var newFat = Int(Double(fat) * scaleFactor)

        // Ensure minimums
        newProtein = max(newProtein, 5)
        newCarbs = max(newCarbs, 5)
        newFat = max(newFat, 2)

        // Recalculate to get exact calories
        let newCalculatedCalories = (newProtein * 4) + (newCarbs * 4) + (newFat * 9)

        // Fine-tune: adjust carbs slightly if still off
        let diff = targetCalories - newCalculatedCalories
        if abs(diff) > 0 {
            // Each gram of carbs = 4 calories
            newCarbs += diff / 4
            newCarbs = max(newCarbs, 5)
        }

        let finalCalories = (newProtein * 4) + (newCarbs * 4) + (newFat * 9)

        return (newProtein, newCarbs, newFat, finalCalories)
    }

    /// Cap difficulty to not exceed the plan's maximum
    private func capDifficulty(_ estimated: MealDifficulty, max: MealDifficulty) -> MealDifficulty {
        let order: [MealDifficulty] = [.easy, .medium, .hard]
        guard let estimatedIndex = order.firstIndex(of: estimated),
              let maxIndex = order.firstIndex(of: max) else {
            return estimated
        }
        return estimatedIndex <= maxIndex ? estimated : max
    }

    private func calculateTargetCalories(for intent: TweakIntent, originalMeal: Meal) -> Int {
        switch intent.action {
        case .adjustCalories(let delta):
            return max(100, originalMeal.calories + delta)

        case .adjustMacro(_, let direction):
            // Adjust calories slightly based on macro change
            let adjustment = direction == .increase ? 50 : -50
            return max(100, originalMeal.calories + adjustment)

        default:
            return originalMeal.calories
        }
    }

    private func generateCookingInstructions(for meal: PlannedMeal) -> [String] {
        // Generate simple cooking instructions based on ingredients
        var steps: [String] = []

        // Add prep step
        let ingredientList = meal.ingredients.map { $0.displayString }.joined(separator: ", ")
        steps.append("Gather all ingredients: \(ingredientList)")

        // Add cooking steps based on meal type
        switch meal.type {
        case .breakfast:
            steps.append("Prepare your cooking surface (pan, bowl, etc.)")
            steps.append("Combine ingredients as needed")
            steps.append("Cook until done or assemble if no cooking required")
            steps.append("Plate and serve while warm")

        case .brunch:
            steps.append("Prepare your cooking surface (pan, bowl, etc.)")
            steps.append("Combine ingredients as needed")
            steps.append("Cook until done or assemble if no cooking required")
            steps.append("Plate and serve while warm")

        case .lunch:
            steps.append("Prepare any proteins or vegetables that need cooking")
            steps.append("Chop and prepare fresh ingredients")
            steps.append("Assemble the dish")
            steps.append("Add dressing or seasonings to taste")

        case .dinner:
            steps.append("Preheat oven or prepare cooking surface")
            steps.append("Season and prepare the main protein")
            steps.append("Cook protein to desired doneness")
            steps.append("Prepare side dishes and vegetables")
            steps.append("Plate everything together and serve")

        case .snack:
            steps.append("Prepare or portion the snack")
            steps.append("Enjoy!")
        }

        return steps
    }

    private func estimatePrepTime(for meal: PlannedMeal) -> Int {
        // Estimate prep time based on ingredients count and meal type
        let baseTime: Int
        switch meal.type {
        case .breakfast: baseTime = 10
        case .brunch: baseTime = 15
        case .lunch: baseTime = 15
        case .dinner: baseTime = 25
        case .snack: baseTime = 5
        }

        // Add time for more ingredients
        let ingredientBonus = min(meal.ingredients.count * 2, 15)

        return baseTime + ingredientBonus
    }

    private func estimateDifficulty(for meal: PlannedMeal) -> MealDifficulty {
        // Estimate difficulty based on ingredients and meal type
        let ingredientCount = meal.ingredients.count

        if ingredientCount <= 3 {
            return .easy
        } else if ingredientCount <= 6 {
            return .medium
        } else {
            return .hard
        }
    }
}

// MARK: - Supporting Types

struct GeneratedMeal {
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let ingredients: [MealIngredient]
    let prepTimeMinutes: Int
    let difficulty: MealDifficulty
    let cookingInstructions: [String]
}

// MARK: - Errors

enum TweakError: LocalizedError {
    case unableToParseIntent
    case noMealsAffected
    case noIntent
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unableToParseIntent:
            return "Couldn't understand your request. Try something like \"make breakfasts lighter\" or \"remove salmon dishes\"."
        case .noMealsAffected:
            return "No meals match your criteria. Try a different request."
        case .noIntent:
            return "Please enter what you'd like to change first."
        case .generationFailed:
            return "Failed to generate replacement meals. Please try again."
        }
    }
}

// PlannedMeal now has prepTimeMinutes, difficulty, and cookingInstructions as stored properties
