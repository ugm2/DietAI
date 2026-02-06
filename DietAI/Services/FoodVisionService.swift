import Foundation
import CoreImage
import MLXLMCommon
import MLXVLM

// MARK: - Food Vision Errors

enum FoodVisionError: LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case analysisTimeout
    case cameraError(String)
    case parsingError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Vision AI model is not loaded"
        case .invalidResponse:
            return "Could not understand the food analysis"
        case .analysisTimeout:
            return "Analysis took too long"
        case .cameraError(let msg):
            return "Camera error: \(msg)"
        case .parsingError(let msg):
            return "Failed to parse response: \(msg)"
        }
    }
}

// MARK: - Food Vision Service

/// High-level service for analyzing food images and estimating nutrition
@MainActor
final class FoodVisionService {
    static let shared = FoodVisionService()

    private let visionManager = VisionModelManager.shared

    private init() {}

    // MARK: - Analysis

    /// Analyze food image and estimate nutrition
    /// - Parameters:
    ///   - image: CIImage of the food
    ///   - userHint: Optional description from user (e.g., "salmon salad")
    /// - Returns: FoodEstimate with calories, macros, and confidence
    func analyzeFood(
        image: CIImage,
        userHint: String? = nil
    ) async throws -> FoodEstimate {
        // Ensure model is loaded
        let loaded = await visionManager.loadModelIfNeeded()
        guard loaded, let container = visionManager.visionContainer else {
            throw FoodVisionError.modelNotLoaded
        }

        let prompt = buildPrompt(hint: userHint)

        // Validate image has valid dimensions
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height
        guard imageWidth > 0 && imageHeight > 0 && !imageWidth.isNaN && !imageHeight.isNaN else {
            throw FoodVisionError.cameraError("Invalid image dimensions")
        }

        // Resize image to reduce memory usage (VLM doesn't need 4K resolution)
        let resizedImage = resizeImageForVLM(image, maxDimension: 1024)

        // IMPORTANT: Render the CIImage to ensure it has actual pixel data
        // CIImage is lazy - it might not contain rendered pixels until forced
        let processedImage = renderCIImage(resizedImage)

        #if DEBUG
        print("📷 Analyzing food image:")
        print("   - Original: \(Int(imageWidth))x\(Int(imageHeight))")
        print("   - Processed: \(Int(processedImage.extent.width))x\(Int(processedImage.extent.height))")
        print("   - VLM: \(visionManager.currentTier.displayName)")
        print("   - Model ID: \(visionManager.modelId)")
        if let hint = userHint {
            print("   - User hint: \(hint)")
        }
        print("📷 Sending to VLM...")
        #endif

        let output = try await container.perform { context in
            // VLM uses UserInput with images parameter
            // Use Chat.Message for proper image embedding
            let chatMessages: [Chat.Message] = [
                .user(prompt, images: [.ciImage(processedImage)])
            ]

            #if DEBUG
            print("📷 Preparing input with \(chatMessages.count) messages...")
            #endif

            let input = try await context.processor.prepare(
                input: UserInput(chat: chatMessages)
            )

            #if DEBUG
            print("📷 Input prepared, starting generation...")
            #endif

            let params = GenerateParameters(
                maxTokens: 500,
                temperature: 0.1
            )

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { tokens -> GenerateDisposition in
                // Stop after reasonable token count
                return tokens.count < 500 ? .more : .stop
            }

            return result.output
        }

        #if DEBUG
        print("📷 ========== VLM RAW OUTPUT ==========")
        print(output)
        print("📷 ========== END VLM OUTPUT ==========")
        print("📷 Output length: \(output.count) characters")
        #endif

        // Release VLM if using sequential strategy
        visionManager.releaseIfNeeded()

        return try parseResponse(output)
    }

    // MARK: - Image Processing

    /// Resize image to reduce memory usage while maintaining quality for VLM
    private func resizeImageForVLM(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let width = image.extent.width
        let height = image.extent.height

        // Already small enough
        if max(width, height) <= maxDimension {
            return image
        }

        // Calculate scale factor
        let scale = maxDimension / max(width, height)
        let transform = CGAffineTransform(scaleX: scale, y: scale)

        return image.transformed(by: transform)
    }

    /// Render CIImage to ensure it contains actual pixel data
    /// CIImage is lazy and may not have rendered pixels until forced
    private func renderCIImage(_ image: CIImage) -> CIImage {
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Render to CGImage and back to CIImage to ensure pixel data exists
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            #if DEBUG
            print("⚠️ Failed to render CIImage, using original")
            #endif
            return image
        }

        #if DEBUG
        print("📷 Rendered CGImage: \(cgImage.width)x\(cgImage.height), bpp: \(cgImage.bitsPerPixel)")
        #endif

        return CIImage(cgImage: cgImage)
    }

    // MARK: - Prompt Engineering

    private func buildPrompt(hint: String?) -> String {
        var prompt = """
        Look at this food photo carefully. What food do you see?

        Identify:
        1. The MAIN protein (meat, fish, chicken, tofu, eggs, etc.)
        2. All vegetables and sides
        3. Any sauces or garnishes

        Output JSON with this exact structure:
        {
            "food_name": "descriptive name",
            "portion_description": "brief size (e.g. 200g, 1 plate, 2 fillets)",
            "calories": 0,
            "protein": 0,
            "carbs": 0,
            "fat": 0,
            "confidence": 0.8,
            "components": ["item1", "item2"]
        }
        """

        if let hint = hint, !hint.isEmpty {
            prompt += "\n\nThe user says this is: \(hint)"
        }

        prompt += "\n\nJSON:"

        return prompt
    }

    // MARK: - Response Parsing

    private func parseResponse(_ json: String) throws -> FoodEstimate {
        // Extract JSON from response
        let cleaned = extractJSON(from: json)

        guard let data = cleaned.data(using: .utf8) else {
            throw FoodVisionError.parsingError("Could not convert response to data")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(FoodEstimate.self, from: data)
        } catch {
            #if DEBUG
            print("📷 JSON Parsing Error: \(error)")
            print("📷 Cleaned JSON: \(cleaned)")
            #endif
            throw FoodVisionError.parsingError(error.localizedDescription)
        }
    }

    /// Extract JSON from model output, handling various formats
    private func extractJSON(from text: String) -> String {
        var cleaned = text

        #if DEBUG
        print("📷 Raw text to extract JSON from: \(text.prefix(500))")
        #endif

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```JSON", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Try to find JSON object by looking for { and }
        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}") {
            let jsonRange = startIndex...endIndex
            cleaned = String(cleaned[jsonRange])
        }

        // Clean up common issues
        cleaned = cleaned
            .trimmingCharacters(in: .whitespacesAndNewlines)
            // Fix trailing commas before ] or }
            .replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
            .replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
            // Fix single quotes to double quotes (some models use single quotes)
            .replacingOccurrences(of: "'", with: "\"")
            // Remove any text before the first {
            .replacingOccurrences(of: "^[^{]*", with: "", options: .regularExpression)

        #if DEBUG
        print("📷 Cleaned JSON: \(cleaned.prefix(500))")
        #endif

        return cleaned
    }

    // MARK: - Model Status

    /// Check if the vision model is ready for use
    var isModelReady: Bool {
        visionManager.isModelLoaded
    }

    /// Get the current model status message
    var statusMessage: String {
        visionManager.status
    }

    /// Get loading progress (0.0 to 1.0)
    var loadingProgress: Double {
        visionManager.loadingProgress
    }

    /// Preload the model in the background
    func preloadModel() async {
        await visionManager.loadModelIfNeeded()
    }
}
