import ChiefPluginUI
import SwiftUI

/// Point geometry shared by the SwiftUI capsule and its interaction regions.
/// Coordinates are local to the flipped scene, including a scrolled shell.
enum NativeMokuCapsuleLayout {
    static let overviewExpansionAnimation = Animation.smooth(duration: 0.42, extraBounce: 0)
    static let idleSize = CGSize(width: 168, height: 44)
    static let landingScale: CGFloat = 76.0 / 58.0
    /// Shared by the capsule glass, its clip shape and the nested composer
    /// surfaces (including attachment chips, which derive their concentric
    /// radius from this value).
    static let cornerRadius: CGFloat = 29

    static func restingInset(forHeight height: CGFloat) -> CGFloat {
        max(24, min(36, height * 0.05))
    }

    static func frame(in viewport: CGRect, landing: Bool = false, reading: Bool = false) -> CGRect {
        let restingBottom = landing ? 24 : restingInset(forHeight: viewport.height)
        // Reading gives the expanding composer a lower seat. Keep a physical
        // margin even in compact/zoomed windows; never translate outside the fit.
        let bottom = reading && !landing ? max(12, restingBottom - 16) : restingBottom
        let width = min(landing ? 680 : 560, max(0, viewport.width - 48))
        return CGRect(x: viewport.midX - width / 2, y: viewport.minY + 24,
                      width: width, height: max(0, viewport.height - bottom - 24))
    }

    static func surface(in frame: CGRect, expanded: Bool, height: CGFloat, centered: Bool = false) -> CGRect {
        let width = expanded ? frame.width : min(idleSize.width, frame.width)
        let height = min(max(0, expanded ? height : idleSize.height), frame.height)
        return CGRect(x: frame.midX - width / 2, y: centered ? frame.midY - height / 2 : frame.maxY - height,
                      width: width, height: height)
    }

    static func idleSurface(in viewport: CGRect) -> CGRect {
        surface(in: frame(in: viewport), expanded: false, height: idleSize.height)
    }

    static func panel(in viewport: CGRect, above surface: CGRect, question: Bool) -> CGRect {
        let width = min(question ? 760 : 480, max(0, viewport.width - 48))
        let height = min(question ? 440 : 280, max(0, surface.minY - viewport.minY - 42))
        return CGRect(x: viewport.midX - width / 2, y: surface.minY - 18 - height, width: width, height: height)
    }
}

/// The resident character's painted canvas and the seat it occupies. Moku's
/// message row and Settings' header share this seat, so the face keeps one size
/// wherever it sits.
enum NativeMokuFaceLayout {
    /// Canvas the painter scales its 640-unit geometry into.
    static let canvas = CGSize(width: 58, height: 49)
    /// Layout seat that centres the canvas on Moku's row.
    static let seat = CGSize(width: 34, height: 25)
}

/// Reuses the real Moku eyes, including their tilt, proportions and expression.
struct NativeMokuCapsuleEyes: Shape {
    typealias ScalarPair = AnimatablePair<Double, Double>
    typealias EyeData = AnimatablePair<ScalarPair, AnimatablePair<ScalarPair, ScalarPair>>
    private var left: MokuEye
    private var right: MokuEye
    var blink: Double

    // Animate the resolved geometry, including expression changes. Animating
    // only focus replaces the idle expression's size and tilt in a single frame.
    var animatableData: AnimatablePair<EyeData, EyeData> {
        get { .init(Self.data(left), Self.data(right)) }
        set { left = Self.eye(newValue.first); right = Self.eye(newValue.second) }
    }

    init(expression: MokuExpression, focus: Double, blink: Double = 1) {
        let eyes = Self.resolved(expression: expression, focus: focus)
        self.init(left: eyes.left, right: eyes.right, blink: blink)
    }

    init(left: MokuEye, right: MokuEye, blink: Double = 1) {
        self.left = left; self.right = right; self.blink = blink
    }

