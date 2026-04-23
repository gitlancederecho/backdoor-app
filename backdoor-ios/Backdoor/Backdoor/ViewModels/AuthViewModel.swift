import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AuthViewModel {
    var session: Session?
    var staff: Staff?
    var isLoading = true
    var error: String?

    var isSignedIn: Bool { session != nil }
    var isAdmin: Bool { staff?.role == .admin }

    init() {
        Task { await start() }
    }

    private func start() async {
        // Restore existing session
        session = try? await supabase.auth.session
        if let uid = session?.user.id {
            await loadStaff(uid: uid)
        }
        isLoading = false

        // Listen for auth state changes
        for await (event, newSession) in supabase.auth.authStateChanges {
            switch event {
            case .signedIn, .tokenRefreshed, .userUpdated:
                session = newSession
                if let uid = newSession?.user.id { await loadStaff(uid: uid) }
            case .signedOut:
                session = nil
                staff = nil
            default:
                break
            }
        }
    }

    private func loadStaff(uid: UUID) async {
        let results: [Staff] = (try? await supabase
            .from("staff")
            .select()
            .eq("auth_user_id", value: uid)
            .limit(1)
            .execute()
            .value) ?? []
        staff = results.first
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, name: String) async throws {
        // Pass `name` so the handle_new_auth_user trigger can seed staff.name correctly.
        _ = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["name": .string(name)]
        )
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    func refreshStaff() async {
        if let uid = session?.user.id { await loadStaff(uid: uid) }
    }

    // MARK: - Profile editing

    private struct NamePatch: Encodable { var name: String }
    private struct AvatarPatch: Encodable { var avatarUrl: String }

    /// Update the current user's profile. Pass nil to leave a field untouched.
    func updateOwnProfile(name: String?, avatarUrl: String?) async throws {
        guard let staffId = staff?.id else { return }

        if let name, !name.isEmpty {
            try await supabase
                .from("staff")
                .update(NamePatch(name: name))
                .eq("id", value: staffId)
                .execute()
        }
        if let avatarUrl, !avatarUrl.isEmpty {
            try await supabase
                .from("staff")
                .update(AvatarPatch(avatarUrl: avatarUrl))
                .eq("id", value: staffId)
                .execute()
        }
        await refreshStaff()
    }

    func uploadAvatar(imageData: Data, mimeType: String = "image/jpeg") async throws -> String {
        guard let staffId = staff?.id else {
            throw NSError(domain: "AuthViewModel", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let ext = mimeType.contains("png") ? "png" : "jpg"
        let path = "avatars/\(staffId)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        try await supabase.storage
            .from(photoBucket)
            .upload(path, data: imageData,
                    options: FileOptions(contentType: mimeType, upsert: true))
        let publicUrl = try supabase.storage
            .from(photoBucket)
            .getPublicURL(path: path)
        return publicUrl.absoluteString
    }
}
