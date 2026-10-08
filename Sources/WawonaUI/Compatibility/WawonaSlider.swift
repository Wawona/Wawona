import SwiftUI

/// Cross-platform value control. `Slider` (and `Stepper`) are unavailable on
/// tvOS, so that target uses discrete − / + buttons with the same binding,
/// range, and step.
struct WawonaSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        #if os(tvOS)
        HStack(spacing: 16) {
            Button {
                value = max(range.lowerBound, value - step)
            } label: {
                Image(systemName: "minus")
            }
            .disabled(value <= range.lowerBound)

            Text("\(Int(value.rounded()))")
                .monospacedDigit()
                .frame(minWidth: 64)

            Button {
                value = min(range.upperBound, value + step)
            } label: {
                Image(systemName: "plus")
            }
            .disabled(value >= range.upperBound)
        }
        #else
        Slider(value: $value, in: range, step: step)
        #endif
    }
}
