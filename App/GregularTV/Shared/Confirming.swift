import GregularScreens
import SwiftUI

extension View {
    /// Asks `confirmation` while `isPresented`: its action's button does
    /// `action`, and Cancel does nothing. GregularScreens decides what needs
    /// asking and what it says (see `Confirmation`).
    func confirming(_ confirmation: Confirmation?, isPresented: Binding<Bool>,
                    action: @escaping () -> Void) -> some View {
        confirmationDialog(confirmation?.question ?? "", isPresented: isPresented, titleVisibility: .visible,
                           presenting: confirmation) { confirmation in
            Button(confirmation.action, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.detail)
        }
    }
}
