import Foundation

/// First-launch welcome alert strings. Rust `welcome_copy` is authority.
/// Rule: `wawona-welcome-alert`.
public enum WelcomeCopy {
    /// Fallback when the domain staticlib is not linked (unit tests / previews).
    private static let fallbackTitle = "Welcome to Wawona"
    private static let fallbackMessage =
        "A Universal Wayland Compositor. Tap '+' to add a Machine."
    private static let fallbackContinue = "Continue"

    public static var title: String {
        #if os(watchOS)
        fallbackTitle
        #else
        WawonaDomainBridge.welcomeTitle() ?? fallbackTitle
        #endif
    }

    public static var message: String {
        #if os(watchOS)
        fallbackMessage
        #else
        WawonaDomainBridge.welcomeMessage() ?? fallbackMessage
        #endif
    }

    public static var continueLabel: String {
        #if os(watchOS)
        fallbackContinue
        #else
        WawonaDomainBridge.welcomeContinue() ?? fallbackContinue
        #endif
    }
}
