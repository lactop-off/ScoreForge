import Foundation

/// Builds a guaranteed-valid layout from a schema's fields, formulas, and
/// actions. Used both as the mechanical fallback when AI/imported layouts are
/// unusable (docs/design.md §9.5) and to seed a layout for manually created
/// templates. Every node references only ids that exist, so the result never
/// produces layout validation warnings.
public enum DefaultLayoutBuilder {
    public static func build(for schema: Schema) -> LayoutNode {
        var children: [LayoutNode] = [LayoutNode(type: LayoutNode.Kind.playerHeader.rawValue)]

        // A round table for per-round cells, when the game is round-based.
        let perRoundFields = schema.fields.filter { $0.scope == .perPlayerPerRound }
        let perRoundFormulas = schema.formulas.filter { $0.scope == .perPlayerPerRound && $0.display }
        if schema.structure == .rounds, !perRoundFields.isEmpty {
            children.append(LayoutNode(
                type: LayoutNode.Kind.scoreTable.rawValue,
                rowField: "round",
                columnGroup: "player",
                cellFields: perRoundFields.map(\.id) + perRoundFormulas.map(\.id)
            ))
        }

        // An input control for every editable field.
        children += schema.fields.map(control(for:))

        // A read-out for every displayable non-cell formula (totals, ranks, …).
        for formula in schema.formulas where formula.display && formula.scope != .perPlayerPerRound {
            let style = LayoutNode.Style(fontScale: formula.scope == .perPlayer ? 1.3 : nil,
                                         emphasis: formula.scope == .perPlayer)
            children.append(LayoutNode(type: LayoutNode.Kind.label.rawValue, bind: formula.id, style: style))
        }

        // All actions, if any.
        if !schema.actions.isEmpty {
            children.append(LayoutNode(type: LayoutNode.Kind.actionBar.rawValue,
                                       actions: schema.actions.map(\.id)))
        }

        return LayoutNode(type: LayoutNode.Kind.vstack.rawValue, children: children, spacing: 12)
    }

    private static func control(for field: Field) -> LayoutNode {
        switch field.type {
        case .bool:
            return LayoutNode(type: LayoutNode.Kind.toggle.rawValue, field: field.id, label: field.label)
        case .select:
            return LayoutNode(type: LayoutNode.Kind.segmented.rawValue, field: field.id, label: field.label)
        case .text:
            return LayoutNode(type: LayoutNode.Kind.textInput.rawValue, field: field.id, label: field.label)
        case .integer, .number:
            return LayoutNode(type: LayoutNode.Kind.counter.rawValue, field: field.id, label: field.label, step: 1)
        }
    }
}
