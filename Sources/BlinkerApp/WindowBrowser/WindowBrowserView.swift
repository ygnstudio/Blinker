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
    }

    private var content: some View {
        VStack(spacing: 12) {
            HStack {
                Label(controller.dockMode ? (controller.windows.first?.appName ?? String(localized: "窗口预览"))
                    : String(localized: "切换窗口"), systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                Spacer()
                if controller.isLoading {
                    ProgressView().controlSize(.small)
                }
                Text("\(controller.windows.count)").foregroundStyle(.secondary)
                Button { controller.dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("关闭预览")
            }
            if controller.windows.isEmpty {
                ContentUnavailableView(
                    controller.isLoading ? String(localized: "正在查找窗口…") : String(localized: "没有可显示的窗口"),
                    systemImage: "macwindow"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                controls
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
        .buttonStyle(.plain)
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
