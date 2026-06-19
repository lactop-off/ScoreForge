import Foundation

/// How the runtime decides who has won. See docs/design.md §7.6.
public struct WinCondition: Codable, Equatable {
    public var type: Kind
    public var scoreFormula: String
    public var target: Double?
    public var rounds: Int?
    /// Whether the lowest score wins. When nil it is derived from `type`
    /// (`lowestTotal` → true, otherwise false). Set explicitly to model games
    /// where the end trigger and the winning direction differ — e.g. a penalty
    /// race that ends when someone *reaches* a threshold but the *lowest* total
    /// wins (docs/design.md §7.7).
    public var lowerWins: Bool?
    public var tieBreaker: TieBreaker
    public var customExpression: String?

    public init(
        type: Kind,
        scoreFormula: String,
        target: Double? = nil,
        rounds: Int? = nil,
        lowerWins: Bool? = nil,
        tieBreaker: TieBreaker = .none,
        customExpression: String? = nil
    ) {
        self.type = type
        self.scoreFormula = scoreFormula
        self.target = target
        self.rounds = rounds
        self.lowerWins = lowerWins
        self.tieBreaker = tieBreaker
        self.customExpression = customExpression
    }

    /// Effective winning direction, applying the `type`-based default.
    public var lowestWins: Bool { lowerWins ?? (type == .lowestTotal) }

    public enum Kind: String, Codable, Equatable {
        case highestTotal
        case lowestTotal
        case firstToReach
        case afterNRounds
        case customExpression
    }

    public enum TieBreaker: String, Codable, Equatable {
        case none
        case fewestRounds
        case headToHead
        case customExpression
    }
}
