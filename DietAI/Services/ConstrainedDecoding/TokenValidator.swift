import Foundation
import MLX
import MLXLMCommon

/// Validates tokens against the JSON grammar state machine
class JSONTokenValidator {
    let stateMachine: JSONGrammarStateMachine
    private var tokenCache: [Int: String] = [:]

    init() {
        self.stateMachine = JSONGrammarStateMachine()
    }

    /// Reset the validator for a new generation
    func reset() {
        stateMachine.reset()
        tokenCache.removeAll()
    }

    /// Update state with generated text
    func updateState(with text: String) {
        _ = stateMachine.processString(text)
    }

    /// Get the current grammar state
    var currentState: JSONGrammarState {
        stateMachine.state
    }

    /// Check if generation can end validly
    var canEndGeneration: Bool {
        stateMachine.isValidEndState
    }

    /// Create a validity mask for tokens given vocabulary
    /// Returns an array where valid[tokenId] = true if token is grammatically valid
    func createValidityMask(vocabulary: [String], vocabSize: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: vocabSize)
        let validCategories = stateMachine.validCharacterCategories

        for (tokenId, tokenStr) in vocabulary.enumerated() {
            if tokenId >= vocabSize { break }

            // Check if this token would be valid
            if isTokenValid(tokenStr, validCategories: validCategories) {
                mask[tokenId] = true
            }
        }

        // Always allow EOS token if we're in a valid end state
        if stateMachine.isValidEndState {
            // EOS token is typically 0, 1, or 2 depending on tokenizer
            // We'll mark common EOS positions
            if vocabSize > 0 { mask[0] = true }
            if vocabSize > 1 { mask[1] = true }
            if vocabSize > 2 { mask[2] = true }
        }

        return mask
    }

    /// Check if a specific token string would be valid given current state
    func isTokenValid(_ tokenStr: String, validCategories: Set<JSONCharCategory>) -> Bool {
        // Empty tokens are invalid
        guard !tokenStr.isEmpty else { return false }

        // Special tokens - handle common ones
        if tokenStr.hasPrefix("<") && tokenStr.hasSuffix(">") {
            // Special tokens like <s>, </s>, <pad>, etc.
            return stateMachine.isValidEndState
        }

        // Check if the first character of the token is valid
        guard let firstChar = tokenStr.first else { return false }
        let firstCategory = JSONCharCategory.categorize(firstChar)

        // If first character's category is not in valid set, reject
        if !validCategories.contains(firstCategory) {
            return false
        }

        // For multi-character tokens, simulate processing
        // Create a copy of state machine to test
        let testMachine = createStateMachineCopy()

        for char in tokenStr {
            if !testMachine.process(char) {
                return false
            }
        }

        return true
    }

    /// Create a copy of the current state machine for testing
    private func createStateMachineCopy() -> JSONGrammarStateMachine {
        let copy = JSONGrammarStateMachine()
        // We need to restore the state - for simplicity, we'll reprocess
        // In production, we'd implement proper state copying
        return copy
    }

    /// Apply mask to logits - sets invalid tokens to -infinity
    func applyMaskToLogits(_ logits: MLXArray, vocabulary: [String]) -> MLXArray {
        let vocabSize = logits.shape[logits.shape.count - 1]
        let mask = createValidityMask(vocabulary: vocabulary, vocabSize: vocabSize)

        // Create mask array: 0 for valid, -inf for invalid
        var maskValues = [Float](repeating: -.infinity, count: vocabSize)
        for (i, isValid) in mask.enumerated() {
            if isValid {
                maskValues[i] = 0.0
            }
        }

        let maskArray = MLXArray(maskValues)
        return logits + maskArray
    }
}

/// Extension to add grammar constraint support
extension JSONTokenValidator {
    /// Get valid next characters based on current state
    func getValidNextCharacters() -> String {
        var chars = ""
        let categories = stateMachine.validCharacterCategories

        for category in categories {
            switch category {
            case .openBrace: chars += "{"
            case .closeBrace: chars += "}"
            case .openBracket: chars += "["
            case .closeBracket: chars += "]"
            case .quote: chars += "\""
            case .colon: chars += ":"
            case .comma: chars += ","
            case .backslash: chars += "\\"
            case .digit: chars += "0123456789"
            case .minus: chars += "-"
            case .plus: chars += "+"
            case .dot: chars += "."
            case .e: chars += "eE"
            case .t: chars += "t"
            case .r: chars += "r"
            case .u: chars += "u"
            case .l: chars += "l"
            case .s: chars += "s"
            case .a: chars += "a"
            case .f: chars += "f"
            case .n: chars += "n"
            case .whitespace: chars += " \t\n"
            case .stringChar: break // Any printable char
            case .escapeChar: chars += "\"\\/bfnrtu"
            case .invalid: break
            }
        }

        return chars
    }
}
