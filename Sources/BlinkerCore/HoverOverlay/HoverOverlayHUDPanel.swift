import AppKit
import SwiftUI

/// One workspace entry shown in the HUD restore list.
public struct HUDWorkspaceItem: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let windowCount: Int

    public init(id: UUID, name: String, windowCount: Int) {
        self.id = id
        self.name = name
        self.windowCount = windowCount
    }
}

/// Bilingual helper for the HUD. The overlay is not part of the settings
/// window, so the app-level `tr` (which follows the language preference)
/// does not apply here; follow the system locale instead.
private func hudText(_ zhText: String, _ enText: String) -> String {
    Locale.current.languageCode == "zh" ? zhText : enText
}

/// The SwiftUI content of the window-management HUD: a compact placement
/// grid acting on the hovered window, plus one-tap workspace restore rows.
struct HoverOverlayHUDContent: View {
    let appName: String?
    let placements: [ButtonAction]
    let workspaces: [HUDWorkspaceItem]
    let onAction: (ButtonAction) -> Void
    let onRestore: (UUID) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.grid.3x3")
                    .font(.caption.weight(.semibold))
                Text(hudText("窗口管理", "Window Manager"))
                    .font(.caption.weight(.semibold))
                if let appName {
                    Text("· \(appName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(placements, id: \.rawValue) { action in
                    Button {
                        onAction(action)
                    } label: {
                        VStack(spacing: 3) {
                            miniScreen(for: action)
                            Text(action.overlayLocalizedLabel)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            if workspaces.isEmpty {
                Text(hudText("尚未保存工作区", "No workspaces saved"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(workspaces) { workspace in
                    Button {
                        onRestore(workspace.id)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(workspace.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(hudText("\(workspace.windowCount) 窗", "\(workspace.windowCount) win"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onHover { hovering in
            if !hovering {
                onClose()
            }
        }
    }

    /// Miniature preview of the target region, mirroring the settings
    /// panel's PlacementTile rendering.
    @ViewBuilder
    private func miniScreen(for action: ButtonAction) -> some View {
        if let placement = WindowPlacement(action: action) {
            let frame = WindowGeometry.tiledFrame(placement, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: max(6, frame.width * 52), height: max(4, frame.height * 30))
            }
            .frame(width: 56, height: 34)
        } else {
            // Non-placement fallback (defensive; the HUD grid is placements only).
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                .frame(width: 56, height: 34)
        }
    }
}

/// Borderless, non-activating panel hosting the window-management HUD. It
/// floats below the enlarged traffic-light group and stays alive while the
/// cursor remains inside it.
final class HoverOverlayHUDPanel: NSPanel {
    /// - Parameter axFrame: The HUD frame in AX (top-left origin) coordinates.
    init(axFrame: CGRect, content: HoverOverlayHUDContent) {
        let globalMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let appKitFrame = CGRect(
            x: axFrame.minX,
            y: globalMaxY - axFrame.maxY,
            width: axFrame.width,
            height: axFrame.height
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: appKitFrame.size)
        super.init(
            contentRect: appKitFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        hasShadow = false
        isReleasedWhenClosed = false
        contentView = hostingView
    }
}

// MARK: - Core-side labels

extension ButtonAction {
    /// Locale-based label for HUD rendering. The settings UI has its own
    /// preference-aware `localizedLabel`; this one follows the system locale
    /// because the HUD lives outside the settings window.
    var overlayLocalizedLabel: String {
        switch self {
        case .closeWindow: hudText("关闭窗口", "Close Window")
        case .quitApp: hudText("退出应用", "Quit App")
        case .minimize: hudText("最小化", "Minimize")
        case .hideApp: hudText("隐藏应用", "Hide App")
        case .maximize: hudText("最大化", "Maximize")
        case .almostMaximize: hudText("准最大化", "Almost Max")
        case .fullscreen: hudText("全屏", "Fullscreen")
        case .tileLeft: hudText("左半屏", "Left Half")
        case .tileRight: hudText("右半屏", "Right Half")
        case .tileTop: hudText("上半屏", "Top Half")
        case .tileBottom: hudText("下半屏", "Bottom Half")
        case .tileTopLeft: hudText("左上", "Top Left")
        case .tileTopRight: hudText("右上", "Top Right")
        case .tileBottomLeft: hudText("左下", "Bottom Left")
        case .tileBottomRight: hudText("右下", "Bottom Right")
        case .centerWindow: hudText("居中", "Center")
        case .moveToNextDisplay: hudText("下一屏", "Next Display")
        case .none: hudText("无操作", "Do Nothing")
        case .windowManagerPanel: hudText("窗口管理", "Window Manager")
        }
    }
}
