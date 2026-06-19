import Foundation

/// Addresses a single cell of a scoped value. Absent dimensions are nil, so a
/// `global` value lives at (nil, nil), a `perPlayer` value at (player, nil), etc.
public struct CellKey: Hashable {
    public var player: Int?
    public var round: Int?
    public init(player: Int? = nil, round: Int? = nil) {
        self.player = player
        self.round = round
    }
}

/// The mutable value store for a single game in progress. Holds raw field
/// values (set by actions/input) and the most recently computed formula values.
public struct GameState: Equatable {
    public private(set) var players: [String]
    /// Number of active rounds. `freeform` games use a single implicit round.
    public internal(set) var roundCount: Int

    var fields: [String: [CellKey: Value]] = [:]
    var formulas: [String: [CellKey: Value]] = [:]

    public init(players: [String], roundCount: Int) {
        self.players = players
        self.roundCount = roundCount
    }

    public var playerIndices: [Int] { Array(players.indices) }
    public var roundIndices: [Int] { Array(0..<max(roundCount, 1)) }

    func field(_ id: String, at key: CellKey) -> Value? { fields[id]?[key] }
    func formula(_ id: String, at key: CellKey) -> Value? { formulas[id]?[key] }

    mutating func setField(_ id: String, at key: CellKey, _ value: Value) {
        fields[id, default: [:]][key] = value
    }
    mutating func setFormula(_ id: String, at key: CellKey, _ value: Value) {
        formulas[id, default: [:]][key] = value
    }

    mutating func renamePlayer(_ index: Int, to name: String) {
        guard players.indices.contains(index) else { return }
        players[index] = name
    }
}
