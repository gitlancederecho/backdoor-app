import SwiftUI

/// The standard 56pt accent-color "+" button pinned to the bottom-
/// trailing of an admin list. Two flavors:
///
/// - `init(action:)` — single tap fires `action`. Used in folder
///   detail (just creates a task in this folder), Categories,
///   Staff, etc.
/// - `init(menu:)` — tap opens a menu. Used at the Tasks root
///   ("New task" / "New folder"). The closure builds the Menu's
///   content; the button label and chrome stay uniform.
struct FloatingAddButton<MenuContent: View>: View {
    private let kind: Kind
    private enum Kind {
        case action(() -> Void)
        case menu(() -> MenuContent)
    }

    /// Single-action variant.
    init(action: @escaping () -> Void) where MenuContent == EmptyView {
        self.kind = .action(action)
    }

    /// Menu variant — `menuContent` returns the Menu's children.
    init(@ViewBuilder menu menuContent: @escaping () -> MenuContent) {
        self.kind = .menu(menuContent)
    }

    var body: some View {
        Group {
            switch kind {
            case .action(let action):
                Button(action: action) { plusLabel }
            case .menu(let content):
                Menu { content() } label: { plusLabel }
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private var plusLabel: some View {
        Image(systemName: "plus")
            .font(.title2.bold())
            .foregroundColor(.black)
            .frame(width: 56, height: 56)
            .background(Color.bdAccent)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }
}
