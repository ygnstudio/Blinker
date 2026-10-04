// Capture lifecycle adapted from Macbook_Duo_Effect by Ruixiang Huang (MIT).
// Upstream af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1, Sources/BlurOverlay.swift.
// Modified: serialized start/stop, permission preflight, display validation and menu access.
// See ThirdParty/MacbookDuoEffect for attribution and license.
import AppKit
import MetalKit
import ScreenCaptureKit

@MainActor
protocol LidEffectPresenting: AnyObject {
    var onFailure: ((String) -> Void)? { get set }
    var onFirstFrame: (() -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    func update(progress: Double, configuration: LidEffectConfiguration, openingStartProgress: Double?)
    func finish()
    func clear()
}

/// One capture can be opening, active or closing. Rapid gestures cannot start overlapping streams.
@MainActor
final class LidEffectOverlay: LidEffectPresenting {
    var onFailure: ((String) -> Void)?
    var onFirstFrame: (() -> Void)?
    var onFinished: (() -> Void)?
    private var window: NSWindow?
    private var stream: SCStream?
    private var renderer: LidEffectFrameRenderer?
    private var opening: Task<Void, Never>?
    private var closing: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var request = LidEffectPresentationRequest()
    private var configuration = LidEffectConfiguration()
    private var deadline: Timer?
    private var finishingDeadline: Timer?
    private var finishingTicket: UUID?

    func update(progress: Double, configuration: LidEffectConfiguration,
                openingStartProgress: Double? = nil) {
        guard request.update(progress: progress, openingStartProgress: openingStartProgress) else {
            clear()
            return
        }
        self.configuration = configuration.normalized()
        cancelFinishingDeadline()
        renderer?.setEffect(progress: request.progress, configuration: self.configuration,
                            openingStartProgress: openingStartProgress)
        if request.isFinishing, request.hasPresented {
            installFinishingDeadline()
        }
        startIfNeeded()
    }

    private func startIfNeeded() {
        guard request.isRequested else { return }
        guard stream == nil, opening == nil, closing == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            fail(String(localized: "屏幕特效需要屏幕录制权限。"))
            return
        }
        generation &+= 1
        let ticket = generation
        installDeadline(ticket: ticket)
        opening = Task { [weak self] in await self?.open(ticket: ticket) }
    }

    private func open(ticket: UInt64) async {
        defer {
            opening = nil
            startIfNeeded()
        }
        do {
            guard let screen = Self.builtInScreen,
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { throw CaptureError.missingDisplay }
            let displayID = number.uint32Value
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            let options = Self.captureOptions(frame: frame, scale: scale)
            // Register the transparent overlay before enumeration, including when no settings window exists.
            let presentation = try makePresentation(frame: frame, options: options, ticket: ticket)
            window = presentation.panel
            renderer = presentation.receiver
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard ticket == generation, request.isRequested, !Task.isCancelled else { return }
            guard Self.builtInScreen?.frame == frame else { throw CaptureError.missingDisplay }
            let filter = try Self.captureFilter(content: content, displayID: displayID,
                                                windowNumber: presentation.panel.windowNumber)
            try await startCapture(
                filter: filter,
                options: options,
                presentation: presentation,
                ticket: ticket
            )
        } catch {
            guard ticket == generation else { return }
            fail(String(localized: "无法启动屏幕特效，请检查屏幕录制权限后重试。"))
        }
    }

    private static func captureFilter(content: SCShareableContent, displayID: CGDirectDisplayID,
                                      windowNumber: Int) throws -> SCContentFilter {
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { throw CaptureError.missingDisplay }
        let pid = ProcessInfo.processInfo.processIdentifier
        if let ownApp = content.applications.first(where: { $0.processID == pid }) {
            return SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        }
        // A menu-bar-only app is not guaranteed to appear in the shareable applications list.
        // Never capture with an empty exclusion: that could feed the overlay back into itself.
        guard windowNumber > 0, let ownWindow = content.windows.first(where: {
            $0.windowID == CGWindowID(windowNumber) && $0.owningApplication?.processID == pid
        }) else { throw CaptureError.missingOverlay }
        return SCContentFilter(display: display, excludingWindows: [ownWindow])
    }

