import Foundation

/// A serialisable capture of a game's *raw* input values — everything needed to
/// resume an interrupted game (docs/design.md FR-12). Derived formula values are
/// intentionally omitted: they are recomputed on restore, so the snapshot stays
/// small and can never disagree with the formulas. This is the data the iOS
/// SwiftData layer persists (mapped to EntryEntity); see docs/ios-integration.md §3.
public struct GameSnapshot: Codable, Equatable {
    public struct FieldEntry: Codable, Equatable {
        public var fieldId: String
        public var player: Int?
        public var round: Int?
        public var value: Value
        public init(fieldId: String, player: Int?, round: Int?, value: Value) {
            self.fieldId = fieldId
            self.player = player
            self.round = round
            self.value = value
        }
    }

    public var players: [String]
    public var roundCount: Int
    public var entries: [FieldEntry]

    public init(players: [String], roundCount: Int, entries: [FieldEntry]) {
        self.players = players
        self.roundCount = roundCount
        self.entries = entries
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: data)
    }
}

extension GameRuntime {
    /// Captures the current raw field values (skipping missing/unset cells), in a
    /// deterministic order, for autosave.
    public func snapshot() -> GameSnapshot {
        var entries: [GameSnapshot.FieldEntry] = []
        for (fieldId, cells) in state.fields {
            for (key, value) in cells where value != .missing {
                entries.append(.init(fieldId: fieldId, player: key.player, round: key.round, value: value))
            }
        }
        entries.sort { lhs, rhs in
            if lhs.fieldId != rhs.fieldId { return lhs.fieldId < rhs.fieldId }
            if (lhs.player ?? -1) != (rhs.player ?? -1) { return (lhs.player ?? -1) < (rhs.player ?? -1) }
            return (lhs.round ?? -1) < (rhs.round ?? -1)
        }
        return GameSnapshot(players: state.players, roundCount: state.roundCount, entries: entries)
    }

    /// Restores raw values from a snapshot and recomputes. The runtime must have
    /// been created with the same players (use `restored(schema:snapshot:)`).
    public func restore(from snapshot: GameSnapshot) {
        if snapshot.roundCount > state.roundCount { state.roundCount = snapshot.roundCount }
        for entry in snapshot.entries {
            state.setField(entry.fieldId, at: CellKey(player: entry.player, round: entry.round), entry.value)
        }
        recompute()
    }

    /// Builds a runtime for `schema` and restores `snapshot` into it.
    public static func restored(schema: Schema, snapshot: GameSnapshot) throws -> GameRuntime {
        let runtime = try GameRuntime(schema: schema, playerNames: snapshot.players)
        runtime.restore(from: snapshot)
        return runtime
    }
}
