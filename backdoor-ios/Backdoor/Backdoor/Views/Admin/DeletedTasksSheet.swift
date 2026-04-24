import SwiftUI

/// Lists soft-deleted (`is_active = false`) task templates with
/// per-row Restore, plus an edit-mode bulk-restore action. Kept as
/// a separate surface so the main Tasks list stays focused on
/// "what's live right now."
struct DeletedTasksSheet: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var deleted: [TaskTemplate] = []
    @State private var isLoading = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<UUID> = []
    @State private var searchText: String = ""

    private var filtered: [TaskTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return deleted }
        return deleted.filter { t in
            t.title.localizedCaseInsensitiveContains(q)
                || (t.titleJa?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchField(prompt: tr("search_tasks"), text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider().background(Color.bdBorder)
                    content
                    if editMode.isEditing, !selectedIds.isEmpty {
                        bulkBar
                    }
                }
            }
            .navigationTitle(tr("deleted_tasks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("close")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? tr("done") : tr("edit")) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if editMode.isEditing {
                                editMode = .inactive
                                selectedIds = []
                            } else {
                                editMode = .active
                            }
                        }
                    }
                    .foregroundColor(.bdAccent)
                    .disabled(filtered.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && deleted.isEmpty {
            VStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "trash.slash")
                    .font(.system(size: 36))
                    .foregroundColor(.gray.opacity(0.6))
                Text(tr("no_deleted_tasks"))
                    .font(.subheadline).foregroundColor(.gray)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selectedIds) {
                ForEach(filtered) { task in
                    DeletedRow(
                        task: task,
                        categories: adminVM.categories,
                        isEditing: editMode.isEditing,
                        onRestore: { Task { await restore([task]) } }
                    )
                    .tag(task.id)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .environment(\.editMode, $editMode)
        }
    }

    private var bulkBar: some View {
        let allSelected = !filtered.isEmpty
            && selectedIds.isSuperset(of: Set(filtered.map(\.id)))
        return HStack(spacing: 10) {
            Button {
                if allSelected {
                    selectedIds = []
                } else {
                    selectedIds = Set(filtered.map(\.id))
                }
            } label: {
                Text(allSelected ? tr("deselect_all") : tr("select_all"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.bdAccent)
            }
            .buttonStyle(.plain)
            Text(String(format: tr("selected_count"), selectedIds.count))
                .font(.caption).foregroundColor(.gray)
            Spacer()
            Button {
                let targets = filtered.filter { selectedIds.contains($0.id) }
                Task { await restore(targets) }
            } label: {
                Label(tr("restore"), systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.bdAccent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.bdBorder), alignment: .top)
    }

    private func load() async {
        isLoading = true
        deleted = await adminVM.fetchDeletedTaskTemplates()
        isLoading = false
    }

    private func restore(_ templates: [TaskTemplate]) async {
        await adminVM.restoreTaskTemplates(templates)
        selectedIds = []
        editMode = .inactive
        await load()
    }
}

private struct DeletedRow: View {
    let task: TaskTemplate
    let categories: [Category]
    let isEditing: Bool
    let onRestore: () -> Void
    @Environment(LanguageManager.self) private var lang

    private var displayTitle: String { lang.pick(en: task.title, ja: task.titleJa) }

    var body: some View {
        let _ = lang.current
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                HStack(spacing: 4) {
                    Text(CategoryDisplay.localized(task.category, in: categories))
                    Text("·")
                    Text(task.isRecurring ? tr("recurring") : tr("filter_one_off"))
                }
                .font(.caption)
                .foregroundColor(.gray)
            }
            Spacer()
            if !isEditing {
                Button(tr("restore"), action: onRestore)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.bdAccent)
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .cardStyle()
    }
}
