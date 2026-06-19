import Foundation

/// Computes a valid evaluation order for formulas from their inter-dependencies
/// and rejects cycles (docs/design.md §7.4, §8.4). Formulas are ordered as ids,
/// not per-cell instances: evaluating a formula fills every cell in its scope,
/// so a dependent formula always sees complete inputs.
enum DependencyGraph {
    enum GraphError: Error, Equatable, CustomStringConvertible {
        case cycle([String])
        public var description: String {
            switch self {
            case .cycle(let ids): return "circular formula dependency: \(ids.joined(separator: " → "))"
            }
        }
    }

    /// Returns formula ids in an order where every formula appears after the
    /// formulas it depends on. Field references and references to ids outside
    /// `formulaIds` (e.g. raw fields) are ignored for ordering.
    static func topologicalOrder(formulas: [Formula]) throws -> [String] {
        let formulaIds = Set(formulas.map(\.id))
        var dependencies: [String: Set<String>] = [:]
        for formula in formulas {
            let refs = (try? Parser.parse(formula.expression).referencedIds) ?? []
            dependencies[formula.id] = refs.intersection(formulaIds).subtracting([formula.id])
        }

        var ordered: [String] = []
        var state: [String: Mark] = [:]

        func visit(_ id: String, stack: [String]) throws {
            switch state[id] {
            case .done: return
            case .visiting:
                throw GraphError.cycle(stack + [id])
            case nil:
                state[id] = .visiting
                for dep in (dependencies[id] ?? []).sorted() {
                    try visit(dep, stack: stack + [id])
                }
                state[id] = .done
                ordered.append(id)
            }
        }

        for formula in formulas {
            try visit(formula.id, stack: [])
        }
        return ordered
    }

    private enum Mark { case visiting, done }
}
