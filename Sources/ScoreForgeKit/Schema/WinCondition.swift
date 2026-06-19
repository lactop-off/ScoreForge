import Foundation

/// How the runtime decides who has won. See docs/design.md §7.6.
public struct WinCondition: Codable, Equatable {
    public var type: Kind
    public var scoreFormula: String
    public var target: Double?
    public var rounds: Int?
    public var tieBreaker: TieBreaker
    public var customExpression: String?

    public init(
        type: Kind,
        scoreFormula: String,
        target: Double? = nil,
        rounds: Int? = nil,
        tieBreaker: TieBreaker = .none,
        customExpression: String? = nil
    ) {
        self.type = type
        self.scoreFormula = scoreFormula
        self.target = target
        self.rounds = rounds
        self.tieBreaker = tieBreaker
        self.customExpression = customExpression
    }

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
