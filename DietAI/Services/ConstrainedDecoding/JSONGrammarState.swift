import Foundation

/// Represents the current state in JSON parsing
enum JSONGrammarState: Equatable {
    case start                          // Expecting value start
    case inObject                       // Inside {}, expecting key or }
    case expectingKey                   // Expecting a string key
    case inKey                          // Inside a key string
    case afterKey                       // After key, expecting :
    case expectingValue                 // After :, expecting value
    case inString                       // Inside a string value
    case inStringEscape                 // After \ in string
    case inNumber                       // Inside a number
    case inNumberDecimal                // After . in number
    case inNumberExponent               // After e/E in number
    case inTrue(Int)                    // Parsing "true", Int = chars matched
    case inFalse(Int)                   // Parsing "false", Int = chars matched
    case inNull(Int)                    // Parsing "null", Int = chars matched
    case inArray                        // Inside [], expecting value or ]
    case afterValue                     // After a value, expecting , or } or ]
    case complete                       // Valid JSON complete
    case error(String)                  // Parse error
}

/// Stack element for tracking nested structures
enum JSONStackElement: Equatable {
    case object
    case array
}

/// JSON Grammar State Machine - tracks valid parse states
class JSONGrammarStateMachine {
    private(set) var state: JSONGrammarState = .start
    private(set) var stack: [JSONStackElement] = []

    /// Valid character categories for the current state
    var validCharacterCategories: Set<JSONCharCategory> {
        switch state {
        case .start:
            return [.openBrace, .openBracket, .quote, .digit, .minus, .t, .f, .n, .whitespace]

        case .inObject:
            return [.quote, .closeBrace, .whitespace]

        case .expectingKey:
            return [.quote, .whitespace]

        case .inKey:
            return [.quote, .stringChar, .backslash]

        case .afterKey:
            return [.colon, .whitespace]

        case .expectingValue:
            return [.openBrace, .openBracket, .quote, .digit, .minus, .t, .f, .n, .whitespace]

        case .inString:
            return [.quote, .stringChar, .backslash]

        case .inStringEscape:
            return [.escapeChar]

        case .inNumber:
            return [.digit, .dot, .e, .comma, .closeBrace, .closeBracket, .whitespace]

        case .inNumberDecimal:
            return [.digit, .e, .comma, .closeBrace, .closeBracket, .whitespace]

        case .inNumberExponent:
            return [.digit, .plus, .minus, .comma, .closeBrace, .closeBracket, .whitespace]

        case .inTrue(let n):
            switch n {
            case 1: return [.r]
            case 2: return [.u]
            case 3: return [.e]
            default: return [.comma, .closeBrace, .closeBracket, .whitespace]
            }

        case .inFalse(let n):
            switch n {
            case 1: return [.a]
            case 2: return [.l]
            case 3: return [.s]
            case 4: return [.e]
            default: return [.comma, .closeBrace, .closeBracket, .whitespace]
            }

        case .inNull(let n):
            switch n {
            case 1: return [.u]
            case 2: return [.l]
            case 3: return [.l]
            default: return [.comma, .closeBrace, .closeBracket, .whitespace]
            }

        case .inArray:
            return [.openBrace, .openBracket, .quote, .digit, .minus, .t, .f, .n, .closeBracket, .whitespace]

        case .afterValue:
            if let top = stack.last {
                switch top {
                case .object:
                    return [.comma, .closeBrace, .whitespace]
                case .array:
                    return [.comma, .closeBracket, .whitespace]
                }
            }
            return [.whitespace]

        case .complete:
            return [.whitespace]

        case .error:
            return []
        }
    }

