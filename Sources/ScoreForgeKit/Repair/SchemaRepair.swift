import Foundation

/// Mechanically repairs a schema into a guaranteed-valid, playable one by
/// dropping or fixing the parts a validator would reject, and falling back to a
/// default layout / synthesized score when needed. This is the deterministic
/// "always end up in a usable state" guarantee from docs/design.md §9.5 and the
/// acceptance criterion that a failed generation still yields an editable sheet.
///
/// It does not call the model; the AI re-prompt loop (§9.5, max 2 retries) lives
/// in the iOS generation pipeline and uses these same building blocks.
public enum SchemaRepair {
    public struct Note: Equatable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Returns a repaired schema and the list of changes made. The result is
    /// guaranteed to pass `SchemaValidator.validate(_:).isValid`.
    public static func repair(_ input: Schema) -> (schema: Schema, notes: [Note]) {
        var notes: [Note] = []
        func note(_ m: String) { notes.append(Note(message: m)) }

        var s = SchemaNormalizer.normalize(input)

        s.fields = keepFirstUnique(s.fields, id: \.id) { note("dropped duplicate field '\($0)'") }
        let fieldIds = Set(s.fields.map(\.id))

        // A formula may not share an id with a field.
        s.formulas = s.formulas.filter { formula in
            if fieldIds.contains(formula.id) {
                note("dropped formula '\(formula.id)' (id collides with a field)")
                return false
            }
            return true
        }
        s.formulas = keepFirstUnique(s.formulas, id: \.id) { note("dropped duplicate formula '\($0)'") }
        s.actions = keepFirstUnique(s.actions, id: \.id) { note("dropped duplicate action '\($0)'") }

        s.formulas = pruneFormulas(s.formulas, fieldIds: fieldIds, note: note)
        s.actions = repairActions(s.actions, fieldIds: fieldIds, note: note)
        s.winCondition = repairWinCondition(s.winCondition, schema: &s, note: note)

        // Rebuild the layout only if the authored one has any problems, so we
        // preserve intent when it is already sound.
        if layoutHasIssues(s) {
            s.layout = DefaultLayoutBuilder.build(for: s)
            note("rebuilt layout from a safe default template")
        }

        // Safety net: if anything unexpected remains, fall back hard.
        if !SchemaValidator.validate(s).isValid {
            s = minimalFallback(from: s)
            note("applied minimal fallback template to guarantee a usable sheet")
        }

        return (s, notes)
    }

    // MARK: - Formulas

    /// Iteratively removes formulas that can't parse, call unknown functions,
    /// reference missing ids, or participate in a dependency cycle, until the
    /// remaining set is self-consistent and acyclic.
    private static func pruneFormulas(
        _ formulas: [Formula], fieldIds: Set<String>, note: (String) -> Void
    ) -> [Formula] {
        var current = formulas
        var changed = true
        while changed {
            changed = false
            let valueIds = fieldIds.union(current.map(\.id))
            var kept: [Formula] = []
            for formula in current {
                guard let expr = try? Parser.parse(formula.expression) else {
                    note("dropped formula '\(formula.id)' (cannot parse expression)"); changed = true; continue
                }
                let unknown = expr.calledFunctionNames.subtracting(BuiltinFunctions.known)
                if let fn = unknown.sorted().first {
                    note("dropped formula '\(formula.id)' (unknown function '\(fn)')"); changed = true; continue
                }
                if let bad = expr.referencedIds.subtracting(valueIds).sorted().first {
                    note("dropped formula '\(formula.id)' (references missing '\(bad)')"); changed = true; continue
                }
                kept.append(formula)
            }
            current = kept

            // Break one cycle per pass; the loop then re-prunes dangling refs.
            if let victim = cycleMember(in: current) {
                current.removeAll { $0.id == victim }
                note("dropped formula '\(victim)' to break a dependency cycle")
                changed = true
            }
        }
        return current
    }

    private static func cycleMember(in formulas: [Formula]) -> String? {
        do {
            _ = try DependencyGraph.topologicalOrder(formulas: formulas)
            return nil
        } catch let DependencyGraph.GraphError.cycle(path) {
            return path.last
        } catch {
            return nil
        }
    }

    // MARK: - Actions

