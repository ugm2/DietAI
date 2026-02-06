import Foundation

// MARK: - Food Database Service

@MainActor
@Observable
final class FoodDatabaseService {
    static let shared = FoodDatabaseService()

    private let baseURL = "https://world.openfoodfacts.org/api/v2/product"
    private let session: URLSession
    private let decoder: JSONDecoder

    private(set) var isLoading = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Product Lookup

    /// Fetch product information by barcode from OpenFoodFacts
    func fetchProduct(barcode: String) async throws -> ScannedProduct {
        isLoading = true
        defer { isLoading = false }

        // Clean barcode (remove any whitespace)
        let cleanBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/\(cleanBarcode)") else {
            throw FoodDatabaseError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("DietAI/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FoodDatabaseError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FoodDatabaseError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw FoodDatabaseError.productNotFound
            }
            throw FoodDatabaseError.invalidResponse
        }

        let apiResponse: OpenFoodFactsResponse
        do {
            apiResponse = try decoder.decode(OpenFoodFactsResponse.self, from: data)
        } catch {
            throw FoodDatabaseError.invalidResponse
        }

        guard apiResponse.isFound else {
            throw FoodDatabaseError.productNotFound
        }

        guard let product = ScannedProduct.from(response: apiResponse) else {
            throw FoodDatabaseError.noNutritionData
        }

        // Check if we have meaningful nutrition data
        if product.caloriesPer100g == 0 &&
           product.proteinPer100g == 0 &&
           product.carbsPer100g == 0 &&
           product.fatPer100g == 0 {
            throw FoodDatabaseError.noNutritionData
        }

        return product
    }
}
