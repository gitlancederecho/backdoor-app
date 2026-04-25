import SwiftUI

/// The fixed palette an admin can pick from when creating or editing
/// a folder. Stored on `task_folders.color` as a hex string. nil
/// (default) renders as the app accent gold so existing rows keep
/// looking the way they did before colors landed.
enum FolderTint: String, CaseIterable, Identifiable {
    case gold   = "#e8b84b"
    case red    = "#e57373"
    case orange = "#f6a26b"
    case green  = "#76c97a"
    case blue   = "#5aa6e8"
    case purple = "#a06ae3"
    case pink   = "#e578b0"
    case gray   = "#9aa0a6"

    var id: String { rawValue }
    var color: Color { Color(hex: rawValue) }

    /// Resolve a stored hex string (or nil) to a Color. Unknown
    /// hex strings round-trip through `Color(hex:)` so admins
    /// who hand-set custom colors via the DB still see something
    /// sensible.
    static func color(forStored hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return .bdAccent }
        return Color(hex: hex)
    }
}
