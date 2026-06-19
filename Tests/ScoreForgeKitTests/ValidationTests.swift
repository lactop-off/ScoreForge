import XCTest
@testable import ScoreForgeKit

final class ValidationTests: XCTestCase {
    private func baseSchema(
        formulas: [Formula],
        actions: [Action] = [],
        layout: LayoutNode = LayoutNode(type: "vstack"),
        win: WinCondition = .init(type: .highestTotal, scoreFormula: "total")
    ) -> Schema {
        Schema(
            name: "T",
            players: .init(min: 2, max: 4, default: 2),
            structure: .freeform,
            fields: [Field(id: "p", label: "P", type: .integer, scope: .perPlayer, default: .number(0))],
            actions: actions,
            formulas: formulas,
            layout: layout,
            winCondition: win
        )
    }

    func testValidSchemaPasses() {
        let schema = baseSchema(formulas: [
            Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')")
        ])
        XCTAssertTrue(SchemaValidator.validate(schema).isValid)
    }

    func testUnknownReferenceIsError() {
        let schema = baseSchema(formulas: [
            Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('nope')")
        ])
        let report = SchemaValidator.validate(schema)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.errors.contains { $0.message.contains("unknown id 'nope'") })
    }

    func testUnknownFunctionIsError() {
        let schema = baseSchema(formulas: [
            Formula(id: "total", label: "T", scope: .perPlayer, expression: "wat('p')")
        ])
        XCTAssertTrue(SchemaValidator.validate(schema).errors.contains { $0.message.contains("unknown function 'wat'") })
    }

    func testCircularDependencyIsError() {
        let schema = baseSchema(formulas: [
            Formula(id: "a", label: "A", scope: .perPlayer, expression: "field('b')"),
            Formula(id: "b", label: "B", scope: .perPlayer, expression: "field('a')"),
            Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')")
        ])
        XCTAssertTrue(SchemaValidator.validate(schema).errors.contains { $0.message.contains("circular") })
    }

    func testDuplicateIdsAreErrors() {
        let schema = baseSchema(formulas: [
            Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')"),
            Formula(id: "total", label: "T2", scope: .perPlayer, expression: "field('p')")
        ])
        XCTAssertTrue(SchemaValidator.validate(schema).errors.contains { $0.message.contains("duplicate formula id") })
    }

    func testActionTargetingUnknownFieldIsError() {
        let schema = baseSchema(
            formulas: [Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')")],
            actions: [Action(id: "x", label: "x", effects: [.init(target: "ghost", op: .add, value: .number(1))])]
        )
        XCTAssertTrue(SchemaValidator.validate(schema).errors.contains { $0.message.contains("unknown field 'ghost'") })
    }

    func testUnknownLayoutTypeIsWarningNotError() {
        let schema = baseSchema(
            formulas: [Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')")],
            layout: LayoutNode(type: "hologram")
        )
        let report = SchemaValidator.validate(schema)
        XCTAssertTrue(report.isValid) // still usable
        XCTAssertTrue(report.warnings.contains { $0.message.contains("unknown node type 'hologram'") })
    }

    func testWinConditionUnknownScoreIsError() {
        let schema = baseSchema(
            formulas: [Formula(id: "total", label: "T", scope: .perPlayer, expression: "field('p')")],
            win: .init(type: .highestTotal, scoreFormula: "missing")
        )
        XCTAssertTrue(SchemaValidator.validate(schema).errors.contains { $0.message.contains("unknown score") })
    }
}
