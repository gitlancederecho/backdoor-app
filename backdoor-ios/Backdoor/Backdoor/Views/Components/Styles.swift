import SwiftUI

// MARK: - Colors

extension Color {
    static let bgPrimary  = Color(hex: "0a0a0a")
    static let bgCard     = Color(hex: "1a1a1a")
    static let bgElevated = Color(hex: "242424")
    static let bdBorder   = Color(hex: "2a2a2a")
    static let bdAccent   = Color(hex: "e8b84b")

    static let statusPending  = Color(hex: "ef4444")
    static let statusProgress = Color(hex: "eab308")
    static let statusDone     = Color(hex: "22c55e")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension TaskStatus {
    var color: Color {
        switch self {
        case .pending:     return .statusPending
        case .in_progress: return .statusProgress
        case .completed:   return .statusDone
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bdAccent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bgElevated)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bdBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - Card modifier

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.bdBorder, lineWidth: 1))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardModifier()) }
}

// MARK: - Input style

struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.bgCard)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.bdBorder, lineWidth: 1))
    }
}

extension View {
    func inputStyle() -> some View { modifier(InputStyle()) }
}
