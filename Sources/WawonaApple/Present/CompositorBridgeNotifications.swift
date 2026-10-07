import Foundation

extension Notification.Name {
    public static let WWNNativeClientWillLaunch =
        Notification.Name("WWNNativeClientWillLaunchNotification")
    public static let WWNClientMinimizeRequested =
        Notification.Name("WWNClientMinimizeRequestedNotification")
    public static let WWNClientFocusRequested =
        Notification.Name("WWNClientFocusRequestedNotification")
    public static let WWNHostWindowsDidChange =
        Notification.Name("WWNHostWindowsDidChangeNotification")
    public static let WWNClientSelectionDidChange =
        Notification.Name("WWNClientSelectionDidChangeNotification")
}

#if os(iOS) || os(tvOS) || os(visionOS)
public let WWNClientWindowSceneActivityType = "com.aspauldingcode.wawona.client-window-scene"
public let WWNClientWindowSceneWindowIdKey = "WWNClientWindowSceneWindowIdKey"
#endif
