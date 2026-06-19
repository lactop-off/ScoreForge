import Foundation
import ScoreForgeKit

// A minimal command-line driver that validates and plays a bundled preset, so
// the cross-platform engine can be exercised without the iOS app.
// Usage: scoreforge-cli [presetName]

let args = Array(CommandLine.arguments.dropFirst())

// `scoreforge-cli export <preset>` prints shareable template JSON to stdout.
if args.first == "export" {
    let name = args.dropFirst().first ?? "points-race"
    guard let schema = Presets.load(name) else {
        FileHandle.standardError.write(Data("Unknown preset '\(name)'.\n".utf8))
        exit(1)
    }
    let data = try TemplateTransfer.export(schema)
    FileHandle.standardOutput.write(data)
    print()
    exit(0)
}

let presetName = args.first ?? "points-race"

guard let schema = Presets.load(presetName) else {
    FileHandle.standardError.write(Data("Unknown preset '\(presetName)'. Options: \(Presets.identifiers.joined(separator: ", "))\n".utf8))
    exit(1)
}

print("Preset: \(schema.name)")
let report = SchemaValidator.validate(schema)
print("Validation: \(report.isValid ? "OK" : "FAILED") — \(report.errors.count) error(s), \(report.warnings.count) warning(s)")
for issue in report.issues { print("  \(issue)") }

guard report.isValid else { exit(2) }

let runtime = try GameRuntime(schema: schema, playerNames: ["Aoi", "Ren", "Sora"])

// Drive a few moves to demonstrate live recomputation.
switch schema.structure {
case .freeform:
    runtime.applyAction("add5", player: 0)
    runtime.applyAction("add5", player: 0)
    runtime.applyAction("add1", player: 1)
case .rounds:
    let field = schema.fields.first!.id
    runtime.setField(field, player: 0, round: 0, value: .number(3))
    runtime.setField(field, player: 1, round: 0, value: .number(5))
}

print("\nStandings:")
let result = runtime.evaluateResult()
for standing in result.standings {
    let name = runtime.state.players[standing.player]
    let mark = result.winnerIndices.contains(standing.player) ? " ★" : ""
    print("  \(name): \(standing.score.displayText)\(mark)")
}
print("Finished: \(result.isFinished)")
