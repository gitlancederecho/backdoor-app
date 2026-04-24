import SwiftUI

/// One row in a searchable picker list.
struct PickerRow<RowID: Hashable>: Identifiable {
    let id: RowID
    let label: String
    /// Optional subtitle shown under the label in gray caption.
    var sublabel: String? = nil
    /// Optional leading avatar (initials + url).
    var avatar: (initials: String, url: String?)? = nil
    /// If true, row is always visible regardless of the search query
    /// and renders in a muted style — useful for "All", "Anyone",
    /// "None" pseudo-rows that aren't really data.
    var isSpecial: Bool = false
}

/// Generic sheet with a search field at the top and a scrollable list
/// of tappable rows. Used everywhere we had a `Menu` with a long list:
/// reassign, assignee filters, category pickers, actor pickers, etc.
///
/// Search matches case-insensitively against label and sublabel.
/// Special rows (all / anyone / none) bypass the filter and stay
/// pinned at the top in display order.
struct SearchablePickerSheet<RowID: Hashable>: View {
    let title: String
    let rows: [PickerRow<RowID>]
    let selectedID: RowID?
    let onPick: (RowID) -> Void

    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [PickerRow<RowID>] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return rows }
        return rows.filter { row in
            if row.isSpecial { return true }
            if row.label.localizedCaseInsensitiveContains(q) { return true }
            if let s = row.sublabel, s.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchField(prompt: tr("search"), text: $query)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().background(Color.bdBorder)
                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundColor(.gray.opacity(0.5))
                            Text(tr("picker_no_matches"))
                                .font(.subheadline).foregroundColor(.gray)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filtered) { row in
                                    rowView(row)
                                        .padding(.horizontal, 16)
                                }
                                Spacer().frame(height: 24)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func rowView(_ row: PickerRow<RowID>) -> some View {
        let isSelected = row.id == selectedID
        Button {
            onPick(row.id)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                if let avatar = row.avatar {
                    AvatarView(initials: avatar.initials, url: avatar.url, size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(row.isSpecial && !isSelected ? .gray : .white)
                    if let s = row.sublabel {
                        Text(s).font(.caption2).foregroundColor(.gray)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bdAccent)
                }
            }
            .padding(12)
            .background(isSelected ? Color.bdAccent.opacity(0.08) : Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
