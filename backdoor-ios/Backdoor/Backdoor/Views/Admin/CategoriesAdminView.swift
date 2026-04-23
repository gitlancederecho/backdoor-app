import SwiftUI

/// Admin CRUD for task categories.
///
/// Normal mode: each row shows per-row Edit + Delete actions (Delete is
/// hidden for built-ins). Tap the top-right Edit button to enter edit
/// mode — rows gain selection circles + drag handles; a bottom bar
/// offers bulk Delete. Built-in rows cannot be deleted individually or
/// in bulk; the UI filters them out of the selection's effective
/// delete set.
struct CategoriesAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang

    @State private var editingCategory: Category?
    @State private var showingNew = false
    @State private var deleteTarget: Category?
    @State private var editMode: EditMode = .inactive
    @State private var selectedKeys: Set<String> = []
    @State private var showBulkDeleteConfirm = false

    var body: some View {
        let _ = lang.current
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                Divider().background(Color.bdBorder)
                categoriesList
                if editMode.isEditing, !effectiveDeletableSelection.isEmpty {
                    bulkActionBar
                }
            }

            if !editMode.isEditing {
                Button { showingNew = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundColor(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.bdAccent)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingNew) {
            CategoryEditorSheet(adminVM: adminVM, existing: nil)
                .environment(lang)
        }
        .sheet(item: $editingCategory) { cat in
            CategoryEditorSheet(adminVM: adminVM, existing: cat)
                .environment(lang)
        }
        .alert(
            tr("delete_category_confirm"),
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { cat in
            Button(tr("delete"), role: .destructive) {
                Task { try? await adminVM.deleteCategory(key: cat.key) }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: { cat in
            let count = adminVM.taskCountUsingCategory(cat.key)
            if count > 0 {
                Text(String(format: tr("delete_category_in_use_message"), count))
            } else {
                Text(cat.localized)
            }
        }
        .alert(
            tr("delete_category_confirm"),
            isPresented: $showBulkDeleteConfirm,
            presenting: effectiveDeletableSelection
        ) { keys in
            Button(String(format: tr("delete_n"), keys.count), role: .destructive) {
                Task {
                    await adminVM.deleteCategories(keys: keys)
                    selectedKeys = []
                    editMode = .inactive
                }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: { keys in
            let totalUse = keys.reduce(0) { $0 + adminVM.taskCountUsingCategory($1) }
            if totalUse > 0 {
                Text(String(format: tr("delete_category_in_use_message"), totalUse))
            } else {
                Text(String(format: tr("delete_n_categories"), keys.count))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(tr("categories_hint"))
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(editMode.isEditing ? tr("done") : tr("edit")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if editMode.isEditing {
                        editMode = .inactive
                        selectedKeys = []
                    } else {
                        editMode = .active
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.bdAccent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - List

    private var categoriesList: some View {
        List(selection: $selectedKeys) {
            ForEach(adminVM.categories) { cat in
                CategoryRow(
                    category: cat,
                    taskCount: adminVM.taskCountUsingCategory(cat.key),
                    isEditing: editMode.isEditing,
                    onEdit: { editingCategory = cat },
                    onDelete: { deleteTarget = cat }
                )
                .tag(cat.key)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                // Swipe-to-delete in normal mode for non-builtin rows.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !cat.isBuiltin {
                        Button(role: .destructive) { deleteTarget = cat } label: {
                            Label(tr("delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .onMove { source, destination in
                adminVM.categories.move(fromOffsets: source, toOffset: destination)
                Task { await adminVM.persistCategoryOrder() }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .environment(\.editMode, $editMode)
    }

    // MARK: - Bulk action bar

    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text(String(format: tr("selected_count"), effectiveDeletableSelection.count))
                .font(.subheadline)
                .foregroundColor(.white)
            Spacer()
            Button {
                showBulkDeleteConfirm = true
            } label: {
                Label(
                    String(format: tr("delete_n"), effectiveDeletableSelection.count),
                    systemImage: "trash"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.statusPending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.bdBorder), alignment: .top)
    }

    /// Selection limited to non-builtin rows — built-ins aren't bulk-deletable.
    private var effectiveDeletableSelection: [String] {
        adminVM.categories
            .filter { selectedKeys.contains($0.key) && !$0.isBuiltin }
            .map(\.key)
    }
}

// MARK: - Row

private struct CategoryRow: View {
    let category: Category
    let taskCount: Int
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        let _ = lang.current
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(category.localized)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    if category.isBuiltin {
                        Text(tr("category_builtin_badge"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.bdAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.bdAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(category.key)
                    .font(.caption2.monospaced())
                    .foregroundColor(.gray)
                Text(String(format: tr("category_task_count"), taskCount))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            if !isEditing {
                // Normal mode: per-row edit + delete buttons.
                HStack(spacing: 16) {
                    Button(tr("edit"), action: onEdit)
                        .font(.subheadline)
                        .foregroundColor(.bdAccent)
                    if !category.isBuiltin {
                        Button(tr("delete"), action: onDelete)
                            .font(.subheadline)
                            .foregroundColor(.statusPending)
                    }
                }
            }
            // In edit mode, SwiftUI automatically renders the selection
            // circle (from List(selection:)) and the drag handle
            // (from .onMove), so we don't add anything extra here.
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Editor sheet

private struct CategoryEditorSheet: View {
    @Bindable var adminVM: AdminViewModel
    let existing: Category?
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var labelEn: String = ""
    @State private var labelJa: String = ""
    @State private var sortOrder: Int = 100
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var isNew: Bool { existing == nil }

    private var derivedKey: String {
        existing?.key ?? CategoryDisplay.normalize(labelEn)
    }

    private var isDuplicate: Bool {
        guard isNew, !derivedKey.isEmpty else { return false }
        return adminVM.categories.contains(where: { $0.key == derivedKey })
    }

    private var canSubmit: Bool {
        let trimmed = labelEn.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !isDuplicate && !isSaving
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("label_en")).font(.caption).foregroundColor(.gray)
                            TextField(tr("new_category_placeholder"), text: $labelEn)
                                .inputStyle()
                                .focused($focused)
                                .textInputAutocapitalization(.words)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("label_ja")).font(.caption).foregroundColor(.gray)
                            TextField("例: 棚卸", text: $labelJa).inputStyle()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("sort_order")).font(.caption).foregroundColor(.gray)
                            Stepper(value: $sortOrder, in: 1...999, step: 1) {
                                Text("\(sortOrder)").foregroundColor(.white).font(.system(size: 15, weight: .medium))
                            }
                            .padding(14)
                            .cardStyle()
                        }

                        if !derivedKey.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tr("category_key_label"))
                                    .font(.caption).foregroundColor(.gray)
                                Text(derivedKey)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.bgElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }

                        if isDuplicate {
                            Text(tr("category_duplicate_warning"))
                                .font(.caption)
                                .foregroundColor(.statusPending)
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundColor(.statusPending)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isNew ? tr("add_category") : tr("edit_category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? tr("add") : tr("save")) { Task { await save() } }
                        .foregroundColor(.bdAccent)
                        .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .onAppear { populate() }
    }

    private func populate() {
        if let existing {
            labelEn = existing.labelEn
            labelJa = existing.labelJa ?? ""
            sortOrder = Int(existing.sortOrder)
        } else {
            let maxSort = adminVM.categories.map(\.sortOrder).max() ?? 0
            sortOrder = Int(maxSort) + 1
            focused = true
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        let labelJaValue = labelJa.trimmingCharacters(in: .whitespaces).isEmpty ? nil : labelJa
        let labelEnValue = labelEn.trimmingCharacters(in: .whitespaces)
        do {
            if let existing {
                let patch = CategoryPatch(
                    labelEn: labelEnValue,
                    labelJa: labelJaValue,
                    sortOrder: Int16(clamping: sortOrder)
                )
                try await adminVM.updateCategory(key: existing.key, patch)
            } else {
                let row = NewCategory(
                    key: derivedKey,
                    labelEn: labelEnValue,
                    labelJa: labelJaValue,
                    sortOrder: Int16(clamping: sortOrder),
                    isBuiltin: false
                )
                try await adminVM.createCategory(row)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
