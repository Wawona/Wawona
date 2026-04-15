import SwiftUI

struct AdaptiveNavigationView<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    init(@ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        #if os(iOS)
        NavigationStack { detail }
        #else
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        #endif
    }
}