    static func resolved(expression: MokuExpression, focus: Double) -> (left: MokuEye, right: MokuEye) {
        let idle = MokuGeometry.expressions[expression == .focus ? .idle : expression]!
        let target = MokuGeometry.expressions[.focus]!
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * focus }
        let centerY = mix((idle.left.y + idle.right.y) / 2, (target.left.y + target.right.y) / 2)
        func resolve(_ a: MokuEye, _ b: MokuEye) -> MokuEye {
            MokuEye(x: mix(a.x, b.x), y: mix(a.y, b.y) - centerY,
                    w: mix(a.w, b.w), h: mix(a.h, b.h), radius: mix(a.radius, b.radius),
                    rotation: mix(a.rotation, b.rotation), opacity: 1)
        }
        return (resolve(idle.left, target.left), resolve(idle.right, target.right))
    }

    private static func data(_ eye: MokuEye) -> EyeData {
        .init(.init(eye.x, eye.y), .init(.init(eye.w, eye.h), .init(eye.radius, eye.rotation)))
    }
    private static func eye(_ data: EyeData) -> MokuEye {
        MokuEye(x: data.first.first, y: data.first.second,
                w: data.second.first.first, h: data.second.first.second,
                radius: data.second.second.first, rotation: data.second.second.second, opacity: 1)
    }

    static let eyeScale = 0.22
    static func contour(_ eye: MokuEye, blink: Double) -> Path {
        let w = eye.w * eyeScale, h = eye.h * eyeScale * blink
        return Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                    cornerRadius: eye.radius * eyeScale)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for geometry in [left, right] {
            let scale = Self.eyeScale
            let eye = Self.contour(geometry, blink: blink)
            let transform = CGAffineTransform(rotationAngle: geometry.rotation * .pi / 180)
                .concatenating(CGAffineTransform(translationX: rect.midX + geometry.x * scale,
                                               y: rect.midY + geometry.y * scale))
            path.addPath(eye, transform: transform)
        }
        return path
    }
}

/// Note uses dark regular glass and the conversation follows the workspace appearance.
/// The compact Bar keeps its warm finish. Reduce Transparency makes the shell opaque.
struct NativeMokuCapsuleGlass: View {
    var interactive = true
    var regular = false
    var appearance: ColorScheme = .dark
    var strength = 0.85
    /// A local preview override; system Reduce Transparency always takes priority.
    var forceOpaque = false
    @Environment(\.accessibilityReduceTransparency) private var systemOpaque
    private var opaque: Bool { systemOpaque || forceOpaque }

    var body: some View {
        material.environment(\.colorScheme, appearance)
    }

    @ViewBuilder private var material: some View {
        if opaque {
            if appearance == .light {
                RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius).fill(.background)
            } else {
                NativeMokuCapsuleFinish(opaque: true)
            }
        } else {
            Color.clear
                // Keep one glass node while Note changes the capsule's size and
                // material. Stacking clear and regular shells duplicates sampling.
                .glassEffect(regular ? .regular : interactive ? Glass.clear.interactive() : .clear,
                             in: .rect(cornerRadius: NativeMokuCapsuleLayout.cornerRadius))
                .overlay { NativeMokuCapsuleFinish(opaque: false, strength: strength).opacity(regular ? 0 : 1) }
        }
    }
}

struct NativeMokuCapsuleFinish: View {
    let opaque: Bool
    var strength = 0.85
    private let shape = RoundedRectangle(cornerRadius: NativeMokuCapsuleLayout.cornerRadius)

    var body: some View {
        if opaque {
            shape.fill(Color(red: 0.12, green: 0.11, blue: 0.10))
        } else {
            shape.fill(LinearGradient(stops: [
                .init(color: Color.black.opacity(0.99 * strength), location: 0),
                .init(color: Color(red: 0.04, green: 0.035, blue: 0.03).opacity(0.96 * strength), location: 0.40),
                .init(color: Color(red: 0.16, green: 0.13, blue: 0.10).opacity(0.70 * strength), location: 0.72),
                .init(color: Color(red: 0.38, green: 0.33, blue: 0.26).opacity(0.12 * strength), location: 1),
            ], startPoint: .top, endPoint: .bottom))
                .overlay {
                    shape.strokeBorder(LinearGradient(stops: [
                        .init(color: .white.opacity(0.04 * strength), location: 0),
                        .init(color: .white.opacity(0.08 * strength), location: 0.55),
                        .init(color: Color(red: 1, green: 0.92, blue: 0.78).opacity(0.65 * strength), location: 1),
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                }
        }
    }
}
