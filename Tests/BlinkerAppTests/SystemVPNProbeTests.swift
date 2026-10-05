@testable import BlinkerApp
import Darwin
import XCTest

final class SystemVPNProbeTests: XCTestCase {
    func testTunnelInterfaceNamesMatchKnownPrefixesOnly() {
        for name in ["utun0", "utun4", "ppp0", "ipsec1", "tap0", "tun2"] {
            XCTAssertTrue(TunnelInterfaceClassifier.isTunnelInterface(name), name)
        }
        for name in ["en0", "en1", "lo0", "bridge100", "awdl0", "llw0", "gif0", "stf0", "ap1"] {
            XCTAssertFalse(TunnelInterfaceClassifier.isTunnelInterface(name), name)
        }
    }

    func testActiveTunnelRequiresUpFlagAndRoutableAddress() {
        let upOnly = UInt32(IFF_UP)
        let running = upOnly | UInt32(IFF_RUNNING)
        // macOS system tunnels (Back to My Mac, Continuity): up, no address.
        XCTAssertFalse(TunnelInterfaceClassifier.isActiveTunnel(flags: running, ipv4Addresses: []))
        // Link-local only (DHCP failure) is not carrying traffic.
        XCTAssertFalse(TunnelInterfaceClassifier.isActiveTunnel(flags: running,
                                                                ipv4Addresses: ["169.254.1.2"]))
        // Down interface with an address does not count.
        XCTAssertFalse(TunnelInterfaceClassifier.isActiveTunnel(flags: 0,
                                                                ipv4Addresses: ["10.0.0.2"]))
        // Up with a routable address: connected.
        XCTAssertTrue(TunnelInterfaceClassifier.isActiveTunnel(flags: upOnly,
                                                               ipv4Addresses: ["10.0.0.2"]))
        XCTAssertTrue(TunnelInterfaceClassifier.isActiveTunnel(flags: running,
                                                               ipv4Addresses: ["169.254.1.2", "10.8.0.2"]))
    }

    func testActiveTunnelsFiltersAndSortsStably() {
        let entries = [
            InterfaceAddressEntry(name: "utun3", flags: UInt32(IFF_UP), ipv4Addresses: []),
            InterfaceAddressEntry(name: "utun5", flags: UInt32(IFF_UP), ipv4Addresses: ["10.8.0.2"]),
            InterfaceAddressEntry(name: "en0", flags: UInt32(IFF_UP), ipv4Addresses: ["192.168.1.5"]),
            InterfaceAddressEntry(name: "utun4", flags: UInt32(IFF_UP), ipv4Addresses: ["172.16.0.2"]),
        ]
        XCTAssertEqual(SystemVPNProbe.activeTunnels(from: entries), ["utun4", "utun5"])
    }

    func testProxyEndpointPrefersFixedEndpointsInProtocolOrder() {
        XCTAssertEqual(SystemVPNProbe.proxyEndpoint(from: [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7890,
            "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080,
        ] as [String: Any]), "127.0.0.1:7890")
        XCTAssertEqual(SystemVPNProbe.proxyEndpoint(from: [
            "HTTPSEnable": 1, "HTTPSProxy": "proxy.local",
        ] as [String: Any]), "proxy.local")
        XCTAssertEqual(SystemVPNProbe.proxyEndpoint(from: [
            "SOCKSEnable": 1, "SOCKSProxy": "10.0.0.1", "SOCKSPort": 10808,
        ] as [String: Any]), "10.0.0.1:10808")
    }

    func testProxyEndpointIgnoresDisabledAndMissingHosts() {
        XCTAssertNil(SystemVPNProbe.proxyEndpoint(from: [
            "HTTPEnable": 0, "HTTPProxy": "127.0.0.1", "HTTPPort": 7890,
        ] as [String: Any]))
        XCTAssertNil(SystemVPNProbe.proxyEndpoint(from: [
            "HTTPEnable": 1,
        ] as [String: Any]))
        XCTAssertNil(SystemVPNProbe.proxyEndpoint(from: [
            "ProxyAutoConfigEnable": 1, "ProxyAutoConfigURLString": "http://x/proxy.pac",
        ] as [String: Any]))
    }

    func testSnapshotVPNActivitySemantics() {
        var vpn = MenuBarSystemSnapshot.VPN()
        XCTAssertFalse(vpn.isActive)
        XCTAssertFalse(vpn.isTunnelConnected)
        vpn.proxyEndpoint = "127.0.0.1:7890"
        XCTAssertTrue(vpn.isActive)
        XCTAssertFalse(vpn.isTunnelConnected)
        vpn.tunnels = ["utun4"]
        XCTAssertTrue(vpn.isTunnelConnected)
        vpn.tunnels = []
        vpn.serviceName = "Work VPN"
        XCTAssertTrue(vpn.isTunnelConnected)
    }
}
