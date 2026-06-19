import Foundation

/// The parsed form of an expression. Walked by both the evaluator and the
/// static dependency analyzer (for the formula DAG, §8.4).
public indirect enum Expr: Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case unary(String, Expr)
    case binary(String, Expr, Expr)
    case ternary(Expr, Expr, Expr)
    case call(String, [Expr])

    /// Collects the ids referenced via `field`, `round`, and the aggregate /
    /// rank functions — i.e. the value ids this expression depends on.
    public var referencedIds: Set<String> {
        var ids: Set<String> = []
        collectReferences(into: &ids)
        return ids
    }

    private func collectReferences(into ids: inout Set<String>) {
        switch self {
        case .number, .string, .bool:
            break
        case .unary(_, let e):
            e.collectReferences(into: &ids)
        case .binary(_, let l, let r):
            l.collectReferences(into: &ids)
            r.collectReferences(into: &ids)
        case .ternary(let c, let a, let b):
            c.collectReferences(into: &ids)
            a.collectReferences(into: &ids)
            b.collectReferences(into: &ids)
        case .call(let name, let args):
            if BuiltinFunctions.referencesValues.contains(name) {
                // The id argument is the last string literal in the call
                // (`field('x')`, `round(n,'x')`, `sumRounds('x')` …).
                for arg in args {
                    if case .string(let id) = arg { ids.insert(id) }
                }
            }
            for arg in args { arg.collectReferences(into: &ids) }
        }
    }
}
