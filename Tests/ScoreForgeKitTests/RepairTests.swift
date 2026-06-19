import XCTest
@testable import ScoreForgeKit

final class RepairTests: XCTestCase {

    func testValidSchemaIsLeftPlayable() {
        for schema in Presets.all {
            let (repaired, notes) = SchemaRepair.repair(schema)
            XCTAssertTrue(SchemaValidator.validate(repaired).isValid)
            // A clean preset should need no structural changes.
            XCTAssertTrue(notes.isEmpty, "\(schema.name) unexpectedly repaired: \(notes)")
        }
    }

    /// A deliberately broken schema: unknown function, dangling reference,
    /// duplicate id, a dependency cycle, an action on a missing field, a bad
    /// win-condition score, and an unknown layout node. Repair must still yield
    /// a valid, playable sheet.
    func testBrokenSchemaBecomesValidAndPlayable() throws {
        let broken = Schema(
            name: "壊れたスキーマ",
            players: .init(min: 5, max: 2, default: 9), // inverted + out of range
            structure: .freeform,
            fields: [
                Field(id: "p", label: "P", type: .integer, scope: .perPlayer),
                Field(id: "p", label: "dup", type: .integer, scope: .perPlayer) // duplicate id
            ],
            actions: [
                Action(id: "ghost", label: "x", effects: [.init(target: "nope", op: .add, value: .number(1))]),
                Action(id: "ok", label: "+1", effects: [.init(target: "p", op: .add, value: .number(1))])
            ],
            formulas: [
                Formula(id: "bad", label: "B", scope: .perPlayer, expression: "frobnicate('p')"),
                Formula(id: "dangling", label: "D", scope: .perPlayer, expression: "field('ghostField')"),
                Formula(id: "a", label: "A", scope: .perPlayer, expression: "field('b')"),
                Formula(id: "b", label: "B2", scope: .perPlayer, expression: "field('a')") // cycle a<->b
            ],
            layout: LayoutNode(type: "hologram", children: [LayoutNode(type: "label", bind: "ghost")]),
            winCondition: .init(type: .highestTotal, scoreFormula: "doesNotExist")
        )

        let (repaired, notes) = SchemaRepair.repair(broken)
        XCTAssertFalse(notes.isEmpty)

        let report = SchemaValidator.validate(repaired)
        XCTAssertTrue(report.isValid, "repair must guarantee validity: \(report.errors)")

        // Inverted player bounds are swapped (2..5) and the default clamped in.
        XCTAssertEqual(repaired.players.min, 2)
        XCTAssertEqual(repaired.players.max, 5)
        XCTAssertEqual(repaired.players.default, 5)

        // The bad/dangling/cyclic formulas are gone; a usable score exists.
        XCTAssertFalse(repaired.formulas.contains { $0.id == "bad" || $0.id == "dangling" })
        XCTAssertTrue(Set(repaired.fields.map(\.id) + repaired.formulas.map(\.id))
            .contains(repaired.winCondition.scoreFormula))

        // The unknown layout node was replaced; the schema actually runs.
        XCTAssertNotNil(repaired.layout.kind)
        let rt = try GameRuntime(schema: repaired, playerNames: ["A", "B"])
        rt.applyAction("ok", player: 0)
        XCTAssertEqual(rt.evaluateResult().standings.count, 2)
    }

    func testRepairIsIdempotent() {
        let broken = Schema(
            name: "x",
            players: .init(min: 2, max: 4, default: 2),
            structure: .freeform,
            fields: [Field(id: "p", label: "P", type: .integer, scope: .perPlayer)],
            formulas: [Formula(id: "z", label: "Z", scope: .perPlayer, expression: "oops('p')")],
            layout: LayoutNode(type: "???"),
            winCondition: .init(type: .highestTotal, scoreFormula: "z")
        )
        let once = SchemaRepair.repair(broken).schema
        let (twice, notes) = SchemaRepair.repair(once)
        XCTAssertTrue(notes.isEmpty, "repairing an already-repaired schema should be a no-op")
        XCTAssertEqual(once, twice)
    }

    func testSchemaWithNoFormulasGetsSynthesizedScore() throws {
        let schema = Schema(
            name: "no formulas",
            players: .init(min: 2, max: 4, default: 2),
            structure: .freeform,
            fields: [Field(id: "pts", label: "Pts", type: .integer, scope: .perPlayer, default: .number(0))],
            formulas: [],
            layout: LayoutNode(type: "vstack"),
            winCondition: .init(type: .highestTotal, scoreFormula: "total")
        )
        let repaired = schema.repaired()
        XCTAssertTrue(SchemaValidator.validate(repaired).isValid)
        XCTAssertFalse(repaired.formulas.isEmpty)
        let rt = try GameRuntime(schema: repaired, playerNames: ["A", "B"])
        rt.setField("pts", player: 0, value: .number(7))
        XCTAssertEqual(rt.value(of: repaired.winCondition.scoreFormula, player: 0), .number(7))
    }

    func testDefaultLayoutCoversFieldsActionsAndFormulas() {
        let schema = Presets.load("points-race")!
        let layout = DefaultLayoutBuilder.build(for: schema)
        // Collect every bind/field/action referenced by the generated layout.
        var fields = Set<String>(), binds = Set<String>(), actions = Set<String>()
        func walk(_ n: LayoutNode) {
            if let f = n.field { fields.insert(f) }
            if let b = n.bind { binds.insert(b) }
            actions.formUnion(n.actions ?? [])
            (n.children ?? []).forEach(walk)
        }
        walk(layout)
        XCTAssertTrue(fields.contains("points"))
        XCTAssertTrue(binds.contains("total"))
        XCTAssertTrue(actions.isSuperset(of: ["add1", "add5", "addInput"]))
        // And it validates cleanly against the schema.
        var s = schema; s.layout = layout
        XCTAssertTrue(SchemaValidator.validate(s).warnings.allSatisfy { !$0.message.contains("layout") })
    }
}
