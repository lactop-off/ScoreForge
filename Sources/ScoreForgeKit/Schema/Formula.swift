import Foundation

/// A derived value computed by a sandboxed expression (totals, ranks, bonuses).
/// See docs/design.md §7.4.
public struct Formula: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var scope: Scope
    public var expression: String
    public var display: Bool

    public init(id: String, label: String, scope: Scope, expression: String, display: Bool = true) {
        self.id = id
        self.label = label
        self.scope = scope
        self.expression = expression
        self.display = display
    }
}
