import XCTest
@testable import ScoreForgeKit

final class GameRuntimeTests: XCTestCase {

    // A compact freeform schema: per-player points with add and expression effects.
    private func pointsSchema(target: Double = 100) -> Schema {
        Schema(
            name: "Points",
            players: .init(min: 2, max: 8, default: 3),
            structure: .freeform,
            fields: [
                Field(id: "points", label: "P", type: .integer, scope: .perPlayer,
                      default: .number(0), min: 0, max: 50)
            ],
            actions: [
                Action(id: "add5", label: "+5", effects: [.init(target: "points", op: .add, value: .number(5))]),
                Action(id: "addInput", label: "+input", effects: [
                    .init(target: "points", op: .applyExpression, value: .string("field('points') + input()"))
                ]),
                Action(id: "addIfLow", label: "+10 if low", effects: [
                    .init(target: "points", op: .add, value: .number(10), when: "field('points') < 20")
                ])
            ],
            formulas: [
                Formula(id: "total", label: "Total", scope: .perPlayer, expression: "field('points')"),
                Formula(id: "rank", label: "Rank", scope: .perPlayer, expression: "rankDesc('total')")
            ],
            layout: LayoutNode(type: "vstack"),
            winCondition: .init(type: .firstToReach, scoreFormula: "total", target: target)
        )
    }

    func testAddEffectAndRecompute() throws {
        let rt = try GameRuntime(schema: pointsSchema(), playerNames: ["A", "B"])
        rt.applyAction("add5", player: 0)
        rt.applyAction("add5", player: 0)
        XCTAssertEqual(rt.value(of: "total", player: 0), .number(10))
        XCTAssertEqual(rt.value(of: "rank", player: 0), .number(1))
        XCTAssertEqual(rt.value(of: "rank", player: 1), .number(2))
    }

    func testApplyExpressionWithInput() throws {
        let rt = try GameRuntime(schema: pointsSchema(), playerNames: ["A", "B"])
        rt.applyAction("addInput", player: 1, input: .number(7))
        rt.applyAction("addInput", player: 1, input: .number(3))
        XCTAssertEqual(rt.value(of: "points", player: 1), .number(10))
    }

