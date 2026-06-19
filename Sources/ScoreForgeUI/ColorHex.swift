#if canImport(SwiftUI)
import SwiftUI

extension Color {
    /// Parses a `#RRGGBB` hex string (the schema's `themeColorHex` /
    /// `style.colorHex`). Returns nil for malformed input so callers can fall
    /// back to a default color (docs/renderer-spec.md §5).
    init?(hex: String?) {
        guard var s = hex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
#endif
