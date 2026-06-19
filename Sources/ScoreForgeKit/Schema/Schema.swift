import Foundation

/// Declarative definition of a scoring sheet. The AI generator (and the manual
/// editor) produce values of this type; the runtime and renderer only ever
/// *interpret* it — never execute arbitrary code. See docs/design.md §7.
public struct Schema: Codable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var name: String
    public var description: String?
    public var origin: Origin
    public var iconSystemName: String?
    public var themeColorHex: String?

    public var players: PlayerSpec
    public var structure: Structure
    public var rounds: RoundSpec?

    public var fields: [Field]
    public var actions: [Action]
    public var formulas: [Formula]
    public var layout: LayoutNode
    public var winCondition: WinCondition

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        origin: Origin = .manual,
        iconSystemName: String? = nil,
        themeColorHex: String? = nil,
        players: PlayerSpec,
        structure: Structure,
        rounds: RoundSpec? = nil,
        fields: [Field],
        actions: [Action] = [],
        formulas: [Formula] = [],
        layout: LayoutNode,
        winCondition: WinCondition
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.description = description
        self.origin = origin
        self.iconSystemName = iconSystemName
        self.themeColorHex = themeColorHex
        self.players = players
        self.structure = structure
        self.rounds = rounds
        self.fields = fields
        self.actions = actions
        self.formulas = formulas
        self.layout = layout
        self.winCondition = winCondition
    }

    public enum Origin: String, Codable, Equatable {
        case ai, manual, preset, imported
    }

    public enum Structure: String, Codable, Equatable {
        /// A single cumulative tally with no explicit round table.
        case freeform
        /// A round-by-round table (rows = rounds, columns = players).
        case rounds
    }

    public struct PlayerSpec: Codable, Equatable {
        public var min: Int
        public var max: Int
        public var `default`: Int
        public var teams: Bool

        public init(min: Int, max: Int, default def: Int, teams: Bool = false) {
            self.min = min
            self.max = max
            self.default = def
            self.teams = teams
        }
    }

    public struct RoundSpec: Codable, Equatable {
        /// When true the number of rounds is fixed up-front; otherwise rounds
        /// are added on demand during play.
        public var fixed: Bool
        public var maxRounds: Int?

        public init(fixed: Bool, maxRounds: Int? = nil) {
            self.fixed = fixed
            self.maxRounds = maxRounds
        }
    }
}

extension Schema {
    /// Decodes a schema from JSON data, tolerating absent optional members.
    public static func decode(from data: Data) throws -> Schema {
        try JSONDecoder().decode(Schema.self, from: data)
    }

    /// Encodes the schema to pretty-printed, stable JSON suitable for export.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
