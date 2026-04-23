import SwiftUI

/// Admin CRUD for task categories. Add / rename / reorder / delete
/// rows in the `categories` table. Built-in rows (is_builtin=true)
/// can still be renamed but not deleted — that's the only guardrail.
struct CategoriesAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang

    @State private var editingCategory: Category?
    @State private var showingNew = false
    @State private var deleteTarget: Category?

    var body: some View {
        let _ = lang.current
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    Text(tr("categories_hint"))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ForEach(adminVM.categories) { cat in
                        CategoryRow(
                            category: cat,
                            taskCount: adminVM.taskCountUsingCategory(cat.key),
                            onEdit: { editingCategory = cat },
                            onDelete: { deleteTarget = cat }
                        )
                        .padding(.horizontal, 16)
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.top, 8)
            }

            Button {
                showingNew = true
            } label: {
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
    }
}

// MARK: - Row

private struct CategoryRow: View {
    let category: Category
    let taskCount: Int
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

                        // Read-only key line (for new rows, it's derived;
                        // for existing rows, keys are immutable since
                        // task.category references them by value).
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
