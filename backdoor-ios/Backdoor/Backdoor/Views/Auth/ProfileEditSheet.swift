import SwiftUI
import PhotosUI

struct ProfileEditSheet: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var uploadedPhotoData: Data?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 24) {
                    // Avatar + picker
                    VStack(spacing: 12) {
                        ZStack {
                            if let previewImage {
                                previewImage
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(
                                    initials: auth.staff?.initials ?? "?",
                                    url: auth.staff?.avatarUrl,
                                    size: 96
                                )
                            }
                        }
                        .overlay(Circle().stroke(Color.bdBorder, lineWidth: 1))

                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Text(tr("change_photo"))
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.bdAccent)
                        }
                    }
                    .padding(.top, 20)

                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("name")).font(.caption).foregroundColor(.gray)
                        TextField(tr("your_name"), text: $name).inputStyle()
                    }
                    .padding(.horizontal, 20)

                    // Email (read-only)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("email")).font(.caption).foregroundColor(.gray)
                        Text(auth.staff?.email ?? "—")
                            .font(.system(size: 15))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 20)

                    if let error {
                        Text(error).font(.caption).foregroundColor(.statusPending)
                    }

                    Spacer()
                }
            }
            .navigationTitle(tr("profile"))
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
        .onAppear { name = auth.staff?.name ?? "" }
        .onChange(of: pickedPhoto) { _, item in
            Task { await loadPreview(item) }
        }
    }

    private func loadPreview(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            uploadedPhotoData = data
            previewImage = Image(uiImage: uiImage)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        do {
            var avatarUrl: String? = nil
            if let data = uploadedPhotoData {
                avatarUrl = try await auth.uploadAvatar(imageData: data)
            }
            try await auth.updateOwnProfile(
                name: name.trimmingCharacters(in: .whitespaces),
                avatarUrl: avatarUrl  // nil = don't change
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
