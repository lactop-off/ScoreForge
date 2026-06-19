import Foundation

/// A tree-walking evaluator for the sandboxed expression DSL. It has no loops,
/// recursion, I/O, randomness, or clock access — only the whitelisted builtins —
/// and is bounded by node-count and call-depth limits so it cannot run away
/// (docs/design.md §8.3). Evaluation is deterministic.
public struct Evaluator {
    public struct Limits {
        public var maxNodes: Int
        public var maxDepth: Int
        public init(maxNodes: Int = 10_000, maxDepth: Int = 64) {
            self.maxNodes = maxNodes
            self.maxDepth = maxDepth
        }
    }

    let context: EvaluationContext
    let limits: Limits

    public init(context: EvaluationContext, limits: Limits = Limits()) {
        self.context = context
        self.limits = limits
    }

    /// Parses and evaluates `source`. Use this for one-off evaluation; the
    /// runtime pre-parses formulas and calls `evaluate(_ expr:)` instead.
    public func evaluate(source: String) throws -> Value {
        let expr = try Parser.parse(source)
        return try evaluate(expr)
    }

    public func evaluate(_ expr: Expr) throws -> Value {
        var budget = limits.maxNodes
        return try eval(expr, depth: 0, budget: &budget)
    }

    private func eval(_ expr: Expr, depth: Int, budget: inout Int) throws -> Value {
        budget -= 1
        guard budget >= 0 else { throw ExpressionError.limitExceeded("node count") }
        guard depth <= limits.maxDepth else { throw ExpressionError.limitExceeded("call depth") }

        switch expr {
        case .number(let n): return .number(n)
        case .string(let s): return .string(s)
        case .bool(let b): return .bool(b)

        case .unary(let op, let operand):
            let v = try eval(operand, depth: depth + 1, budget: &budget)
            return try applyUnary(op, v)

        case .binary(let op, let lhs, let rhs):
            return try applyBinary(op, lhs, rhs, depth: depth, budget: &budget)

        case .ternary(let cond, let a, let b):
            let c = try eval(cond, depth: depth + 1, budget: &budget)
            return c.asBool
                ? try eval(a, depth: depth + 1, budget: &budget)
                : try eval(b, depth: depth + 1, budget: &budget)

        case .call(let name, let args):
            return try callFunction(name, args, depth: depth, budget: &budget)
        }
    }

    // MARK: - Operators

    private func applyUnary(_ op: String, _ v: Value) throws -> Value {
        switch op {
        case "!": return .bool(!v.asBool)
        case "-":
            guard let d = v.asDouble else { return .missing }
            return .number(-d)
        default: throw ExpressionError.syntax("unknown unary operator \(op)")
        }
    }

    private func applyBinary(
        _ op: String, _ lhs: Expr, _ rhs: Expr, depth: Int, budget: inout Int
    ) throws -> Value {
        // Short-circuit logical operators.
        if op == "&&" {
            let l = try eval(lhs, depth: depth + 1, budget: &budget)
            if !l.asBool { return .bool(false) }
            return .bool(try eval(rhs, depth: depth + 1, budget: &budget).asBool)
        }
        if op == "||" {
            let l = try eval(lhs, depth: depth + 1, budget: &budget)
            if l.asBool { return .bool(true) }
            return .bool(try eval(rhs, depth: depth + 1, budget: &budget).asBool)
        }

        let l = try eval(lhs, depth: depth + 1, budget: &budget)
        let r = try eval(rhs, depth: depth + 1, budget: &budget)

        switch op {
        case "==": return .bool(valuesEqual(l, r))
        case "!=": return .bool(!valuesEqual(l, r))
        case "<", "<=", ">", ">=":
            guard let a = l.asDouble, let b = r.asDouble else { return .missing }
            switch op {
            case "<": return .bool(a < b)
            case "<=": return .bool(a <= b)
            case ">": return .bool(a > b)
            default: return .bool(a >= b)
            }
        case "+", "-", "*", "/", "%":
            // Propagate missing rather than crashing (§8.4).
            guard let a = l.asDouble, let b = r.asDouble else { return .missing }
            switch op {
            case "+": return .number(a + b)
            case "-": return .number(a - b)
            case "*": return .number(a * b)
            case "/": return b == 0 ? .missing : .number(a / b)
            default: return b == 0 ? .missing : .number(a.truncatingRemainder(dividingBy: b))
            }
        default:
            throw ExpressionError.syntax("unknown operator \(op)")
        }
    }

