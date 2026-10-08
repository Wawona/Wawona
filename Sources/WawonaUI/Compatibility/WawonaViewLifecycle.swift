import SwiftUI
import Combine

enum WawonaControlSize { case mini, small, regular, large }

extension WawonaBackport where Content: View {
    @ViewBuilder
    func controlSize(_ size: WawonaControlSize) -> some View {
        if #available(iOS 15.0, tvOS 15.0, watchOS 9.0, macOS 11.0, *) {
            switch size {
            case .mini: content.controlSize(.mini)
            case .small: content.controlSize(.small)
            case .regular: content.controlSize(.regular)
            case .large: content.controlSize(.large)
            }
        } else { content }
    }

    @ViewBuilder
    func onChange<Value: Equatable>(of value: Value, initial: Bool = false,
                                    _ action: @escaping (Value, Value) -> Void) -> some View {
        if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
            content.onChange(of: value, initial: initial, action)
        } else {
            content.modifier(WawonaChange(value: value, initial: initial, action: action))
        }
    }

    func onChange<Value: Equatable>(of value: Value, _ action: @escaping (Value) -> Void) -> some View {
        onChange(of: value) { _, new in action(new) }
    }

    @ViewBuilder
    func task(_ action: @escaping @MainActor () async -> Void) -> some View {
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            content.task { await action() }
        } else {
            content.modifier(WawonaViewTask(action: action))
        }
    }
}

private struct WawonaChange<Value: Equatable>: ViewModifier {
    let value: Value
    let initial: Bool
    let action: (Value, Value) -> Void
    @State private var previous: Value
    @State private var delivered = false

    init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
        _previous = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onReceive(Just(value)) { new in
            let old = previous
            let shouldDeliver = old != new || (!delivered && initial)
            if old != new { previous = new }
            if !delivered { delivered = true }
            if shouldDeliver { action(old, new) }
        }
    }
}

private struct WawonaViewTask: ViewModifier {
    let action: @MainActor () async -> Void
    @State private var running: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onAppear {
            guard running == nil else { return }
            running = Task { await action() }
        }.onDisappear {
            running?.cancel()
            running = nil
        }
    }
}

/// iOS 13-safe stand-in for `@StateObject` (iOS 14+).
///
/// Holds the observable once in `@State` and forwards `objectWillChange` so
/// feature views do not need an availability-gated property wrapper.
/// Used by Machines UI wrappers that must stay visible on the product floor.
@propertyWrapper
public struct WawonaStateObject<ObjectType: ObservableObject>: DynamicProperty {
    @State private var box: Box
    @ObservedObject private var observed: Box

    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) {
        let box = Box(wrappedValue())
        _box = State(wrappedValue: box)
        _observed = ObservedObject(wrappedValue: box)
    }

    public var wrappedValue: ObjectType {
        observed.object
    }

    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject(wrappedValue: observed.object).projectedValue
    }

    public mutating func update() {
        if observed !== box {
            _observed = ObservedObject(wrappedValue: box)
        }
    }

    private final class Box: ObservableObject {
        let object: ObjectType
        private var cancellable: AnyCancellable?

        init(_ object: ObjectType) {
            self.object = object
            cancellable = object.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
}
