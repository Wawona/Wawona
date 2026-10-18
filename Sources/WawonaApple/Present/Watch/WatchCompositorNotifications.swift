#if os(watchOS)
import Foundation

public let WWNWatchCompositorFrameReadyNotification =
    Notification.Name("WWNWatchCompositorFrameReadyNotification")
/// `userInfo["front"]` is true while a Wayland client is connected.
/// Terminal parks so the client surface is the visible tab.
public let WWNWatchClientSurfaceNotification =
    Notification.Name("WWNWatchClientSurfaceNotification")
public let WWNGuestConsoleOutputNotification =
    Notification.Name("WWNGuestConsoleOutputNotification")
#endif
