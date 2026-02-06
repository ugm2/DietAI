import Foundation
import SwiftData

// MARK: - Generate Diet Plan Request
struct GenerateDietPlanRequest {
    let goal: GoalType
    let targetCalories: Int
    let restrictions: [String]
    let preferences: [String]
    let durationDays: Int
    let planName: String

    init(
        goal: GoalType = .maintenance,
        targetCalories: Int = 2000,
        restrictions: [String] = [],
        preferences: [String] = [],
        durationDays: Int = 7,
        planName: String = "Generated Plan"
    ) {
        self.goal = goal
        self.targetCalories = targetCalories
        self.restrictions = restrictions
        self.preferences = preferences
        self.durationDays = durationDays
        self.planName = planName
    }
}

// MARK: - Generate Diet Plan Use Case
@MainActor
final class GenerateDietPlanUseCase {
    private let aiModelService: AIModelService
    private let repository: DietPlanRepository

    init(aiModelService: AIModelService, repository: DietPlanRepository) {
        self.aiModelService = aiModelService
        self.repository = repository
    }

    func execute(request: GenerateDietPlanRequest) async throws -> DietPlan {
        // 1. Ensure model is loaded
        if !aiModelService.isLoaded {
            try await aiModelService.loadModel()
        }

        // 2. Build prompt for MLX
        let prompt = PromptTemplate.dietPlan(
            goal: request.goal,
            calories: request.targetCalories,
            restrictions: request.restrictions,
            preferences: request.preferences,
            days: request.durationDays
        )

        // 4. Generate response
        let response = try await aiModelService.generate(
            prompt: prompt.formatForLlama(),
            maxTokens: 2000,
            temperature: 0.1
        )

        // 5. Validate and parse response
        let aiResponse = try AIResponseValidator.validateDietPlanResponse(response)

        // 6. Create and save diet plan
        let plan = try repository.createDietPlan(
            from: aiResponse,
            name: request.planName,
            goal: request.goal,
            calories: request.targetCalories
        )

        return plan
    }

    /// Create a curated fallback diet plan when AI generation fails
    private func createFallbackDietPlan(request: GenerateDietPlanRequest) -> DietPlan {
        let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        var aiDays: [AIDay] = []

        for i in 0..<request.durationDays {
            let dayName = dayNames[i % 7]
            let meals = createFallbackMealsForDay(
                dayIndex: i,
                goal: request.goal,
                dailyCalories: request.targetCalories
            )
            aiDays.append(AIDay(day: dayName, meals: meals))
        }

        let aiResponse = AIResponse(days: aiDays)
        do {
            return try repository.createDietPlan(
                from: aiResponse,
                name: request.planName,
                goal: request.goal,
                calories: request.targetCalories
            )
        } catch {
            // Create a minimal plan if repository fails
            return DietPlan(
                name: request.planName,
                goal: request.goal,
                calories: request.targetCalories
            )
        }
    }

