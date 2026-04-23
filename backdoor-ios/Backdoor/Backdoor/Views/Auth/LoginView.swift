import SwiftUI

enum AuthMode {
    case signIn, signUp
}

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(LanguageManager.self) private var lang
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var successMessage: String?

    private var isSignUp: Bool { mode == .signUp }

    private var canSubmit: Bool {
        !email.isEmpty
            && password.count >= 6
            && (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        let _ = lang.current
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 80)

                    // Logo
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.bgCard)
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.bdBorder))
                                .frame(width: 72, height: 72)
                            Text("B")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.bdAccent)
                        }
                        Text("The Backdoor")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text(isSignUp ? tr("app_subtitle_signup") : tr("app_subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Spacer().frame(height: 32)

                    // Language toggle (top of screen, before any input)
                    Menu {
                        ForEach(AppLanguage.allCases) { l in
                            Button {
                                lang.current = l
                            } label: {
                                if lang.current == l {
                                    Label(l.label, systemImage: "checkmark")
                                } else {
                                    Text(l.label)
                                }
                            }
                        }
                    } label: {
                        Label(lang.current.label, systemImage: "globe")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.bgCard)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.bdBorder))
                    }

                    Spacer().frame(height: 16)

                    // Mode toggle (capsule segment)
                    HStack(spacing: 0) {
                        modeButton(title: tr("sign_in"), mode: .signIn)
                        modeButton(title: tr("sign_up"), mode: .signUp)
                    }
                    .padding(4)
                    .background(Color.bgCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.bdBorder))
                    .padding(.horizontal, 24)

                    Spacer().frame(height: 24)

                    // Form
                    VStack(spacing: 12) {
                        if isSignUp {
                            TextField(tr("your_name"), text: $name)
                                .textContentType(.name)
                                .autocapitalization(.words)
                                .inputStyle()
                        }

                        TextField(tr("email"), text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .inputStyle()

                        SecureField(isSignUp ? tr("password_signup") : tr("password"), text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .inputStyle()

                        if let error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.statusPending)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        if let successMessage {
                            Text(successMessage)
                                .font(.caption)
                                .foregroundColor(.statusDone)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            if isLoading {
                                ProgressView().tint(.black)
                            } else {
                                Text(isSignUp ? tr("create_account") : tr("sign_in"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoading || !canSubmit)
                        .padding(.top, 4)

                        if isSignUp {
                            Text(tr("signup_note"))
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func modeButton(title: String, mode buttonMode: AuthMode) -> some View {
        let selected = mode == buttonMode
        Button(title) {
            withAnimation(.easeInOut(duration: 0.15)) {
                mode = buttonMode
                error = nil
                successMessage = nil
            }
        }
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .foregroundColor(selected ? .black : .gray)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(selected ? Color.bdAccent : Color.clear)
        .clipShape(Capsule())
    }

    private func submit() async {
        isLoading = true
        error = nil
        successMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: trimmedEmail, password: password)
            case .signUp:
                try await auth.signUp(email: trimmedEmail, password: password, name: trimmedName)
                if !auth.isSignedIn {
                    successMessage = tr("check_email")
                    mode = .signIn
                    password = ""
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
