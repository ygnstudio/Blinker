// Capture/Metal presentation adapted from Macbook Duo Effect (MIT).
// Copyright (c) 2026 Ruixiang Huang
// Source: Sources/BlurOverlay.swift (FrameRenderer)
// Commit: af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1
// Modified for Blinker: generation-checked callbacks, terminal cancellation,
// main-actor presentation, shared Duo processing and bounded capture/GPU work.
// See ThirdParty/MacbookDuoEffect for the license and attribution.

import AppKit
import CoreImage
import MetalKit
import ScreenCaptureKit

/// An immutable retain token. Crossing queues only extends the IOSurface lifetime;
/// the completion handler never reads or writes the pixel buffer's storage.
private struct LidEffectFrameLifetime: @unchecked Sendable {
    private let buffer: CVPixelBuffer

    init(_ buffer: CVPixelBuffer) {
        self.buffer = buffer
    }
}

@MainActor
final class LidEffectFrameRenderer: NSObject, SCStreamOutput, SCStreamDelegate, MTKViewDelegate {
    nonisolated let queue = DispatchQueue(label: "local.blinker.lid-frames", qos: .userInteractive)
    private nonisolated let state = LidEffectFrameState()
    private let context: CIContext
    private let commands: MTLCommandQueue
    private let framesInFlight = DispatchSemaphore(value: 2)
    private let onFirstFrame: @MainActor () -> Void
    private let onFailure: @MainActor (String) -> Void
    private let onSettled: @MainActor () -> Void
    private let compatibleDevice: Bool
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private weak var view: MTKView?
    private var configuration: LidEffectConfiguration
    private var targetProgress = 0.0
    private var motion = LidEffectMotion()
    private var lastFrameTime = 0.0

    init(view: MTKView, device: MTLDevice, commands: MTLCommandQueue,
         configuration: LidEffectConfiguration, initialProgress: Double = 0,
         onFirstFrame: @escaping @MainActor () -> Void,
         onFailure: @escaping @MainActor (String) -> Void,
         onSettled: @escaping @MainActor () -> Void = {}) {
        context = CIContext(mtlCommandQueue: commands, options: [.cacheIntermediates: false])
        self.commands = commands
        self.view = view
        self.configuration = configuration.normalized()
        self.onFirstFrame = onFirstFrame
        self.onFailure = onFailure
        self.onSettled = onSettled
        motion = LidEffectMotion(progress: initialProgress)
        compatibleDevice = commands.device.registryID == device.registryID
        super.init()
        state.setTarget(isZero: true)
        view.device = device
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = colorSpace
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.delegate = self
    }

    func setEffect(progress: Double, configuration: LidEffectConfiguration,
                   openingStartProgress: Double? = nil) {
        targetProgress = LidEffectProcessor.unit(progress)
        self.configuration = configuration.normalized()
        let startsOpening = openingStartProgress.map { $0.isFinite && $0 > 0 } ?? false
        if startsOpening, let openingStartProgress {
            motion.beginOpening(at: openingStartProgress)
        } else if targetProgress > 0 {
            motion.cancelEnding()
        }
        state.setTarget(isZero: targetProgress == 0, beginsNewMotion: startsOpening)
    }

    /// A stopped renderer is never reused. Create a receiver for each new capture stream.
    func start() {
        guard state.start() else { return }
        guard compatibleDevice else {
            reportFailure(String(localized: "此设备无法渲染开合盖效果。"))
            return
        }
        view?.isPaused = false
        view?.draw()
    }

    func stop() {
        state.stop()
        view?.isPaused = true
        view?.delegate = nil
        lastFrameTime = 0
        motion.reset()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              )
              as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        if status == .complete, let buffer = sampleBuffer.imageBuffer {
            state.accept(buffer, stream: ObjectIdentifier(stream))
        } else if status == .blank || status == .suspended || status == .stopped {
            reportFailure(String(localized: "显示画面已暂停，开合盖效果已移除。"), stream: ObjectIdentifier(stream))
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        reportFailure(error.localizedDescription, stream: ObjectIdentifier(stream))
    }

    nonisolated func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        // Delegate delivery need not be on main. Keep at most one scheduled draw.
        guard state.requestDraw() else { return }
        Task { @MainActor [weak self, weak view] in
            guard let self else { return }
            state.finishDraw()
            guard let view else { return }
            drawFrame(in: view)
        }
    }

    private func drawFrame(in view: MTKView) {
        guard let frame = state.frame(), framesInFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable, let command = commands.makeCommandBuffer() else {
            framesInFlight.signal()
            return
        }
        let now = CACurrentMediaTime()
        let elapsed = lastFrameTime == 0 ? 1.0 / 60 : now - lastFrameTime
        lastFrameTime = now
        let progress = motion.advance(
            to: targetProgress,
            elapsed: elapsed,
            frames: configuration.smoothingFrames,
            speed: configuration.animationSpeed
        )
        autoreleasepool {
            let input = CIImage(cvPixelBuffer: frame.buffer)
            let output = LidEffectProcessor.image(
                input: input,
                progress: progress,
                configuration: configuration
            )
            let bounds = CGRect(x: 0, y: 0, width: drawable.texture.width, height: drawable.texture.height)
            let scaled = LidEffectProcessor.metalImage(output, bounds: bounds)
            context.render(scaled, to: drawable.texture, commandBuffer: command,
                           bounds: bounds, colorSpace: colorSpace)
            command.present(drawable)
            let budget = framesInFlight
            let lifetime = LidEffectFrameLifetime(frame.buffer)
            let ticket = frame.generation
            let settlement = state.settlementTicket(renderedProgress: progress)
            command.addCompletedHandler { [weak self] finished in
                // Both the IOSurface storage and budget outlive cancellation/deallocation.
                withExtendedLifetime(lifetime) { _ = budget.signal() }
                if finished.status == .error {
                    self?.reportFailure(String(localized: "GPU 渲染失败，请重试开合盖效果。"), ticket: ticket)
                } else if finished.status == .completed {
                    Task { @MainActor [weak self] in
                        self?.completeFrame(ticket: ticket, settlement: settlement)
                    }
                }
            }
            command.commit()
        }
    }

    private func completeFrame(ticket: UUID, settlement: UUID?) {
        if state.markPresented(ticket) {
            onFirstFrame()
        }
        if let settlement, targetProgress == 0, state.markSettled(settlement, generation: ticket) {
            onSettled()
        }
    }

    private nonisolated func reportFailure(
        _ message: String,
        stream: ObjectIdentifier? = nil,
        ticket: UUID? = nil
    ) {
        guard let generation = state.fail(stream: stream, ticket: ticket) else { return }
        Task { @MainActor [weak self] in
            guard let self, state.isFailureCurrent(generation) else { return }
            view?.isPaused = true
            view?.delegate = nil
            onFailure(message)
        }
    }
}
