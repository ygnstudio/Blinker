import AppKit
import CoreImage
import CoreText
import SwiftUI

/// A generated sample desktop: previewing never captures the user's screen or enables the effect.
struct LidEffectPreview: View {
    let configuration: LidEffectConfiguration
    @StateObject private var model = LidPreviewModel()
    @State private var amount = 0.5

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("效果预览").font(.headline)
                    Spacer()
                    Text("模拟画面，不读取屏幕").font(.caption).foregroundStyle(.secondary)
                }
                if let image = model.image {
                    Image(decorative: image, scale: 2)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if !model.unavailable {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 130)
                }
                HStack {
                    Text("模拟合盖").font(.callout)
                    Slider(value: $amount, in: 0 ... 1)
                        .accessibilityLabel("模拟合盖程度")
                    Text("\(Int(amount * 100))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                }
                if model.unavailable {
                    Text("暂时无法生成预览，请调整参数重试。").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(4)
        }
        .onAppear { update() }
        .onChange(of: configuration) { _, _ in update() }
        .onChange(of: amount) { _, _ in update() }
        .onDisappear { model.stop() }
    }

    private func update() {
        model.update(progress: amount, configuration: configuration)
    }
}

@MainActor
private final class LidPreviewModel: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var unavailable = false
    private let worker = LidPreviewWorker()
    private var requested: Request?
    private var rendering: Request?
    private struct Request: Equatable {
        var progress: Double
        var configuration: LidEffectConfiguration
    }

    func update(progress: Double, configuration: LidEffectConfiguration) {
        let request = Request(progress: progress, configuration: configuration)
        guard request != requested else { return }
        requested = request
        drain()
    }

    func stop() {
        requested = nil
    }

    private func drain() {
        guard rendering == nil, let request = requested else { return }
        rendering = request
        worker
            .render(progress: request.progress,
                    configuration: request.configuration) { [weak self] image, available in
                guard let self else { return }
                rendering = nil
                guard requested != nil else { return }
                if requested == request {
                    self.image = image
                    unavailable = !available
                } else {
                    drain()
                }
            }
    }
}

/// Only this queue touches CIContext and the synthetic image; requests coalesce in the model.
private final class LidPreviewWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Blinker.LidEffect.Preview", qos: .userInitiated)
    private var context: CIContext?
    private var source: CIImage?

    func render(progress: Double, configuration: LidEffectConfiguration,
                completion: @escaping @MainActor @Sendable (CGImage?, Bool) -> Void) {
        queue.async { [self] in
            if context == nil {
                context = CIContext(options: [.cacheIntermediates: false])
            }
            if source == nil {
                source = LidPreviewArtwork.image().map { CIImage(cgImage: $0) }
            }
            let result = source.flatMap { input -> CGImage? in
                let image = LidEffectProcessor.image(
                    input: input,
                    progress: progress,
                    configuration: configuration
                )
                return context?.createCGImage(image, from: input.extent)
            }
            Task { @MainActor in completion(result, result != nil) }
        }
    }
}

/// Original vector artwork, kept separate so GPU fixtures can reuse the same non-private input.
enum LidPreviewArtwork {
    static func image() -> CGImage? {
        let width = 720
        let height = 420
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let colors = [CGColor(red: 0.12, green: 0.23, blue: 0.38, alpha: 1),
                      CGColor(red: 0.39, green: 0.66, blue: 0.66, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        context.setFillColor(CGColor(gray: 1, alpha: 0.25))
        context.fill(CGRect(x: 0, y: 398, width: 720, height: 22))
        context.setFillColor(CGColor(gray: 0.97, alpha: 1))
        let window = CGPath(roundedRect: CGRect(x: 84, y: 55, width: 552, height: 306),
                            cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.addPath(window)
        context.fillPath()
        context.setFillColor(CGColor(gray: 0.89, alpha: 1))
        context.fill(CGRect(x: 84, y: 55, width: 128, height: 273))
        for (index, color) in [CGColor(red: 1, green: 0.35, blue: 0.35, alpha: 1),
                               CGColor(red: 1, green: 0.77, blue: 0.2, alpha: 1),
                               CGColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1)].enumerated() {
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: 99 + index * 22, y: 337, width: 13, height: 13))
        }
        context.setFillColor(CGColor(red: 0.18, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 94, y: 274, width: 108, height: 25))
        context.setFillColor(CGColor(gray: 0.5, alpha: 0.25))
        for row in 0 ..< 4 {
            context.fill(CGRect(x: 99, y: 239 - row * 32, width: 92, height: 8))
        }
        for row in 0 ..< 5 {
            context.fill(CGRect(x: 240, y: 238 - row * 31, width: row == 4 ? 186 : 328, height: 9))
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): CTFontCreateWithName(
                "Helvetica-Bold" as CFString,
                28,
                nil
            ),
            .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0.2, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Blinker",
            attributes: attributes
        ))
        context.textPosition = CGPoint(x: 240, y: 280)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
