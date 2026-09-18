import SwiftUI

public struct SheetThemeColors: Equatable, Sendable {
    public let background: Color
    public let rowBackground: Color
    public let accentColor: Color?

    public init(background: Color, rowBackground: Color, accentColor: Color? = nil) {
        self.background = background
        self.rowBackground = rowBackground
        self.accentColor = accentColor
    }
}

private struct SheetThemeColorsKey: EnvironmentKey {
    static let defaultValue: SheetThemeColors? = nil
}

public extension EnvironmentValues {
    var sheetThemeColors: SheetThemeColors? {
        get { self[SheetThemeColorsKey.self] }
        set { self[SheetThemeColorsKey.self] = newValue }
    }
}

public struct ThemedListStyle: ViewModifier {
    @Environment(\.sheetThemeColors) private var sheetThemeColors

    public func body(content: Content) -> some View {
        if let sheetThemeColors {
            content
                .scrollContentBackground(.hidden)
                .background(sheetThemeColors.background.ignoresSafeArea())
        } else {
            content
        }
    }
}

public struct ThemedRowBackground: ViewModifier {
    @Environment(\.sheetThemeColors) private var sheetThemeColors

    public func body(content: Content) -> some View {
        if let sheetThemeColors {
            content.listRowBackground(sheetThemeColors.rowBackground)
        } else {
            content
        }
    }
}

public extension View {
    func themedList() -> some View { modifier(ThemedListStyle()) }
    func themedRow() -> some View { modifier(ThemedRowBackground()) }
}
