import Foundation

// MARK: - Prompt Templates
enum PromptTemplate {
    case dietPlan(goal: GoalType, calories: Int, restrictions: [String], preferences: [String], days: Int)
    case activityAwareDietPlan(goal: GoalType, calories: Int, restrictions: [String], preferences: [String], days: Int, activityContext: ActivityPromptContext)
    case mealSubstitution(currentMeal: String, reason: String?, constraints: String)
    case nutritionAnalysis(mealDescription: String)

    var systemPrompt: String {
        switch self {
        case .dietPlan:
            return """
            You are an expert nutritionist. OUTPUT VALID JSON ONLY - no markdown, no explanation.

            Create balanced meal plans with accurate nutritional information.

            Required JSON structure:
            {
              "days": [
                {
                  "day": "Monday",
                  "meals": [
                    {
                      "type": "Breakfast",
                      "name": "Greek Yogurt Parfait",
                      "calories": 350,
                      "protein": 20,
                      "carbs": 45,
                      "fat": 10,
                      "ingredients": [
                        {"name": "Greek yogurt", "quantity": "1 cup"},
                        {"name": "Granola", "quantity": "1/2 cup"},
                        {"name": "Mixed berries", "quantity": "1/2 cup"},
                        {"name": "Honey", "quantity": "1 tbsp"}
                      ],
                      "prepTime": 5
                    }
                  ]
                }
              ]
            }

            Rules:
            - Include 4 meals per day: Breakfast, Lunch, Snack, Dinner
            - Provide realistic macros (protein, carbs, fat in grams)
            - List 3-6 ingredients per meal with name and quantity
            - Use standard units (cup, tbsp, tsp, oz, g, pieces, etc.)
            - prepTime is in minutes
            - Ensure daily totals match the requested calorie target
            """

        case let .activityAwareDietPlan(_, _, _, _, _, activityContext):
            return """
            You are an expert sports nutritionist. OUTPUT VALID JSON ONLY - no markdown, no explanation.

            Create meal plans optimized for athletic performance and recovery.

            ACTIVITY CONTEXT:
            \(activityContext.promptDescription)

            Required JSON structure:
            {
              "days": [
                {
                  "day": "Monday",
                  "meals": [
                    {
                      "type": "Breakfast",
                      "name": "High-Protein Oatmeal",
                      "calories": 400,
                      "protein": 25,
                      "carbs": 50,
                      "fat": 12,
                      "ingredients": [
                        {"name": "Oats", "quantity": "1 cup"},
                        {"name": "Protein powder", "quantity": "1 scoop"},
                        {"name": "Banana", "quantity": "1 medium"},
                        {"name": "Almond butter", "quantity": "1 tbsp"}
                      ],
                      "prepTime": 10
                    }
                  ]
                }
              ]
            }

            NUTRITION PRINCIPLES FOR ATHLETES:
            - Post-strength training days: Prioritize protein (25-30g per main meal), include fast-digesting carbs
            - Post-cardio/HIIT days: Balance carbs and protein for glycogen replenishment
            - Post-endurance days: Complex carbs, moderate protein, electrolyte-rich foods
            - Recovery/rest days: Lighter meals, anti-inflammatory foods, maintain protein

            Rules:
            - Include 4 meals per day: Breakfast, Lunch, Snack, Dinner
            - Adjust macros based on the activity context above
            - List 3-6 ingredients per meal with name and quantity
            - Use standard units (cup, tbsp, tsp, oz, g, pieces, etc.)
            - prepTime is in minutes
            - Ensure daily totals match the requested calorie target
            """

        case .mealSubstitution:
            return """
            You are a nutritionist helping to substitute meals.
            OUTPUT VALID JSON ONLY with 3 alternative meal suggestions.

            JSON structure:
            {
              "alternatives": [
                {
                  "name": "Alternative Meal Name",
                  "calories": 400,
                  "protein": 25,
                  "carbs": 40,
                  "fat": 12,
                  "ingredients": [
                    {"name": "Ingredient 1", "quantity": "1 cup"},
                    {"name": "Ingredient 2", "quantity": "2 oz"}
                  ],
                  "prepTime": 15,
                  "reason": "Why this is a good alternative"
                }
              ]
            }
            """

        case .nutritionAnalysis:
            return """
            You are a nutrition analysis expert.
            Analyze the described meal and estimate its nutritional content.
            OUTPUT VALID JSON ONLY.

            JSON structure:
            {
              "name": "Identified Meal",
              "calories": 500,
              "protein": 25,
              "carbs": 60,
              "fat": 20,
              "ingredients": [
                {"name": "Detected ingredient 1", "quantity": "estimated amount"},
                {"name": "Detected ingredient 2", "quantity": "estimated amount"}
              ],
              "confidence": 0.85,
              "notes": "Any relevant notes"
            }
            """
        }
    }

