import Foundation

/// The outcome of evaluating a win condition against the current state.
public struct GameResult: Equatable {
    /// Players ordered best-first by the score formula.
    public struct Standing: Equatable {
        public let player: Int
        public let score: Value
        public init(player: Int, score: Value) {
            self.player = player
            self.score = score
        }
    }

    /// Whether the game's end condition is satisfied.
    public let isFinished: Bool
    /// Winning player indices (more than one when tied). When the game isn't
    /// finished these are the current leaders, for live highlighting.
    public let winnerIndices: [Int]
    public let standings: [Standing]

    public init(isFinished: Bool, winnerIndices: [Int], standings: [Standing]) {
        self.isFinished = isFinished
        self.winnerIndices = winnerIndices
        self.standings = standings
    }
}

extension GameRuntime {
    /// Evaluates the schema's win condition. Always returns current standings;
    /// `isFinished` reflects whether the end trigger has fired (docs/design.md §7.6).
    public func evaluateResult() -> GameResult {
        let condition = schema.winCondition
        let scores: [(player: Int, score: Double?)] = state.playerIndices.map {
            ($0, value(of: condition.scoreFormula, player: $0).asDouble)
        }

        let lowerIsBetter = (condition.type == .lowestTotal)
        let standings = scores
            .sorted { lhs, rhs in
                let a = lhs.score ?? (lowerIsBetter ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude)
                let b = rhs.score ?? (lowerIsBetter ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude)
                return lowerIsBetter ? a < b : a > b
            }
            .map { GameResult.Standing(player: $0.player, score: value(of: condition.scoreFormula, player: $0.player)) }

        let isFinished = isEndTriggered(condition, scores: scores)
        let winners = winningPlayers(condition, scores: scores, lowerIsBetter: lowerIsBetter, finished: isFinished)

        return GameResult(isFinished: isFinished, winnerIndices: winners, standings: standings)
    }

    private func isEndTriggered(_ c: WinCondition, scores: [(player: Int, score: Double?)]) -> Bool {
        switch c.type {
        case .highestTotal, .lowestTotal:
            // Open-ended: ends when the user stops the game.
            return false
        case .firstToReach:
            guard let target = c.target else { return false }
            return scores.contains { ($0.score ?? -.greatestFiniteMagnitude) >= target }
        case .afterNRounds:
            guard let n = c.rounds else { return false }
            return state.roundCount >= n
        case .customExpression:
            guard let expr = c.customExpression else { return false }
            return ((try? Evaluator(context: self).evaluate(source: expr)) ?? .missing).asBool
        }
    }

    private func winningPlayers(
        _ c: WinCondition,
        scores: [(player: Int, score: Double?)],
        lowerIsBetter: Bool,
        finished: Bool
    ) -> [Int] {
        let valid = scores.compactMap { pair in pair.score.map { (pair.player, $0) } }
        guard !valid.isEmpty else { return [] }
        let best = lowerIsBetter ? valid.map(\.1).min()! : valid.map(\.1).max()!
        return valid.filter { $0.1 == best }.map(\.0).sorted()
    }
}
