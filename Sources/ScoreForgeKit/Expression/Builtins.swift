import Foundation

/// Provides the data an expression can read. The runtime supplies the
/// concrete implementation; tests can supply a lightweight stub.
public protocol EvaluationContext {
    /// The player the expression is being evaluated for (nil for global scope).
    var currentPlayer: Int? { get }
    /// The round the expression is being evaluated for (nil when not round-scoped).
    var currentRound: Int? { get }
    /// The most recent user input, available to actions via `input()`.
    var inputValue: Value? { get }

    var playerIndices: [Int] { get }
    var roundIndices: [Int] { get }

    /// Resolves a field or formula value, honouring the id's declared scope.
    /// `player`/`round` are hints; dimensions the id doesn't use are ignored.
    func resolve(id: String, player: Int?, round: Int?) -> Value
}

/// The whitelist of callable functions (docs/design.md §8.3). Anything outside
/// this set is rejected at evaluation time — there is no arbitrary dispatch.
enum BuiltinFunctions {
    /// Functions whose string-literal arguments name a field/formula id. Used by
    /// the static dependency analyzer (`Expr.referencedIds`).
    static let referencesValues: Set<String> = [
        "field", "round", "sumRounds", "avgRounds",
        "sum", "max", "min", "count", "rankDesc", "rankAsc",
    ]

    static let known: Set<String> = referencesValues.union([
        "input", "abs", "floor", "ceil", "clamp", "if",
    ])
}
