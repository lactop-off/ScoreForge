import Foundation

/// One unit of recordable data (e.g. a bid, a penalty, a number of tricks won).
/// See docs/design.md §7.2.
public struct Field: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var type: FieldType
    public var scope: Scope
    public var `default`: ScalarValue?
    public var min: Double?
    public var max: Double?
    public var options: [SelectOption]?

    public init(
        id: String,
        label: String,
        type: FieldType,
        scope: Scope,
        default def: ScalarValue? = nil,
        min: Double? = nil,
        max: Double? = nil,
        options: [SelectOption]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.scope = scope
        self.default = def
        self.min = min
        self.max = max
        self.options = options
    }

    public enum FieldType: String, Codable, Equatable {
        case integer, number, text, bool, select
    }

    public struct SelectOption: Codable, Equatable {
        public var value: String
        public var label: String
        public init(value: String, label: String) {
            self.value = value
            self.label = label
        }
    }
}

/// The granularity at which a value (field or formula) exists. See §7.2.
public enum Scope: String, Codable, Equatable, CaseIterable {
    case global
    case perPlayer
    case perPlayerPerRound
    case perRound

    var hasPlayer: Bool { self == .perPlayer || self == .perPlayerPerRound }
    var hasRound: Bool { self == .perRound || self == .perPlayerPerRound }
}

/// A simple JSON scalar usable as a field default or a literal effect value.
public enum ScalarValue: Codable, Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported scalar value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .string(let s): try c.encode(s)
        }
    }

    public var value: Value {
        switch self {
        case .number(let d): return .number(d)
        case .bool(let b): return .bool(b)
        case .string(let s): return .string(s)
        }
    }
}