    private func startCapture(filter: SCContentFilter, options: SCStreamConfiguration,
                              presentation: Presentation, ticket: UInt64) async throws {
        let receiver = presentation.receiver
        let capture = SCStream(filter: filter, configuration: options, delegate: receiver)
        try capture.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: receiver.queue)
        do {
            try await capture.startCapture()
        } catch {
            receiver.stop()
            try? await capture.stopCapture()
            throw error
        }
        guard ticket == generation, request.isRequested, !Task.isCancelled else {
            receiver.stop()
            try? await capture.stopCapture()
            return
        }
        stream = capture
        presentation.view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        receiver.setEffect(progress: request.progress, configuration: configuration,
                           openingStartProgress: request.initialProgress > 0 ? request.initialProgress : nil)
        receiver.start()
    }

    private struct Presentation {
        let panel: NSWindow
        let view: MTKView
        let receiver: LidEffectFrameRenderer
    }

    private func makePresentation(frame: CGRect, options: SCStreamConfiguration, ticket: UInt64)
        throws -> Presentation {
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue()
        else { throw CaptureError.missingMetal }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Keep system menus and Dock above the visual effect so Pause is always reachable.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let view = MTKView(frame: CGRect(origin: .zero, size: frame.size), device: device)
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: options.width, height: options.height)
        panel.contentView = view
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let receiver = LidEffectFrameRenderer(view: view, device: device, commands: commands,
                                              configuration: configuration,
                                              initialProgress: request.initialProgress,
                                              onFirstFrame: { [weak self] in
                                                  guard let self, ticket == generation,
                                                        request.isRequested else { return }
                                                  deadline?.invalidate()
                                                  deadline = nil
                                                  request.didPresent()
                                                  window?.alphaValue = 1
                                                  onFirstFrame?()
                                                  if request.isFinishing {
                                                      installFinishingDeadline()
                                                  }
                                              }, onFailure: { [weak self] _ in
                                                  guard let self, ticket == generation else { return }
                                                  fail(String(localized: "屏幕画面已中断，特效已移除。"))
                                              }, onSettled: { [weak self] in
                                                  guard let self, ticket == generation,
                                                        request.isRequested,
                                                        request.isFinishing else { return }
                                                  clear()
                                                  onFinished?()
                                              })
        return Presentation(panel: panel, view: view, receiver: receiver)
    }

    private static func captureOptions(frame: CGRect, scale: CGFloat) -> SCStreamConfiguration {
        let value = SCStreamConfiguration()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let ratio = min(scale, (lowPower ? 1920 : 2560) / max(1, frame.width))
        value.width = max(1, Int(frame.width * ratio))
        value.height = max(1, Int(frame.height * ratio))
        value.minimumFrameInterval = CMTime(value: 1, timescale: lowPower ? 30 : 60)
        value.queueDepth = 3
        value.pixelFormat = kCVPixelFormatType_32BGRA
        value.showsCursor = false
        value.capturesAudio = false
        value.captureMicrophone = false
        value.colorSpaceName = CGColorSpace.sRGB
        return value
    }

    static var builtInScreen: NSScreen? {
        NSScreen.screens.first {
            guard let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
        }
    }

    private func installDeadline(ticket: UInt64) {
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, ticket == generation, !request.hasPresented else { return }
                fail(String(localized: "未收到屏幕画面，特效已移除。"))
            }
        }
        deadline = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fail(_ message: String) {
        clear()
        onFailure?(message)
    }

    func finish() {
        guard request.finish() else { return }
        renderer?.setEffect(progress: 0, configuration: configuration,
                            openingStartProgress: request.initialProgress > 0 ? request.initialProgress : nil)
        if request.hasPresented {
            installFinishingDeadline()
        }
    }

    private func installFinishingDeadline() {
        guard finishingDeadline == nil else { return }
        let ticket = generation
        let ending = UUID()
        finishingTicket = ending
        // Normal transitions last at most two seconds. A stalled drawable must not retain capture.
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, ticket == generation, finishingTicket == ending,
                      request.isFinishing else { return }
                clear()
                onFinished?()
            }
        }
        finishingDeadline = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelFinishingDeadline() {
        finishingTicket = nil
        finishingDeadline?.invalidate()
        finishingDeadline = nil
    }

    func clear() {
        guard request.isRequested || stream != nil || window != nil || opening != nil else { return }
        request.clear()
        generation &+= 1
        opening?.cancel()
        deadline?.invalidate()
        deadline = nil
        cancelFinishingDeadline()
        renderer?.stop()
        renderer = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        if let previous = stream {
            stream = nil
            closing = Task { [weak self] in
                try? await previous.stopCapture()
                guard let self else { return }
                closing = nil
                startIfNeeded()
            }
        }
    }

    private enum CaptureError: Error { case missingDisplay, missingMetal, missingOverlay }
}
