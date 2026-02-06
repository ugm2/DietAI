import Foundation

// MARK: - Ingredient Aggregator
/// Smart ingredient aggregation service that groups similar ingredients
/// Uses deterministic normalization first, then AI for ambiguous cases
@MainActor
final class IngredientAggregator {

    static let shared = IngredientAggregator()

    // MARK: - Normalization

    /// Common prefixes to strip from ingredient names
    private let stripPrefixes = [
        "grilled", "boneless", "skinless", "fresh", "frozen", "cooked", "raw",
        "diced", "sliced", "chopped", "minced", "shredded", "cubed", "whole",
        "organic", "lean", "extra lean", "low-fat", "fat-free", "reduced-fat",
        "unsalted", "salted", "roasted", "toasted", "steamed", "baked", "fried",
        "sauteed", "boiled", "poached", "smoked", "canned", "dried", "ground"
    ]

    /// Common suffixes to strip
    private let stripSuffixes = [
        "pieces", "piece", "chunks", "chunk", "strips", "strip",
        "halves", "half", "slices", "slice"
    ]

    /// Normalize an ingredient name to its base form
    func normalizeIngredientName(_ name: String) -> String {
        var normalized = name.lowercased().trimmingCharacters(in: .whitespaces)

        // Remove prefixes
        for prefix in stripPrefixes {
            if normalized.hasPrefix(prefix + " ") {
                normalized = String(normalized.dropFirst(prefix.count + 1))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Remove suffixes
        for suffix in stripSuffixes {
            if normalized.hasSuffix(" " + suffix) {
                normalized = String(normalized.dropLast(suffix.count + 1))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Handle pluralization (simple cases)
        if normalized.hasSuffix("ies") && normalized.count > 4 {
            // berries -> berry
            normalized = String(normalized.dropLast(3)) + "y"
        } else if normalized.hasSuffix("es") && !normalized.hasSuffix("ches") && !normalized.hasSuffix("shes") {
            // tomatoes -> tomato
            normalized = String(normalized.dropLast(2))
        } else if normalized.hasSuffix("s") && !normalized.hasSuffix("ss") {
            // eggs -> egg (but not "grass")
            normalized = String(normalized.dropLast(1))
        }

        return normalized
    }

    // MARK: - Grouping

    /// Group ingredients by normalized name (deterministic pass)
    func groupIngredients(_ ingredients: [MealIngredient]) -> [String: [MealIngredient]] {
        var groups: [String: [MealIngredient]] = [:]

        for ingredient in ingredients {
            let key = normalizeIngredientName(ingredient.name)
            groups[key, default: []].append(ingredient)
        }

        return groups
    }

    // MARK: - Ambiguity Detection

    /// Find potentially duplicate groups that might need AI resolution
    func findAmbiguousGroups(_ groups: [String: [MealIngredient]]) -> [[String]] {
        let keys = Array(groups.keys).sorted()
        var ambiguous: [[String]] = []
        var processed: Set<String> = []

        for i in 0..<keys.count {
            if processed.contains(keys[i]) { continue }

            var similar: [String] = [keys[i]]

            for j in (i+1)..<keys.count {
                if processed.contains(keys[j]) { continue }

                if arePotentiallySame(keys[i], keys[j]) {
                    similar.append(keys[j])
                    processed.insert(keys[j])
                }
            }

            if similar.count > 1 {
                ambiguous.append(similar)
                processed.insert(keys[i])
            }
        }

        return ambiguous
    }

    /// Check if two normalized names might be the same ingredient
    private func arePotentiallySame(_ name1: String, _ name2: String) -> Bool {
        // One contains the other
        if name1.contains(name2) || name2.contains(name1) {
            return true
        }

        // Levenshtein distance for similar names
        let distance = levenshteinDistance(name1, name2)
        let maxLen = max(name1.count, name2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLen))

        // If more than 70% similar, flag as potentially the same
        return similarity > 0.7
    }

    /// Simple Levenshtein distance calculation
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - AI Resolution

    /// Resolve ambiguous ingredient groups using AI (single batch call)
    func resolveAmbiguousWithAI(
        ambiguousGroups: [[String]],
        allGroups: [String: [MealIngredient]]
    ) async -> [String: String] {
        // Returns a mapping of original normalized name -> canonical name
        guard !ambiguousGroups.isEmpty else { return [:] }

        // Build the prompt for AI
        let prompt = buildAIPrompt(ambiguousGroups: ambiguousGroups)

        do {
            let response = try await generateAIResponse(prompt: prompt)
            return parseAIResponse(response, ambiguousGroups: ambiguousGroups)
        } catch {
            print("AI resolution failed: \(error)")
            // Return identity mapping on failure
            return [:]
        }
    }

    private func buildAIPrompt(ambiguousGroups: [[String]]) -> String {
        var groupsJSON: [[String: Any]] = []

        for (index, group) in ambiguousGroups.enumerated() {
            groupsJSON.append([
                "id": index,
                "items": group
            ])
        }

        let groupsStr = ambiguousGroups.enumerated().map { idx, group in
            "Group \(idx): \(group.joined(separator: ", "))"
        }.joined(separator: "\n")

        return """
        <|begin_of_text|><|start_header_id|>system<|end_header_id|>
        You are a grocery expert. For each group of ingredient names, determine which items are the SAME ingredient (should be combined on a shopping list) and which are DIFFERENT.

        Rules:
        - "chicken breast" and "boneless chicken breast" = SAME (both are chicken breast)
        - "tomato" and "cherry tomato" = DIFFERENT (different varieties)
        - "quinoa" and "cooked quinoa" = SAME (same ingredient, different state)
        - "bell pepper" and "red bell pepper" = SAME (red is just a color variant)
        - "feta" and "feta cheese" = SAME

        Respond with ONLY valid JSON. For each group, provide the canonical name and which items map to it:
        {"groups":[{"canonical":"chicken breast","items":["chicken breast","grilled chicken breast","boneless chicken breast"]},{"canonical":"cherry tomato","items":["cherry tomato"]}]}
        <|eot_id|><|start_header_id|>user<|end_header_id|>
        Analyze these ingredient groups and determine which are the same:
        \(groupsStr)
        <|eot_id|><|start_header_id|>assistant<|end_header_id|>
        {
        """
    }

    private func generateAIResponse(prompt: String) async throws -> String {
        let modelManager = ModelManager.shared

        guard modelManager.isModelLoaded else {
            throw IngredientAggregatorError.modelNotLoaded
        }

        return try await modelManager.generate(prompt: prompt, maxTokens: 500)
    }

    private func parseAIResponse(_ response: String, ambiguousGroups: [[String]]) -> [String: String] {
        var mapping: [String: String] = [:]

        // Clean and parse JSON
        var cleaned = response
        if !cleaned.hasPrefix("{") {
            if let start = cleaned.firstIndex(of: "{") {
                cleaned = String(cleaned[start...])
            }
        }
        if !cleaned.hasSuffix("}") {
            if let end = cleaned.lastIndex(of: "}") {
                cleaned = String(cleaned[...end])
            } else {
                cleaned += "}"
            }
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONDecoder().decode(AIGroupingResponse.self, from: data) else {
            return mapping
        }

        // Build mapping from items to canonical names
        for group in json.groups {
            for item in group.items {
                mapping[item] = group.canonical
            }
        }

        return mapping
    }

    // MARK: - Quantity Aggregation

    /// Aggregate quantities for grouped ingredients
    func aggregateQuantities(_ ingredients: [MealIngredient]) -> AggregatedQuantity {
        var parsedQuantities: [ParsedQuantity] = []

        for ingredient in ingredients {
            let quantity = ingredient.quantity.trimmingCharacters(in: .whitespaces)
            if quantity.isEmpty {
                // Empty quantity - count as 1 item
                parsedQuantities.append(ParsedQuantity(amount: 1, unit: "", original: "", isDescriptive: false))
            } else if let parsed = parseQuantity(quantity) {
                parsedQuantities.append(parsed)
            }
        }

        // Try to combine quantities with same units
        return combineQuantities(parsedQuantities, rawQuantities: ingredients.map { $0.quantity })
    }

    /// Common descriptive quantities that should not be parsed as numeric
    private let descriptiveQuantities = [
        "a pinch", "pinch", "to taste", "as needed", "optional",
        "a dash", "dash", "a splash", "splash", "a handful", "handful",
        "some", "few", "several", "a bit", "a little"
    ]

    /// Words that indicate a descriptive/preparation modifier, not a unit
    private let preparationModifiers = [
        "sliced", "diced", "chopped", "minced", "crushed", "grated",
        "shredded", "julienned", "cubed", "halved", "quartered",
        "thinly", "roughly", "finely", "coarsely"
    ]

    private func parseQuantity(_ quantityStr: String) -> ParsedQuantity? {
        let trimmed = quantityStr.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        let lower = trimmed.lowercased()

        // Check if it's a purely descriptive quantity
        for desc in descriptiveQuantities {
            if lower == desc || lower.hasPrefix(desc + " ") || lower.hasSuffix(" " + desc) {
                return ParsedQuantity(amount: 0, unit: "", original: trimmed, isDescriptive: true)
            }
        }

        // Check if it's just a preparation modifier (no actual quantity)
        let words = lower.components(separatedBy: .whitespaces)
        let isOnlyModifier = words.allSatisfy { word in
            preparationModifiers.contains(word) || word.isEmpty
        }
        if isOnlyModifier && !words.isEmpty {
            return ParsedQuantity(amount: 0, unit: "", original: trimmed, isDescriptive: true)
        }

        // Pattern: number (with optional fraction) + optional unit + optional modifiers
        // Match patterns like: "1 cup", "200g", "1/2 cup", "1 1/2 cups", "2 medium"
        let pattern = #"^(\d+(?:\s*/\s*\d+|\.\d+)?(?:\s+\d+/\d+)?)\s*([a-zA-Z]+(?:\s+[a-zA-Z]+)*)?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range(at: 1).location != NSNotFound else {
            // No number found - treat as descriptive
            return ParsedQuantity(amount: 0, unit: "", original: trimmed, isDescriptive: true)
        }

        let numberRange = Range(match.range(at: 1), in: trimmed)
        let unitRange = match.range(at: 2).location != NSNotFound ? Range(match.range(at: 2), in: trimmed) : nil

        var amount: Double = 1
        var unit = ""

        if let numRange = numberRange {
            let numStr = String(trimmed[numRange])
            amount = parseFraction(numStr)
        }

        if let uRange = unitRange {
            // Extract just the first word as the unit, rest might be modifiers
            let unitText = String(trimmed[uRange]).lowercased()
            let unitWords = unitText.components(separatedBy: .whitespaces)

            // First word is the unit (or size descriptor like "medium", "large")
            unit = unitWords.first ?? ""

            // If remaining words are all modifiers, ignore them
            // If there are non-modifier words, keep them
            if unitWords.count > 1 {
                let restWords = Array(unitWords.dropFirst())
                let nonModifiers = restWords.filter { !preparationModifiers.contains($0) }
                if !nonModifiers.isEmpty {
                    // Has additional non-modifier content, keep it attached
                    unit = unitText
                }
            }
        }

        return ParsedQuantity(amount: amount, unit: unit, original: trimmed, isDescriptive: false)
    }

    private func parseFraction(_ str: String) -> Double {
        // Handle mixed fractions like "1 1/2"
        let parts = str.components(separatedBy: " ")
        if parts.count == 2, let whole = Double(parts[0]) {
            if let fraction = parseSingleFraction(parts[1]) {
                return whole + fraction
            }
        }

        return parseSingleFraction(str) ?? 1
    }

    private func parseSingleFraction(_ str: String) -> Double? {
        if str.contains("/") {
            let parts = str.components(separatedBy: "/")
            if parts.count == 2,
               let num = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let denom = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               denom != 0 {
                return num / denom
            }
        }
        return Double(str)
    }

    private func combineQuantities(_ parsed: [ParsedQuantity], rawQuantities: [String]) -> AggregatedQuantity {
        // Separate numeric quantities from descriptive ones
        var numericByUnit: [String: Double] = [:]
        var descriptiveQuantities: Set<String> = []

        for pq in parsed {
            if pq.isDescriptive {
                // Keep descriptive quantities as-is, deduplicate
                let normalized = pq.original.lowercased()
                descriptiveQuantities.insert(normalized)
            } else {
                // Aggregate numeric quantities by unit
                let normalizedUnit = normalizeUnit(pq.unit)
                numericByUnit[normalizedUnit, default: 0] += pq.amount
            }
        }

        // Try to convert compatible units for numeric quantities
        let converted = convertCompatibleUnits(numericByUnit)

        // Format the final quantity string
        var parts: [String] = []

        // Add numeric quantities
        for (unit, amount) in converted.sorted(by: { $0.key < $1.key }) {
            let formatted = formatAmount(amount)
            if unit.isEmpty {
                // Just a count, like "3" (for "3 eggs")
                if amount > 0 {
                    parts.append(formatted)
                }
            } else {
                parts.append("\(formatted) \(unit)")
            }
        }

        // Add descriptive quantities (sorted, with original capitalization preserved)
        let sortedDescriptive = descriptiveQuantities.sorted()
        for desc in sortedDescriptive {
            // Capitalize first letter for display
            parts.append(desc.prefix(1).uppercased() + desc.dropFirst())
        }

        let displayString = parts.isEmpty ? "\(rawQuantities.count)" : parts.joined(separator: ", ")

        return AggregatedQuantity(
            displayString: displayString,
            totalCount: rawQuantities.count
        )
    }

    private func normalizeUnit(_ unit: String) -> String {
        let lower = unit.lowercased()

        // Normalize common unit variations
        let unitMap: [String: String] = [
            "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
            "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
            "cup": "cup", "cups": "cup",
            "oz": "oz", "ounce": "oz", "ounces": "oz",
            "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
            "g": "g", "gram": "g", "grams": "g",
            "kg": "kg", "kilogram": "kg", "kilograms": "kg",
            "ml": "ml", "milliliter": "ml", "milliliters": "ml",
            "l": "l", "liter": "l", "liters": "l",
            "clove": "clove", "cloves": "clove",
            "slice": "slice", "slices": "slice",
            "piece": "piece", "pieces": "piece",
            "medium": "medium", "large": "large", "small": "small"
        ]

        return unitMap[lower] ?? lower
    }

    private func convertCompatibleUnits(_ quantities: [String: Double]) -> [String: Double] {
        var result = quantities

        // Convert g to kg if total > 1000g
        if let grams = result["g"], grams >= 1000 {
            result.removeValue(forKey: "g")
            result["kg", default: 0] += grams / 1000
        }

        // Convert ml to l if total > 1000ml
        if let ml = result["ml"], ml >= 1000 {
            result.removeValue(forKey: "ml")
            result["l", default: 0] += ml / 1000
        }

        // Convert oz to lb if total > 16oz
        if let oz = result["oz"], oz >= 16 {
            result.removeValue(forKey: "oz")
            result["lb", default: 0] += oz / 16
        }

        return result
    }

    private func formatAmount(_ amount: Double) -> String {
        if amount == amount.rounded() {
            return String(Int(amount))
        }

        // Try common fractions
        let fractions: [(Double, String)] = [
            (0.25, "1/4"), (0.5, "1/2"), (0.75, "3/4"),
            (0.33, "1/3"), (0.67, "2/3"),
            (0.125, "1/8"), (0.375, "3/8"), (0.625, "5/8"), (0.875, "7/8")
        ]

        let wholePart = Int(amount)
        let fractionalPart = amount - Double(wholePart)

        for (value, string) in fractions {
            if abs(fractionalPart - value) < 0.05 {
                if wholePart > 0 {
                    return "\(wholePart) \(string)"
                }
                return string
            }
        }

        return String(format: "%.1f", amount)
    }

    // MARK: - Full Aggregation Pipeline

    /// Main entry point: aggregate ingredients with smart grouping
    func aggregate(
        ingredients: [MealIngredient],
        useAI: Bool = true
    ) async -> [AggregatedIngredientResult] {
        // Step 1: Group by normalized name
        var groups = groupIngredients(ingredients)

        // Step 2: Find ambiguous groups that might need AI resolution
        if useAI {
            let ambiguous = findAmbiguousGroups(groups)

            if !ambiguous.isEmpty {
                // Step 3: Resolve with AI
                let mapping = await resolveAmbiguousWithAI(
                    ambiguousGroups: ambiguous,
                    allGroups: groups
                )

                // Step 4: Merge groups based on AI resolution
                groups = mergeGroups(groups, with: mapping)
            }
        }

        // Step 5: Aggregate quantities for each group
        return groups.map { key, items in
            let displayName = items.first?.name.capitalized ?? key.capitalized
            let quantity = aggregateQuantities(items)

            return AggregatedIngredientResult(
                canonicalName: displayName,
                normalizedKey: key,
                ingredients: items,
                aggregatedQuantity: quantity
            )
        }
        .sorted { $0.canonicalName < $1.canonicalName }
    }

    private func mergeGroups(
        _ groups: [String: [MealIngredient]],
        with mapping: [String: String]
    ) -> [String: [MealIngredient]] {
        var merged: [String: [MealIngredient]] = [:]

        for (key, items) in groups {
            let canonicalKey = mapping[key] ?? key
            merged[canonicalKey, default: []].append(contentsOf: items)
        }

        return merged
    }
}

// MARK: - Supporting Types

struct ParsedQuantity {
    let amount: Double
    let unit: String
    let original: String
    let isDescriptive: Bool  // True for non-numeric quantities like "a pinch", "to taste"

    init(amount: Double, unit: String, original: String, isDescriptive: Bool = false) {
        self.amount = amount
        self.unit = unit
        self.original = original
        self.isDescriptive = isDescriptive
    }
}

struct AggregatedQuantity {
    let displayString: String
    let totalCount: Int
}

struct AggregatedIngredientResult {
    let canonicalName: String
    let normalizedKey: String
    let ingredients: [MealIngredient]
    let aggregatedQuantity: AggregatedQuantity
}

struct AIGroupingResponse: Codable {
    let groups: [AIGroup]
}

struct AIGroup: Codable {
    let canonical: String
    let items: [String]
}

enum IngredientAggregatorError: Error {
    case modelNotLoaded
    case parsingFailed
}
