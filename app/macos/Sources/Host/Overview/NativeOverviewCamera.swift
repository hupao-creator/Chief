import Foundation
import Observation

public struct NativeOverviewTransform: Codable, Equatable, Sendable {
    public var scale: Double
    public var x: Double
    public var y: Double

    public init(scale: Double = 1, x: Double = 0, y: Double = 0) {
        self.scale = scale
        self.x = x
        self.y = y
    }

    public static let identity = Self()

    func project(_ frame: CGRect) -> CGRect {
        CGRect(x: x + frame.minX * scale, y: y + frame.minY * scale,
               width: frame.width * scale, height: frame.height * scale)
    }
}

public struct NativeOverviewContentRect: Codable, Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double

    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }

    public static let zero = Self(left: 0, top: 0, width: 0, height: 0)
}

public struct NativeOverviewViewport: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var toolbarBottom: Double
    public var bottomReservedHeight: Double

    public init(width: Double, height: Double, toolbarBottom: Double = 0, bottomReservedHeight: Double = 0) {
        self.width = width
        self.height = height
        self.toolbarBottom = toolbarBottom
        self.bottomReservedHeight = bottomReservedHeight
    }
}

/// Viewport geometry is independent of card selection and keyboard focus.
public enum NativeOverviewCameraGeometry {
    public static let compactViewportWidth: Double = 620

    /// Unobstructed band reported by visibility probes.
    public static func contentRegion(_ viewport: NativeOverviewViewport) -> NativeOverviewContentRect {
        let top = min(max(0, viewport.toolbarBottom), viewport.height)
        let bottom = max(top, viewport.height - max(0, viewport.bottomReservedHeight))
        return .init(left: 0, top: top, width: max(0, viewport.width), height: bottom - top)
    }

    /// Packing and projection use the window beneath the floating controls.
    public static func framingRegion(_ viewport: NativeOverviewViewport) -> NativeOverviewContentRect {
        let horizontalMargin = viewport.width <= compactViewportWidth ? 32.0 : 64.0
        let verticalMargin = 30.0
        let horizontalInset = viewport.width > 2 * horizontalMargin ? horizontalMargin : 0
        let verticalInset = viewport.height > 2 * verticalMargin ? verticalMargin : 0
        return .init(left: horizontalInset, top: verticalInset,
                     width: max(0, viewport.width - 2 * horizontalInset),
                     height: max(0, viewport.height - 2 * verticalInset))
    }
}

/// A horizontal scroll position survives layout updates and reader visits.
/// Only changes to the available scroll range can shorten the retained offset.
@MainActor @Observable
public final class NativeOverviewCamera {
    public internal(set) var viewport: NativeOverviewViewport?
    public private(set) var scrollOffset = 0.0
    public private(set) var maximumOffset = 0.0
    private var leading: NativeOverviewTransform?
    @ObservationIgnored var onChange: (() -> Void)?

    public init() {}

    public var isInitialized: Bool { leading != nil }
    public var transform: NativeOverviewTransform {
        guard var value = leading else { return .identity }
        value.x -= scrollOffset
        return value
    }

    func install(_ geometry: NativeOverviewGeometry) {
        leading = geometry.leadingTransform
        maximumOffset = geometry.maximumScrollOffset
        scrollOffset = min(scrollOffset, maximumOffset)
        onChange?()
    }

    public func scroll(by distance: Double) {
        guard distance.isFinite else { return }
        let next = min(maximumOffset, max(0, scrollOffset + distance))
        guard next != scrollOffset else { return }
        scrollOffset = next
        onChange?()
    }
}
