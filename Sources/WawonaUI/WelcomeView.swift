import SwiftUI
import WawonaModel

/// First-launch welcome as a **native alert**, not a full-screen page.
///
/// macOS: SwiftUI `.alert` (AppKit `NSAlert` under the hood).
/// iOS / iPadOS / tvOS / visionOS: the same SwiftUI alert chrome.
/// watchOS: same pattern in `WawonaWatchRootView` (Watch does not link WawonaUI).
struct WelcomeAlertModifier: ViewModifier {
    @ObservedObject var preferences: WawonaPreferences
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert("Welcome to Wawona", isPresented: $isPresented) {
                Button("Continue") {
                    preferences.hasCompletedWelcome = true
                    preferences.save()
                    isPresented = false
                }
                .accessibilityIdentifier(WawonaA11y.welcomeContinue)
            } message: {
                Text(
                    "One control surface for macOS, iOS, iPadOS, tvOS, visionOS, watchOS, and Android. Add a machine when you are ready."
                )
            }
    }
}

extension View {
    /// Present the first-launch welcome as a system alert over Machines.
    func wawonaWelcomeAlert(
        preferences: WawonaPreferences,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(WelcomeAlertModifier(preferences: preferences, isPresented: isPresented))
    }
}
