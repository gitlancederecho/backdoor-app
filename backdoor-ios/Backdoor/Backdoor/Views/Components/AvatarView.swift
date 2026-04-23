import SwiftUI

struct AvatarView: View {
    let initials: String
    let url: String?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.bdBorder, lineWidth: 1))
    }

    private var initialsView: some View {
        ZStack {
            Color.bgElevated
            Text(initials)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

struct StatusDot: View {
    let status: TaskStatus
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
    }
}
