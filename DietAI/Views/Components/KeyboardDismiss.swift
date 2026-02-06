import SwiftUI

// MARK: - Keyboard Dismiss Helper
enum KeyboardDismiss {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Keyboard Dismiss Modifier
extension View {
    /// Dismisses the keyboard when tapping outside of text fields
    /// Uses a simultaneous gesture to avoid interfering with scrolling
    func dismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                KeyboardDismiss.dismiss()
            }
        )
    }

    /// Adds a toolbar button to dismiss keyboard
    func keyboardDismissToolbar() -> some View {
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    KeyboardDismiss.dismiss()
                }
            }
        }
    }

    /// Configures a ScrollView to dismiss keyboard on scroll and tap
    func keyboardDismissible() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
    }

    /// For Forms: adds both tap dismiss and keyboard toolbar
    func formKeyboardDismissible() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
            .dismissKeyboardOnTap()
    }
}

// MARK: - Keyboard Dismissing Container
/// A container view that dismisses keyboard on background tap
struct KeyboardDismissingView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                KeyboardDismiss.dismiss()
            }
    }
}
