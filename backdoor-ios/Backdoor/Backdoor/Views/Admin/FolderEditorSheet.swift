import SwiftUI
import Supabase

/// Create / rename a folder. Creation uses `folder = nil`; editing
/// passes the existing row. Description is optional. No color picker
/// yet — the `color` column exists for a future tint affordance.
struct FolderEditorSheet: View {
    /// nil = creating a new folder.
    var folder: TaskFolder?
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
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

    private func save() async {
        isSaving = true
        error = nil
        do {
            if let f = folder {
                // Rename + description update. Description changes are
                // part of the rename path to keep one save action.
                try await adminVM.renameFolder(f, to: name)
                let cleaned = description.trimmingCharacters(in: .whitespaces)
                if cleaned != (f.description ?? "") {
                    try await supabase
                        .from("task_folders")
                        .update(TaskFolderPatch(description: cleaned.isEmpty ? "" : cleaned))
                        .eq("id", value: f.id)
                        .execute()
                }
            } else {
                try await adminVM.createFolder(name: name, description: description)
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
                                    .foregroundColor(.bdAccent)
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