    var userPrompt: String {
        switch self {
        case let .dietPlan(goal, calories, restrictions, preferences, days):
            let restrictionsText = restrictions.isEmpty ? "None" : restrictions.joined(separator: ", ")
            let preferencesText = preferences.isEmpty ? "No specific preferences" : preferences.joined(separator: ", ")

            return """
            Create a \(days)-day diet plan with:
            - Goal: \(goal.rawValue)
            - Daily calories: \(calories) kcal
            - Dietary restrictions: \(restrictionsText)
            - Food preferences: \(preferencesText)

            Include Breakfast, Lunch, Snack, and Dinner for each day.
            """

        case let .activityAwareDietPlan(goal, calories, restrictions, preferences, days, activityContext):
            let restrictionsText = restrictions.isEmpty ? "None" : restrictions.joined(separator: ", ")
            let preferencesText = preferences.isEmpty ? "No specific preferences" : preferences.joined(separator: ", ")

            var activityText = ""
            if let dominant = activityContext.dominantCategory {
                activityText = "\n- Primary training focus: \(dominant.rawValue)"
            }
            if activityContext.isRecoveryWindowActive {
                activityText += "\n- Currently in post-workout recovery window"
            }
            if activityContext.weeklyTrend.workoutDays > 0 {
                activityText += "\n- Weekly workout frequency: \(activityContext.weeklyTrend.workoutDays) days"
            }

            return """
            Create a \(days)-day diet plan optimized for my activity level:
            - Goal: \(goal.rawValue)
            - Daily calories: \(calories) kcal
            - Dietary restrictions: \(restrictionsText)
            - Food preferences: \(preferencesText)\(activityText)

            Include Breakfast, Lunch, Snack, and Dinner for each day.
            Adjust protein and carbs based on my workout patterns.
            """

        case let .mealSubstitution(currentMeal, reason, constraints):
            let reasonText = reason ?? "user preference"
            return """
            The user wants to substitute: "\(currentMeal)"
            Reason: \(reasonText)
            Constraints: \(constraints)

            Suggest 3 alternatives with similar nutritional value.
            """

        case let .nutritionAnalysis(mealDescription):
            return """
            Analyze this meal and estimate its nutritional content:
            "\(mealDescription)"
            """
        }
    }

    func formatForLlama() -> String {
        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        \(systemPrompt)
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        \(userPrompt)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        """
    }
}

// MARK: - Response Validation
struct AIResponseValidator {
    static func cleanJSON(_ response: String) -> String {
        response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validateDietPlanResponse(_ json: String) throws -> AIResponse {
        let cleanJSON = cleanJSON(json)
        guard let data = cleanJSON.data(using: .utf8) else {
            throw ValidationError.invalidData
        }
        return try JSONDecoder().decode(AIResponse.self, from: data)
    }
}

enum ValidationError: LocalizedError {
    case invalidData
    case invalidStructure
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Could not process AI response data"
        case .invalidStructure:
            return "AI response has invalid structure"
        case .missingField(let field):
            return "Missing required field: \(field)"
        }
    }
}
