import AppKit
import SwiftUI

/// The network block's detail rows: Wi-Fi name with its Location Services
/// guidance, VPN/proxy presence, averaged throughput and the local/public
/// address rows. Each row has its own settings toggle.
extension SystemStatusPanel {
    @ViewBuilder
    var networkDetailRows: some View {
        let configuration = preferences.configuration
        if configuration.showsWiFiName {
            wifiNameRow
        }
        if configuration.showsVPNStatus, let vpn = monitor.snapshot.vpn {
            vpnRow(vpn)
        }
        if configuration.showsNetworkActivity, let activity = monitor.snapshot.networkActivity {
            Label("↓ \(SystemNetworkActivity.formatRate(activity.downBytesPerSecond))"
                + " ↑ \(SystemNetworkActivity.formatRate(activity.upBytesPerSecond))",
                systemImage: "arrow.up.arrow.down")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .accessibilityLabel(String(localized: "实时上下行速率"))
        }
        if configuration.showsLocalIPAddress, let address = monitor.snapshot.localIPAddress {
            Label(String(localized: "本机 IP \(address)"), systemImage: "house")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
        }
        if configuration.showsPublicIPAddress {
            if let address = monitor.snapshot.publicIPAddress {
                Label(String(localized: "公网 IP \(address)"), systemImage: "globe")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
            } else {
                Label("公网 IP 读取中…", systemImage: "globe")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var wifiNameRow: some View {
        if let name = monitor.snapshot.wifiName {
            Label(name, systemImage: "wifi")
                .foregroundStyle(.secondary).font(.callout).lineLimit(2)
        } else {
            switch monitor.wiFiNameAccess {
            case .authorized:
                EmptyView()
            case .notDetermined:
                Button {
                    handleWiFiNameAccess(monitor.requestWiFiNameAccess())
                } label: {
                    Label("允许定位以显示 Wi-Fi 名称", systemImage: "location")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
            case .denied, .restricted:
                Button {
                    openLocationSettings()
                } label: {
                    Label("定位已关闭，无法显示 Wi-Fi 名称", systemImage: "location.slash")
                        .font(.callout)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    private func handleWiFiNameAccess(_ result: WiFiNameAccessRequestResult) {
        if result == .openLocationSettings {
            openLocationSettings()
        }
    }

    private func openLocationSettings() {
        guard let url = ProjectLinks.locationPrivacy else { return }
        NSWorkspace.shared.open(url)
    }

    private func vpnRow(_ vpn: MenuBarSystemSnapshot.VPN) -> some View {
        HStack(spacing: 6) {
            Image(systemName: vpn.isTunnelConnected ? "lock.shield" : "network.badge.shield.half.filled")
                .frame(width: 18)
            if let service = vpn.serviceName {
                Text("VPN：\(service)").lineLimit(2)
            } else if vpn.isTunnelConnected {
                Text("VPN：已连接")
            } else if let endpoint = vpn.proxyEndpoint {
                Text("代理：\(endpoint)").lineLimit(2)
            }
        }
        .foregroundStyle(.secondary).font(.callout)
        .accessibilityElement(children: .combine)
    }
}
