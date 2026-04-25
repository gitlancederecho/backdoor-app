import SwiftUI

/// Single-value filter pill — used for recurrence/role/status/etc.
/// filter rows. Selected = solid accent capsule with black text;
/// unselected = elevated bg with gray text. Tap fires `action`.
///
/// Example:
/// ```
/// FilterPill(label: tr("recurring"),
///            isSelected: recurrenceFilter == .recurring) {
///     recurrenceFilter = .recurring
/// }
/// ```
struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(label, action: action)
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? .black : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.bdAccent : Color.bgElevated)
            .clipShape(Capsule())
    }
}

/// Decorative version of `LabeledFilterPill` — "label: value ▾"
/// without any tap handling. Used as a `Menu`'s label, where SwiftUI
/// owns the gesture. Use `LabeledFilterPill` when you want a Button.
struct LabeledFilterPillLabel: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bgElevated)
        .clipShape(Capsule())
    }
}

/// Two-line filter pill — "label: value ▾" — used to open a picker
/// (category, assignee, etc). Label is the static descriptor; value
/// is the current selection's display name. Tapping fires `action`
/// (host typically presents a sheet).
///
/// Example:
/// ```
/// LabeledFilterPill(
///     label: tr("tasks_filter_category"),
///     value: categoryFilter.map { CategoryDisplay.localized($0, in: cats) }
///                         ?? tr("history_range_all")
/// ) { showingCategoryPicker = true }
/// ```
struct LabeledFilterPill: View {
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LabeledFilterPillLabel(label: label, value: value)
        }
        .buttonStyle(.plain)
    }
}
