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
