import GregularScreens
import JavaScriptKit

/// Signing in: the server's address, then a password or Quick Connect, as
/// on Apple TV (`LoginModel` decides everything). Escape, or Cancel, goes
/// back to the main page when there's a server to go back to.
@MainActor final class LoginPage: Page, KeyTarget {
    let element = El("main", "page login")
    private let app: AppModel
    private let model: LoginModel
    private let content = El("div", "content")
    private let steps = El("div", "steps").attribute("aria-hidden", "true")
    private let notice = El("div")
    private let body = El("div", "content")
    private let error = El("div").attribute("role", "alert")
    private var stepKey = ""
    private var redraws: [Redraw] = []
    /// The current step's own redraws, stopped when it changes.
    private var stepRedraws: [Redraw] = []

    init(app: AppModel) {
        self.app = app
        model = app.makeLoginModel()
        let cancel = app.canCancelSignIn ? [El.button("Cancel", "quiet") { app.showMainPage() }] : []
        body.style("padding", "0")
        content.append(steps, notice, body, error)
        element.append(Parts.appBar(cancel), content, Parts.footer())
        redraws = [
            Redraw { [weak self] in self?.drawStep() },
            Redraw { [weak self] in self?.drawNotes() },
        ]
        Keys.take(self)
    }

    func close() {
        (redraws + stepRedraws).forEach { $0.stop() }
        // A Quick Connect code approved after this signs nothing in.
        model.stop()
        Keys.release(self)
    }

    func appeared() {
        Focus.focusable(in: body).first?.focus()
    }

    func press(_ button: RemoteButton) -> Bool {
        if button == .menu, app.canCancelSignIn {
            app.showMainPage()
            return true
        }
        guard let direction = button.direction, direction == .up || direction == .down else { return false }
        return Focus.move(direction, within: element)
    }

    private func drawNotes() {
        notice.replaceChildren(app.signedOutReason.map { [Parts.callout($0, kind: "warn", icon: .warning)] } ?? [])
        error.replaceChildren(model.errorMessage.map { [Parts.callout($0, kind: "danger", icon: .warning)] } ?? [])
    }

    /// A new form only when the step changes; the fields keep what's typed.
    private func drawStep() {
        let (key, number) = switch model.step {
        case .enterAddress, .connecting: ("address", 1)
        case .signIn(_, let name): ("signIn:" + name, 2)
        case .administrator(let name): ("administrator:" + name, 2)
        }
        guard key != stepKey else { return }
        stepKey = key
        stepRedraws.forEach { $0.stop() }
        stepRedraws = []
        steps.replaceChildren((1...2).map { El("span", $0 <= number ? "done" : "") })
        switch model.step {
        case .enterAddress, .connecting:
            body.replaceChildren(addressStep())
        case .signIn(_, let serverName):
            body.replaceChildren(signInStep(serverName: serverName))
        case .administrator(let serverName):
            body.replaceChildren(administratorStep(serverName: serverName))
        }
        // Focus the first field (or button) of the new step, once it's on the page.
        if element.object.isConnected.boolean == true { appeared() }
    }

    private func addressStep() -> [El] {
        // Text, not "url": an address without "https://" is fine here, and the model checks it.
        let field = textField("address", label: "Server address", placeholder: LoginModel.addressExample, value: model.address) { [model] in
            model.address = $0
        }
        field.input.attribute("autocomplete", "url").attribute("inputmode", "url")
        let connect = El("button", "button primary", text: "Connect").attribute("type", "submit")
        let form = El("form", "card", [field.wrapper, connect])
        submit(form) { [model] in await model.connect() }
        stepRedraws.append(Redraw { [model] in
            let connecting = if case .connecting = model.step { true } else { false }
            connect.object.disabled = .boolean(connecting)
            connect.text = connecting ? "Connecting…" : "Connect"
        })
        return [
            El("h1", "page-title", text: "Connect to your server"),
            El("p", "page-lede", text: LoginModel.addressPrompt + "."),
            form,
            Parts.callout(Self.httpNote, icon: .info),
        ]
    }

