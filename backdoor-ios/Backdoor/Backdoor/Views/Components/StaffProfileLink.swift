import SwiftUI

/// Wraps content in a Button that presents `StaffProfileView` as a sheet
/// for the given staff. When `staff` is nil the content renders as-is —
/// no tap affordance — so call sites can pass an optional safely.
///
/// Safe inside other sheets (SwiftUI supports nested sheet presentation);
/// SwiftUI's environment propagation forwards `LanguageManager` etc. to
/// the presented profile.
private struct StaffProfileLinkModifier: ViewModifier {
    let staff: Staff?
    @State private var presented: Staff?

    func body(content: Content) -> some View {
        if let staff {
            Button { presented = staff } label: { content }
                .buttonStyle(.plain)
                .sheet(item: $presented) { s in
                    StaffProfileView(staff: s)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Make this view a tappable link to `staff`'s profile. No-op when
    /// `staff` is nil. Inside a List, use `.buttonStyle(.borderless)`
    /// on siblings so SwiftUI routes taps correctly (see CLAUDE.md
    /// gotchas).
    func staffProfileLink(_ staff: Staff?) -> some View {
        modifier(StaffProfileLinkModifier(staff: staff))
    }
}
