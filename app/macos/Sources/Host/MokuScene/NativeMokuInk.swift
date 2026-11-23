import SwiftUI

/// Local control feedback uses the compact Stop reveal's timing. Observe the
/// visual role or eligibility at the seat, never the live draft or catalog.
extension Animation {
    static let mokuInk = Animation.easeInOut(duration: 0.12)
}

extension View {
    func mokuInk<Value: Equatable>(value: Value) -> some View {
        modifier(MokuInkAnimation(value: value))
    }
}

private struct MokuInkAnimation<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .mokuInk, value: value)
    }
}

/// Two text surfaces share one seat. The outgoing ink uses the first half
/// of the fade and the incoming ink uses the second, including on reversal.
struct NativeMokuHandoffInk: ViewModifier, @preconcurrency Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(max(0, 2 * progress - 1))
    }
}
