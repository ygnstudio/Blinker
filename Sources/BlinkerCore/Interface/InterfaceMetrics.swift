import Foundation

/// Custom surfaces only. Native windows, controls and sheets keep system geometry.
public enum InterfaceMetrics {
    public enum Radius {
        public static let control: CGFloat = 8
        public static let group: CGFloat = 12
        public static let floating: CGFloat = 16
        public static let glassShell: CGFloat = 24
    }

    public enum Surface {
        public static let panelTintOpacity = 0.55
        public static let groupFillOpacity = 0.35
        public static let pageArrivalOpacity = 0.88
    }

    public enum Motion {
        public static let pressRelease: TimeInterval = 0.12
        public static let pageArrival: TimeInterval = 0.12
        public static let previewArrival: TimeInterval = 0.12
        public static let previewDeparture: TimeInterval = 0.10
    }
}
