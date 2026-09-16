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

/// The app target's language preference mirrored into Core. The overlay is
/// not part of the settings window, so it cannot observe `AppPreferences`
/// directly; the app delegate copies the preference here on launch and on
/// every change. `nil` means "no preference known" — follow the system
/// locale (also the standalone-Core behavior in tests).
public enum OverlayL10n {
    public static var preferEnglish: Bool?
}

/// Bilingual helper for the HUD. Prefers the app-level language choice
/// (mirrored via `OverlayL10n.preferEnglish`) so the HUD never disagrees
/// with the settings UI; falls back to the system locale when unset.
private func hudText(_ zhText: String, _ enText: String) -> String {
    let systemIsChinese = Locale.current.language.languageCode?.identifier == "zh"
    let english = OverlayL10n.preferEnglish ?? !systemIsChinese
    return english ? enText : zhText
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
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDHoverButtonStyle())
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
                            Text(String(localized: "\(workspace.windowCount) 窗", bundle: .module))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        // The padding grows the row's hit area and gives the
                        // hover background room; the panel's height math in
                        // `openHUD` accounts for it (30 pt per row).
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDHoverButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(width: 252)
        // No opaque backdrop here: the hosting panel layers this content on
        // the same glass material as the hover tray (see HoverOverlayHUDPanel).
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

/// Hover feedback for HUD buttons: `.plain` gives no pointer indication on
/// the glass backdrop, so tiles and rows lift their fill from 5% to 12%
/// primary on hover/press. Shared by the placement grid and workspace rows.
private struct HUDHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(isHovered || configuration.isPressed ? 0.12 : 0.05))
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

/// Borderless, non-activating panel hosting the window-management HUD. It
/// floats below the enlarged traffic-light group and stays alive while the
/// cursor remains inside it. The backdrop uses the same glass material as
/// the hover tray (`NSGlassEffectView` on macOS 26+, a masked
/// `NSVisualEffectView` before), so the two surfaces read as one family.
final class HoverOverlayHUDPanel: NSPanel {
    /// Corner radius matching the SwiftUI content's tile rounding.
    static let cornerRadius: CGFloat = 14

    /// The panel's current frame in AX (top-left origin) coordinates —
    /// measured from the hosted content, then repositioned via `setAXFrame`.
    private(set) var axFrame: CGRect

    /// - Parameters:
    ///   - axOrigin: The HUD's top-left origin in AX coordinates. The size
    ///     comes from the content's ideal size (`fittingSize`), floored at a
    ///     conservative minimum — `NSHostingView.fittingSize` measured
    ///     outside a window can report a stale ideal height for lazy
    ///     content, and a too-short panel would clip the workspace rows.
    ///   - content: The SwiftUI content to host.
    init(axOrigin: CGPoint, content: HoverOverlayHUDContent) {
        let hostingView = NSHostingView(rootView: content)
        let measured = hostingView.fittingSize
        // Grid (3 rows) + header + divider + one workspace row + padding:
        // anything smaller means the measurement went stale.
        let minimumHeight: CGFloat = 150
        let size = NSSize(
            width: max(252, measured.width),
            height: max(minimumHeight, measured.height)
        )
        let appKitFrame = AXQuery.appKitFrame(
            fromAXRect: CGRect(origin: axOrigin, size: CGSize(width: size.width, height: size.height))
        )
        axFrame = CGRect(origin: axOrigin, size: CGSize(width: size.width, height: size.height))
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

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let radius = Self.cornerRadius
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: container.bounds)
            glass.cornerRadius = radius
            container.addSubview(glass)
        } else {
            let backdrop = NSVisualEffectView(frame: container.bounds)
            backdrop.material = .underWindowBackground
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active
            backdrop.maskImage = HoverOverlayTrayPanel.roundedMaskImage(
                size: container.bounds.size,
                radius: radius
            )
            container.addSubview(backdrop)
        }
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        contentView = container
    }

    /// Repositions the panel to a new frame in AX (top-left origin)
    /// coordinates, keeping its measured size.
    func setAXFrame(_ frame: CGRect) {
        setFrameOrigin(AXQuery.appKitFrame(fromAXRect: frame).origin)
        axFrame = CGRect(origin: frame.origin, size: axFrame.size)
    }
}

// MARK: - Core-side labels

extension ButtonAction {
    /// Locale-based label for HUD rendering, resolved from Core's own String
    /// Catalog (`Bundle.module`) so the HUD follows the system language. The
    /// wording matches the settings labels so the two surfaces share one
    /// vocabulary.
    var overlayLocalizedLabel: String {
        switch self {
        case .closeWindow: String(localized: "关闭窗口", bundle: .module)
        case .quitApp: String(localized: "退出应用", bundle: .module)
        case .minimize: String(localized: "最小化", bundle: .module)
        case .hideApp: String(localized: "隐藏应用", bundle: .module)
        case .maximize: String(localized: "最大化", bundle: .module)
        case .almostMaximize: String(localized: "准最大化", bundle: .module)
        case .fullscreen: String(localized: "全屏", bundle: .module)
        case .tileLeft: String(localized: "左半屏", bundle: .module)
        case .tileRight: String(localized: "右半屏", bundle: .module)
        case .tileTop: String(localized: "上半屏", bundle: .module)
        case .tileBottom: String(localized: "下半屏", bundle: .module)
        case .tileTopLeft: String(localized: "左上屏", bundle: .module)
        case .tileTopRight: String(localized: "右上屏", bundle: .module)
        case .tileBottomLeft: String(localized: "左下屏", bundle: .module)
        case .tileBottomRight: String(localized: "右下屏", bundle: .module)
        case .centerWindow: String(localized: "窗口居中", bundle: .module)
        case .moveToNextDisplay: String(localized: "下一显示器", bundle: .module)
        case .none: String(localized: "无操作", bundle: .module)
        case .windowManagerPanel: String(localized: "窗口面板", bundle: .module)
        }
    }
}
