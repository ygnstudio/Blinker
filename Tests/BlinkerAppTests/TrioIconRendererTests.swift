import AppKit
@testable import BlinkerApp
import XCTest

final class TrioIconRendererTests: XCTestCase {
    func testBatteryUnknownNeverBecomesFullAndPowerIndicatorsRemainAccurate() {
        XCTAssertNil(TrioIconMapping.batteryProgress(nil))
        XCTAssertEqual(TrioIconMapping.batteryIndicator(nil), .plug)
        var battery = MenuBarSystemSnapshot.Battery(percentage: nil, isCharging: false,
                                                    isConnectedToPower: false, isLowPower: false)
        XCTAssertNil(TrioIconMapping.batteryProgress(battery))
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery), .unknown)
        battery.isCharging = true
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery), .bolt)
        XCTAssertNil(TrioIconMapping.batteryProgress(battery))
        battery.isCharging = false
        battery.isConnectedToPower = true
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery), .plug)
    }

    func testBatteryThresholdPrecedenceAndClampedPercentage() {
        var battery = MenuBarSystemSnapshot.Battery(percentage: 19, isCharging: true,
                                                    isConnectedToPower: true, isLowPower: true)
        XCTAssertEqual(TrioIconMapping.batteryColor(battery), .critical)
        battery.percentage = 20
        XCTAssertEqual(TrioIconMapping.batteryColor(battery), .lowPower)
        battery.isLowPower = false
        XCTAssertEqual(TrioIconMapping.batteryColor(battery), .charging)
        battery.isCharging = false
        battery.isConnectedToPower = false
        XCTAssertEqual(TrioIconMapping.batteryColor(battery), .foreground)
        battery.percentage = 140
        XCTAssertEqual(TrioIconMapping.batteryProgress(battery), 1)
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery), .percentage(100))
        battery.percentage = -1
        XCTAssertEqual(TrioIconMapping.batteryProgress(battery), 0)
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery), .percentage(0))
    }

    func testVolumeUnknownAndMuteAreDistinctWithFourQuarterSteps() {
        XCTAssertNil(TrioIconMapping.volumeSteps(nil))
        XCTAssertNil(TrioIconMapping.volumeSteps(.init(scalar: nil, isMuted: false)))
        XCTAssertNil(TrioIconMapping.volumeSteps(.init(scalar: .nan, isMuted: false)))
        XCTAssertNil(TrioIconMapping.volumeSteps(.init(scalar: .infinity, isMuted: false)))
        XCTAssertEqual(TrioIconMapping.volumeSteps(.init(scalar: nil, isMuted: true)), 0)
        for (scalar, level) in [(-1.0, 0), (0, 0), (0.001, 1), (0.25, 1), (0.251, 2),
                                (0.5, 2), (0.501, 3), (0.75, 3), (0.751, 4), (1, 4), (2, 4)] {
            XCTAssertEqual(TrioIconMapping.volumeSteps(.init(scalar: scalar, isMuted: false)), level)
        }
        XCTAssertEqual(TrioIconMapping.volumeSteps(.init(scalar: 1, isMuted: true)), 0)
    }

    func testNetworkStrengthUsesThreeBarsAndBoundsUnexpectedReadings() {
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: -1), 0)
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: 0), 0)
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: 1), 0.33)
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: 2), 0.66)
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: 3), 1)
        XCTAssertEqual(TrioIconMapping.wifiValue(strength: 99), 1)
    }

    @MainActor
    func testVectorImageKeepsSizeAndDrawsForBothMenuBarAppearances() throws {
        let snapshot = MenuBarSystemSnapshot(
            battery: .init(percentage: 75, isCharging: false, isConnectedToPower: false, isLowPower: false),
            network: .wifi(strength: 3), volume: .init(scalar: 1, isMuted: false)
        )
        let image = TrioIconRenderer.image(snapshot: snapshot)
        XCTAssertEqual(image.size, NSSize(width: 22, height: 22))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(TrioIconRenderer.image(snapshot: snapshot, size: .nan).size, image.size)
        let light = try pixels(snapshot, appearance: .aqua)
        let dark = try pixels(snapshot, appearance: .darkAqua)
        XCTAssertGreaterThan(light.count, 500)
        XCTAssertGreaterThan(dark.count, 500)
        XCTAssertLessThan(averageBrightness(light), 0.35)
        XCTAssertGreaterThan(averageBrightness(dark), 0.65)
    }

    @MainActor
    func testRenderedBatteryUsesRedYellowAndChargingGreen() throws {
        var snapshot = MenuBarSystemSnapshot(
            battery: .init(percentage: 19, isCharging: false, isConnectedToPower: false, isLowPower: false),
            network: .wifi(strength: 3), volume: .init(scalar: 0.5, isMuted: false)
        )
        let critical = try pixels(snapshot, appearance: .aqua)
        XCTAssertGreaterThan(critical.filter { $0.redComponent > $0.greenComponent * 1.5 }.count, 40)
        snapshot.battery?.percentage = 75
        snapshot.battery?.isLowPower = true
        let lowPower = try pixels(snapshot, appearance: .aqua)
        XCTAssertGreaterThan(lowPower.filter {
            $0.redComponent > 0.5 && $0.greenComponent > 0.3 && $0.blueComponent < 0.1
        }.count, 100)
        snapshot.battery?.isLowPower = false
        snapshot.battery?.isCharging = true
        let charging = try pixels(snapshot, appearance: .aqua)
        XCTAssertGreaterThan(charging.filter { $0.greenComponent > $0.redComponent * 1.5 }.count, 100)
    }

    @MainActor
    func testUnknownVolumeAndDifferentNetworkModesRenderDistinctImages() throws {
        let unknown = try bitmap(.unknown, appearance: .aqua)
        var snapshot = MenuBarSystemSnapshot.unknown
        snapshot.volume = .init(scalar: nil, isMuted: true)
        let muted = try bitmap(snapshot, appearance: .aqua)
        XCTAssertNotEqual(unknown.tiffRepresentation, muted.tiffRepresentation)
        var representations = Set<Data>()
        for network in [MenuBarSystemSnapshot.Network.unknown, .off, .disconnected, .wired,
                        .wifi(strength: 1), .wifi(strength: 2), .wifi(strength: 3)] {
            snapshot.network = network
            let data = try XCTUnwrap(try bitmap(snapshot, appearance: .aqua).tiffRepresentation)
            XCTAssertTrue(
                representations.insert(data).inserted,
                "Network states must not share a fake healthy image"
            )
        }
    }

    @MainActor
    private func bitmap(_ snapshot: MenuBarSystemSnapshot,
                        appearance: NSAppearance.Name,
                        configuration: MenuBarConfiguration = .init()) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0,
                                                    bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        let image = try TrioIconRenderer.image(snapshot: snapshot, size: 120,
                                               appearance: XCTUnwrap(NSAppearance(named: appearance)),
                                               configuration: configuration)
        image.draw(in: NSRect(x: 0, y: 0, width: 120, height: 120))
        return bitmap
    }

    @MainActor
    private func pixels(_ snapshot: MenuBarSystemSnapshot,
                        appearance: NSAppearance.Name) throws -> [NSColor] {
        let bitmap = try bitmap(snapshot, appearance: appearance)
        return (0 ..< 120).flatMap { row in
            (0 ..< 120).compactMap { column in
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { return nil }
                return color
            }
        }
    }

    private func averageBrightness(_ pixels: [NSColor]) -> CGFloat {
        pixels.reduce(0) { $0 + $1.brightnessComponent } / CGFloat(max(1, pixels.count))
    }
}

