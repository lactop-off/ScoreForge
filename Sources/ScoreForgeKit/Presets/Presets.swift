import Foundation

/// Bundled scoring sheets, available even on devices that can't run the
/// on-device generator (docs/design.md FR-15, §14 MVP). Shipped as JSON so they
/// exercise exactly the same decode path as imported and AI-generated schemas.
public enum Presets {
    /// Resource file names (without extension), in display order.
    public static let identifiers = [
        "trick-taking", "points-race", "low-score",
        "penalty-race", "category-yaku", "double-or-nothing",
    ]

    /// All bundled presets that decode successfully.
    public static var all: [Schema] {
        identifiers.compactMap { load($0) }
    }

    /// Loads a single preset by resource name, or nil if missing/invalid.
    public static func load(_ name: String) -> Schema? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
                ?? Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? Schema.decode(from: data)
    }
}
