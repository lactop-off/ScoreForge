import XCTest
@testable import ScoreForgeKit

final class PresetTests: XCTestCase {
    func testAllPresetsLoad() {
        XCTAssertEqual(Presets.all.count, Presets.identifiers.count,
                       "every bundled preset should decode")
    }

    func testAllPresetsValidate() {
        for schema in Presets.all {
            let report = SchemaValidator.validate(schema)
            XCTAssertTrue(report.isValid, "\(schema.name) failed validation: \(report.errors)")
        }
    }

    func testAllPresetsArePlayable() throws {
        for schema in Presets.all {
            let rt = try GameRuntime(schema: schema, playerNames: ["A", "B", "C"])
            let result = rt.evaluateResult()
            XCTAssertEqual(result.standings.count, 3, "\(schema.name) should rank all players")
        }
    }

    func testSchemaJSONRoundTrips() throws {
        for schema in Presets.all {
            let data = try schema.encoded()
            let decoded = try Schema.decode(from: data)
            XCTAssertEqual(schema, decoded, "\(schema.name) should survive an encode/decode round-trip")
        }
    }

    func testTrickTakingBonusScoring() throws {
        let schema = try XCTUnwrap(Presets.load("trick-taking"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        // A: bid 2, won 2 → 10 + 2 = 12. B: bid 2, won 1 → 0.
        rt.setField("bid", player: 0, round: 0, value: .number(2))
        rt.setField("won", player: 0, round: 0, value: .number(2))
        rt.setField("bid", player: 1, round: 0, value: .number(2))
        rt.setField("won", player: 1, round: 0, value: .number(1))
        XCTAssertEqual(rt.value(of: "total", player: 0), .number(12))
        XCTAssertEqual(rt.value(of: "total", player: 1), .number(0))
    }

    func testPenaltyRaceEndsAtThresholdButLowestWins() throws {
        let schema = try XCTUnwrap(Presets.load("penalty-race"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B", "C"])
        // A piles up penalties and crosses 500; C stays lowest.
        rt.applyAction("addPenalty", player: 0, input: .number(300))
        rt.applyAction("addPenalty", player: 0, input: .number(250)) // 550 → triggers end
        rt.applyAction("addPenalty", player: 1, input: .number(120))
        rt.applyAction("addPenalty", player: 2, input: .number(40))

        let result = rt.evaluateResult()
        XCTAssertTrue(result.isFinished, "reaching 500 ends the game")
        XCTAssertEqual(result.winnerIndices, [2], "lowest penalty total wins")
        XCTAssertEqual(result.standings.first?.player, 2)
    }

    func testCategorySelectScoring() throws {
        let schema = try XCTUnwrap(Presets.load("category-yaku"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        rt.setField("yaku", player: 0, round: 0, value: .string("triple"))   // 30
        rt.setField("yaku", player: 0, round: 1, value: .string("pair"))     // 10
        rt.setField("yaku", player: 1, round: 0, value: .string("straight")) // 20
        XCTAssertEqual(rt.value(of: "total", player: 0), .number(40))
        XCTAssertEqual(rt.value(of: "total", player: 1), .number(20))
        XCTAssertEqual(rt.value(of: "rank", player: 0), .number(1))
    }

    func testDoubleOrNothingBoolToggle() throws {
        let schema = try XCTUnwrap(Presets.load("double-or-nothing"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        rt.setField("points", player: 0, round: 0, value: .number(10))
        XCTAssertEqual(rt.value(of: "roundScore", player: 0, round: 0), .number(10))
        rt.applyAction("toggleRisk", player: 0, round: 0) // risked → doubled
        XCTAssertEqual(rt.value(of: "roundScore", player: 0, round: 0), .number(20))
        XCTAssertEqual(rt.value(of: "total", player: 0), .number(20))
    }

    func testPointsRaceInputAction() throws {
        let schema = try XCTUnwrap(Presets.load("points-race"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        rt.applyAction("addInput", player: 0, input: .number(40))
        rt.applyAction("addInput", player: 0, input: .number(60))
        let result = rt.evaluateResult()
        XCTAssertTrue(result.isFinished) // reached 100
        XCTAssertEqual(result.winnerIndices, [0])
    }
}
