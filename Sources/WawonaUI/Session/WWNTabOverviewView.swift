#if os(iOS) || os(visionOS) || os(macOS) || os(tvOS)
import SwiftUI

/// Demoted List host. Product Tab Overview is Safari Exposé
/// (`WWNClientTabExposeView` via `WWNMainRouter.showTabOverview`).
struct WWNTabOverviewView: View {
    var body: some View {
        Color.clear
            .backport.navigationTitle("Tab Overview")
            .accessibility(hidden: true)
    }
}
#endif
