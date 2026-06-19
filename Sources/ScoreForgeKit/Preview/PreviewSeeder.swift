import Foundation

/// Fills a runtime with plausible, deterministic sample values so a freshly
/// generated or edited template can be previewed with live totals and ranks
/// (docs/design.md FR-04). Values vary by player and round so standings are
/// non-trivial. Deterministic by design — no randomness.
public enum PreviewSeeder {
    public static func seed(_ runtime: GameRuntime) {
        let players = runtime.state.playerIndices
        let rounds = runtime.state.roundIndices
        for field in runtime.schema.fields {
            for cell in cells(for: field.scope, players: players, rounds: rounds) {
                let value = sampleValue(for: field, player: cell.player ?? 0, round: cell.round ?? 0)
                runtime.setField(field.id, player: cell.player, round: cell.round, value: value)
            }
        }
    }

    private static func cells(for scope: Scope, players: [Int], rounds: [Int]) -> [CellKey] {
        switch scope {
        case .global: return [CellKey()]
        case .perPlayer: return players.map { CellKey(player: $0) }
        case .perRound: return rounds.map { CellKey(round: $0) }
        case .perPlayerPerRound: return players.flatMap { p in rounds.map { CellKey(player: p, round: $0) } }
        }
    }

    private static func sampleValue(for field: Field, player: Int, round: Int) -> Value {
        switch field.type {
        case .integer, .number:
            // Spread values across the allowed range, biased by player so totals differ.
            let base = Double(2 + player * 2 + round)
            if let lo = field.min, let hi = field.max, hi >= lo {
                let span = hi - lo
                return .number((lo + Double((player + round) % (Int(span) + 1))).rounded())
            }
            return .number(base)
        case .bool:
            return .bool((player + round) % 2 == 0)
        case .select:
            if let options = field.options, !options.isEmpty {
                return .string(options[(player + round) % options.count].value)
            }
            return .string("")
        case .text:
            return .string("\(field.label) \(player + 1)")
        }
    }
}
