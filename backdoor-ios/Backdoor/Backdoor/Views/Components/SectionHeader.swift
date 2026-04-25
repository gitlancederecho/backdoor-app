import SwiftUI

/// The uniform "uppercase, tracked, gray" section header used across
/// admin lists (Folders / Unfiled, Operating hours, Per-staff stats,
/// etc.). Caller controls horizontal/vertical placement; this view
/// only owns the typography.
struct SectionHeader: View {
    let text: String
    /// When true the header gets the same horizontal/vertical padding
    /// the in-list version used (16 / 6). Set false when wrapping in a
    /// custom container.
    var inset: Bool = true

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundColor(.gray)
            .tracking(1.2)
            .padding(.horizontal, inset ? 16 : 0)
            .padding(.vertical, inset ? 6 : 0)
    }
}
