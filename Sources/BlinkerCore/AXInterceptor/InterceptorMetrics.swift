import CoreGraphics

/// Layout constants shared across the interception surfaces
/// (traffic-light interceptor and window snapper).
enum InterceptorMetrics {
    /// Vertical extent of the title-bar band that both the traffic-light
    /// interceptor and the window snapper treat as their trigger zone.
    static let titleBarBandHeight: CGFloat = 32
}
