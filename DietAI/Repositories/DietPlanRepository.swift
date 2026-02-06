import Foundation
import SwiftData

// MARK: - Diet Plan Repository Protocol
protocol DietPlanRepositoryProtocol {
    func fetchAll() throws -> [DietPlan]
    func fetch(by id: UUID) throws -> DietPlan?
    func save(_ plan: DietPlan) throws
    func delete(_ plan: DietPlan) throws
    func deleteAll() throws
}

// MARK: - Diet Plan Repository Implementation
@MainActor
final class DietPlanRepository: DietPlanRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [DietPlan] {
        let descriptor = FetchDescriptor<DietPlan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(by id: UUID) throws -> DietPlan? {
        let descriptor = FetchDescriptor<DietPlan>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func save(_ plan: DietPlan) throws {
        modelContext.insert(plan)
        try modelContext.save()
    }

    func delete(_ plan: DietPlan) throws {
        modelContext.delete(plan)
        try modelContext.save()
    }

    func deleteAll() throws {
        let plans = try fetchAll()
        for plan in plans {
            modelContext.delete(plan)
        }
        try modelContext.save()
    }

    // MARK: - Create Diet Plan from AI Response
    func createDietPlan(
        from aiResponse: AIResponse,
        name: String,
        goal: GoalType,
        calories: Int
    ) throws -> DietPlan {
        let newPlan = DietPlan(name: name, goal: goal, calories: calories)
        modelContext.insert(newPlan)

        for aiDay in aiResponse.days {
            let newDay = DailyPlan(date: Date(), dayName: aiDay.day)
            newDay.plan = newPlan
            modelContext.insert(newDay)

            for aiMeal in aiDay.meals {
                let type = MealType(rawValue: aiMeal.type) ?? .snack

                let newMeal = Meal(
                    type: type,
                    name: aiMeal.name,
                    calories: aiMeal.calories,
                    protein: aiMeal.protein ?? 0,
                    carbs: aiMeal.carbs ?? 0,
                    fat: aiMeal.fat ?? 0
                )
                newMeal.ingredients = aiMeal.getMealIngredients()
                newMeal.day = newDay
                modelContext.insert(newMeal)
            }
        }

        try modelContext.save()
        return newPlan
    }
}

// MARK: - Daily Plan Repository Protocol
protocol DailyPlanRepositoryProtocol {
    func fetchMeals(for day: DailyPlan) throws -> [Meal]
    func addMeal(_ meal: Meal, to day: DailyPlan) throws
    func removeMeal(_ meal: Meal) throws
}

// MARK: - Meal Repository Protocol
protocol MealRepositoryProtocol {
    func update(_ meal: Meal) throws
    func substituteWithAlternative(_ meal: Meal, alternative: AIMeal) throws -> Meal
}

@MainActor
final class MealRepository: MealRepositoryProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func update(_ meal: Meal) throws {
        try modelContext.save()
    }

    func substituteWithAlternative(_ meal: Meal, alternative: AIMeal) throws -> Meal {
        meal.name = alternative.name
        meal.calories = alternative.calories
        meal.protein = alternative.protein ?? meal.protein
        meal.carbs = alternative.carbs ?? meal.carbs
        meal.fat = alternative.fat ?? meal.fat
        meal.ingredients = alternative.getMealIngredients().isEmpty ? meal.ingredients : alternative.getMealIngredients()
        try modelContext.save()
        return meal
    }
}
