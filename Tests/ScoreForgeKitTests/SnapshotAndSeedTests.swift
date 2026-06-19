import XCTest
@testable import ScoreForgeKit

final class SnapshotAndSeedTests: XCTestCase {

    func testValueCodableRoundTrip() throws {
        let cases: [Value] = [.number(42), .number(-3.5), .bool(true), .bool(false), .string("役"), .missing]
        for value in cases {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(Value.self, from: data), value)
        }
    }

    func testSnapshotRestoresInterruptedGame() throws {
        let schema = try XCTUnwrap(Presets.load("trick-taking"))
        let original = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        original.addRound() // two rounds
        original.setField("bid", player: 0, round: 0, value: .number(2))
        original.setField("won", player: 0, round: 0, value: .number(2))
        original.setField("won", player: 1, round: 1, value: .number(3))
        original.setField("bid", player: 1, round: 1, value: .number(3))

        let snapshot = original.snapshot()
        XCTAssertEqual(snapshot.roundCount, 2)

        // Resume into a brand-new runtime.
        let resumed = try GameRuntime.restored(schema: schema, snapshot: snapshot)
        XCTAssertEqual(resumed.state.roundCount, 2)
        XCTAssertEqual(resumed.value(of: "bid", player: 0, round: 0), .number(2))
        XCTAssertEqual(resumed.value(of: "roundScore", player: 0, round: 0), .number(12)) // recomputed
        XCTAssertEqual(resumed.value(of: "total", player: 0), original.value(of: "total", player: 0))
        XCTAssertEqual(resumed.value(of: "total", player: 1), original.value(of: "total", player: 1))
    }

    func testSnapshotJSONRoundTrips() throws {
        let schema = try XCTUnwrap(Presets.load("points-race"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B", "C"])
        rt.applyAction("add5", player: 0)
        rt.applyAction("addInput", player: 1, input: .number(13))

        let snapshot = rt.snapshot()
        let decoded = try GameSnapshot.decode(from: snapshot.encoded())
        XCTAssertEqual(decoded, snapshot)
    }

    func testSnapshotIsDeterministic() throws {
        let schema = try XCTUnwrap(Presets.load("low-score"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        rt.setField("strokes", player: 1, round: 0, value: .number(4))
        rt.setField("strokes", player: 0, round: 0, value: .number(2))
        XCTAssertEqual(rt.snapshot(), rt.snapshot()) // stable ordering
    }

    func testPreviewSeederProducesLiveVariedStandings() throws {
        let schema = try XCTUnwrap(Presets.load("low-score"))
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B", "C", "D"])
        PreviewSeeder.seed(rt)
        let standings = rt.evaluateResult().standings
        XCTAssertEqual(standings.count, 4)
        // Seeded values vary by player, so not everyone is tied.
        let scores = Set(standings.compactMap { $0.score.asDouble })
        XCTAssertGreaterThan(scores.count, 1, "preview data should yield a meaningful ranking")
    }

    func testPreviewSeederFillsAllFieldTypes() throws {
        let schema = try XCTUnwrap(Presets.load("double-or-nothing")) // has integer + bool
        let rt = try GameRuntime(schema: schema, playerNames: ["A", "B"])
        PreviewSeeder.seed(rt)
        // Every per-round cell got a concrete (non-missing) value.
        for p in rt.state.playerIndices {
            XCTAssertFalse(rt.value(of: "points", player: p, round: 0).isMissing)
            XCTAssertFalse(rt.value(of: "risked", player: p, round: 0).isMissing)
        }
    }
}
