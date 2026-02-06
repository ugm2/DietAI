import Foundation

// MARK: - OpenFoodFacts API Response

/// Root response from OpenFoodFacts API
struct OpenFoodFactsResponse: Codable {
    let code: String
    let status: Int
    let statusVerbose: String?
    let product: OpenFoodFactsProduct?

    enum CodingKeys: String, CodingKey {
        case code
        case status
        case statusVerbose = "status_verbose"
        case product
    }

    var isFound: Bool {
        status == 1 && product != nil
    }
}

/// Product details from OpenFoodFacts
struct OpenFoodFactsProduct: Codable {
    let productName: String?
    let brands: String?
    let imageURL: String?
    let servingSize: String?
    let quantity: String?           // Total package quantity (e.g., "600g", "1L")
    let productQuantity: String?    // Numeric quantity in grams
    let nutriments: OpenFoodFactsNutriments?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case imageURL = "image_url"
        case servingSize = "serving_size"
        case quantity
        case productQuantity = "product_quantity"
        case nutriments
    }
}

/// Nutritional information from OpenFoodFacts
struct OpenFoodFactsNutriments: Codable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?

    // Per serving values (if available)
    let energyKcalServing: Double?
    let proteinsServing: Double?
    let carbohydratesServing: Double?
    let fatServing: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteinsServing = "proteins_serving"
        case carbohydratesServing = "carbohydrates_serving"
        case fatServing = "fat_serving"
    }
}

// MARK: - App Model

/// Processed product data for use in the app
struct ScannedProduct: Identifiable, Equatable {
    let id = UUID()
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: URL?

    // Nutrition per 100g
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double

    // Optional per-serving info
    let servingSize: String?
    let servingSizeGrams: Double?

    // Total product weight (for slider max)
    let totalWeightGrams: Double?

    /// Display name combining product name and brand
    var displayName: String {
        if let brand = brand, !brand.isEmpty {
            return "\(name) (\(brand))"
        }
        return name
    }

    /// Calculate nutrition for a given serving size in grams
    func nutritionFor(grams: Double) -> (calories: Int, protein: Int, carbs: Int, fat: Int) {
        let multiplier = grams / 100.0
        return (
            calories: Int((caloriesPer100g * multiplier).rounded()),
            protein: Int((proteinPer100g * multiplier).rounded()),
            carbs: Int((carbsPer100g * multiplier).rounded()),
            fat: Int((fatPer100g * multiplier).rounded())
        )
    }

    /// Create from OpenFoodFacts API response
    static func from(response: OpenFoodFactsResponse) -> ScannedProduct? {
        guard let product = response.product,
              let name = product.productName, !name.isEmpty else {
            return nil
        }

        let nutriments = product.nutriments

        // Parse serving size to grams if possible
        let servingSizeGrams = parseServingSizeGrams(product.servingSize)

        // Parse total product weight
        let totalWeight = parseTotalWeight(
            quantity: product.quantity,
            productQuantity: product.productQuantity
        )

        return ScannedProduct(
            barcode: response.code,
            name: name,
            brand: product.brands,
            imageURL: product.imageURL.flatMap { URL(string: $0) },
            caloriesPer100g: nutriments?.energyKcal100g ?? 0,
            proteinPer100g: nutriments?.proteins100g ?? 0,
            carbsPer100g: nutriments?.carbohydrates100g ?? 0,
            fatPer100g: nutriments?.fat100g ?? 0,
            servingSize: product.servingSize,
            servingSizeGrams: servingSizeGrams,
            totalWeightGrams: totalWeight
        )
    }

    /// Parse serving size string to grams (e.g., "250ml" -> 250, "30g" -> 30)
    private static func parseServingSizeGrams(_ servingSize: String?) -> Double? {
        guard let serving = servingSize?.lowercased() else { return nil }

        // Try to extract number followed by g or ml
        let pattern = #"(\d+(?:\.\d+)?)\s*(g|ml|gram|grams|milliliter|milliliters)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: serving, range: NSRange(serving.startIndex..., in: serving)),
              let numberRange = Range(match.range(at: 1), in: serving) else {
            return nil
        }

        return Double(serving[numberRange])
    }

    /// Parse total product weight from quantity fields
    private static func parseTotalWeight(quantity: String?, productQuantity: String?) -> Double? {
        // First try productQuantity which is usually numeric in grams
        if let pq = productQuantity, let weight = Double(pq) {
            return weight
        }

        // Fall back to parsing the quantity string (e.g., "600g", "1.5L")
        guard let qty = quantity?.lowercased() else { return nil }

        // Handle liters (convert to ml/g assuming density ~1)
        let literPattern = #"(\d+(?:\.\d+)?)\s*(l|liter|liters|litre|litres)"#
        if let regex = try? NSRegularExpression(pattern: literPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: qty, range: NSRange(qty.startIndex..., in: qty)),
           let numberRange = Range(match.range(at: 1), in: qty),
           let liters = Double(qty[numberRange]) {
            return liters * 1000 // Convert to ml/g
        }

        // Handle grams/ml
        let gramPattern = #"(\d+(?:\.\d+)?)\s*(g|ml|gram|grams|milliliter|milliliters|kg)"#
        if let regex = try? NSRegularExpression(pattern: gramPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: qty, range: NSRange(qty.startIndex..., in: qty)),
           let numberRange = Range(match.range(at: 1), in: qty),
           let unitRange = Range(match.range(at: 2), in: qty),
           let value = Double(qty[numberRange]) {
            let unit = String(qty[unitRange]).lowercased()
            if unit == "kg" {
                return value * 1000
            }
            return value
        }

        return nil
    }
}

// MARK: - Error Types

enum FoodDatabaseError: LocalizedError {
    case productNotFound
    case networkError(Error)
    case invalidResponse
    case noNutritionData

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Product not found in database"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .noNutritionData:
            return "No nutrition data available for this product"
        }
    }
}
