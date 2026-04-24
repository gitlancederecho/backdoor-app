import SwiftUI

/// The shared "⚠ <label>   Undo" toast — used whenever a soft-delete
/// lands. Caller positions it at the bottom of the list (pinned); a
/// 5-second auto-dismiss is managed by the caller via a `Task<Void,
/// Never>` so that a second delete can cancel/replace the first.
///
/// Example wiring on the host view:
///
/// ```
/// @State private var pendingUndo: UndoSpec?
/// @State private var undoDismissTask: Task<Void, Never>?
///
/// if let spec = pendingUndo {
///     UndoToast(labelKey: spec.labelKey) {
///         undoDismissTask?.cancel()
///         pendingUndo = nil
///         spec.onUndo()
///     }
///     .padding(.horizontal, 16).padding(.bottom, 24)
/// }
/// ```
struct UndoToast: View {
    let labelKey: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundColor(.statusPending)
            Text(tr(labelKey))
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Button(tr("undo"), action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.bdAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.bdBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// Value type carried around by host views so the toast + the dismiss
/// timer share the same identity. The `id` lets `.animation(_, value:)`
/// drive the slide-in cleanly when a new soft-delete replaces an
/// earlier one mid-window.
struct UndoSpec: Equatable {
    let id: UUID
    let labelKey: String
    /// Fired when the user taps "Undo". Host clears its own state.
    let onUndo: () -> Void

    init(labelKey: String, onUndo: @escaping () -> Void) {
        self.id = UUID()
        self.labelKey = labelKey
        self.onUndo = onUndo
    }

    static func == (lhs: UndoSpec, rhs: UndoSpec) -> Bool { lhs.id == rhs.id }
}
