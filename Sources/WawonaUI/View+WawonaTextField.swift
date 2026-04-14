import SwiftUI

public extension View {
    /// `textInputAutocapitalization` is not available on macOS `TextField`; Skip export runs SwiftPM on macOS.
    @ViewBuilder
    func wawonaTextFieldNoAutocaps() -> some View {
        #if !os(macOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
