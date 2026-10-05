// Wi-Fi name authorization adapted from Status Trio WiFiNameAuthorizer,
// Copyright 2026 lingyired. Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// See ThirdParty/StatusTrio for license and attribution.
import CoreLocation

/// Since macOS 14, `CWInterface.ssid()` returns nil unless the app holds
/// Location Services authorization. Blinker never reads location itself;
/// the grant only un-redacts the network name.
enum WiFiNameAccess: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum WiFiNameAccessRequestResult: Equatable, Sendable {
    case requested
    case openLocationSettings
    case notNeeded
}

@MainActor
protocol WiFiNameAuthorizing: AnyObject {
    var access: WiFiNameAccess { get }
    var onAccessChange: (() -> Void)? { get set }

    @discardableResult
    func requestAccess() -> WiFiNameAccessRequestResult
}

@MainActor
final class CoreLocationWiFiNameAuthorizer: NSObject, WiFiNameAuthorizing {
    private let manager: CLLocationManager
    private var hasRequestedAuthorization = false

    var onAccessChange: (() -> Void)?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
    }

    var access: WiFiNameAccess {
        Self.map(manager.authorizationStatus)
    }

    @discardableResult
    func requestAccess() -> WiFiNameAccessRequestResult {
        switch access {
        case .notDetermined:
            // Core Location does not report whether its prompt was displayed.
            // A later explicit click must offer a way out if the first request
            // left permission undecided, instead of silently requesting forever.
            guard !hasRequestedAuthorization else { return .openLocationSettings }
            hasRequestedAuthorization = true
            manager.requestWhenInUseAuthorization()
            return .requested
        case .denied, .restricted:
            return .openLocationSettings
        case .authorized:
            return .notNeeded
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> WiFiNameAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}

extension CoreLocationWiFiNameAuthorizer: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.onAccessChange?()
        }
    }
}
