import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @FocusState private var focus: Field?
    enum Field { case name, email, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text("Vnua-connect")
                        .font(VnuaFont.font(.largeTitle, .bold))
                    Text("Giving clubs a chance. Find new student groups at \(app.campus.name), join or help found one, and check in at events.")
                        .font(VnuaFont.font(.body))
                        .foregroundStyle(Palette.secondaryText)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 16) {
                    field("Your name", text: $name, field: .name)
                        .textContentType(.name)
                        .submitLabel(.next)
                    field("School email", text: $email, field: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .disabled(codeSent)

                    if codeSent {
                        field("6-digit code", text: $code, field: .code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                        Text(app.isDemo ? "Demo mode: any 6 digits work." : "We emailed a 6-digit code to \(email). It can take a minute, so check spam too. Codes expire after 10 minutes.")
                            .font(VnuaFont.font(.footnote))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                VStack(spacing: 12) {
                    Button(action: submit) {
                        if busy { ProgressView().tint(Palette.onAccent) }
                        else { Text(codeSent ? "Verify and continue" : "Email me a code") }
                    }
                    .buttonStyle(.vnuaPrimary)
                    .disabled(busy || !canSubmit)

                    if codeSent {
                        Button("Use a different email") { codeSent = false; code = "" }
                            .buttonStyle(.vnuaSecondary)
                    }
                }

                Text(app.isDemo ? "Demo mode: all clubs and events are fictional. Not affiliated with or endorsed by \(app.campus.name)." : "Vnua-connect is student-run and not affiliated with or endorsed by \(app.campus.name).")
                    .font(VnuaFont.font(.caption))
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .onSubmit {
            switch focus {
            case .name: focus = .email
            default: submit()
            }
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && email.contains("@") && (!codeSent || (6...8).contains(code.count))
    }

    private func field(_ title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(VnuaFont.font(.subheadline, .medium))
            TextField(title, text: text)
                .font(VnuaFont.font(.body))
                .focused($focus, equals: field)
                .padding(.horizontal, 14)
                .frame(minHeight: Metrics.minTap + 4)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(focus == field ? Palette.accent : Palette.divider, lineWidth: focus == field ? 2 : 1))
        }
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            if !codeSent {
                if await app.run({ try await app.api.requestCode(email: email, name: name, campus: app.campus) }) != nil {
                    codeSent = true
                    focus = .code
                }
            } else if let profile = await app.run({
                try await app.api.verify(email: email, name: name, code: code, campus: app.campus)
            }) {
                await app.signedIn(profile)
            }
        }
    }
}

#Preview {
    SignInView().environment(AppState(api: MockAPI()))
}
