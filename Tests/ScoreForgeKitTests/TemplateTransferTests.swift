import XCTest
@testable import ScoreForgeKit

final class TemplateTransferTests: XCTestCase {

    func testExportImportRoundTripPreservesContent() throws {
        let original = Presets.load("trick-taking")!
        let data = try TemplateTransfer.export(original)
        // Keep the same id so we can compare everything but origin.
        let outcome = try TemplateTransfer.importTemplate(from: data, assignNewID: false)

        XCTAssertFalse(outcome.wasRepaired)
        XCTAssertEqual(outcome.schema.origin, .imported)
        var expected = original
        expected.origin = .imported
        XCTAssertEqual(outcome.schema, expected)
    }

    func testImportAssignsNewIDByDefault() throws {
        let original = Presets.load("points-race")!
        let data = try TemplateTransfer.export(original)
        let outcome = try TemplateTransfer.importTemplate(from: data)
        XCTAssertNotEqual(outcome.schema.id, original.id)
        XCTAssertEqual(outcome.schema.origin, .imported)
    }

    func testImportMalformedJSONThrows() {
        let data = Data("{ this is not json ".utf8)
        XCTAssertThrowsError(try TemplateTransfer.importTemplate(from: data))
    }

    func testImportValidJSONMissingRequiredFieldThrows() {
        // Valid JSON, but not a template (no fields/players/etc.).
        let data = Data(#"{"hello":"world"}"#.utf8)
        XCTAssertThrowsError(try TemplateTransfer.importTemplate(from: data)) { error in
            guard case TemplateTransfer.ImportError.notATemplate = error else {
                return XCTFail("expected notATemplate, got \(error)")
            }
        }
    }

    func testImportInvalidButDecodableSchemaIsRepaired() throws {
        // Decodes fine, but the win condition points at a non-existent score
        // and a formula references an unknown id → must import via repair.
        let broken = Schema(
            name: "共有された壊れたシート",
            players: .init(min: 2, max: 4, default: 3),
            structure: .freeform,
            fields: [Field(id: "p", label: "P", type: .integer, scope: .perPlayer, default: .number(0))],
            actions: [Action(id: "inc", label: "+1", effects: [.init(target: "p", op: .add, value: .number(1))])],
            formulas: [Formula(id: "weird", label: "W", scope: .perPlayer, expression: "field('missing')")],
            layout: LayoutNode(type: "vstack"),
            winCondition: .init(type: .highestTotal, scoreFormula: "nope")
        )
        let data = try TemplateTransfer.export(broken)

        let outcome = try TemplateTransfer.importTemplate(from: data)
        XCTAssertFalse(outcome.originalReport.isValid)
        XCTAssertTrue(outcome.wasRepaired)
        XCTAssertFalse(outcome.repairNotes.isEmpty)
        XCTAssertTrue(outcome.isValid)

        // And the repaired import is actually playable.
        let rt = try GameRuntime(schema: outcome.schema, playerNames: ["A", "B"])
        rt.applyAction("inc", player: 0)
        XCTAssertEqual(rt.evaluateResult().standings.count, 2)
    }

    func testSuggestedFileName() {
        let schema = Presets.load("low-score")!
        let name = TemplateTransfer.suggestedFileName(for: schema)
        XCTAssertTrue(name.hasSuffix(".scoreforge.json"))
        XCTAssertFalse(name.contains(" "))
    }

    func testFileURLRoundTrip() throws {
        let schema = Presets.load("trick-taking")!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(TemplateTransfer.suggestedFileName(for: schema))
        try TemplateTransfer.export(schema, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let outcome = try TemplateTransfer.importTemplate(from: url, assignNewID: false)
        XCTAssertEqual(outcome.schema.name, schema.name)
        XCTAssertFalse(outcome.wasRepaired)
    }
}
