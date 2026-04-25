import SwiftUI
import Supabase

/// Create / rename a folder. Creation uses `folder = nil`; editing
/// passes the existing row.
struct FolderEditorSheet: View {
    /// nil = creating a new folder.
    var folder: TaskFolder?
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    /// Selected hex string from the `FolderTint` palette. nil = use
    /// the default app accent.
    @State private var selectedColor: String?
    @State private var isSaving = false
    @State private var error: String?

    private var isEditing: Bool { folder != nil }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(tr("folder_name")) {
                            TextField(tr("folder_name"), text: $name).inputStyle()
                        }
                        field(tr("folder_description")) {
                            TextField(tr("folder_description"), text: $description).inputStyle()
                        }
                        field(tr("color")) {
                            colorPicker
                        }
                        if let error {
                            Text(error).font(.caption).foregroundColor(.statusPending)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(isEditing ? tr("edit_folder") : tr("new_folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("save")) { Task { await save() } }
                        .foregroundColor(.bdAccent)
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let f = folder {
                name = f.name
                description = f.description ?? ""
                selectedColor = f.color
            } else {
                // New folder defaults to the app accent so the swatch
                // shows a checkmark from the start (no "no color"
                // ambiguous state).
                selectedColor = FolderTint.gold.rawValue
            }
        }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundColor(.gray)
            content()
        }
    }

    /// Horizontal swatch picker. Each tint is a 32pt circle with a
    /// thicker stroke when selected. Defaults to `.gold` (the app
    /// accent) when nothing's been chosen yet.
    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(FolderTint.allCases) { tint in
                let isSelected = (selectedColor ?? FolderTint.gold.rawValue) == tint.rawValue
                Button {
                    selectedColor = tint.rawValue
                } label: {
                    Circle()
                        .fill(tint.color)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.white : Color.bdBorder,
                                        lineWidth: isSelected ? 2 : 1)
                        )
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.black)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tint.rawValue)
            }
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            if let f = folder {
                // Rename + description + color update — bundled into
                // one save action. Description / color changes pass
                // through `TaskFolderPatch` directly since neither
                // has the nullable-omits-on-encode trap (we always
                // send a real String, just possibly empty).
                try await adminVM.renameFolder(f, to: name)
                let cleaned = description.trimmingCharacters(in: .whitespaces)
                if cleaned != (f.description ?? "") {
                    try await supabase
                        .from("task_folders")
                        .update(TaskFolderPatch(description: cleaned.isEmpty ? "" : cleaned))
                        .eq("id", value: f.id)
                        .execute()
                }
                if selectedColor != f.color {
                    try await supabase
                        .from("task_folders")
                        .update(TaskFolderPatch(color: selectedColor))
                        .eq("id", value: f.id)
                        .execute()
                }
                await adminVM.fetchAll()
            } else {
                try await adminVM.createFolder(
                    name: name,
                    description: description,
                    color: selectedColor
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

/// Sheet for picking a destination folder (or "Unfiled") when bulk-
/// moving tasks. `currentFolderId` = the folder we're moving from
/// (so it's hidden from the list — no-op to move in place).
struct MoveToFolderPicker: View {
    let currentFolderId: UUID?
    let folders: [TaskFolder]
    let onPick: (UUID?) -> Void

    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                List {
                    // "Unfiled" row — only shown when we're not already in Unfiled.
                    if currentFolderId != nil {
                        Button {
                            onPick(nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "tray")
                                    .foregroundColor(.gray)
                                Text(tr("unfiled"))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.bgCard)
                    }

                    ForEach(folders.filter { $0.id != currentFolderId }) { f in
                        Button {
                            onPick(f.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(FolderTint.color(forStored: f.color))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).foregroundColor(.white)
                                    if let desc = f.description, !desc.isEmpty {
                                        Text(desc).font(.caption).foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.bgCard)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(tr("move_to_folder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
