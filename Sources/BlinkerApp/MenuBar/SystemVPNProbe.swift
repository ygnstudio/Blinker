// VPN probe design adapted from Status Trio VPNProbe/VPNMonitor,
// Copyright 2026 lingyired. Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// Modified for Blinker: folded into the existing snapshot read, no separate monitor.
// See ThirdParty/StatusTrio for license and attribution.
import Darwin
import Foundation
import SystemConfiguration

/// One `getifaddrs` pass, folded to a single entry per interface name.
struct InterfaceAddressEntry: Equatable, Sendable {
    let name: String
    let flags: UInt32
    let ipv4Addresses: [String]
}

enum InterfaceAddressReader {
    static func read() -> [InterfaceAddressEntry] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var order: [String] = []
        var flagsByName: [String: UInt32] = [:]
        var addressesByName: [String: [String]] = [:]
        var cursor = first
        while true {
            let node = cursor.pointee
            if let name = String(validatingCString: node.ifa_name) {
                if flagsByName[name] == nil {
                    order.append(name)
                }
                flagsByName[name] = UInt32(node.ifa_flags)
                if let address = node.ifa_addr,
                   address.pointee.sa_family == UInt8(AF_INET),
                   let text = numericHost(of: address) {
                    addressesByName[name, default: []].append(text)
                }
            }
            guard let next = node.ifa_next else { break }
            cursor = next
        }
        return order.map { name in
            InterfaceAddressEntry(name: name, flags: flagsByName[name] ?? 0,
                                  ipv4Addresses: addressesByName[name] ?? [])
        }
    }

    private static func numericHost(of address: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(address, socklen_t(address.pointee.sa_len),
                                 &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        // String(cString:) is deprecated in Swift 6; decode the bytes instead.
        return String(bytes: bytes, encoding: .utf8)
    }
}

/// Pure rules, kept separate from the I/O so every decision is testable.
enum TunnelInterfaceClassifier {
    /// `utun` covers built-in and third-party clients on macOS 15+; the rest
    /// are the older point-to-point names a system VPN service can create.
    static let namePrefixes = ["utun", "ppp", "ipsec", "tap", "tun"]

    static func isTunnelInterface(_ name: String) -> Bool {
        namePrefixes.contains { name.hasPrefix($0) }
    }

    /// A tunnel counts as connected only when it is up *and* holds a routable
    /// IPv4 address. The address test keeps macOS's own tunnels (Back to My
    /// Mac, Continuity) out: they are UP/RUNNING with no IPv4 address.
    static func isActiveTunnel(flags: UInt32, ipv4Addresses: [String]) -> Bool {
        guard flags & UInt32(IFF_UP) != 0 else { return false }
        return ipv4Addresses.contains { !isLinkLocal($0) }
    }

    /// 169.254.0.0/16, self-assigned when DHCP fails: not carrying traffic.
    static func isLinkLocal(_ address: String) -> Bool {
        address.hasPrefix("169.254.")
    }
}

enum SystemVPNProbe {
    /// Active tunnel interface names, sorted for a stable snapshot value.
    static func activeTunnels(from entries: [InterfaceAddressEntry]) -> [String] {
        entries.filter {
            TunnelInterfaceClassifier.isTunnelInterface($0.name)
                && TunnelInterfaceClassifier.isActiveTunnel(flags: $0.flags,
                                                            ipv4Addresses: $0.ipv4Addresses)
        }.map(\.name).sorted()
    }

    /// Interface types identifying a service as VPN. PPTP is deliberately
    /// absent: removed from macOS, the constant is deprecated.
    static let vpnInterfaceTypes: Set<String> = [
        kSCNetworkInterfaceTypePPP as String,
        kSCNetworkInterfaceTypeIPSec as String,
        kSCNetworkInterfaceTypeL2TP as String,
    ]

    /// The name of the first connected system VPN service. Reading the service
    /// list needs no entitlement; a standard (non-admin) account can be
    /// refused, which is survivable: tunnels still report the connection.
    static func connectedVPNServiceName() -> String? {
        guard let preferences = SCPreferencesCreate(nil, "Blinker.VPN" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]
        else { return nil }
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  vpnInterfaceTypes.contains(type),
                  let serviceID = SCNetworkServiceGetServiceID(service),
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID, nil, nil),
                  SCNetworkConnectionGetStatus(connection) == .connected,
                  let name = SCNetworkServiceGetName(service) as String?, !name.isEmpty
            else { continue }
            return name
        }
        return nil
    }

    /// Active system-wide proxy endpoint (`host:port`), if any. A proxy is a
    /// separate, weaker signal than a tunnel; the panel labels it differently.
    static func proxyEndpoint() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "Blinker.VPN" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/Proxies" as CFString)
              as? [String: Any]
        else { return nil }
        return proxyEndpoint(from: value)
    }

    private struct ProxyCandidate {
        let enabled: String
        let host: String
        let port: String
    }

    static func proxyEndpoint(from value: [String: Any]) -> String? {
        let candidates = [
            ProxyCandidate(enabled: "HTTPEnable", host: "HTTPProxy", port: "HTTPPort"),
            ProxyCandidate(enabled: "HTTPSEnable", host: "HTTPSProxy", port: "HTTPSPort"),
            ProxyCandidate(enabled: "SOCKSEnable", host: "SOCKSProxy", port: "SOCKSPort"),
        ]
        for candidate in candidates where enabled(value[candidate.enabled]) {
            guard let host = value[candidate.host] as? String, !host.isEmpty else { return nil }
            guard let port = (value[candidate.port] as? NSNumber)?.intValue else { return host }
            return "\(host):\(port)"
        }
        return nil
    }

    private static func enabled(_ raw: Any?) -> Bool {
        ((raw as? NSNumber)?.intValue ?? 0) != 0
    }

    static func read() -> MenuBarSystemSnapshot.VPN? {
        let vpn = MenuBarSystemSnapshot.VPN(
            tunnels: activeTunnels(from: InterfaceAddressReader.read()),
            serviceName: connectedVPNServiceName(),
            proxyEndpoint: proxyEndpoint()
        )
        return vpn.isActive ? vpn : nil
    }
}
