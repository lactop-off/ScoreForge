import Foundation

/// A node in the recursive view tree the renderer maps to SwiftUI. Unknown
/// `type` values are preserved verbatim so the renderer can degrade to a safe
/// placeholder rather than failing. See docs/design.md §7.5.
public struct LayoutNode: Codable, Equatable {
    /// Kept as a raw string (not an enum) so a schema referencing a leaf type a
    /// given app version doesn't know about still decodes and round-trips.
    public var type: String
    public var children: [LayoutNode]?

    // Common leaf bindings.
    public var field: String?
    public var bind: String?
    public var label: String?
    public var step: Double?
    public var actions: [String]?
    public var spacing: Double?

    // scoreTable configuration.
    public var rowField: String?
    public var columnGroup: String?
    public var cellFields: [String]?

    public var style: Style?

    public init(
        type: String,
        children: [LayoutNode]? = nil,
        field: String? = nil,
        bind: String? = nil,
        label: String? = nil,
        step: Double? = nil,
        actions: [String]? = nil,
        spacing: Double? = nil,
        rowField: String? = nil,
        columnGroup: String? = nil,
        cellFields: [String]? = nil,
        style: Style? = nil
    ) {
        self.type = type
        self.children = children
        self.field = field
        self.bind = bind
        self.label = label
        self.step = step
        self.actions = actions
        self.spacing = spacing
        self.rowField = rowField
        self.columnGroup = columnGroup
        self.cellFields = cellFields
        self.style = style
    }

    /// Leaf and container kinds the v1 renderer supports (docs/design.md §7.5).
    public enum Kind: String {
        case vstack, hstack, grid, card            // containers
        case counter, stepper, numberInput, textInput, toggle, segmented
        case label, badge, scoreTable, playerHeader, actionBar, spacer, divider
    }

    /// The recognised kind, or nil when the type is unknown (→ renderer fallback).
    public var kind: Kind? { Kind(rawValue: type) }

    /// Visual styling, clamped to a safe range by the renderer.
    public struct Style: Codable, Equatable {
        public var fontScale: Double?
        public var emphasis: Bool?
        public var colorHex: String?
        public var alignment: String?

        public init(
            fontScale: Double? = nil,
            emphasis: Bool? = nil,
            colorHex: String? = nil,
            alignment: String? = nil
        ) {
            self.fontScale = fontScale
            self.emphasis = emphasis
            self.colorHex = colorHex
            self.alignment = alignment
        }
    }
}
