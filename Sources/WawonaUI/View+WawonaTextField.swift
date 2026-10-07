import SwiftUI

public extension View {
    /// `textInputAutocapitalization` is not available on macOS `TextField`.
    @ViewBuilder
    func wawonaTextFieldNoAutocaps() -> some View {
        #if !os(macOS)
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            self.textInputAutocapitalization(.never)
        } else {
            self.autocapitalization(.none)
        }
        #else
        self
        #endif
    }
}
