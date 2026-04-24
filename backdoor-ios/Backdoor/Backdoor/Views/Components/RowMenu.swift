import SwiftUI

/// Declarative action shown in a row's contextual `⋯` menu. Call sites
/// use the presets (`.edit`, `.share`, `.reassign`, `.move`) when
/// possible; free-form actions go through the full initializer.
struct RowAction {
    /// Localization key for the menu label.
    let labelKey: String
    /// SF Symbol name.
    let systemImage: String
    /// Hide the action when false — e.g. admin-only "Reassign" on a
    /// row seen by staff.
    let isVisible: Bool
    /// Fired when the menu item is tapped. Synchronous from the
    /// menu's perspective; wrap async work in a `Task { ... }` inside
    /// the closure.
    let perform: () -> Void

    init(
        labelKey: String,
        systemImage: String,
        isVisible: Bool = true,
        perform: @escaping () -> Void
    ) {
        self.labelKey = labelKey
        self.systemImage = systemImage
        self.isVisible = isVisible
        self.perform = perform
    }

    // MARK: - Presets

    static func edit(isVisible: Bool = true, perform: @escaping () -> Void) -> RowAction {
        RowAction(labelKey: "edit", systemImage: "pencil", isVisible: isVisible, perform: perform)
    }
    static func share(isVisible: Bool = true, perform: @escaping () -> Void) -> RowAction {
        RowAction(labelKey: "share", systemImage: "square.and.arrow.up", isVisible: isVisible, perform: perform)
    }
    static func reassign(isVisible: Bool = true, perform: @escaping () -> Void) -> RowAction {
        RowAction(labelKey: "reassign", systemImage: "arrow.triangle.2.circlepath", isVisible: isVisible, perform: perform)
    }
    static func move(isVisible: Bool = true, perform: @escaping () -> Void) -> RowAction {
        RowAction(labelKey: "move_to_folder", systemImage: "folder", isVisible: isVisible, perform: perform)
    }
}

/// How a delete in the row menu should behave. The rule (see CLAUDE.md
/// row-action policy): soft-delete → no confirm, post-delete undo
/// toast; hard-delete → confirm alert, no undo.
enum RowDeleteBehavior {
    /// Reversible. After `perform` fires, the host should present an
    /// undo toast wired to `undo`.
    case soft(undo: () -> Void)
    /// Irreversible. Host presents a confirmation alert first; once
    /// confirmed, `perform` fires and nothing follows.
    case hard(titleKey: String, messageKey: String? = nil)
}

struct RowDelete {
    let labelKey: String
    let behavior: RowDeleteBehavior
    let perform: () -> Void

    init(
        labelKey: String = "delete",
        behavior: RowDeleteBehavior,
        perform: @escaping () -> Void
    ) {
        self.labelKey = labelKey
        self.behavior = behavior
        self.perform = perform
    }
}

/// The ellipsis menu button itself. The host view:
/// - Supplies the actions / delete spec.
/// - Handles `onDelete` by (a) firing `perform` directly for soft and
///   presenting an `UndoToast`, or (b) storing the `RowDelete` to
///   drive a confirm alert for hard. `RowMenu` itself never presents
///   alerts or toasts — those live at the list level so they sit on
///   top of the list chrome, not per-row.
struct RowMenu: View {
    let actions: [RowAction]
    let delete: RowDelete?
    /// Called when the Delete menu item is tapped. If nil and
    /// `delete` is non-nil, `delete.perform` is fired directly
    /// (useful for lightweight surfaces that don't want the full
    /// confirm/toast plumbing).
    let onDelete: ((RowDelete) -> Void)?

    init(
        actions: [RowAction] = [],
        delete: RowDelete? = nil,
        onDelete: ((RowDelete) -> Void)? = nil
    ) {
        self.actions = actions
        self.delete = delete
        self.onDelete = onDelete
    }

    var body: some View {
        Menu {
            ForEach(visibleActions.indices, id: \.self) { i in
                let a = visibleActions[i]
                Button(action: a.perform) {
                    Label(tr(a.labelKey), systemImage: a.systemImage)
                }
            }
            if let delete {
                if !visibleActions.isEmpty { Divider() }
                Button(role: .destructive) {
                    if let onDelete { onDelete(delete) }
                    else { delete.perform() }
                } label: {
                    Label(tr(delete.labelKey), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.gray)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var visibleActions: [RowAction] {
        actions.filter(\.isVisible)
    }
}