    /// Create curated fallback meals for a single day
    private func createFallbackMealsForDay(dayIndex: Int, goal: GoalType, dailyCalories: Int) -> [AIMeal] {
        // Calorie distribution: Breakfast 25%, Lunch 30%, Snack 15%, Dinner 30%
        let breakfastCal = Int(Double(dailyCalories) * 0.25)
        let lunchCal = Int(Double(dailyCalories) * 0.30)
        let snackCal = Int(Double(dailyCalories) * 0.15)
        let dinnerCal = Int(Double(dailyCalories) * 0.30)

        // Curated meals organized by goal
        let fallbackLibrary: [GoalType: [[AIMeal]]] = [
            .weightLoss: [
                // Day variation 1
                [
                    AIMeal(type: "Breakfast", name: "Greek Yogurt Parfait", calories: breakfastCal, protein: 20, carbs: 30, fat: 8, ingredientStrings: ["Greek yogurt", "mixed berries", "granola", "honey"]),
                    AIMeal(type: "Lunch", name: "Grilled Chicken Salad", calories: lunchCal, protein: 35, carbs: 15, fat: 12, ingredientStrings: ["chicken breast", "mixed greens", "cucumber", "olive oil"]),
                    AIMeal(type: "Snack", name: "Apple with Almond Butter", calories: snackCal, protein: 4, carbs: 20, fat: 8, ingredientStrings: ["apple", "almond butter"]),
                    AIMeal(type: "Dinner", name: "Baked Salmon with Vegetables", calories: dinnerCal, protein: 35, carbs: 20, fat: 15, ingredientStrings: ["salmon", "asparagus", "lemon", "olive oil"])
                ],
                // Day variation 2
                [
                    AIMeal(type: "Breakfast", name: "Egg White Omelette", calories: breakfastCal, protein: 25, carbs: 10, fat: 8, ingredientStrings: ["egg whites", "spinach", "tomatoes", "feta cheese"]),
                    AIMeal(type: "Lunch", name: "Turkey Wrap", calories: lunchCal, protein: 30, carbs: 35, fat: 10, ingredientStrings: ["turkey breast", "whole wheat wrap", "lettuce", "mustard"]),
                    AIMeal(type: "Snack", name: "Cottage Cheese with Berries", calories: snackCal, protein: 12, carbs: 15, fat: 3, ingredientStrings: ["cottage cheese", "strawberries"]),
                    AIMeal(type: "Dinner", name: "Shrimp Stir Fry", calories: dinnerCal, protein: 30, carbs: 25, fat: 12, ingredientStrings: ["shrimp", "broccoli", "bell peppers", "ginger"])
                ]
            ],
            .muscleGain: [
                [
                    AIMeal(type: "Breakfast", name: "Protein Pancakes", calories: breakfastCal, protein: 30, carbs: 40, fat: 10, ingredientStrings: ["protein powder", "oats", "eggs", "banana"]),
                    AIMeal(type: "Lunch", name: "Chicken Rice Bowl", calories: lunchCal, protein: 40, carbs: 50, fat: 12, ingredientStrings: ["chicken breast", "brown rice", "black beans", "avocado"]),
                    AIMeal(type: "Snack", name: "Protein Shake", calories: snackCal, protein: 25, carbs: 15, fat: 5, ingredientStrings: ["protein powder", "banana", "milk"]),
                    AIMeal(type: "Dinner", name: "Steak with Sweet Potato", calories: dinnerCal, protein: 45, carbs: 40, fat: 18, ingredientStrings: ["ribeye steak", "sweet potato", "broccoli"])
                ],
                [
                    AIMeal(type: "Breakfast", name: "Steak and Eggs", calories: breakfastCal, protein: 35, carbs: 5, fat: 20, ingredientStrings: ["sirloin steak", "eggs", "avocado"]),
                    AIMeal(type: "Lunch", name: "Salmon Rice Bowl", calories: lunchCal, protein: 38, carbs: 45, fat: 15, ingredientStrings: ["salmon", "white rice", "edamame", "teriyaki sauce"]),
                    AIMeal(type: "Snack", name: "Greek Yogurt with Nuts", calories: snackCal, protein: 18, carbs: 12, fat: 10, ingredientStrings: ["Greek yogurt", "almonds", "honey"]),
                    AIMeal(type: "Dinner", name: "Chicken Pasta", calories: dinnerCal, protein: 40, carbs: 55, fat: 14, ingredientStrings: ["chicken breast", "whole wheat pasta", "marinara sauce", "parmesan"])
                ]
            ],
            .maintenance: [
                [
                    AIMeal(type: "Breakfast", name: "Avocado Toast with Eggs", calories: breakfastCal, protein: 15, carbs: 30, fat: 18, ingredientStrings: ["whole grain bread", "avocado", "poached eggs"]),
                    AIMeal(type: "Lunch", name: "Mediterranean Bowl", calories: lunchCal, protein: 25, carbs: 40, fat: 15, ingredientStrings: ["falafel", "hummus", "cucumber", "quinoa"]),
                    AIMeal(type: "Snack", name: "Mixed Nuts", calories: snackCal, protein: 6, carbs: 8, fat: 14, ingredientStrings: ["almonds", "cashews", "walnuts"]),
                    AIMeal(type: "Dinner", name: "Grilled Chicken with Rice", calories: dinnerCal, protein: 35, carbs: 40, fat: 12, ingredientStrings: ["chicken breast", "brown rice", "steamed vegetables"])
                ],
                [
                    AIMeal(type: "Breakfast", name: "Oatmeal with Fruit", calories: breakfastCal, protein: 10, carbs: 45, fat: 8, ingredientStrings: ["oatmeal", "banana", "blueberries", "honey"]),
                    AIMeal(type: "Lunch", name: "Chicken Caesar Salad", calories: lunchCal, protein: 30, carbs: 20, fat: 18, ingredientStrings: ["chicken breast", "romaine lettuce", "parmesan", "caesar dressing"]),
                    AIMeal(type: "Snack", name: "Cheese and Crackers", calories: snackCal, protein: 8, carbs: 15, fat: 10, ingredientStrings: ["cheddar cheese", "whole grain crackers"]),
                    AIMeal(type: "Dinner", name: "Fish Tacos", calories: dinnerCal, protein: 28, carbs: 35, fat: 15, ingredientStrings: ["white fish", "corn tortillas", "cabbage slaw", "lime"])
                ]
            ],
            .keto: [
                [
                    AIMeal(type: "Breakfast", name: "Bacon and Eggs", calories: breakfastCal, protein: 20, carbs: 2, fat: 30, ingredientStrings: ["bacon", "eggs", "avocado"]),
                    AIMeal(type: "Lunch", name: "Cobb Salad", calories: lunchCal, protein: 35, carbs: 8, fat: 35, ingredientStrings: ["chicken", "bacon", "eggs", "avocado", "blue cheese"]),
                    AIMeal(type: "Snack", name: "Cheese and Pepperoni", calories: snackCal, protein: 10, carbs: 2, fat: 15, ingredientStrings: ["mozzarella", "pepperoni"]),
                    AIMeal(type: "Dinner", name: "Ribeye with Butter", calories: dinnerCal, protein: 40, carbs: 3, fat: 40, ingredientStrings: ["ribeye steak", "butter", "asparagus"])
                ],
                [
                    AIMeal(type: "Breakfast", name: "Smoked Salmon Plate", calories: breakfastCal, protein: 22, carbs: 3, fat: 28, ingredientStrings: ["smoked salmon", "cream cheese", "capers", "cucumber"]),
                    AIMeal(type: "Lunch", name: "Bunless Burger", calories: lunchCal, protein: 38, carbs: 5, fat: 38, ingredientStrings: ["beef patty", "cheese", "lettuce", "tomato", "mayo"]),
                    AIMeal(type: "Snack", name: "Avocado with Everything", calories: snackCal, protein: 3, carbs: 4, fat: 18, ingredientStrings: ["avocado", "everything bagel seasoning", "olive oil"]),
                    AIMeal(type: "Dinner", name: "Salmon with Creamy Spinach", calories: dinnerCal, protein: 35, carbs: 5, fat: 38, ingredientStrings: ["salmon", "spinach", "cream", "garlic"])
                ]
            ]
        ]

        let goalMeals = fallbackLibrary[goal] ?? fallbackLibrary[.maintenance]!
        let dayVariation = dayIndex % goalMeals.count
        return goalMeals[dayVariation]
    }
}

