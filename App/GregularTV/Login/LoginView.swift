import GregularScreens
import SwiftUI

struct LoginView: View {
    @State private var model: LoginModel

    /// Shown above the form, for example "Your sign-in has expired".
    private let notice: String?

    /// - Parameter model: from `AppModel.makeLoginModel()`, which signs in
    ///   with it and knows which server kind it's talking to.
    init(model: LoginModel, notice: String? = nil) {
        self.notice = notice
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 48) {
            Text("Gregular TV").font(.system(size: 80, weight: .heavy, design: .rounded))
            Text("We now return to your Gregular programming.").font(.title3).foregroundStyle(.secondary)
            if let notice {
                Text(notice).foregroundStyle(.yellow).multilineTextAlignment(.center)
            }

            switch model.step {
            case .enterAddress, .connecting:
                addressForm
            case .signIn(_, let serverName):
                signInForms(serverName: serverName)
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(80)
    }

    private var addressForm: some View {
        VStack(spacing: 32) {
            Text("Enter your Jellyfin server address").font(.title3)
            TextField("e.g. 192.168.1.10:8096", text: $model.address)
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

            HStack(alignment: .top, spacing: 120) {
                VStack(spacing: 24) {
                    Text("Quick Connect").font(.headline)
                    if let code = model.quickConnectCode {
                        Text(code)
                            .font(.system(size: 96, weight: .bold, design: .monospaced))
                        Text("In another Jellyfin app, open your profile ▸ Quick Connect and enter this code.")
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
