import SwiftUI

/// Drop-in replacement for `@State`.
/// In the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode.app, and this
/// project builds with the Command Line Tools alone. `@StateObject` is still a plain property
/// wrapper, so we box the value in one. Usage is identical: `@ViewState var x = 0`, `$x` is a Binding.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> { $box.value }
}
