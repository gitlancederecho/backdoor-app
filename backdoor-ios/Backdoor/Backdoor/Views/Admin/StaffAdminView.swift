import SwiftUI

struct StaffAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang
    @State private var editingStaff: Staff?

    var body: some View {
        let _ = lang.current
        ScrollView {
            LazyVStack(spacing: 8) {
                Text(tr("staff_signup_hint"))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                ForEach(adminVM.allStaff) { member in
                    StaffRow(
                        staff: member,
                        onToggleRole: { Task { try? await adminVM.setRole(member, role: member.role == .admin ? .staff : .admin) } },
                        onToggleActive: { Task { try? await adminVM.toggleActive(member) } },
                        onEdit: { editingStaff = member }
                    )
                    .padding(.horizontal, 16)
                }
                Spacer().frame(height: 24)
            }
            .padding(.top, 12)
        }
        .sheet(item: $editingStaff) { staff in
            EditStaffSheet(staff: staff, adminVM: adminVM)
                .environment(lang)
        }
    }
}

private struct StaffRow: View {
    let staff: Staff
    let onToggleRole: () -> Void
    let onToggleActive: () -> Void
    let onEdit: () -> Void
    @Environment(LanguageManager.self) private var lang

    private var roleLabel: String {
        staff.role == .admin ? tr("role_admin") : tr("role_staff")
    }

    var body: some View {
        let _ = lang.current
        HStack(spacing: 12) {
            AvatarView(initials: staff.initials, url: staff.avatarUrl, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(staff.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(staff.email)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(roleLabel, action: onToggleRole)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(staff.role == .admin ? Color.bdAccent.opacity(0.15) : Color.bgElevated)
                    .foregroundColor(staff.role == .admin ? .bdAccent : .gray)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(staff.role == .admin ? Color.bdAccent.opacity(0.4) : Color.bdBorder))

                Button(staff.isActive ? tr("active") : tr("inactive"), action: onToggleActive)
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.bgElevated)
                    .foregroundColor(staff.isActive ? .gray : .statusPending)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(staff.isActive ? Color.bdBorder : Color.statusPending.opacity(0.4)))

                Button(tr("edit"), action: onEdit)
                    .font(.caption)
                    .foregroundColor(.bdAccent)
            }
        }
        .padding(14)
        .cardStyle()
    }
}

private struct EditStaffSheet: View {
    let staff: Staff
    @Bindable var adminVM: AdminViewModel
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("name")).font(.caption).foregroundColor(.gray)
                        TextField(tr("name"), text: $name).inputStyle()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    Spacer()
                }
            }
            .navigationTitle(tr("edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("cancel")) { dismiss() }.foregroundColor(.gray)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("save")) {
                        Task {
                            isSaving = true
                            try? await adminVM.updateStaffName(staff, name: name)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .foregroundColor(.bdAccent)
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { name = staff.name }
    }
}
