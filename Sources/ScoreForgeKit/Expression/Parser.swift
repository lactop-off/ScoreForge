import Foundation

/// A recursive-descent parser implementing the grammar in docs/design.md §8.2.
/// Precedence (low→high): ?: , ||, &&, comparison, +/-, * / %, unary, primary.
struct Parser {
    private let tokens: [Token]
    private var pos = 0

    private init(tokens: [Token]) { self.tokens = tokens }

    /// Parses a complete expression string into an AST.
    static func parse(_ source: String) throws -> Expr {
        var lexer = Lexer(source)
        let tokens = try lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpr()
        guard parser.pos == tokens.count else {
            throw ExpressionError.syntax("unexpected trailing tokens")
        }
        return expr
    }

    private mutating func parseExpr() throws -> Expr { try ternary() }

    private mutating func ternary() throws -> Expr {
        let cond = try logicalOr()
        if match(.question) {
            let a = try parseExpr()
            try expect(.colon)
            let b = try parseExpr()
            return .ternary(cond, a, b)
        }
        return cond
    }

    private mutating func logicalOr() throws -> Expr {
        var left = try logicalAnd()
        while matchOp("||") {
            let right = try logicalAnd()
            left = .binary("||", left, right)
        }
        return left
    }

    private mutating func logicalAnd() throws -> Expr {
        var left = try comparison()
        while matchOp("&&") {
            let right = try comparison()
            left = .binary("&&", left, right)
        }
        return left
    }

    private mutating func comparison() throws -> Expr {
        var left = try additive()
        while let op = peekOp(in: ["==", "!=", "<", "<=", ">", ">="]) {
            advance()
            let right = try additive()
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func additive() throws -> Expr {
        var left = try multiplicative()
        while let op = peekOp(in: ["+", "-"]) {
            advance()
            let right = try multiplicative()
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func multiplicative() throws -> Expr {
        var left = try unary()
        while let op = peekOp(in: ["*", "/", "%"]) {
            advance()
            let right = try unary()
            left = .binary(op, left, right)
        }
        return left
    }

    private mutating func unary() throws -> Expr {
        if let op = peekOp(in: ["!", "-"]) {
            advance()
            return .unary(op, try unary())
        }
        return try primary()
    }

    private mutating func primary() throws -> Expr {
        guard pos < tokens.count else {
            throw ExpressionError.syntax("unexpected end of expression")
        }
        let token = tokens[pos]
        switch token {
        case .number(let n):
            advance(); return .number(n)
        case .string(let s):
            advance(); return .string(s)
        case .bool(let b):
            advance(); return .bool(b)
        case .lparen:
            advance()
            let e = try parseExpr()
            try expect(.rparen)
            return e
        case .ident(let name):
            advance()
            try expect(.lparen)
            let args = try parseArgs()
            return .call(name, args)
        default:
            throw ExpressionError.syntax("unexpected token")
        }
    }

    private mutating func parseArgs() throws -> [Expr] {
        var args: [Expr] = []
        if match(.rparen) { return args }
        repeat {
            args.append(try parseExpr())
        } while match(.comma)
        try expect(.rparen)
        return args
    }

    // MARK: - Token helpers

    private mutating func advance() { pos += 1 }

    private mutating func match(_ t: Token) -> Bool {
        guard pos < tokens.count, tokens[pos] == t else { return false }
        pos += 1
        return true
    }

    private mutating func matchOp(_ op: String) -> Bool {
        guard pos < tokens.count, tokens[pos] == .op(op) else { return false }
        pos += 1
        return true
    }

    private func peekOp(in set: [String]) -> String? {
        guard pos < tokens.count, case .op(let o) = tokens[pos], set.contains(o) else { return nil }
        return o
    }

    private mutating func expect(_ t: Token) throws {
        guard match(t) else {
            throw ExpressionError.syntax("expected token \(t)")
        }
    }
}
