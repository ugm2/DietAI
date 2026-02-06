import Foundation

// These structs match the AI's JSON output exactly.
// We use them only for decoding, then we throw them away.

struct AIResponse: Codable {
    let days: [AIDay]

    init(days: [AIDay]) {
        self.days = days
    }
}

struct AIDay: Codable {
    let day: String // e.g., "Monday"
    let meals: [AIMeal]

    init(day: String, meals: [AIMeal]) {
        self.day = day
        self.meals = meals
    }
}

/// Structured ingredient from AI response
struct AIIngredient: Codable {
    let name: String
    let quantity: String

    init(name: String, quantity: String = "") {
        self.name = name
        self.quantity = quantity
    }

    /// Convert to MealIngredient for storage
    func toMealIngredient() -> MealIngredient {
        MealIngredient(name: name, quantity: quantity)
    }
}

struct AIMeal: Codable {
    let type: String // e.g., "Breakfast"
    let name: String
    let calories: Int
    let protein: Int?
    let carbs: Int?
    let fat: Int?
    let ingredients: [AIIngredient]?
    let prepTime: Int? // minutes

    // Regular initializer for programmatic construction
    init(type: String, name: String, calories: Int, protein: Int?, carbs: Int?, fat: Int?, ingredients: [AIIngredient]?, prepTime: Int? = nil) {
        self.type = type
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredients = ingredients
        self.prepTime = prepTime
    }

    /// Convenience initializer with string ingredients (legacy support)
    init(type: String, name: String, calories: Int, protein: Int?, carbs: Int?, fat: Int?, ingredientStrings: [String]?, prepTime: Int? = nil) {
        self.type = type
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.ingredients = ingredientStrings?.map { AIIngredient(name: $0) }
        self.prepTime = prepTime
    }

    // Custom decoding to handle LLM outputting numbers as strings or floats
    // Also handles both structured and string-based ingredients
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)

        // Handle calories as Int, String, or Double
        calories = try Self.decodeFlexibleInt(from: container, forKey: .calories) ?? 0

        // Handle optional macros flexibly
        protein = try Self.decodeFlexibleInt(from: container, forKey: .protein)
        carbs = try Self.decodeFlexibleInt(from: container, forKey: .carbs)
        fat = try Self.decodeFlexibleInt(from: container, forKey: .fat)
        prepTime = try Self.decodeFlexibleInt(from: container, forKey: .prepTime)

        // Handle ingredients - try structured format first, then fall back to strings
        if let structuredIngredients = try? container.decodeIfPresent([AIIngredient].self, forKey: .ingredients) {
            ingredients = structuredIngredients
        } else if let stringIngredients = try? container.decodeIfPresent([String].self, forKey: .ingredients) {
            // Convert legacy string format to structured format
            ingredients = stringIngredients.map { str in
                let parsed = MealIngredient.fromLegacyString(str)
                return AIIngredient(name: parsed.name, quantity: parsed.quantity)
            }
        } else {
            ingredients = nil
        }
    }

    private static func decodeFlexibleInt(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Int? {
        // Try Int first
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return intValue
        }
        // Try Double (common LLM output)
        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        // Try String
        if let stringValue = try? container.decode(String.self, forKey: key),
           let intValue = Int(stringValue) {
            return intValue
        }
        // Key might not exist
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type, name, calories, protein, carbs, fat, ingredients, prepTime
    }

    /// Convert ingredients to MealIngredient array
    func getMealIngredients() -> [MealIngredient] {
        ingredients?.map { $0.toMealIngredient() } ?? []
    }
}
