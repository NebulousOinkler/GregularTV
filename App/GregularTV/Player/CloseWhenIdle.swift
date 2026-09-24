import SwiftUI

extension View {
    /// Closes an on-screen menu after `timeout` without activity, like a TV's
    /// channel list or guide. Pass what changes on activity, such as the
    /// focused item. Each change restarts the countdown.
    func closeWhenIdle(after timeout: Duration, activity: some Equatable, perform close: @escaping () -> Void) -> some View {
        task(id: activity) {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            close()
        }
    }
}
