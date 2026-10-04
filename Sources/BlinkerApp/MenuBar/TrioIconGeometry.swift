// Adapted from Status Trio by lingyired (Apache-2.0).
// Source: Sources/StatusTrioCore/UI/Icon/StatusIconGeometry.swift
// Commit: d1672377a172ee4cb4af53d5054610c407c0d34f
// Modified for Blinker: retain only static battery, Ethernet and volume geometry.
// See ThirdParty/StatusTrio for the license and attribution.

import CoreGraphics
import Foundation

enum TrioIconGeometry {
    static let canvasSize: CGFloat = 120
    // The original artwork is centered in a 119-unit box, not at canvasSize / 2.
    static let artworkCenterX: CGFloat = 59.5
    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: artworkCenterX, y: 61.48715261785473)
    private static let batteryStart: CGFloat = 148.69008689281117 * .pi / 180
    private static let batterySweep: CGFloat = 242.6198262143777 * .pi / 180
    static let batteryChargingBoltPivot = CGPoint(x: artworkCenterX, y: 2.1)
    static let batteryChargingBoltCalibration: CGFloat = 220.0 / 180.0
    static let ethernetStrokeWidth: CGFloat = 4.886659979939819
    static let ethernetDotRadius: CGFloat = 2.4433299899699095
    private static let ethernetSourceBounds = CGRect(x: 56.132, y: 75.812, width: 87.736, height: 46.376)
    private static let ethernetTargetBounds = CGRect(x: 31.5, y: 51.19959879638917,
                                                     width: 56, height: 29.60080240722166)

    static func batteryTopIndicatorCenter(boltScale: CGFloat) -> CGPoint {
        let bolt = batteryChargingBolt().boundingBoxOfPath
        let pivot = batteryChargingBoltPivot
        return CGPoint(
            x: pivot.x + (bolt.midX - pivot.x) * boltScale,
            y: pivot.y + (bolt.midY - pivot.y) * boltScale
        )
    }

    static func batteryValueBaseline(fontSize: CGFloat) -> CGPoint {
        let referenceFontSize: CGFloat = 20
        let referenceBaseline: CGFloat = 17
        let currentFontSize: CGFloat = 32
        let currentBaseline: CGFloat = 24
        let slope = (currentBaseline - referenceBaseline) / (currentFontSize - referenceFontSize)
        return CGPoint(
            x: artworkCenterX,
            y: referenceBaseline + (fontSize - referenceFontSize) * slope
        )
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func batteryGapFraction(topGapWidth: CGFloat) -> Double {
        guard topGapWidth.isFinite, topGapWidth > 0 else { return 0 }
        let arcLength = batteryRadius * batterySweep
        guard arcLength.isFinite, arcLength > 0 else { return 0 }
        return min(1, max(0, Double(topGapWidth / arcLength)))
    }

    static func batteryChargingBolt(scale: CGFloat = 1) -> CGPath {
        let path = chargingBoltPath()
        guard scale.isFinite, scale > 0, scale != 1 else { return path }
        let pivot = batteryChargingBoltPivot
        var transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: pivot.x * (1 - scale), ty: pivot.y * (1 - scale)
        )
        return path.copy(using: &transform) ?? path
    }

    private static func chargingBoltPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 62.1, y: 2.2))
        path.addQuadCurve(
            to: CGPoint(x: 62.6, y: 3.3),
            control: CGPoint(x: 62.8, y: 2.5)
        )
        path.addLine(to: CGPoint(x: 61.2, y: 7.8))
        path.addLine(to: CGPoint(x: 65.9, y: 7.8))
        path.addQuadCurve(
            to: CGPoint(x: 67.3, y: 8.6),
            control: CGPoint(x: 66.9, y: 7.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: 67, y: 10),
            control: CGPoint(x: 67.6, y: 9.3)
        )
        path.addLine(to: CGPoint(x: 57, y: 21.3))
        path.addQuadCurve(
            to: CGPoint(x: 55.6, y: 21.6),
            control: CGPoint(x: 56.4, y: 22)
        )
        path.addQuadCurve(
            to: CGPoint(x: 55.3, y: 20.5),
            control: CGPoint(x: 55, y: 21.3)
        )
        path.addLine(to: CGPoint(x: 57.4, y: 14.1))
        path.addLine(to: CGPoint(x: 52.9, y: 14.1))
        path.addQuadCurve(
            to: CGPoint(x: 51.6, y: 13.3),
            control: CGPoint(x: 52, y: 14.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: 51.9, y: 12),
            control: CGPoint(x: 51.3, y: 12.6)
        )
        path.addLine(to: CGPoint(x: 61.1, y: 2.7))
        path.addQuadCurve(
            to: CGPoint(x: 62.1, y: 2.2),
            control: CGPoint(x: 61.6, y: 2.1)
        )
        path.closeSubpath()
        return path
    }

    static func ethernetChevrons() -> [CGPath] {
        let left = ethernetPolyline([
            CGPoint(x: 79.32, y: 79.64),
            CGPoint(x: 59.96, y: 99),
            CGPoint(x: 79.32, y: 118.36),
        ])
        let right = ethernetPolyline([
            CGPoint(x: 120.68, y: 79.64),
            CGPoint(x: 140.04, y: 99),
            CGPoint(x: 120.68, y: 118.36),
        ])
        return [left, right]
    }

    static func ethernetDots() -> [CGPoint] {
        [
            ethernetPoint(x: 84.688, y: 99),
            ethernetPoint(x: 100, y: 99),
            ethernetPoint(x: 115.312, y: 99),
        ]
    }

    private static func ethernetPolyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: ethernetPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: ethernetPoint(x: point.x, y: point.y))
        }
        return path
    }

    private static func ethernetPoint(x coordinateX: CGFloat, y coordinateY: CGFloat) -> CGPoint {
        let scaleX = ethernetTargetBounds.width / ethernetSourceBounds.width
        let scaleY = ethernetTargetBounds.height / ethernetSourceBounds.height
        return CGPoint(
            x: ethernetTargetBounds.minX + (coordinateX - ethernetSourceBounds.minX) * scaleX,
            y: ethernetTargetBounds.minY + (coordinateY - ethernetSourceBounds.minY) * scaleY
        )
    }

    static func volumeDots() -> [CGPoint] {
        [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8),
        ]
    }

    static func volumeArc(progress: Double) -> CGPath {
        let progress = clampedUnit(progress)
        let path = CGMutablePath()
        guard progress > 0 else { return path }
        let start: CGFloat = 121.82 * .pi / 180
        let end: CGFloat = 59.12 * .pi / 180
        path.addArc(center: batteryCenter, radius: batteryRadius, startAngle: start,
                    endAngle: start - (start - end) * CGFloat(progress), clockwise: true)
        return path
    }

    static func batteryArc(
        from start: Double,
        to end: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat
    ) -> CGPath {
        guard start.isFinite, end.isFinite else { return CGMutablePath() }
        let clampedStart = clampedUnit(start)
        let clampedEnd = clampedUnit(end)
        guard clampedEnd > clampedStart else { return CGMutablePath() }

        let path = CGMutablePath()
        guard hasTopGap else {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
            return path
        }

        let gapFraction = batteryGapFraction(topGapWidth: topGapWidth)
        let gapStartProgress = (1 - gapFraction) / 2
        let gapEndProgress = gapStartProgress + gapFraction

        let firstSegmentEnd = min(clampedEnd, gapStartProgress)
        if firstSegmentEnd > clampedStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(firstSegmentEnd)
            ))
        }

        let secondSegmentStart = max(clampedStart, gapEndProgress)
        if clampedEnd > secondSegmentStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(secondSegmentStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
        }
        return path
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
