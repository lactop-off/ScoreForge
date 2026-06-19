#if canImport(SwiftUI)
import Foundation
import Observation
import ScoreForgeKit

/// SwiftUI-facing wrapper around the (synchronous, deterministic) `GameRuntime`.
/// The runtime itself is not observable, so every mutation bumps `revision`; the
/// renderer reads `revision` once at its root to re-render the whole tree.
/// See docs/renderer-spec.md §1.
@Observable
public final class GameViewModel {
    @ObservationIgnored public let runtime: GameRuntime
    public var schema: Schema { runtime.schema }

    /// The cell that scoped input controls currently edit (docs/renderer-spec.md §1).
    public var activePlayer: Int = 0
    public var activeRound: Int = 0

    /// Bumped after every mutation to drive SwiftUI updates.
    public private(set) var revision: Int = 0

    public init(runtime: GameRuntime) {
        self.runtime = runtime
    }

    public convenience init(schema: Schema, players: [String]) throws {
        self.init(runtime: try GameRuntime(schema: schema, playerNames: players))
    }

    // MARK: - Reads

    public var players: [String] { runtime.state.players }
    public var roundIndices: [Int] { runtime.state.roundIndices }
    public var result: GameResult { runtime.evaluateResult() }
    public var canUndo: Bool { runtime.canUndo }

    public func value(_ id: String, player: Int? = nil, round: Int? = nil) -> Value {
        runtime.value(of: id, player: player, round: round)
    }

    public func isField(_ id: String) -> Bool { schema.fields.contains { $0.id == id } }
    public func field(_ id: String) -> Field? { schema.fields.first { $0.id == id } }
    public func action(_ id: String) -> Action? { schema.actions.first { $0.id == id } }

    /// Resolves the active cell for a field from its scope.
    public func target(for fieldId: String) -> (player: Int?, round: Int?) {
        guard let scope = field(fieldId)?.scope else { return (nil, nil) }
        return (scope.hasPlayer ? activePlayer : nil, scope.hasRound ? activeRound : nil)
    }

    public func cellValue(_ fieldId: String) -> Value {
        let t = target(for: fieldId)
        return runtime.value(of: fieldId, player: t.player, round: t.round)
    }

    /// Whether an action reads a user-supplied input value (`input()`), so the UI
    /// can prompt for it before applying.
    public func actionNeedsInput(_ id: String) -> Bool {
        action(id)?.effects.contains { effect in
            if case .string(let src)? = effect.value { return src.contains("input(") }
            return false
        } ?? false
    }

    // MARK: - Mutations

    public func setField(_ id: String, _ value: Value) {
        let t = target(for: id)
        runtime.setField(id, player: t.player, round: t.round, value: value)
        changed()
    }

    public func setField(_ id: String, player: Int?, round: Int?, value: Value) {
        runtime.setField(id, player: player, round: round, value: value)
        changed()
    }

    public func step(_ id: String, by delta: Double) {
        let current = cellValue(id).asDouble ?? 0
        setField(id, .number(current + delta))
    }

    public func tap(action id: String, input: Value? = nil) {
        runtime.applyAction(id, player: activePlayer, round: activeRound, input: input)
        changed()
    }

    public func addRound() {
        runtime.addRound()
        activeRound = max(0, runtime.state.roundCount - 1)
        changed()
    }

    public func undo() {
        _ = runtime.undo()
        changed()
    }

    public func rename(player index: Int, to name: String) {
        runtime.renamePlayer(index, to: name)
        changed()
    }

    private func changed() { revision &+= 1 }
}
#endif
