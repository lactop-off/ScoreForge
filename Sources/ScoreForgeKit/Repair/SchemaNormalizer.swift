import Foundation

/// Fills in the small, non-destructive defaults a schema needs to be usable,
/// without changing its meaning. Run before validation/repair so that absent
/// field defaults, an out-of-range player default, or a missing round spec
/// don't surface as problems. See docs/design.md §9.3.
public enum SchemaNormalizer {
    public static func normalize(_ schema: Schema) -> Schema {
        var s = schema

        // Player counts: clamp to a sane, self-consistent range.
        var players = s.players
        if players.min > players.max { swap(&players.min, &players.max) } // preserve both bounds
        players.min = Swift.max(1, players.min)
        players.max = Swift.max(players.min, players.max)
        players.default = Swift.min(Swift.max(players.default, players.min), players.max)
        s.players = players

        // Round-based games need a round spec.
        if s.structure == .rounds, s.rounds == nil {
            s.rounds = .init(fixed: false, maxRounds: nil)
        }

        // Field defaults and ordered bounds.
        s.fields = s.fields.map { field in
            var f = field
            if f.default == nil { f.default = defaultScalar(for: f.type) }
            if let lo = f.min, let hi = f.max, lo > hi { f.min = hi; f.max = lo }
            return f
        }

        return s
    }

    static func defaultScalar(for type: Field.FieldType) -> ScalarValue {
        switch type {
        case .integer, .number: return .number(0)
        case .bool: return .bool(false)
        case .text, .select: return .string("")
        }
    }
}
