/// Setting focus in the same update that shows a screen can fail, leaving
/// whatever tvOS chose (or nothing). Screens that move focus as they appear
/// wait this long first.
enum FocusSettling {
    static func wait() async {
        try? await Task.sleep(for: .milliseconds(100))
    }
}
