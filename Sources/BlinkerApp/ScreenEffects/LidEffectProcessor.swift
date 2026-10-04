// Duo projection and graduated blur adapted from Macbook Duo Effect (MIT).
// Copyright (c) 2026 Ruixiang Huang
// Sources: Sources/EffectProcessor.swift and Sources/EffectModel.swift
// Commit: af3b89df6c11f9fb6d07b5a6c9872cfde08bb2a1
// Modified for Blinker: bounded configuration, arbitrary image origins, shared
// preview/live processing while preserving the original Duo projection.
// See ThirdParty/MacbookDuoEffect for the license and attribution.

import CoreImage
import Foundation

enum LidEffectProcessor {
    static func image(input: CIImage, progress: Double, configuration: LidEffectConfiguration) -> CIImage {
        let progress = unit(progress)
        let extent = input.extent
        guard progress > 0, valid(extent) else { return input }
        let configuration = configuration.normalized()
        let amount = progress * progress * (3 - 2 * progress)
        return duo(input, amount: amount, configuration: configuration)
    }

    /// Match the drawable extent without flipping Core Image's bottom-left coordinates.
    static func metalImage(_ input: CIImage, bounds: CGRect) -> CIImage {
        guard valid(input.extent), valid(bounds) else { return input }
        let origin = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX,
                                                             y: -input.extent.minY))
        let scaled = origin.transformed(by: CGAffineTransform(scaleX: bounds.width / input.extent.width,
                                                              y: bounds.height / input.extent.height))
        return scaled.transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
            .cropped(to: bounds)
    }

    static func topWidth(progress: Double, tilt: Double) -> Double {
        let delta = min(75, max(0, tilt.isFinite ? tilt : 80) * unit(progress)) * .pi / 180
        let depth = 1 / (cos(delta) + 0.2 * sin(delta))
        return max(0.08, 1 - depth * sin(delta) / 2.5)
    }

    static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.minX.isFinite && rect.minY.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }

    private static func duo(_ input: CIImage, amount: Double,
                            configuration: LidEffectConfiguration) -> CIImage {
        let extent = input.extent
        let inset = extent.width * (1 - topWidth(progress: amount, tilt: configuration.tilt)) / 2
        let transformed = input.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: extent.minX + inset, y: extent.maxY),
            "inputTopRight": CIVector(x: extent.maxX - inset, y: extent.maxY),
            "inputBottomLeft": CIVector(x: extent.minX, y: extent.minY),
            "inputBottomRight": CIVector(x: extent.maxX, y: extent.minY),
        ])
        let background = CIImage(color: .black).cropped(to: extent)
        let projected = transformed.composited(over: background).cropped(to: extent)
        let radius = min(extent.width, extent.height) * 0.06 * configuration.blur * amount
        let softened = frosted(projected, radius: radius, configuration: configuration)
        let light = 1 - configuration.darkness * amount
        return softened.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: light, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: light, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: light, w: 0),
        ]).cropped(to: extent)
    }

    private static func frosted(_ image: CIImage, radius: Double,
                                configuration: LidEffectConfiguration) -> CIImage {
        guard radius > 0, configuration.frost > 0 else { return image }
        let extent = image.extent
        let start = extent.minY + extent.height * (1 - configuration.edgeSoftness) * 0.75
        guard let mask = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: start),
            "inputPoint1": CIVector(x: extent.midX, y: extent.maxY),
            "inputColor0": CIColor(red: 0.05, green: 0.05, blue: 0.05),
            "inputColor1": CIColor.white,
        ])?.outputImage?.cropped(to: extent) else { return image }
        let blurred = image.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: [
            kCIInputRadiusKey: radius, "inputMask": mask,
        ]).cropped(to: extent)
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: blurred, kCIInputTimeKey: configuration.frost,
        ]).cropped(to: extent)
    }
}