    func testFieldClampRespectsMinMax() throws {
        let rt = try GameRuntime(schema: pointsSchema(), playerNames: ["A", "B"])
        rt.setField("points", player: 0, value: .number(999)) // max 50
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(50))
        rt.setField("points", player: 0, value: .number(-5))  // min 0
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(0))
    }

    func testEffectGuardWhen() throws {
        let rt = try GameRuntime(schema: pointsSchema(), playerNames: ["A", "B"])
        rt.applyAction("addIfLow", player: 0) // 0 < 20 → +10
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(10))
        rt.setField("points", player: 0, value: .number(25))
        rt.applyAction("addIfLow", player: 0) // 25 < 20 false → no change
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(25))
    }

    func testUndoRestoresPreviousState() throws {
        let rt = try GameRuntime(schema: pointsSchema(), playerNames: ["A", "B"])
        rt.applyAction("add5", player: 0)
        rt.applyAction("add5", player: 0)
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(10))
        XCTAssertTrue(rt.undo())
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(5))
        XCTAssertTrue(rt.undo())
        XCTAssertEqual(rt.value(of: "points", player: 0), .number(0))
        XCTAssertFalse(rt.canUndo)
        XCTAssertFalse(rt.undo())
    }

    func testFirstToReachFinishes() throws {
        let rt = try GameRuntime(schema: pointsSchema(target: 20), playerNames: ["A", "B"])
        rt.setField("points", player: 0, value: .number(20))
        let result = rt.evaluateResult()
        XCTAssertTrue(result.isFinished)
        XCTAssertEqual(result.winnerIndices, [0])
        XCTAssertEqual(result.standings.first?.player, 0)
    }

    // Per-player-per-round trick-taking style: bonus when bid == won.
    private func roundsSchema() -> Schema {
        Schema(
            name: "Rounds",
            players: .init(min: 2, max: 6, default: 4),
            structure: .rounds,
            rounds: .init(fixed: false, maxRounds: 5),
            fields: [
                Field(id: "bid", label: "Bid", type: .integer, scope: .perPlayerPerRound, default: .number(0), min: 0),
                Field(id: "won", label: "Won", type: .integer, scope: .perPlayerPerRound, default: .number(0), min: 0)
            ],
            formulas: [
                Formula(id: "roundScore", label: "RS", scope: .perPlayerPerRound,
                        expression: "field('bid') == field('won') ? 10 + field('won') : 0"),
                Formula(id: "total", label: "Total", scope: .perPlayer, expression: "sumRounds('roundScore')"),
                Formula(id: "rank", label: "Rank", scope: .perPlayer, expression: "rankDesc('total')")
            ],
            layout: LayoutNode(type: "vstack"),
            winCondition: .init(type: .afterNRounds, scoreFormula: "total", rounds: 3)
        )
    }

    func testPerPlayerPerRoundAndSumRounds() throws {
        let rt = try GameRuntime(schema: roundsSchema(), playerNames: ["A", "B"])
        rt.addRound() // now 2 rounds
        // Round 0: A bids 2 wins 2 → 12; B bids 1 wins 0 → 0.
        rt.setField("bid", player: 0, round: 0, value: .number(2))
        rt.setField("won", player: 0, round: 0, value: .number(2))
        rt.setField("bid", player: 1, round: 0, value: .number(1))
        rt.setField("won", player: 1, round: 0, value: .number(0))
        // Round 1: A bids 0 wins 1 → 0; B bids 3 wins 3 → 13.
        rt.setField("won", player: 0, round: 1, value: .number(1))
        rt.setField("bid", player: 1, round: 1, value: .number(3))
        rt.setField("won", player: 1, round: 1, value: .number(3))

        XCTAssertEqual(rt.value(of: "roundScore", player: 0, round: 0), .number(12))
        XCTAssertEqual(rt.value(of: "total", player: 0), .number(12))
        XCTAssertEqual(rt.value(of: "total", player: 1), .number(13))
        XCTAssertEqual(rt.value(of: "rank", player: 1), .number(1))
    }

    func testAddRoundRespectsMax() throws {
        let rt = try GameRuntime(schema: roundsSchema(), playerNames: ["A", "B"])
        for _ in 0..<10 { rt.addRound() }
        XCTAssertEqual(rt.state.roundCount, 5) // capped at maxRounds
    }

    func testAfterNRoundsFinishes() throws {
        let rt = try GameRuntime(schema: roundsSchema(), playerNames: ["A", "B"])
        XCTAssertFalse(rt.evaluateResult().isFinished) // 1 round < 3
        rt.addRound(); rt.addRound() // 3 rounds
        XCTAssertTrue(rt.evaluateResult().isFinished)
    }

    func testLowestTotalWinnerDirection() throws {
        let schema = Schema(
            name: "Golf",
            players: .init(min: 2, max: 4, default: 2),
            structure: .rounds,
            rounds: .init(fixed: true, maxRounds: 2),
            fields: [Field(id: "s", label: "S", type: .integer, scope: .perPlayerPerRound, default: .number(0))],
            formulas: [
                Formula(id: "total", label: "T", scope: .perPlayer, expression: "sumRounds('s')"),
                Formula(id: "rank", label: "R", scope: .perPlayer, expression: "rankAsc('total')")
            ],
            layout: LayoutNode(type: "vstack"),
            winCondition: .init(type: .lowestTotal, scoreFormula: "total")
        )
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        rt.setField("s", player: 0, round: 0, value: .number(5))
        rt.setField("s", player: 1, round: 0, value: .number(2))
        let result = rt.evaluateResult()
        XCTAssertEqual(result.winnerIndices, [1]) // lowest total wins
        XCTAssertEqual(result.standings.first?.player, 1)
    }
}
