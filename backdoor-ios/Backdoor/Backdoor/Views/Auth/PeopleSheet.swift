import SwiftUI
import Supabase

/// Social-media-style people search. Lists every active staff member
/// with a search bar pinned to the top; tapping a row opens their
/// read-only StaffProfileView. Admins can still manage staff from the
/// Admin → Staff tab — this sheet is for peer-to-peer discovery.
struct PeopleSheet: View {
    @Environment(LanguageManager.self) private var lang
    @Environment(\.dismiss) private var dismiss

    @State private var allStaff: [Staff] = []
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var selectedPeer: Staff?

    private var filtered: [Staff] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let base = allStaff.filter { $0.isActive }
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.email.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        let _ = lang.current
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchField(prompt: tr("search_staff"), text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider().background(Color.bdBorder)

                    if filtered.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "person.2")
                                .font(.system(size: 36))
                                .foregroundColor(.gray.opacity(0.6))
                            Text(tr("people_empty"))
                                .font(.subheadline).foregroundColor(.gray)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(filtered) { person in
                                    Button {
                                        selectedPeer = person
                                    } label: {
                                        PersonRow(staff: person)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                }
                                Spacer().frame(height: 24)
                            }
                            .padding(.top, 12)
                        }
                        .refreshable { await load() }
                    }
                }
            }
            .navigationTitle(tr("people_title"))
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
        .task { await load() }
        .sheet(item: $selectedPeer) { peer in
            StaffProfileView(staff: peer).environment(lang)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let rows: [Staff] = (try? await supabase
            .from("staff")
            .select()
            .order("name")
            .execute()
            .value) ?? []
        allStaff = rows
    }
}

private struct PersonRow: View {
    let staff: Staff
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        let _ = lang.current
        HStack(spacing: 12) {
            AvatarView(initials: staff.initials, url: staff.avatarUrl, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(staff.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    if staff.role == .admin {
                        Text(tr("role_admin"))
                            .font(.caption2.weight(.semibold)).foregroundColor(.bdAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.bdAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(staff.email)
                    .font(.caption).foregroundColor(.gray).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundColor(.gray.opacity(0.5))
        }
        .padding(14)
        .cardStyle()
    }
}
