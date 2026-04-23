import SwiftUI

/// Compact search input styled to match the existing filter pills.
/// Leading magnifying-glass icon, trailing clear button when there's
/// text. Designed to be dropped into admin filter bars.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(.gray)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(.gray))
                .font(.subheadline)
                .foregroundColor(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(.gray.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
