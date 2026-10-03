import AppKit
import BlinkerCore
import SwiftUI

struct WindowBrowserView: View {
    @ObservedObject var controller: WindowBrowserController
    @ObservedObject var thumbnails: WindowThumbnailStore

    var body: some View {
        let size = controller.presentationSize
        let scale = controller.previewScale
        content
            .frame(width: size.width / scale, height: size.height / scale)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: thumbnails.captureUnavailable) { _, _ in controller.updatePresentationSize() }
    }

    private var content: some View {
        VStack(spacing: 8) {
            HStack {
                Label(controller.dockMode ? (controller.windows.first?.appName ?? String(localized: "窗口预览"))
                    : String(localized: "切换窗口"), systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if controller.isLoading, !controller.windows.isEmpty,
                   !controller.isPerformingAction, !thumbnails.isRetrying {
                    OperationProgress(message: String(localized: "正在更新…"))
                } else if !controller.windows.isEmpty {
                    Text("\(controller.windows.count)").foregroundStyle(.secondary)
                }
                Button { controller.dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless).help("关闭预览")
                .accessibilityLabel("关闭预览")
            }
            if controller.windows.isEmpty {
                if controller.isLoading {
                    OperationProgress(message: String(localized: "正在查找窗口…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("没有可显示的窗口", systemImage: "macwindow")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if controller.usesThumbnails {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                                     count: controller.layout.columns), spacing: 12) {
                                tiles
                            }
                        } else {
                            LazyVStack(spacing: 4) { tiles }
                        }
                    }
                    .onChange(of: controller.selectedID) { _, id in
                        if let id {
                            proxy.scrollTo(id)
                        }
                    }
                }
                .id(controller.presentationID)
                if controller.usesThumbnails, thumbnails.captureUnavailable {
                    ThumbnailCaptureNotice(isRetrying: thumbnails.isRetrying,
                                           isPerformingAction: controller.isPerformingAction,
                                           onRetry: controller.retryThumbnails)
                }
                controls
                    .opacity(controller.isPerformingAction ? 0 : 1)
                    .disabled(controller.isPerformingAction)
                    .accessibilityHidden(controller.isPerformingAction)
                    .overlay(alignment: .leading) {
                        if controller.isPerformingAction {
                            OperationProgress(message: String(localized: "正在处理窗口…"))
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .padding(16)
    }

    private var tiles: some View {
        let session = controller.presentationID
        return ForEach(controller.windows) { window in
            WindowPreviewTile(window: window, image: thumbnails.images[window.id],
                              selected: window.id == controller.selectedID,
                              compact: !controller.usesThumbnails,
                              thumbnailHeight: controller.layout.thumbnailHeight,
                              onSelect: { controller.select(window.id) },
                              onActivate: { controller.commit(window.id) })
                .id(window.id)
                .onAppear { controller.setVisible(window.id, visible: true, session: session) }
                .onDisappear { controller.setVisible(window.id, visible: false, session: session) }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { controller.perform(.closeWindow) } label: { Image(systemName: "xmark.circle.fill") }
                .tint(.red).help("关闭窗口")
            Button { controller.perform(.minimize) } label: { Image(systemName: "minus.circle.fill") }
                .tint(.yellow).help("最小化")
            Menu {
                ForEach([ButtonAction.maximize, .centerWindow, .tileLeft, .tileRight,
                         .tileFirstThird, .tileCenterThird, .tileLastThird, .tileFirstTwoThirds,
                         .tileLastTwoThirds, .moveToNextDisplay, .restorePreviousFrame],
                        id: \.self) { action in
                    Button(action.localizedLabel) { controller.perform(action) }
                }
            } label: { Image(systemName: "rectangle.split.2x2") }
                .menuStyle(.borderlessButton).fixedSize().help("窗口管理")
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { scale in
                    Button {
                        controller.preferences.previewScale = scale
                    } label: {
                        if abs(controller.preferences.previewScale - scale) < 0.001 {
                            Label("\(Int(scale * 100))%", systemImage: "checkmark")
                        } else {
                            Text("\(Int(scale * 100))%")
                        }
                    }
                }
            } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .menuStyle(.borderlessButton).fixedSize().help("预览大小")
                .accessibilityLabel("预览大小")
            Spacer(minLength: 4)
            if controller.presentationSize.width / controller.previewScale >= 360 {
                Text("↵ 打开 · Esc 取消").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .disabled(controller.selectedID == nil)
    }
}

struct ThumbnailCaptureNotice: View {
    let isRetrying: Bool
    var isPerformingAction = false
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isRetrying {
                if isPerformingAction {
                    Text("正在重试缩略图…").font(.caption).foregroundStyle(.secondary)
                } else {
                    OperationProgress(message: String(localized: "正在重试缩略图…"))
                }
            } else {
                Text("缩略图暂不可用").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("重试", action: onRetry)
                    .controlSize(.small)
                    .disabled(isPerformingAction)
            }
        }
        .frame(height: 24)
    }
}

private struct WindowPreviewTile: View {
    let window: BrowserWindow
    let image: NSImage?
    let selected: Bool
    let compact: Bool
    let thumbnailHeight: CGFloat
    let onSelect: () -> Void
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 8) {
                if !compact {
                    thumbnail
                }
                caption
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(WindowPreviewButtonStyle())
        .onHover {
            if $0 {
                onSelect()
            }
        }
        .help(window.appName + " — " + window.title)
        .accessibilityLabel(window.appName + " — " + window.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(3)
            } else {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 48, height: 48)
            }
            if window.isMinimized || window.isHidden {
                VStack {
                    Spacer()
                    Text(window.isMinimized ? String(localized: "已最小化") : String(localized: "已隐藏"))
                        .font(.caption2).padding(4).background(.regularMaterial, in: Capsule())
                }.padding(6)
            }
        }
        .frame(height: thumbnailHeight)
    }

    private var caption: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon).resizable().frame(width: compact ? 30 : 18, height: compact ? 30 : 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(window.appName)
                    if window.isTab {
                        Label("标签页", systemImage: "rectangle.on.rectangle")
                    }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var icon: NSImage {
        NSRunningApplication(processIdentifier: window.pid)?.icon
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
    }
}

/// Press feedback acknowledges the pointer immediately; it never delays activation or animates selection.
private struct WindowPreviewButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pressFeedback = Animation.easeOut(duration: 0.12)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .transaction { $0.animation = nil }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion || configuration.isPressed ? nil : Self.pressFeedback,
                       value: configuration.isPressed)
    }
}
