import SwiftUI

public extension View {
    /// `textInputAutocapitalization` is not available on macOS `TextField`.
    @ViewBuilder
    func wawonaTextFieldNoAutocaps() -> some View {
        #if !os(macOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
