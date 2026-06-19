import Foundation

/// A user-triggerable operation (a button, a stepper increment, …) declared as
/// a set of effects on fields. See docs/design.md §7.3.
public struct Action: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var iconSystemName: String?
    public var effects: [Effect]

    public init(id: String, label: String, iconSystemName: String? = nil, effects: [Effect]) {
        self.id = id
        self.label = label
        self.iconSystemName = iconSystemName
        self.effects = effects
    }

    public struct Effect: Codable, Equatable {
        public var target: String
        public var op: Op
        /// Either a literal scalar or, for `.applyExpression`, an expression
        /// string. Stored as a flexible scalar so JSON round-trips cleanly.
        public var value: ScalarValue?
        /// Optional guard expression: the effect only applies when this is true.
        public var when: String?

        public init(target: String, op: Op, value: ScalarValue? = nil, when: String? = nil) {
            self.target = target
            self.op = op
            self.value = value
            self.when = when
        }

        public enum Op: String, Codable, Equatable {
            case set, add, subtract, toggle, applyExpression
        }
    }
}
