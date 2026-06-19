import Foundation

/// A runtime value flowing through the expression engine. `.missing` models an
/// undefined / un-evaluable result and renders as "—" (docs/design.md §8.4).
public enum Value: Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case missing

    public var isMissing: Bool { self == .missing }

    /// Best-effort numeric coercion. Bools map to 1/0; numeric strings parse.
    public var asDouble: Double? {
        switch self {
        case .number(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s)
        case .missing: return nil
        }
    }

    /// Truthiness used by `?:`, `&&`, `||`, `!`, and effect guards.
    public var asBool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return !s.isEmpty
        case .missing: return false
        }
    }

    /// A human-facing string ("—" for missing, integers without a decimal).
    public var displayText: String {
        switch self {
        case .number(let d):
            if d.rounded() == d && abs(d) < 1e15 {
                return String(Int(d))
            }
            return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .string(let s): return s
        case .missing: return "—"
        }
    }
}

/// Tagged JSON encoding so a stored value round-trips unambiguously (a bool is
/// never mistaken for a number). Used by game-state persistence.
extension Value: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case number, bool, string, missing }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .number: self = .number(try c.decode(Double.self, forKey: .value))
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .value))
        case .string: self = .string(try c.decode(String.self, forKey: .value))
        case .missing: self = .missing
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let d): try c.encode(Kind.number, forKey: .type); try c.encode(d, forKey: .value)
        case .bool(let b): try c.encode(Kind.bool, forKey: .type); try c.encode(b, forKey: .value)
        case .string(let s): try c.encode(Kind.string, forKey: .type); try c.encode(s, forKey: .value)
        case .missing: try c.encode(Kind.missing, forKey: .type)
        }
    }
}