extension TrioIconRendererTests {
    private var example: MenuBarSystemSnapshot {
        .init(battery: .init(percentage: 75, isCharging: false, isConnectedToPower: false, isLowPower: false),
              network: .wifi(strength: 3), volume: .init(scalar: 0.35, isMuted: false))
    }

    func testBatteryIndicatorSwitchesAndConnectedPercentagePriority() throws {
        var configuration = MenuBarConfiguration()
        var battery = try XCTUnwrap(example.battery)
        configuration.showsBatteryPercentage = false
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery, configuration: configuration), .none)
        battery.isCharging = true
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery, configuration: configuration), .bolt)
        configuration.showsChargingIndicator = false
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery, configuration: configuration), .none)
        configuration.showsBatteryPercentage = true
        XCTAssertEqual(
            TrioIconMapping.batteryIndicator(battery, configuration: configuration),
            .percentage(75)
        )
        configuration.showsChargingIndicator = true
        configuration.showsPercentageWhenConnected = true
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery, configuration: configuration), .bolt)
        battery.isCharging = false
        battery.isConnectedToPower = true
        XCTAssertEqual(
            TrioIconMapping.batteryIndicator(battery, configuration: configuration),
            .percentage(75)
        )
        configuration.showsPercentageWhenConnected = false
        XCTAssertEqual(TrioIconMapping.batteryIndicator(battery, configuration: configuration), .plug)
    }

    func testBatteryColorSwitchAndCustomThreshold() throws {
        var configuration = MenuBarConfiguration()
        var battery = try XCTUnwrap(example.battery)
        battery.percentage = 30
        configuration.batteryCriticalThreshold = 30
        XCTAssertEqual(TrioIconMapping.batteryColor(battery, configuration: configuration), .foreground)
        configuration.batteryCriticalThreshold = 31
        XCTAssertEqual(TrioIconMapping.batteryColor(battery, configuration: configuration), .critical)
        configuration.usesBatteryColors = false
        battery.isLowPower = true
        battery.isCharging = true
        XCTAssertEqual(TrioIconMapping.batteryColor(battery, configuration: configuration), .foreground)
    }

    func testBluetoothReplacementRespectsNetworkErrorsAndSelectedOutputTransport() {
        var snapshot = example
        var configuration = MenuBarConfiguration()
        configuration.replacesNetworkWithBluetooth = true
        XCTAssertFalse(TrioIconMapping.replacesNetwork(snapshot, configuration: configuration))
        snapshot.volume?.isBluetooth = true
        for network in [MenuBarSystemSnapshot.Network.wifi(strength: 1), .wired] {
            snapshot.network = network
            XCTAssertTrue(TrioIconMapping.replacesNetwork(snapshot, configuration: configuration))
        }
        for network in [MenuBarSystemSnapshot.Network.off, .disconnected, .unknown] {
            snapshot.network = network
            XCTAssertFalse(TrioIconMapping.replacesNetwork(snapshot, configuration: configuration))
        }
        configuration.prioritizesNetworkErrors = false
        XCTAssertTrue(TrioIconMapping.replacesNetwork(snapshot, configuration: configuration))
        configuration.replacesNetworkWithBluetooth = false
        XCTAssertFalse(TrioIconMapping.replacesNetwork(snapshot, configuration: configuration))
    }

    @MainActor
    func testStrokeAndSymbolSizesAffectRenderedArtwork() throws {
        let baseline = try bitmap(example, appearance: .aqua).tiffRepresentation
        let mutations: [(inout MenuBarConfiguration) -> Void] = [
            { $0.stroke = .light }, { $0.stroke = .bold }, { $0.batterySymbolScale = 0.9 },
            { $0.batterySymbolScale = 1.1 }, { $0.wifiSymbolScale = 1 }, { $0.wifiSymbolScale = 1.8 },
            { $0.showsBatteryPercentage = false }, { $0.showsBatteryInCenter = true },
            { $0.volumeStyle = .arc },
        ]
        for mutation in mutations {
            var configuration = MenuBarConfiguration()
            mutation(&configuration)
            let rendered = try bitmap(example, appearance: .aqua, configuration: configuration)
            XCTAssertNotEqual(baseline, rendered.tiffRepresentation)
        }
    }

    @MainActor
    func testColorPreferenceRemovesBatteryTintFromActualPixels() throws {
        var snapshot = example
        snapshot.battery?.percentage = 30
        var configuration = MenuBarConfiguration()
        configuration.batteryCriticalThreshold = 40
        let colored = try bitmap(snapshot, appearance: .aqua, configuration: configuration)
        configuration.usesBatteryColors = false
        let monochrome = try bitmap(snapshot, appearance: .aqua, configuration: configuration)
        XCTAssertGreaterThan(tintedPixelCount(colored), 100)
        XCTAssertEqual(tintedPixelCount(monochrome), 0)
    }

    @MainActor
    func testCenterBatteryOverridesBluetoothAndUnknownBatteryKeepsNetwork() throws {
        var snapshot = example
        var configuration = MenuBarConfiguration()
        configuration.showsBatteryInCenter = true
        configuration.replacesNetworkWithBluetooth = true
        let percentage = try bitmap(snapshot, appearance: .aqua, configuration: configuration)
            .tiffRepresentation
        snapshot.volume?.isBluetooth = true
        snapshot.network = .wired
        XCTAssertEqual(percentage, try bitmap(snapshot, appearance: .aqua,
                                              configuration: configuration).tiffRepresentation)
        snapshot.battery?.percentage = nil
        snapshot.volume?.isBluetooth = false
        let unknownWired = try bitmap(snapshot, appearance: .aqua, configuration: configuration)
            .tiffRepresentation
        snapshot.network = .off
        XCTAssertNotEqual(unknownWired, try bitmap(snapshot, appearance: .aqua,
                                                   configuration: configuration).tiffRepresentation)
    }

    @MainActor
    func testWiredWiFiOptionUsesFullSignalAndBluetoothHasSymbolFallbackAndTint() throws {
        var snapshot = example
        var configuration = MenuBarConfiguration()
        configuration.showsWiFiForWired = true
        let wifi = try bitmap(snapshot, appearance: .aqua, configuration: configuration).tiffRepresentation
        snapshot.network = .wired
        XCTAssertEqual(wifi, try bitmap(snapshot, appearance: .aqua,
                                        configuration: configuration).tiffRepresentation)
        snapshot.volume?.isBluetooth = true
        configuration.replacesNetworkWithBluetooth = true
        let headphones = try bitmap(snapshot, appearance: .aqua, configuration: configuration)
            .tiffRepresentation
        snapshot.volume?.symbolName = "blinker.missing.symbol"
        XCTAssertEqual(headphones, try bitmap(snapshot, appearance: .aqua,
                                              configuration: configuration).tiffRepresentation)
        configuration.bluetoothSymbolScale = 1
        XCTAssertNotEqual(headphones, try bitmap(snapshot, appearance: .aqua,
                                                 configuration: configuration).tiffRepresentation)
        configuration.replacesNetworkWithBluetooth = false
        configuration.usesBluetoothVolumeColor = true
        XCTAssertGreaterThan(try tintedPixelCount(bitmap(snapshot, appearance: .aqua,
                                                         configuration: configuration)), 100)
    }

    @MainActor
    func testVolumeArcIsContinuousAndUnknownIsNotMuted() throws {
        var snapshot = example
        var configuration = MenuBarConfiguration()
        configuration.volumeStyle = .arc
        snapshot.volume?.scalar = 0.26
        let lower = try bitmap(snapshot, appearance: .aqua, configuration: configuration).tiffRepresentation
        snapshot.volume?.scalar = 0.49
        XCTAssertNotEqual(lower, try bitmap(snapshot, appearance: .aqua,
                                            configuration: configuration).tiffRepresentation)
        snapshot.volume?.scalar = nil
        let unknown = try bitmap(snapshot, appearance: .aqua, configuration: configuration).tiffRepresentation
        snapshot.volume?.isMuted = true
        XCTAssertNotEqual(unknown, try bitmap(snapshot, appearance: .aqua,
                                              configuration: configuration).tiffRepresentation)
    }

    @MainActor
    func testDockBackgroundsKeepTransparentCornersAndRespectForcedPalette() throws {
        let light = try dockBitmap(background: .light, appearance: .darkAqua)
        let dark = try dockBitmap(background: .dark, appearance: .aqua)
        let transparent = try dockBitmap(background: .transparent, appearance: .aqua)
        XCTAssertGreaterThan(try XCTUnwrap(light.colorAt(x: 100, y: 512)).brightnessComponent, 0.9)
        XCTAssertLessThan(try XCTUnwrap(dark.colorAt(x: 100, y: 512)).brightnessComponent, 0.2)
        XCTAssertEqual(try XCTUnwrap(transparent.colorAt(x: 100, y: 512)).alphaComponent, 0)
        XCTAssertEqual(try XCTUnwrap(light.colorAt(x: 0, y: 0)).alphaComponent, 0)
        XCTAssertEqual(try dockBitmap(background: .system, appearance: .aqua).tiffRepresentation,
                       light.tiffRepresentation)
        XCTAssertEqual(try dockBitmap(background: .system, appearance: .darkAqua).tiffRepresentation,
                       dark.tiffRepresentation)
    }

    @MainActor
    private func dockBitmap(background: MenuBarConfiguration.DockBackground,
                            appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        var configuration = MenuBarConfiguration()
        configuration.dockBackground = background
        let image = try DockIconRenderer.image(snapshot: example, configuration: configuration,
                                               appearance: XCTUnwrap(NSAppearance(named: appearance)))
        XCTAssertEqual(image.size, NSSize(width: 1024, height: 1024))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0,
                                                    bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        image.draw(in: NSRect(origin: .zero, size: image.size))
        return bitmap
    }

    @MainActor
    private func tintedPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        (0 ..< bitmap.pixelsHigh).reduce(0) { total, row in
            total + (0 ..< bitmap.pixelsWide).filter { column in
                guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5 else { return false }
                return max(color.redComponent, color.greenComponent, color.blueComponent)
                    - min(color.redComponent, color.greenComponent, color.blueComponent) > 0.15
            }.count
        }
    }
}
