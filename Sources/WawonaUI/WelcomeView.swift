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
        // iOS 13 Alert API (not the iOS 15+ ViewBuilder alert). Button title
        // "Continue" remains the agent-device press target; WawonaA11y.welcomeContinue
        // cannot attach to Alert actions below iOS 14.
        content.alert(isPresented: $isPresented) {
            Alert(
                title: Text(WelcomeCopy.title),
                message: Text(WelcomeCopy.message),
                dismissButton: .default(Text(WelcomeCopy.continueLabel)) {
                    preferences.hasCompletedWelcome = true
                    preferences.save()
                    isPresented = false
                }
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
