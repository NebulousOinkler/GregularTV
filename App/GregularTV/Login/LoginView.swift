import GregularScreens
import SwiftUI

struct LoginView: View {
    @State private var model: LoginModel

    /// Shown above the form, for example "Your sign-in has expired".
    private let notice: String?
    /// Back to the main page, when there's a server to go back to (adding
    /// another). Menu does it too. Nil for the first server: then Menu
    /// leaves the app, as on the main page.
    private let onCancel: (() -> Void)?

    /// - Parameter model: from `AppModel.makeLoginModel()`, which signs in
    ///   with it and knows which server kind it's talking to.
    init(model: LoginModel, notice: String? = nil, onCancel: (() -> Void)? = nil) {
        self.notice = notice
        self.onCancel = onCancel
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 48) {
            Masthead()
            if let notice {
                Text(notice).foregroundStyle(.yellow).multilineTextAlignment(.center)
            }

            switch model.step {
            case .enterAddress, .connecting:
                addressForm
            case .signIn(_, let serverName):
                signInForms(serverName: serverName)
            case .administrator(let serverName):
                administratorWarning(serverName: serverName)
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if let onCancel {
                Button("Cancel", action: onCancel)
            }
        }
        .padding(80)
        .onExitCommand(perform: onCancel)
        // A Quick Connect code approved after this signs nothing in.
        .onDisappear { model.stop() }
    }

    private func administratorWarning(serverName: String) -> some View {
        VStack(spacing: 40) {
            Text("Sign in to \(serverName) as an administrator?").font(.title2)
            Text(LoginModel.administratorWarning)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 1200)
            HStack(spacing: 40) {
                Button("Use Another Account") { Task { await model.useAnotherAccount() } }
                Button("Sign In Anyway") { Task { await model.continueAsAdministrator() } }
            }
        }
    }

    private var addressForm: some View {
        VStack(spacing: 32) {
            Text(LoginModel.addressPrompt).font(.title3)
            TextField(LoginModel.addressExample, text: $model.address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { Task { await model.connect() } }
                .frame(maxWidth: 900)
            Button("Connect") { Task { await model.connect() } }
                .disabled(isConnecting)
            if isConnecting { ProgressView() }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = model.step { true } else { false }
    }

    private func signInForms(serverName: String) -> some View {
        VStack(spacing: 40) {
            Text("Sign in to \(serverName)").font(.title2)
            if let note = model.connectionNote {
                Label(note, systemImage: "lock.open").font(.callout).foregroundStyle(.yellow)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 1300)
            }

            HStack(alignment: .top, spacing: 120) {
                VStack(spacing: 24) {
                    Text("Quick Connect").font(.headline)
                    if let code = model.quickConnectCode {
                        Text(code)
                            .font(.system(size: 96, weight: .bold, design: .monospaced))
                        Text(LoginModel.quickConnectHint)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let note = model.quickConnectNote {
                        Text(note).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: 600)

                VStack(spacing: 24) {
                    Text("Password").font(.headline)
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                        .onSubmit { Task { await model.signInWithPassword() } }
                    Button("Sign In") { Task { await model.signInWithPassword() } }
                        .disabled(model.username.isEmpty || model.isSigningIn)
                }
                .frame(width: 600)
            }

            Button("Use a different server") { model.changeServer() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
}
