import XCTest
@testable import ScoreForgeKit

/// A fixed lookup table standing in for the runtime, so expressions can be
/// tested in isolation.
private struct StubContext: EvaluationContext {
    var currentPlayer: Int? = 0
    var currentRound: Int? = 0
    var inputValue: Value? = nil
    var playerIndices: [Int] = [0, 1, 2]
    var roundIndices: [Int] = [0, 1, 2]
    /// (id, player, round) → value. Missing keys resolve to .missing.
    var values: [String: Value] = [:]

    func resolve(id: String, player: Int?, round: Int?) -> Value {
        values["\(id)|\(player.map(String.init) ?? "-")|\(round.map(String.init) ?? "-")"]
            ?? values[id]
            ?? .missing
    }
}

final class ExpressionEngineTests: XCTestCase {
    private func eval(_ src: String, _ ctx: StubContext = StubContext()) throws -> Value {
        try Evaluator(context: ctx).evaluate(source: src)
    }

    func testArithmeticPrecedence() throws {
        XCTAssertEqual(try eval("2 + 3 * 4"), .number(14))
        XCTAssertEqual(try eval("(2 + 3) * 4"), .number(20))
        XCTAssertEqual(try eval("10 - 2 - 3"), .number(5))     // left-associative
        XCTAssertEqual(try eval("7 % 3"), .number(1))
        XCTAssertEqual(try eval("-5 + 2"), .number(-3))
    }

    func testComparisonAndLogical() throws {
        XCTAssertEqual(try eval("3 > 2 && 1 < 2"), .bool(true))
        XCTAssertEqual(try eval("3 < 2 || 5 == 5"), .bool(true))
        XCTAssertEqual(try eval("!(1 == 1)"), .bool(false))
        XCTAssertEqual(try eval("2 >= 2 && 2 <= 1"), .bool(false))
    }

    func testTernary() throws {
        XCTAssertEqual(try eval("1 == 1 ? 10 : 20"), .number(10))
        XCTAssertEqual(try eval("1 == 2 ? 10 : 20"), .number(20))
        // Nested
        XCTAssertEqual(try eval("0 ? 1 : (1 ? 2 : 3)"), .number(2))
    }

    func testMathBuiltins() throws {
        XCTAssertEqual(try eval("abs(-7)"), .number(7))
        XCTAssertEqual(try eval("floor(3.9)"), .number(3))
        XCTAssertEqual(try eval("ceil(3.1)"), .number(4))
        XCTAssertEqual(try eval("round(3.5)"), .number(4))
        XCTAssertEqual(try eval("clamp(15, 0, 10)"), .number(10))
        XCTAssertEqual(try eval("clamp(-3, 0, 10)"), .number(0))
        XCTAssertEqual(try eval("min(4, 9, 2)"), .number(2))
        XCTAssertEqual(try eval("max(4, 9, 2)"), .number(9))
        XCTAssertEqual(try eval("if(2 > 1, 100, 200)"), .number(100))
    }

    func testFieldReferenceAndInput() throws {
        var ctx = StubContext()
        ctx.values["score|0|0"] = .number(42)
        ctx.inputValue = .number(7)
        XCTAssertEqual(try eval("field('score')", ctx), .number(42))
        XCTAssertEqual(try eval("field('score') + input()", ctx), .number(49))
    }

    func testAggregatesAndRank() throws {
        var ctx = StubContext()
        ctx.values["total|0|0"] = .number(30)
        ctx.values["total|1|0"] = .number(50)
        ctx.values["total|2|0"] = .number(10)
        XCTAssertEqual(try eval("sum('total')", ctx), .number(90))
        XCTAssertEqual(try eval("max('total')", ctx), .number(50))
        XCTAssertEqual(try eval("min('total')", ctx), .number(10))
        XCTAssertEqual(try eval("count('total')", ctx), .number(3))
        // Player 0 has 30 → one player (50) is higher → rank 2 desc.
        XCTAssertEqual(try eval("rankDesc('total')", ctx), .number(2))
        // Ascending: two players (50, ... wait 10<30) → one lower (10) → rank 2.
        XCTAssertEqual(try eval("rankAsc('total')", ctx), .number(2))
    }

    func testRankTiesShareRank() throws {
        var ctx = StubContext()
        ctx.values["total|0|0"] = .number(50)
        ctx.values["total|1|0"] = .number(50)
        ctx.values["total|2|0"] = .number(10)
        // Both leaders rank 1 (competition ranking).
        XCTAssertEqual(try eval("rankDesc('total')", ctx), .number(1))
    }

    func testRoundReferenceAndSumRounds() throws {
        var ctx = StubContext()
        ctx.values["pts|0|0"] = .number(5)
        ctx.values["pts|0|1"] = .number(8)
        ctx.values["pts|0|2"] = .number(2)
        XCTAssertEqual(try eval("round(1, 'pts')", ctx), .number(8))
        XCTAssertEqual(try eval("sumRounds('pts')", ctx), .number(15))
        XCTAssertEqual(try eval("avgRounds('pts')", ctx), .number(5))
    }

    func testDivisionByZeroIsMissingNotCrash() throws {
        XCTAssertEqual(try eval("1 / 0"), .missing)
        XCTAssertEqual(try eval("5 % 0"), .missing)
        // Missing propagates through arithmetic.
        XCTAssertEqual(try eval("(1 / 0) + 3"), .missing)
    }

    func testUnknownFunctionThrows() {
        XCTAssertThrowsError(try eval("frobnicate(1)")) { error in
            XCTAssertEqual(error as? ExpressionError, .unknownFunction("frobnicate"))
        }
    }

    func testSyntaxErrors() {
        XCTAssertThrowsError(try eval("1 +"))
        XCTAssertThrowsError(try eval("(1 + 2"))
        XCTAssertThrowsError(try eval("1 2 3"))
        XCTAssertThrowsError(try eval("'unterminated"))
    }

    func testNodeBudgetStopsRunaway() {
        // A deeply nested expression beyond the node budget must error, not hang.
        let huge = String(repeating: "1+", count: 20) + "1"
        let ctx = StubContext()
        let evaluator = Evaluator(context: ctx, limits: .init(maxNodes: 5, maxDepth: 64))
        XCTAssertThrowsError(try evaluator.evaluate(source: huge)) { error in
            XCTAssertEqual(error as? ExpressionError, .limitExceeded("node count"))
        }
    }

    func testShortCircuitAvoidsMissingPropagation() throws {
        // false && (1/0) → false without evaluating the divide-by-zero side.
        XCTAssertEqual(try eval("false && (1 / 0 > 0)"), .bool(false))
        XCTAssertEqual(try eval("true || (1 / 0 > 0)"), .bool(true))
    }
}