    /// Process a character and update state
    @discardableResult
    func process(_ char: Character) -> Bool {
        let category = JSONCharCategory.categorize(char)

        // Skip whitespace in most states
        if category == .whitespace {
            switch state {
            case .inString, .inKey, .inStringEscape:
                break // Whitespace is significant in strings
            default:
                return true // Skip whitespace
            }
        }

        switch state {
        case .start:
            return processStart(char, category)
        case .inObject:
            return processInObject(char, category)
        case .expectingKey:
            return processExpectingKey(char, category)
        case .inKey:
            return processInKey(char, category)
        case .afterKey:
            return processAfterKey(char, category)
        case .expectingValue:
            return processExpectingValue(char, category)
        case .inString:
            return processInString(char, category)
        case .inStringEscape:
            return processInStringEscape(char, category)
        case .inNumber, .inNumberDecimal, .inNumberExponent:
            return processInNumber(char, category)
        case .inTrue(let n):
            return processInTrue(char, n)
        case .inFalse(let n):
            return processInFalse(char, n)
        case .inNull(let n):
            return processInNull(char, n)
        case .inArray:
            return processInArray(char, category)
        case .afterValue:
            return processAfterValue(char, category)
        case .complete:
            return category == .whitespace
        case .error:
            return false
        }
    }

    /// Process a string and return if valid
    func processString(_ str: String) -> Bool {
        for char in str {
            if !process(char) {
                return false
            }
        }
        return true
    }

    /// Reset the state machine
    func reset() {
        state = .start
        stack = []
    }

    /// Check if current state can be a valid end state
    var isValidEndState: Bool {
        state == .complete || (state == .afterValue && stack.isEmpty)
    }

    // MARK: - State Processing

    private func processStart(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .openBrace:
            state = .inObject
            stack.append(.object)
            return true
        case .openBracket:
            state = .inArray
            stack.append(.array)
            return true
        case .quote:
            state = .inString
            return true
        case .digit, .minus:
            state = .inNumber
            return true
        case .t:
            state = .inTrue(1)
            return true
        case .f:
            state = .inFalse(1)
            return true
        case .n:
            state = .inNull(1)
            return true
        default:
            state = .error("Expected value at start")
            return false
        }
    }

    private func processInObject(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .quote:
            state = .inKey
            return true
        case .closeBrace:
            _ = stack.popLast()
            state = stack.isEmpty ? .complete : .afterValue
            return true
        default:
            state = .error("Expected key or } in object")
            return false
        }
    }

    private func processExpectingKey(_ char: Character, _ category: JSONCharCategory) -> Bool {
        if category == .quote {
            state = .inKey
            return true
        }
        state = .error("Expected key")
        return false
    }

    private func processInKey(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .quote:
            state = .afterKey
            return true
        case .backslash:
            state = .inStringEscape
            return true
        case .stringChar:
            return true
        default:
            state = .error("Invalid character in key")
            return false
        }
    }

    private func processAfterKey(_ char: Character, _ category: JSONCharCategory) -> Bool {
        if category == .colon {
            state = .expectingValue
            return true
        }
        state = .error("Expected : after key")
        return false
    }

    private func processExpectingValue(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .openBrace:
            state = .inObject
            stack.append(.object)
            return true
        case .openBracket:
            state = .inArray
            stack.append(.array)
            return true
        case .quote:
            state = .inString
            return true
        case .digit, .minus:
            state = .inNumber
            return true
        case .t:
            state = .inTrue(1)
            return true
        case .f:
            state = .inFalse(1)
            return true
        case .n:
            state = .inNull(1)
            return true
        default:
            state = .error("Expected value")
            return false
        }
    }

    private func processInString(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .quote:
            state = .afterValue
            return true
        case .backslash:
            state = .inStringEscape
            return true
        case .stringChar:
            return true
        default:
            state = .error("Invalid character in string")
            return false
        }
    }

    private func processInStringEscape(_ char: Character, _ category: JSONCharCategory) -> Bool {
        // After backslash, accept escape characters
        if "\"\\bfnrtu/".contains(char) {
            state = .inString
            return true
        }
        state = .error("Invalid escape sequence")
        return false
    }

    private func processInNumber(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .digit:
            return true
        case .dot:
            state = .inNumberDecimal
            return true
        case .e:
            state = .inNumberExponent
            return true
        case .comma:
            return handleComma()
        case .closeBrace:
            return handleCloseBrace()
        case .closeBracket:
            return handleCloseBracket()
        default:
            state = .error("Invalid character in number")
            return false
        }
    }

    private func processInTrue(_ char: Character, _ n: Int) -> Bool {
        let expected: Character = ["t", "r", "u", "e"][n]
        if char == expected {
            if n == 3 {
                state = .afterValue
            } else {
                state = .inTrue(n + 1)
            }
            return true
        }
        state = .error("Invalid 'true' literal")
        return false
    }

    private func processInFalse(_ char: Character, _ n: Int) -> Bool {
        let expected: Character = ["f", "a", "l", "s", "e"][n]
        if char == expected {
            if n == 4 {
                state = .afterValue
            } else {
                state = .inFalse(n + 1)
            }
            return true
        }
        state = .error("Invalid 'false' literal")
        return false
    }

    private func processInNull(_ char: Character, _ n: Int) -> Bool {
        let expected: Character = ["n", "u", "l", "l"][n]
        if char == expected {
            if n == 3 {
                state = .afterValue
            } else {
                state = .inNull(n + 1)
            }
            return true
        }
        state = .error("Invalid 'null' literal")
        return false
    }

    private func processInArray(_ char: Character, _ category: JSONCharCategory) -> Bool {
        switch category {
        case .closeBracket:
            _ = stack.popLast()
            state = stack.isEmpty ? .complete : .afterValue
            return true
        case .openBrace:
            state = .inObject
            stack.append(.object)
            return true
        case .openBracket:
            state = .inArray
            stack.append(.array)
            return true
        case .quote:
            state = .inString
            return true
        case .digit, .minus:
            state = .inNumber
            return true
        case .t:
            state = .inTrue(1)
            return true
        case .f:
            state = .inFalse(1)
            return true
        case .n:
            state = .inNull(1)
            return true
        default:
            state = .error("Expected value or ] in array")
            return false
        }
    }

    private func processAfterValue(_ char: Character, _ category: JSONCharCategory) -> Bool {
        guard let top = stack.last else {
            if category == .whitespace {
                return true
            }
            state = .error("Unexpected character after complete JSON")
            return false
        }

        switch (top, category) {
        case (.object, .comma):
            state = .expectingKey
            return true
        case (.object, .closeBrace):
            return handleCloseBrace()
        case (.array, .comma):
            state = .inArray
            return true
        case (.array, .closeBracket):
            return handleCloseBracket()
        default:
            state = .error("Expected comma or closing bracket")
            return false
        }
    }

    private func handleComma() -> Bool {
        guard let top = stack.last else {
            state = .error("Unexpected comma")
            return false
        }

        switch top {
        case .object:
            state = .expectingKey
        case .array:
            state = .inArray
        }
        return true
    }

    private func handleCloseBrace() -> Bool {
        guard let top = stack.last, top == .object else {
            state = .error("Unexpected }")
            return false
        }
        _ = stack.popLast()
        state = stack.isEmpty ? .complete : .afterValue
        return true
    }

    private func handleCloseBracket() -> Bool {
        guard let top = stack.last, top == .array else {
            state = .error("Unexpected ]")
            return false
        }
        _ = stack.popLast()
        state = stack.isEmpty ? .complete : .afterValue
        return true
    }
}

