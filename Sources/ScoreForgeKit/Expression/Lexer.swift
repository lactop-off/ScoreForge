import Foundation

/// Errors raised while lexing, parsing, or evaluating an expression.
public enum ExpressionError: Error, Equatable, CustomStringConvertible {
    case syntax(String)
    case unknownFunction(String)
    case arity(String)
    case limitExceeded(String)
    case type(String)

    public var description: String {
        switch self {
        case .syntax(let m): return "syntax error: \(m)"
        case .unknownFunction(let m): return "unknown function: \(m)"
        case .arity(let m): return "wrong number of arguments: \(m)"
        case .limitExceeded(let m): return "evaluation limit exceeded: \(m)"
        case .type(let m): return "type error: \(m)"
        }
    }
}

enum Token: Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case ident(String)
    case op(String)
    case lparen, rparen, comma, question, colon
}

/// Turns source text into a flat token stream. String literals use single
/// quotes (matching the schema examples in §7.4).
struct Lexer {
    private let chars: [Character]
    private var pos = 0

    init(_ source: String) { chars = Array(source) }

    mutating func tokenize() throws -> [Token] {
        var tokens: [Token] = []
        while let t = try next() { tokens.append(t) }
        return tokens
    }

    private mutating func next() throws -> Token? {
        skipWhitespace()
        guard pos < chars.count else { return nil }
        let c = chars[pos]

        if c.isNumber || (c == "." && peekIsDigit(1)) {
            return number()
        }
        if c == "'" {
            return try string()
        }
        if c.isLetter || c == "_" {
            return identifier()
        }

        // Multi-character operators first.
        for opStr in ["==", "!=", "<=", ">=", "&&", "||"] {
            if matches(opStr) { advance(opStr.count); return .op(opStr) }
        }
        pos += 1
        switch c {
        case "(": return .lparen
        case ")": return .rparen
        case ",": return .comma
        case "?": return .question
        case ":": return .colon
        case "+", "-", "*", "/", "%", "<", ">", "!":
            return .op(String(c))
        default:
            throw ExpressionError.syntax("unexpected character '\(c)'")
        }
    }

    private mutating func number() -> Token {
        var s = ""
        while pos < chars.count, chars[pos].isNumber || chars[pos] == "." {
            s.append(chars[pos]); pos += 1
        }
        return .number(Double(s) ?? 0)
    }

    private mutating func string() throws -> Token {
        pos += 1 // opening quote
        var s = ""
        while pos < chars.count, chars[pos] != "'" {
            s.append(chars[pos]); pos += 1
        }
        guard pos < chars.count else {
            throw ExpressionError.syntax("unterminated string literal")
        }
        pos += 1 // closing quote
        return .string(s)
    }

    private mutating func identifier() -> Token {
        var s = ""
        while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_" {
            s.append(chars[pos]); pos += 1
        }
        switch s {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: return .ident(s)
        }
    }

    private mutating func skipWhitespace() {
        while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
    }

    private func peekIsDigit(_ offset: Int) -> Bool {
        let i = pos + offset
        return i < chars.count && chars[i].isNumber
    }

    private func matches(_ s: String) -> Bool {
        let a = Array(s)
        guard pos + a.count <= chars.count else { return false }
        for (i, ch) in a.enumerated() where chars[pos + i] != ch { return false }
        return true
    }

    private mutating func advance(_ n: Int) { pos += n }
}
