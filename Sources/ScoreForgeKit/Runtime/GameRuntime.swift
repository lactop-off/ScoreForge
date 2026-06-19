import Foundation

/// Drives a live game: applies actions, recomputes derived formulas in
/// dependency order, evaluates the win condition, and keeps an undo stack.
/// Implements `EvaluationContext` so the expression engine can read its state.
/// See docs/design.md §10.1.
public final class GameRuntime: EvaluationContext {
    public let schema: Schema
    public private(set) var state: GameState

    private let fieldsById: [String: Field]
    private let formulasById: [String: Formula]
    private let actionsById: [String: Action]
    private let scopeById: [String: Scope]
    private let fieldDefaults: [String: Value]
    private let parsedFormulas: [String: Expr]
    private let topoOrder: [String]

    private var undoStack: [GameState] = []
    private let maxUndo = 50

    // Evaluation cursor (mutated while computing formulas / applying effects).
    private var cursorPlayer: Int?
    private var cursorRound: Int?
    private var cursorInput: Value?

    /// Surfaces formulas whose evaluation raised an error (e.g. unknown function
    /// in a hand-edited expression). The offending cell shows "—".
    public private(set) var evaluationWarnings: [String] = []

    public init(schema: Schema, playerNames: [String]) throws {
        self.schema = schema

        fieldsById = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.id, $0) })
        formulasById = Dictionary(uniqueKeysWithValues: schema.formulas.map { ($0.id, $0) })
        actionsById = Dictionary(uniqueKeysWithValues: schema.actions.map { ($0.id, $0) })

        var scopes: [String: Scope] = [:]
        var defaults: [String: Value] = [:]
        for field in schema.fields {
            scopes[field.id] = field.scope
            defaults[field.id] = field.default?.value ?? Self.zeroValue(for: field.type)
        }
        for formula in schema.formulas { scopes[formula.id] = formula.scope }
        scopeById = scopes
        fieldDefaults = defaults

        parsedFormulas = schema.formulas.reduce(into: [:]) { acc, formula in
            acc[formula.id] = try? Parser.parse(formula.expression)
        }
        topoOrder = (try? DependencyGraph.topologicalOrder(formulas: schema.formulas))
            ?? schema.formulas.map(\.id)

        let initialRounds: Int
        switch schema.structure {
        case .freeform:
            initialRounds = 1
        case .rounds:
            initialRounds = (schema.rounds?.fixed == true ? schema.rounds?.maxRounds : nil) ?? 1
        }
        state = GameState(players: playerNames, roundCount: max(initialRounds, 1))

        recompute()
    }

    private static func zeroValue(for type: Field.FieldType) -> Value {
        switch type {
        case .integer, .number: return .number(0)
        case .bool: return .bool(false)
        case .text, .select: return .string("")
        }
    }

    // MARK: - EvaluationContext

    public var currentPlayer: Int? { cursorPlayer }
    public var currentRound: Int? { cursorRound }
    public var inputValue: Value? { cursorInput }
    public var playerIndices: [Int] { state.playerIndices }
    public var roundIndices: [Int] { state.roundIndices }

    public func resolve(id: String, player: Int?, round: Int?) -> Value {
        guard let scope = scopeById[id] else { return .missing }
        let key = normalizedKey(scope: scope, player: player, round: round)
        if formulasById[id] != nil {
            return state.formula(id, at: key) ?? .missing
        }
        return state.field(id, at: key) ?? fieldDefaults[id] ?? .missing
    }

    private func normalizedKey(scope: Scope, player: Int?, round: Int?) -> CellKey {
        CellKey(player: scope.hasPlayer ? player : nil,
                round: scope.hasRound ? round : nil)
    }

    // MARK: - Reads

    /// The current value of a field or formula for the given player/round.
    public func value(of id: String, player: Int? = nil, round: Int? = nil) -> Value {
        resolve(id: id, player: player, round: round)
    }

    // MARK: - Mutations

    /// Directly sets a field value (e.g. from a numeric input box), clamped to
    /// the field's declared range, then recomputes.
    public func setField(_ id: String, player: Int? = nil, round: Int? = nil, value: Value) {
        guard let field = fieldsById[id] else { return }
        snapshot()
        let key = normalizedKey(scope: field.scope, player: player, round: round)
        state.setField(id, at: key, clamped(value, to: field))
        recompute()
    }

    /// Applies a declared action's effects for the given player/round.
    /// `input` is exposed to effect expressions via `input()`.
    public func applyAction(_ actionId: String, player: Int? = nil, round: Int? = nil, input: Value? = nil) {
        guard let action = actionsById[actionId] else { return }
        snapshot()
        cursorPlayer = player
        cursorRound = round
        cursorInput = input
        defer { cursorInput = nil }

        for effect in action.effects {
            if let guardExpr = effect.when, !evaluate(guardExpr).asBool { continue }
            apply(effect, player: player, round: round)
        }
        recompute()
    }

    private func apply(_ effect: Action.Effect, player: Int?, round: Int?) {
        guard let field = fieldsById[effect.target] else { return }
        let key = normalizedKey(scope: field.scope, player: player, round: round)
        let current = state.field(effect.target, at: key) ?? fieldDefaults[effect.target] ?? .number(0)

        let result: Value
        switch effect.op {
        case .set:
            result = effect.value?.value ?? current
        case .add:
            result = .number((current.asDouble ?? 0) + (effect.value?.value.asDouble ?? 0))
        case .subtract:
            result = .number((current.asDouble ?? 0) - (effect.value?.value.asDouble ?? 0))
        case .toggle:
            result = .bool(!current.asBool)
        case .applyExpression:
            if case .string(let expr) = effect.value {
                result = evaluate(expr)
            } else {
                result = current
            }
        }
        state.setField(effect.target, at: key, clamped(result, to: field))
    }

    private func clamped(_ value: Value, to field: Field) -> Value {
        guard case .number(let d) = value else { return value }
        var x = d
        if let lo = field.min { x = Swift.max(x, lo) }
        if let hi = field.max { x = Swift.min(x, hi) }
        if field.type == .integer { x = x.rounded() }
        return .number(x)
    }

    /// Adds a round (for `rounds` games whose round count isn't fixed).
    @discardableResult
    public func addRound() -> Int {
        if let max = schema.rounds?.maxRounds, state.roundCount >= max { return state.roundCount }
        snapshot()
        state.roundCount += 1
        recompute()
        return state.roundCount
    }

    public func renamePlayer(_ index: Int, to name: String) {
        snapshot()
        state.renamePlayer(index, to: name)
    }

    // MARK: - Recompute

    /// Re-evaluates every formula in dependency order, filling each scope cell.
    public func recompute() {
        evaluationWarnings.removeAll()
        let evaluator = Evaluator(context: self)

        for fid in topoOrder {
            guard let formula = formulasById[fid], let expr = parsedFormulas[fid] else { continue }
            for key in cells(for: formula.scope) {
                cursorPlayer = key.player
                cursorRound = key.round
                cursorInput = nil
                do {
                    let value = try evaluator.evaluate(expr)
                    state.setFormula(fid, at: key, value)
                } catch {
                    state.setFormula(fid, at: key, .missing)
                    evaluationWarnings.append("\(fid): \(error)")
                }
            }
        }
        cursorPlayer = nil
        cursorRound = nil
    }

    private func cells(for scope: Scope) -> [CellKey] {
        switch scope {
        case .global:
            return [CellKey()]
        case .perPlayer:
            return state.playerIndices.map { CellKey(player: $0) }
        case .perRound:
            return state.roundIndices.map { CellKey(round: $0) }
        case .perPlayerPerRound:
            return state.playerIndices.flatMap { p in
                state.roundIndices.map { CellKey(player: p, round: $0) }
            }
        }
    }

    private func evaluate(_ source: String) -> Value {
        (try? Evaluator(context: self).evaluate(source: source)) ?? .missing
    }

    // MARK: - Undo

    public var canUndo: Bool { !undoStack.isEmpty }

    private func snapshot() {
        undoStack.append(state)
        if undoStack.count > maxUndo { undoStack.removeFirst() }
    }

    @discardableResult
    public func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        return true
    }
}
