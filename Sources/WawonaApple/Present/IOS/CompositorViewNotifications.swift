#if canImport(UIKit) && !os(watchOS)
import Foundation

public let WWNHostKeyboardGeometryDidChangeNotification =
    Notification.Name("WWNHostKeyboardGeometryDidChangeNotification")
public let WWNTvRequestSessionExitNotification =
    Notification.Name("WWNTvRequestSessionExitNotification")
public let WWNTvKeyboardFocusDidChangeNotification =
    Notification.Name("WWNTvKeyboardFocusDidChangeNotification")
public let WWNRequestSelectTabAtIndexNotification =
    Notification.Name("WWNRequestSelectTabAtIndexNotification")
public let WWNRequestSelectNextTabNotification =
    Notification.Name("WWNRequestSelectNextTabNotification")
public let WWNRequestSelectPreviousTabNotification =
    Notification.Name("WWNRequestSelectPreviousTabNotification")
public let WWNRequestToggleTabExposeNotification =
    Notification.Name("WWNRequestToggleTabExposeNotification")
public let WWNRequestNewTabNotification =
    Notification.Name("WWNRequestNewTabNotification")
public let WWNRequestCloseActiveTabNotification =
    Notification.Name("WWNRequestCloseActiveTabNotification")
#endif