// MARK: - Meal Substitution Use Case
@MainActor
final class SubstituteMealUseCase {
    private let aiModelService: AIModelService
    private let mealRepository: MealRepository

    init(aiModelService: AIModelService, mealRepository: MealRepository) {
        self.aiModelService = aiModelService
        self.mealRepository = mealRepository
    }

    struct SubstitutionRequest {
        let meal: Meal
        let reason: String?
        let constraints: String
    }

    struct SubstitutionResponse: Codable {
        let alternatives: [AIMeal]
    }

    func execute(request: SubstitutionRequest) async throws -> [AIMeal] {
        let prompt = PromptTemplate.mealSubstitution(
            currentMeal: request.meal.name,
            reason: request.reason,
            constraints: request.constraints
        )

        let response = try await aiModelService.generate(
            prompt: prompt.formatForLlama(),
            maxTokens: 1000,
            temperature: 0.3
        )

        let cleanJSON = AIResponseValidator.cleanJSON(response)
        guard let data = cleanJSON.data(using: .utf8) else {
            throw ValidationError.invalidData
        }

        let substitutionResponse = try JSONDecoder().decode(SubstitutionResponse.self, from: data)
        return substitutionResponse.alternatives
    }

    func applySubstitution(meal: Meal, alternative: AIMeal) throws -> Meal {
        return try mealRepository.substituteWithAlternative(meal, alternative: alternative)
    }
}