    private static func repairActions(
        _ actions: [Action], fieldIds: Set<String>, note: (String) -> Void
    ) -> [Action] {
        actions.compactMap { action in
            let effects = action.effects.filter { effect in
                guard fieldIds.contains(effect.target) else {
                    note("dropped effect in action '\(action.id)' (unknown target '\(effect.target)')")
                    return false
                }
                if let when = effect.when, (try? Parser.parse(when)) == nil {
                    note("dropped effect in action '\(action.id)' (invalid guard)")
                    return false
                }
                if effect.op == .applyExpression {
                    guard case .string(let src)? = effect.value, (try? Parser.parse(src)) != nil else {
                        note("dropped effect in action '\(action.id)' (invalid expression)")
                        return false
                    }
                }
                return true
            }
            if effects.isEmpty {
                note("dropped action '\(action.id)' (no valid effects)")
                return nil
            }
            var a = action
            a.effects = effects
            return a
        }
    }

    // MARK: - Win condition

    private static func repairWinCondition(
        _ win: WinCondition, schema s: inout Schema, note: (String) -> Void
    ) -> WinCondition {
        var win = win
        let valueIds = Set(s.fields.map(\.id)).union(s.formulas.map(\.id))
        guard !valueIds.contains(win.scoreFormula) else { return win }

        // Prefer an existing per-player formula as the score.
        if let perPlayer = s.formulas.first(where: { $0.scope == .perPlayer }) ?? s.formulas.first {
            note("win condition score set to existing formula '\(perPlayer.id)'")
            win.scoreFormula = perPlayer.id
            return win
        }

        // Otherwise synthesize a total from a numeric field (or a constant).
        let id = uniqueId("total", taken: valueIds)
        let numeric = s.fields.first { $0.type == .integer || $0.type == .number }
        let expression: String
        let scope: Scope
        if let field = numeric {
            expression = field.scope.hasRound ? "sumRounds('\(field.id)')" : "field('\(field.id)')"
            scope = .perPlayer
        } else {
            expression = "0"
            scope = .perPlayer
        }
        s.formulas.append(Formula(id: id, label: "合計", scope: scope, expression: expression))
        note("synthesized score formula '\(id)' for the win condition")
        win.scoreFormula = id
        return win
    }

    // MARK: - Layout

    private static func layoutHasIssues(_ s: Schema) -> Bool {
        let valueIds = Set(s.fields.map(\.id)).union(s.formulas.map(\.id))
        let fieldIds = Set(s.fields.map(\.id))
        let actionIds = Set(s.actions.map(\.id))
        func walk(_ n: LayoutNode) -> Bool {
            if n.kind == nil { return true }
            if let b = n.bind, !valueIds.contains(b) { return true }
            if let f = n.field, !fieldIds.contains(f) { return true }
            if (n.actions ?? []).contains(where: { !actionIds.contains($0) }) { return true }
            return (n.children ?? []).contains(where: walk)
        }
        return walk(s.layout)
    }

    // MARK: - Fallback

    /// The last-resort sheet: keep the (already de-duplicated) fields, drop all
    /// formulas, synthesize a score, and use a default layout.
    private static func minimalFallback(from s: Schema) -> Schema {
        var fallback = s
        let scoreId = "total"
        let numeric = s.fields.first { $0.type == .integer || $0.type == .number }
        let expression = numeric.map { $0.scope.hasRound ? "sumRounds('\($0.id)')" : "field('\($0.id)')" } ?? "0"
        fallback.formulas = [Formula(id: scoreId, label: "合計", scope: .perPlayer, expression: expression)]
        fallback.actions = s.actions // already validated by repairActions
        fallback.winCondition = WinCondition(type: .highestTotal, scoreFormula: scoreId)
        fallback.layout = DefaultLayoutBuilder.build(for: fallback)
        return fallback
    }

    // MARK: - Helpers

    private static func keepFirstUnique<T>(
        _ items: [T], id: (T) -> String, onDrop: (String) -> Void
    ) -> [T] {
        var seen = Set<String>()
        var out: [T] = []
        for item in items {
            if seen.insert(id(item)).inserted { out.append(item) } else { onDrop(id(item)) }
        }
        return out
    }

    private static func uniqueId(_ base: String, taken: Set<String>) -> String {
        if !taken.contains(base) { return base }
        var i = 2
        while taken.contains("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }
}

public extension Schema {
    /// Returns a repaired copy guaranteed to pass validation. See `SchemaRepair`.
    func repaired() -> Schema { SchemaRepair.repair(self).schema }
}
