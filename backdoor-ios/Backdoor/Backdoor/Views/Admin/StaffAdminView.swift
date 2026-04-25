import SwiftUI

enum StaffRoleFilter: Hashable { case all, admins, staffOnly }
enum StaffStatusFilter: Hashable { case all, active, inactive }

struct StaffAdminView: View {
    @Bindable var adminVM: AdminViewModel
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss
    @State private var editingStaff: Staff?

    // Filters
    @State private var searchText: String = ""
    @State private var roleFilter: StaffRoleFilter = .all
    @State private var statusFilter: StaffStatusFilter = .all

    // Edit mode + selection
    @State private var editMode: EditMode = .inactive
    @State private var selectedIds: Set<UUID> = []
    @State private var showBulkDeactivateConfirm = false
    @State private var showBulkActivateConfirm = false

    private var filteredStaff: [Staff] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return adminVM.allStaff.filter { s in
            switch roleFilter {
            case .all: break
            case .admins:    if s.role != .admin { return false }
            case .staffOnly: if s.role != .staff { return false }
            }
            switch statusFilter {
            case .all: break
            case .active:   if !s.isActive { return false }
            case .inactive: if s.isActive  { return false }
            }
            if !q.isEmpty {
                let nameMatch = s.name.localizedCaseInsensitiveContains(q)
                let emailMatch = s.email.localizedCaseInsensitiveContains(q)
                if !nameMatch && !emailMatch { return false }
            }
            return true
        }
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider().background(Color.bdBorder)
                    staffList
                    if editMode.isEditing, !effectiveSelection.isEmpty {
                        bulkActionBar
                    }
                }
            }
            .navigationTitle(tr("admin_staff"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCard, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("close")) { dismiss() }.foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editingStaff) { staff in
            EditStaffSheet(staff: staff, adminVM: adminVM)
                .environment(lang)
        }
        .alert(
            tr("deactivate_staff_confirm"),
            isPresented: $showBulkDeactivateConfirm,
            presenting: effectiveSelection
        ) { ids in
            Button(String(format: tr("deactivate_n"), ids.count), role: .destructive) {
                Task {
                    await adminVM.bulkSetStaffActive(
                        ids: ids, to: false, excludingSelf: auth.staff?.id
                    )
                    selectedIds = []
                    editMode = .inactive
                }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: { ids in
            Text(String(format: tr("deactivate_staff_message"), ids.count))
        }
        .alert(
            tr("activate_staff_confirm"),
            isPresented: $showBulkActivateConfirm,
            presenting: effectiveSelection
        ) { ids in
            Button(String(format: tr("activate_n"), ids.count)) {
                Task {
                    await adminVM.bulkSetStaffActive(
                        ids: ids, to: true, excludingSelf: auth.staff?.id
                    )
                    selectedIds = []
                    editMode = .inactive
                }
            }
            Button(tr("cancel"), role: .cancel) {}
        } message: { ids in
            Text(String(format: tr("activate_staff_message"), ids.count))
        }
    }

    // MARK: - List

    private var staffList: some View {
        List(selection: $selectedIds) {
            // Signup hint rides with the scroll, so filters at the
            // top remain pinned.
            Text(tr("staff_signup_hint"))
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .selectionDisabled()

            ForEach(filteredStaff) { member in
                StaffRow(
                    staff: member,
                    isSelf: member.id == auth.staff?.id,
                    isEditing: editMode.isEditing,
                    onToggleRole: { Task { try? await adminVM.setRole(member, role: member.role == .admin ? .staff : .admin) } },
                    onToggleActive: { Task { try? await adminVM.toggleActive(member) } },
                    onEdit: { editingStaff = member }
                )
                .tag(member.id)
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

    // MARK: - Bulk action bar

    /// Selection excluding the caller's own row — the bulk actions
    /// (especially Deactivate) can't target self, so we filter client-
    /// side too for clear affordance labels.
    private var effectiveSelection: [UUID] {
        selectedIds.subtracting(auth.staff.map { [$0.id] } ?? []).map { $0 }
    }

    private var bulkActionBar: some View {
        // Select-all excludes the caller's own row (same rule as
        // `effectiveSelection`) so the label always reflects what
        // the bulk activate/deactivate actions would actually touch.
        let selectableIds = Set(filteredStaff.map(\.id))
            .subtracting(auth.staff.map { [$0.id] } ?? [])
        let allSelected = !selectableIds.isEmpty && selectableIds.isSubset(of: selectedIds)
        return HStack(spacing: 10) {
            Button {
                if allSelected {
                    selectedIds.subtract(selectableIds)
                } else {
                    selectedIds.formUnion(selectableIds)
                }
            } label: {
                Text(allSelected ? tr("deselect_all") : tr("select_all"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.bdAccent)
            }
            .buttonStyle(.plain)
            .disabled(selectableIds.isEmpty)

            Text(String(format: tr("selected_count"), effectiveSelection.count))
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Button {
                showBulkActivateConfirm = true
            } label: {
                Label(tr("activate"), systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bdAccent)
            }
            Button {
                showBulkDeactivateConfirm = true
            } label: {
                Label(tr("deactivate"), systemImage: "slash.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.statusPending)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgCard)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.bdBorder), alignment: .top)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SearchField(prompt: tr("search_staff"), text: $searchText)
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
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.bdAccent)
            }

            // Role pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterPill(label: tr("role_all"),
                               isSelected: roleFilter == .all) {
                        roleFilter = .all
                    }
                    FilterPill(label: tr("role_admins"),
                               isSelected: roleFilter == .admins) {
                        roleFilter = .admins
                    }
                    FilterPill(label: tr("role_staff_only"),
                               isSelected: roleFilter == .staffOnly) {
                        roleFilter = .staffOnly
                    }
                }
            }

            // Status pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterPill(label: tr("status_all"),
                               isSelected: statusFilter == .all) {
                        statusFilter = .all
                    }
                    FilterPill(label: tr("status_active"),
                               isSelected: statusFilter == .active) {
                        statusFilter = .active
                    }
                    FilterPill(label: tr("status_inactive"),
                               isSelected: statusFilter == .inactive) {
                        statusFilter = .inactive
                    }
                }
            }
        }
    }
}

private struct StaffRow: View {
    let staff: Staff
    let isSelf: Bool
    let isEditing: Bool
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

            if isEditing {
                // In edit mode the List shows the selection circle.
                // Show a subtle "(you)" tag on the caller's own row
                // since their selection is ignored by the bulk actions.
                if isSelf {
                    Text(tr("you_self_tag"))
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            } else {
                // Per-row buttons need borderless style so each is
                // tappable individually inside a List row (otherwise
                // SwiftUI collapses the whole row into a single tap
                // target and tap events land on the wrong button —
                // or none at all).
                HStack(spacing: 8) {
                    Button(roleLabel, action: onToggleRole)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(staff.role == .admin ? Color.bdAccent.opacity(0.15) : Color.bgElevated)
                        .foregroundColor(staff.role == .admin ? .bdAccent : .gray)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(staff.role == .admin ? Color.bdAccent.opacity(0.4) : Color.bdBorder))
                        .buttonStyle(.borderless)

                    Button(staff.isActive ? tr("active") : tr("inactive"), action: onToggleActive)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.bgElevated)
                        .foregroundColor(staff.isActive ? .gray : .statusPending)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(staff.isActive ? Color.bdBorder : Color.statusPending.opacity(0.4)))
                        .buttonStyle(.borderless)

                    Button(tr("edit"), action: onEdit)
                        .font(.caption)
                        .foregroundColor(.bdAccent)
                        .buttonStyle(.borderless)
                }
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
