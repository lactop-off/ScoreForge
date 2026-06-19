import Foundation

/// Static checks run on a schema before it is saved or played, mirroring the
/// validation pass in the AI pipeline (docs/design.md §9.5). Errors block use;
/// warnings degrade gracefully (e.g. unknown layout nodes → placeholder).
public struct ValidationIssue: Equatable, CustomStringConvertible {
    public enum Severity: String { case error, warning }
    public let severity: Severity
    public let message: String
    public var description: String { "[\(severity.rawValue)] \(message)" }

    static func error(_ m: String) -> ValidationIssue { .init(severity: .error, message: m) }
    static func warning(_ m: String) -> ValidationIssue { .init(severity: .warning, message: m) }
}

public struct ValidationReport: Equatable {
    public let issues: [ValidationIssue]
    public var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    public var isValid: Bool { errors.isEmpty }
}

public enum SchemaValidator {
    public static func validate(_ schema: Schema) -> ValidationReport {
        var issues: [ValidationIssue] = []

        let fieldIds = Set(schema.fields.map(\.id))
        let formulaIds = Set(schema.formulas.map(\.id))
        let valueIds = fieldIds.union(formulaIds)

        // Duplicate ids.
        issues += duplicates(schema.fields.map(\.id)).map { .error("duplicate field id '\($0)'") }
        issues += duplicates(schema.formulas.map(\.id)).map { .error("duplicate formula id '\($0)'") }
        issues += duplicates(schema.actions.map(\.id)).map { .error("duplicate action id '\($0)'") }
        if let dup = fieldIds.intersection(formulaIds).first {
            issues.append(.error("id '\(dup)' is used by both a field and a formula"))
        }

        // Players sanity.
        let p = schema.players
        if p.min < 1 { issues.append(.error("players.min must be >= 1")) }
        if p.max < p.min { issues.append(.error("players.max must be >= players.min")) }
        if p.default < p.min || p.default > p.max {
            issues.append(.warning("players.default is outside [min, max]"))
        }

        // Formula expressions: parseability, references, unknown functions.
        for formula in schema.formulas {
            switch parse(formula.expression) {
            case .failure(let err):
                issues.append(.error("formula '\(formula.id)' has \(err)"))
            case .success(let expr):
                issues += unknownFunctions(expr).map {
                    .error("formula '\(formula.id)' calls unknown function '\($0)'")
                }
                for ref in expr.referencedIds where !valueIds.contains(ref) {
                    issues.append(.error("formula '\(formula.id)' references unknown id '\(ref)'"))
                }
            }
        }

        // Action effects: target must exist; guard/expression must parse.
        for action in schema.actions {
            for effect in action.effects {
                if !fieldIds.contains(effect.target) {
                    issues.append(.error("action '\(action.id)' targets unknown field '\(effect.target)'"))
                }
                if let when = effect.when, case .failure(let err) = parse(when) {
                    issues.append(.error("action '\(action.id)' guard has \(err)"))
                }
                if effect.op == .applyExpression, case .string(let src)? = effect.value,
                   case .failure(let err) = parse(src) {
                    issues.append(.error("action '\(action.id)' expression has \(err)"))
                }
            }
        }

        // Circular formula dependencies.
        if case .failure(let err) = Result(catching: {
            try DependencyGraph.topologicalOrder(formulas: schema.formulas)
        }) {
            issues.append(.error("\(err)"))
        }

        // Win condition references a real, evaluable score formula.
        if !valueIds.contains(schema.winCondition.scoreFormula) {
            issues.append(.error("win condition references unknown score '\(schema.winCondition.scoreFormula)'"))
        }
        if schema.winCondition.type == .firstToReach, schema.winCondition.target == nil {
            issues.append(.warning("firstToReach win condition has no target value"))
        }

        // Layout: unknown node types and dangling bindings degrade to warnings.
        validateLayout(schema.layout, valueIds: valueIds, fieldIds: fieldIds,
                       actionIds: Set(schema.actions.map(\.id)), into: &issues)

        return ValidationReport(issues: issues)
    }

    // MARK: - Helpers

    private static func validateLayout(
        _ node: LayoutNode, valueIds: Set<String>, fieldIds: Set<String>,
        actionIds: Set<String>, into issues: inout [ValidationIssue]
    ) {
        if node.kind == nil {
            issues.append(.warning("layout uses unknown node type '\(node.type)' (will show a placeholder)"))
        }
        if let bind = node.bind, !valueIds.contains(bind) {
            issues.append(.warning("layout binds to unknown value '\(bind)'"))
        }
        if let field = node.field, !fieldIds.contains(field) {
            issues.append(.warning("layout references unknown field '\(field)'"))
        }
        for action in node.actions ?? [] where !actionIds.contains(action) {
            issues.append(.warning("layout references unknown action '\(action)'"))
        }
        for child in node.children ?? [] {
            validateLayout(child, valueIds: valueIds, fieldIds: fieldIds, actionIds: actionIds, into: &issues)
        }
    }

    private static func parse(_ source: String) -> Result<Expr, ExpressionError> {
        do { return .success(try Parser.parse(source)) }
        catch let e as ExpressionError { return .failure(e) }
        catch { return .failure(.syntax("\(error)")) }
    }

    private static func unknownFunctions(_ expr: Expr) -> [String] {
        var names: [String] = []
        func walk(_ e: Expr) {
            switch e {
            case .call(let name, let args):
                if !BuiltinFunctions.known.contains(name) { names.append(name) }
                args.forEach(walk)
            case .unary(_, let o): walk(o)
            case .binary(_, let l, let r): walk(l); walk(r)
            case .ternary(let c, let a, let b): walk(c); walk(a); walk(b)
            case .number, .string, .bool: break
            }
        }
        walk(expr)
        return names
    }

    private static func duplicates(_ ids: [String]) -> [String] {
        var seen = Set<String>(), dups = Set<String>()
        for id in ids where !seen.insert(id).inserted { dups.insert(id) }
        return dups.sorted()
    }
}