    private func signInStep(serverName: String) -> [El] {
        let note = El("div")
        let code = El("p", "quick-code").attribute("aria-label", "Quick Connect code")
        let codeHint = El("p", "note", text: LoginModel.quickConnectHint)
        let codeNote = El("p", "note")
        let waiting = Parts.spinner("Getting a Quick Connect code")
        let quickConnect = El("section", "card", [El("h2", text: "Quick Connect"), code, codeHint, codeNote, waiting])
        quickConnect.attribute("aria-live", "polite")

        let username = textField("username", label: "Username", placeholder: "", value: model.username) { [model] in model.username = $0 }
        username.input.attribute("autocomplete", "username")
        let password = textField("password", label: "Password", placeholder: "", value: "", kind: "password") { [model] in model.password = $0 }
        password.input.attribute("autocomplete", "current-password")
        let signIn = El("button", "button primary", text: "Sign In").attribute("type", "submit")
        let passwordForm = El("form", "card", [El("h2", text: "With a password"), username.wrapper, password.wrapper, signIn])
        submit(passwordForm) { [model] in await model.signInWithPassword() }

        stepRedraws.append(Redraw { [model] in
            note.replaceChildren(model.connectionNote.map { [Parts.callout($0, kind: "warn", icon: .lock)] } ?? [])
            code.text = model.quickConnectCode ?? ""
            code.hidden = model.quickConnectCode == nil
            codeHint.hidden = model.quickConnectCode == nil
            codeNote.text = model.quickConnectNote ?? ""
            codeNote.hidden = model.quickConnectCode != nil || model.quickConnectNote == nil
            waiting.hidden = model.quickConnectCode != nil || model.quickConnectNote != nil
            signIn.object.disabled = .boolean(model.username.isEmpty || model.isSigningIn)
            signIn.text = model.isSigningIn ? "Signing In…" : "Sign In"
            // The model forgets the password (changing server, stopping): so does the field.
            if model.password.isEmpty { password.input.object.value = "" }
        })
        return [
            El("div", "server-heading", [
                El("span", "avatar", [Icon.server.element]),
                El("div", [El("h1", "page-title", text: "Sign in"), El("p", "page-lede", text: serverName)]),
            ]),
            note,
            El("div", "sign-in-ways", [passwordForm, quickConnect]),
            El("div", "buttons", [El.button("Use a different server", "quiet") { [model] in model.changeServer() }]),
        ]
    }

    private func administratorStep(serverName: String) -> [El] {
        [
            El("h1", "page-title", text: "Sign in to \(serverName) as an administrator?"),
            Parts.callout(LoginModel.administratorWarning, kind: "warn", icon: .warning),
            El("div", "buttons", [
                El.button("Use Another Account", "primary") { [model] in Task { await model.useAnotherAccount() } },
                El.button("Sign In Anyway") { [model] in Task { await model.continueAsAdministrator() } },
            ]),
        ]
    }

    /// Which servers a browser can reach (`BrowserNetwork`).
    static let httpNote = "An https:// address works in any browser. A server on plain http:// works only on your home network, "
        + "and only in Chrome or Edge, which will ask to look for devices on your local network."

    // MARK: Fields

    /// A labelled field: the label is always shown, not just a placeholder.
    private func textField(_ id: String, label: String, placeholder: String, value: String, kind: String = "text",
                           onInput: @escaping @MainActor (String) -> Void) -> (wrapper: El, input: El) {
        let input = El("input")
        input.attribute("id", "field-" + id).attribute("type", kind).attribute("autocapitalize", "off")
            .attribute("autocorrect", "off").attribute("spellcheck", "false")
        if !placeholder.isEmpty { input.attribute("placeholder", placeholder) }
        input.object.value = .string(value)
        input.on("input") { event in onInput(event.target.value.string ?? "") }
        let wrapper = El("div", "field", [El("label", text: label).attribute("for", "field-" + id), input])
        return (wrapper, input)
    }

    private func submit(_ form: El, _ action: @escaping @MainActor () async -> Void) {
        form.attribute("novalidate", "")
        form.on("submit") { event in
            _ = event.preventDefault!()
            Task { await action() }
        }
    }
}
