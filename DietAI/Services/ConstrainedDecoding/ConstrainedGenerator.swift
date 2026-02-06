import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Generator that provides enhanced JSON output reliability
/// Since MLX Swift doesn't expose token-level sampling control,
/// this focuses on post-processing and repair strategies
@MainActor
class ConstrainedJSONGenerator {

    /// Generate with automatic retry and repair on JSON parse failure
    static func generateWithRepair(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int = 2000,
        temperature: Float = 0.1,
        maxRetries: Int = 2,  // Reduced from 3 to speed up
        onProgress: ((String) -> Void)? = nil
    ) async throws -> String {
        var lastOutput = ""
        var currentTemp = temperature

        for attempt in 1...maxRetries {
            onProgress?("Generating (attempt \(attempt)/\(maxRetries))...")

            // Capture temperature for this attempt to avoid Swift 6 concurrency warning
            let attemptTemp = currentTemp

            let output = try await generateWithEarlyStop(
                container: container,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: attemptTemp
            )

            lastOutput = output

            // Try to extract and validate JSON
            if let validJSON = extractAndRepairJSON(from: output) {
                #if DEBUG
                print("✅ JSON extraction successful on attempt \(attempt)")
                #endif
                return validJSON
            }

            // If we got a reasonable output but JSON parsing failed, try repair only
            if attempt < maxRetries {
                #if DEBUG
                print("⚠️ JSON extraction failed, attempt \(attempt)/\(maxRetries)")
                #endif
                currentTemp = min(currentTemp + 0.1, 0.5)
            }
        }

        // Try one more aggressive repair on the last output
        if let repairedJSON = aggressiveJSONRepair(from: lastOutput) {
            #if DEBUG
            print("✅ Aggressive repair succeeded")
            #endif
            return repairedJSON
        }

        // Return last output even if invalid - let the caller handle parsing errors
        return lastOutput
    }

    /// Generate with early stopping when JSON appears complete
    private static func generateWithEarlyStop(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) async throws -> String {
        let output = try await container.perform { context in
            let input = try await context.processor.prepare(input: UserInput(prompt: prompt))
            let params = GenerateParameters(maxTokens: maxTokens, temperature: temperature)

            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { (tokens: [Int]) -> GenerateDisposition in
                // Stop after generating enough tokens for a complete diet plan JSON
                // A 7-day meal plan with 4 meals/day needs ~1500-2000 tokens
                // This prevents endless generation while allowing complete plans
                if tokens.count > 1500 {
                    return .stop
                }
                return .more
            }

            return result.output
        }

        return output
    }

    /// Generate with post-processing - simpler approach that relies on repair
    static func generate(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int = 2000,
        temperature: Float = 0.1
    ) async throws -> String {
        let output = try await generateWithEarlyStop(
            container: container,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature
        )

        // Post-process to extract clean JSON
        if let validJSON = extractAndRepairJSON(from: output) {
            return validJSON
        }

        return output
    }

    /// More aggressive JSON repair for edge cases
    private static func aggressiveJSONRepair(from text: String) -> String? {
        var cleaned = text

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```JSON", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Find JSON boundaries
        guard let startIndex = cleaned.firstIndex(of: "{") else {
            return nil
        }

        // Find the last closing brace, or add one if missing
        var endIndex = cleaned.lastIndex(of: "}") ?? cleaned.endIndex

        // If no closing brace, we'll add one
        if cleaned.lastIndex(of: "}") == nil {
            cleaned += "}"
            endIndex = cleaned.index(before: cleaned.endIndex)
        }

        let jsonRange = startIndex...endIndex
        cleaned = String(cleaned[jsonRange])

        // Apply all repairs
        cleaned = repairJSON(cleaned)

        // If days array is incomplete, try to close it
        if cleaned.contains("\"days\"") && !cleaned.contains("]") {
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.hasSuffix("]") {
                // Find last complete meal and close the structure
                if let lastMealEnd = cleaned.range(of: "}", options: .backwards) {
                    let upToLastMeal = String(cleaned[..<lastMealEnd.upperBound])
                    cleaned = upToLastMeal + "]}]}"
                }
            }
        }

        // Balance brackets one more time
        cleaned = balanceBrackets(cleaned)

        // Validate
        if let data = cleaned.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return cleaned
        }

        return nil
    }

    // MARK: - JSON Extraction and Repair

    /// Extract JSON from output and attempt repairs
    static func extractAndRepairJSON(from text: String) -> String? {
        var cleaned = text

        // Remove markdown code blocks
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```JSON", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        // Find JSON boundaries
        guard let startIndex = cleaned.firstIndex(of: "{"),
              let endIndex = cleaned.lastIndex(of: "}") else {
            return nil
        }

        let jsonRange = startIndex...endIndex
        cleaned = String(cleaned[jsonRange])

        // Attempt repairs
        cleaned = repairJSON(cleaned)

        // Validate
        if let data = cleaned.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data) {
            return cleaned
        }

        return nil
    }

    /// Attempt to repair common JSON issues
    private static func repairJSON(_ json: String) -> String {
        var repaired = json

        // Fix trailing commas
        repaired = repaired.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        repaired = repaired.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)

        // Fix missing quotes around keys (simple cases)
        repaired = repaired.replacingOccurrences(
            of: "([{,])\\s*([a-zA-Z_][a-zA-Z0-9_]*)\\s*:",
            with: "$1\"$2\":",
            options: .regularExpression
        )

        // Fix single quotes to double quotes
        repaired = fixQuotes(repaired)

        // Balance braces and brackets
        repaired = balanceBrackets(repaired)

        return repaired
    }

    /// Fix single quotes to double quotes (carefully)
    private static func fixQuotes(_ json: String) -> String {
        var result = ""
        var inString = false
        var prevChar: Character = " "

        for char in json {
            if char == "\"" && prevChar != "\\" {
                inString = !inString
                result.append(char)
            } else if char == "'" && !inString {
                // Replace single quote with double quote outside strings
                result.append("\"")
            } else {
                result.append(char)
            }
            prevChar = char
        }

        return result
    }

    /// Balance brackets by adding missing closing brackets
    private static func balanceBrackets(_ json: String) -> String {
        var braceCount = 0
        var bracketCount = 0
        var inString = false
        var prevChar: Character = " "

        for char in json {
            if char == "\"" && prevChar != "\\" {
                inString = !inString
            }

            if !inString {
                switch char {
                case "{": braceCount += 1
                case "}": braceCount -= 1
                case "[": bracketCount += 1
                case "]": bracketCount -= 1
                default: break
                }
            }
            prevChar = char
        }

        var result = json

        // Add missing closing braces
        while braceCount > 0 {
            result += "}"
            braceCount -= 1
        }

        // Add missing closing brackets
        while bracketCount > 0 {
            result += "]"
            bracketCount -= 1
        }

        return result
    }
}
