import Foundation

/// Reads and writes templates as standalone JSON, for sharing by file
/// (docs/design.md §3.1, §11, FR-14). Export is the schema JSON itself; import
/// decodes it, marks it as imported, then validates and — if needed — repairs
/// it, so a sheet received from someone else is always usable.
public enum TemplateTransfer {

    public enum ImportError: Error, Equatable, CustomStringConvertible {
        case malformedJSON(String)
        case notATemplate(String)
        public var description: String {
            switch self {
            case .malformedJSON(let m): return "malformed JSON: \(m)"
            case .notATemplate(let m): return "not a ScoreForge template: \(m)"
            }
        }
    }

    /// The result of importing a template, including whether repair was needed.
    public struct ImportOutcome {
        /// A validated, ready-to-use schema (repaired if the original was invalid).
        public let schema: Schema
        /// Validation of the file exactly as received, before any repair.
        public let originalReport: ValidationReport
        public let wasRepaired: Bool
        public let repairNotes: [SchemaRepair.Note]

        public var isValid: Bool { SchemaValidator.validate(schema).isValid }
    }

    // MARK: - Export

    /// Encodes a template to pretty-printed, shareable JSON.
    public static func export(_ schema: Schema) throws -> Data {
        try schema.encoded()
    }

    /// Writes a template's JSON to a file URL (e.g. a temp file for the share sheet).
    public static func export(_ schema: Schema, to url: URL) throws {
        try export(schema).write(to: url, options: .atomic)
    }

    /// A filesystem-safe file name like `Trick-Taking.scoreforge.json`.
    public static func suggestedFileName(for schema: Schema) -> String {
        let safe = schema.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let base = safe.isEmpty ? "template" : safe
        return "\(base).scoreforge.json"
    }

    // MARK: - Import

    /// Decodes, marks as imported, then validates and repairs a template.
    /// - Parameter assignNewID: mint a fresh id so an imported sheet can't
    ///   collide with an existing one (recommended when adding to a local store).
    public static func importTemplate(from data: Data, assignNewID: Bool = true) throws -> ImportOutcome {
        let decoded: Schema
        do {
            decoded = try Schema.decode(from: data)
        } catch let error as DecodingError {
            throw ImportError.notATemplate(describe(error))
        } catch {
            throw ImportError.malformedJSON("\(error)")
        }

        var schema = decoded
        schema.origin = .imported
        if assignNewID { schema.id = UUID().uuidString }

        let report = SchemaValidator.validate(schema)
        if report.isValid {
            return ImportOutcome(schema: schema, originalReport: report, wasRepaired: false, repairNotes: [])
        }

        let (repaired, notes) = SchemaRepair.repair(schema)
        return ImportOutcome(schema: repaired, originalReport: report, wasRepaired: true, repairNotes: notes)
    }

    /// Imports a template from a file URL.
    public static func importTemplate(from url: URL, assignNewID: Bool = true) throws -> ImportOutcome {
        try importTemplate(from: Data(contentsOf: url), assignNewID: assignNewID)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "missing required field '\(key.stringValue)'"
        case .typeMismatch(_, let ctx): return "type mismatch at \(path(ctx)): \(ctx.debugDescription)"
        case .valueNotFound(_, let ctx): return "missing value at \(path(ctx))"
        case .dataCorrupted(let ctx): return ctx.debugDescription
        @unknown default: return "\(error)"
        }
    }

    private static func path(_ ctx: DecodingError.Context) -> String {
        ctx.codingPath.map(\.stringValue).joined(separator: ".")
    }
}
