#if os(watchOS)
import Foundation

/// Wrist stand-in for the Machines sidebar: Machines, Tab Overview, and one
/// page per machine tag.
enum WatchHomePage: Hashable {
    case machines
    case tabOverview
    case tag(String)
}

/// Pushed from the gear. Item destination lives on the NavigationStack
/// content. A sheet keeps the Machines toolbar over the settings rows.
enum WatchSettingsRoute: Hashable {
    case global
}
#endif