    private func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        if let x = a.asDouble, let y = b.asDouble { return x == y }
        return a == b
    }

    // MARK: - Function dispatch

    private func callFunction(
        _ name: String, _ argExprs: [Expr], depth: Int, budget: inout Int
    ) throws -> Value {
        guard BuiltinFunctions.known.contains(name) else {
            throw ExpressionError.unknownFunction(name)
        }

        // `input` takes no arguments and reads from the context directly.
        if name == "input" {
            try requireArity(name, argExprs.count, 0)
            return context.inputValue ?? .missing
        }

        let args = try argExprs.map { try eval($0, depth: depth + 1, budget: &budget) }

        switch name {
        case "field":
            let id = try stringArg(name, args, 0)
            return context.resolve(id: id, player: context.currentPlayer, round: context.currentRound)

        case "round":
            // Dual use: round(n,'id') reference, or round(x) math rounding.
            if args.count == 2 {
                guard let n = args[0].asDouble else { return .missing }
                let id = try stringArg(name, args, 1)
                return context.resolve(id: id, player: context.currentPlayer, round: Int(n))
            }
            try requireArity(name, args.count, 1)
            return mathUnary(args[0]) { $0.rounded() }

        case "sumRounds":
            return aggregateRounds(try stringArg(name, args, 0)) { $0.reduce(0, +) }
        case "avgRounds":
            return aggregateRounds(try stringArg(name, args, 0)) {
                $0.isEmpty ? 0 : $0.reduce(0, +) / Double($0.count)
            }

        case "sum":
            return aggregatePlayers(try stringArg(name, args, 0)) { $0.reduce(0, +) }
        case "count":
            let id = try stringArg(name, args, 0)
            let vals = playerValues(of: id)
            return .number(Double(vals.count))

        case "max":
            return try minMax(name, args, isMax: true)
        case "min":
            return try minMax(name, args, isMax: false)

        case "rankDesc":
            return rank(try stringArg(name, args, 0), ascending: false)
        case "rankAsc":
            return rank(try stringArg(name, args, 0), ascending: true)

        case "abs":
            try requireArity(name, args.count, 1)
            return mathUnary(args[0]) { Swift.abs($0) }
        case "floor":
            try requireArity(name, args.count, 1)
            return mathUnary(args[0]) { $0.rounded(.down) }
        case "ceil":
            try requireArity(name, args.count, 1)
            return mathUnary(args[0]) { $0.rounded(.up) }
        case "clamp":
            try requireArity(name, args.count, 3)
            guard let x = args[0].asDouble, let lo = args[1].asDouble, let hi = args[2].asDouble
            else { return .missing }
            return .number(Swift.min(Swift.max(x, lo), hi))
        case "if":
            try requireArity(name, args.count, 3)
            return args[0].asBool ? args[1] : args[2]

        default:
            throw ExpressionError.unknownFunction(name)
        }
    }

    /// `min`/`max` are overloaded: a single field-id string aggregates across
    /// players; numeric arguments are a plain mathematical min/max.
    private func minMax(_ name: String, _ args: [Value], isMax: Bool) throws -> Value {
        if args.count == 1, case .string(let id) = args[0] {
            let vals = playerValues(of: id)
            guard let result = isMax ? vals.max() : vals.min() else { return .missing }
            return .number(result)
        }
        let nums = args.compactMap { $0.asDouble }
        guard nums.count == args.count, let result = isMax ? nums.max() : nums.min() else {
            return .missing
        }
        return .number(result)
    }

    private func mathUnary(_ v: Value, _ f: (Double) -> Double) -> Value {
        guard let d = v.asDouble else { return .missing }
        return .number(f(d))
    }

    // MARK: - Aggregation helpers

    private func aggregateRounds(_ id: String, _ reduce: ([Double]) -> Double) -> Value {
        let nums = context.roundIndices.compactMap {
            context.resolve(id: id, player: context.currentPlayer, round: $0).asDouble
        }
        return .number(reduce(nums))
    }

    private func aggregatePlayers(_ id: String, _ reduce: ([Double]) -> Double) -> Value {
        .number(reduce(playerValues(of: id)))
    }

    private func playerValues(of id: String) -> [Double] {
        context.playerIndices.compactMap {
            context.resolve(id: id, player: $0, round: context.currentRound).asDouble
        }
    }

    private func rank(_ id: String, ascending: Bool) -> Value {
        guard let me = context.resolve(id: id, player: context.currentPlayer, round: context.currentRound).asDouble
        else { return .missing }
        let others = playerValues(of: id)
        // Standard competition ranking: 1 + (number of players strictly better).
        let better = others.filter { ascending ? $0 < me : $0 > me }.count
        return .number(Double(better + 1))
    }

    // MARK: - Argument validation

    private func requireArity(_ name: String, _ got: Int, _ want: Int) throws {
        guard got == want else {
            throw ExpressionError.arity("\(name) expects \(want), got \(got)")
        }
    }

    private func stringArg(_ name: String, _ args: [Value], _ index: Int) throws -> String {
        guard index < args.count, case .string(let s) = args[index] else {
            throw ExpressionError.type("\(name) expects a string id at position \(index)")
        }
        return s
    }
}
