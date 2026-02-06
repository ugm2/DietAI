import Foundation

/// Result from vision-based food analysis
struct FoodEstimate: Codable, Identifiable {
    var id = UUID()

    let foodName: String
    let portionDescription: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let confidence: Double
    let components: [String]

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case portionDescription = "portion_description"
        case calories, protein, carbs, fat, confidence, components
    }

    // MARK: - Transient Properties (not encoded)

    /// The original image data (not persisted)
    var originalImageData: Data?

    /// When this estimate was created
    var analyzedAt: Date = Date()

    // MARK: - Confidence Level

    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.8...: return .high
        case 0.5..<0.8: return .moderate
        default: return .low
        }
    }

    enum ConfidenceLevel {
        case high, moderate, low

        var description: String {
            switch self {
            case .high: return "High confidence"
            case .moderate: return "Moderate confidence"
            case .low: return "Low confidence - please verify"
            }
        }

        var color: String {
            switch self {
            case .high: return "green"
            case .moderate: return "orange"
            case .low: return "red"
            }
        }
    }

    // MARK: - Conversion to MealLog

    /// Convert to MealLog for saving to database
    func toMealLog(mealType: MealType) -> MealLog {
        MealLog(
            name: foodName,
            type: mealType,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat
        )
    }

    // MARK: - Editable Copy

    /// Create a mutable copy with adjusted values
    func withAdjustments(
        foodName: String? = nil,
        portionDescription: String? = nil,
        calories: Int? = nil,
        protein: Int? = nil,
        carbs: Int? = nil,
        fat: Int? = nil
    ) -> FoodEstimate {
        FoodEstimate(
            foodName: foodName ?? self.foodName,
            portionDescription: portionDescription ?? self.portionDescription,
            calories: calories ?? self.calories,
            protein: protein ?? self.protein,
            carbs: carbs ?? self.carbs,
            fat: fat ?? self.fat,
            confidence: self.confidence,
            components: self.components
        )
    }
}

// MARK: - Preview/Testing Support
extension FoodEstimate {
    static let preview = FoodEstimate(
        foodName: "Grilled Chicken Salad",
        portionDescription: "1 large plate (~350g)",
        calories: 450,
        protein: 35,
        carbs: 20,
        fat: 25,
        confidence: 0.85,
        components: ["grilled chicken breast", "mixed greens", "cherry tomatoes", "cucumber", "olive oil dressing"]
    )

    static let lowConfidencePreview = FoodEstimate(
        foodName: "Mixed Dish",
        portionDescription: "1 serving",
        calories: 500,
        protein: 20,
        carbs: 40,
        fat: 25,
        confidence: 0.4,
        components: ["unknown ingredients"]
    )
}