/// Character categories for JSON parsing
enum JSONCharCategory {
    case openBrace      // {
    case closeBrace     // }
    case openBracket    // [
    case closeBracket   // ]
    case quote          // "
    case colon          // :
    case comma          // ,
    case backslash      // \
    case digit          // 0-9
    case minus          // -
    case plus           // +
    case dot            // .
    case e              // e, E
    case t, r, u, l, s, a, f, n // for true, false, null
    case whitespace     // space, tab, newline
    case stringChar     // valid string character
    case escapeChar     // valid escape character
    case invalid        // invalid character

    static func categorize(_ char: Character) -> JSONCharCategory {
        switch char {
        case "{": return .openBrace
        case "}": return .closeBrace
        case "[": return .openBracket
        case "]": return .closeBracket
        case "\"": return .quote
        case ":": return .colon
        case ",": return .comma
        case "\\": return .backslash
        case "0"..."9": return .digit
        case "-": return .minus
        case "+": return .plus
        case ".": return .dot
        case "e", "E": return .e
        case "t": return .t
        case "r": return .r
        case "u": return .u
        case "l": return .l
        case "s": return .s
        case "a": return .a
        case "f": return .f
        case "n": return .n
        case " ", "\t", "\n", "\r": return .whitespace
        default:
            // Most printable characters are valid in strings
            if char.isASCII || char.isLetter || char.isNumber {
                return .stringChar
            }
            return .stringChar // Allow unicode in strings
        }
    }
}
