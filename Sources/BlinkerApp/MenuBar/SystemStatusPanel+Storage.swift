import SwiftUI

/// The storage block: boot volume capacity with a usage bar, and mounted
/// external volumes with per-volume eject. All local data, no permission.
extension SystemStatusPanel {
    @ViewBuilder
    var storageSection: some View {
        let configuration = preferences.configuration
        VStack(alignment: .leading,
               spacing: configuration.panelDensity.rowSpacing) {
            heading("存储", symbol: "internaldrive", page: .storage)
            if configuration.showsInternalStorage, let boot = monitor.snapshot.storage?.boot {
                let available = SystemStorageInfo.formatBytes(boot.availableBytes)
                let total = SystemStorageInfo.formatBytes(boot.totalBytes)
                Text(String(localized: "可用 \(available)（共 \(total)）"))
                    .font(.title3).monospacedDigit().foregroundStyle(.secondary)
                ProgressView(value: boot.usedFraction)
                    .tint(boot.usedFraction >= 0.9 ? .red : .accentColor)
                    .accessibilityLabel("内置磁盘用量")
                    .accessibilityValue("\(Int((boot.usedFraction * 100).rounded()))%")
            }
            if configuration.showsExternalVolumes {
                ForEach(monitor.snapshot.storage?.external ?? []) { volume in
                    externalVolumeRow(volume)
                }
            }
            settingsLink("储存空间设置…", destination: "com.apple.settings.Storage")
        }
    }

    private func externalVolumeRow(_ volume: SystemStorageInfo.Volume) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive").frame(width: 18)
                Text(volume.name).lineLimit(1)
                let available = SystemStorageInfo.formatBytes(volume.availableBytes)
                let total = SystemStorageInfo.formatBytes(volume.totalBytes)
                Text(String(localized: "可用 \(available)（共 \(total)）"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                if ejector.ejectingIDs.contains(volume.id) {
                    ProgressView().controlSize(.small)
                } else if volume.isEjectable {
                    Button {
                        ejector.eject(volume)
                    } label: {
                        Image(systemName: "eject")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "推出 \(volume.name)"))
                    .accessibilityLabel(String(localized: "推出 \(volume.name)"))
                }
            }
            .font(.callout)
            if let error = ejector.errors[volume.id] {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
