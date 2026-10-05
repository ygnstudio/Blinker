import Foundation

extension MenuBarConfiguration {
    enum CodingKeys: String, CodingKey {
        case placement
        case dockBackground
        case iconSize
        case stroke
        case showsBatteryPercentage
        case showsChargingIndicator
        case showsPercentageWhenConnected
        case usesBatteryColors
        case batteryCriticalThreshold
        case batterySymbolScale
        case showsChargingEffect
        case showsChargingHeartbeat
        case wifiSymbolScale
        case showsWiFiForWired
        case showsWiFiForHotspot
        case showsWiFiForTemporary
        case showsWiFiForSharing
        case showsBatteryInCenter
        case volumeStyle
        case replacesNetworkWithBluetooth
        case usesBluetoothVolumeColor
        case prioritizesNetworkErrors
        case bluetoothSymbolScale
        case refreshInterval
        case leftClick
        case sectionOrder
        case enabledSections
        case scrollAdjustsVolume
        case scrollScope
        case scrollDirection
        case naturalScrolling
        case outputDeviceLimit
        case alwaysShowsAllOutputDevices
        case outputDeviceOrder
    }

    /// New settings retain defaults when reading an older saved configuration.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        placement = values.decode(.placement, default: placement)
        dockBackground = values.decode(.dockBackground, default: dockBackground)
        iconSize = values.decode(.iconSize, default: iconSize)
        stroke = values.decode(.stroke, default: stroke)
        showsBatteryPercentage = values.decode(.showsBatteryPercentage, default: showsBatteryPercentage)
        showsChargingIndicator = values.decode(.showsChargingIndicator, default: showsChargingIndicator)
        showsPercentageWhenConnected = values.decode(
            .showsPercentageWhenConnected,
            default: showsPercentageWhenConnected
        )
        usesBatteryColors = values.decode(.usesBatteryColors, default: usesBatteryColors)
        batteryCriticalThreshold = values.decode(.batteryCriticalThreshold, default: batteryCriticalThreshold)
        batterySymbolScale = values.decode(.batterySymbolScale, default: batterySymbolScale)
        showsChargingEffect = values.decode(.showsChargingEffect, default: showsChargingEffect)
        showsChargingHeartbeat = values.decode(.showsChargingHeartbeat, default: showsChargingHeartbeat)
        wifiSymbolScale = values.decode(.wifiSymbolScale, default: wifiSymbolScale)
        showsWiFiForWired = values.decode(.showsWiFiForWired, default: showsWiFiForWired)
        showsWiFiForHotspot = values.decode(.showsWiFiForHotspot, default: showsWiFiForHotspot)
        showsWiFiForTemporary = values.decode(.showsWiFiForTemporary, default: showsWiFiForTemporary)
        showsWiFiForSharing = values.decode(.showsWiFiForSharing, default: showsWiFiForSharing)
        showsBatteryInCenter = values.decode(.showsBatteryInCenter, default: showsBatteryInCenter)
        volumeStyle = values.decode(.volumeStyle, default: volumeStyle)
        replacesNetworkWithBluetooth = values.decode(
            .replacesNetworkWithBluetooth,
            default: replacesNetworkWithBluetooth
        )
        usesBluetoothVolumeColor = values.decode(.usesBluetoothVolumeColor, default: usesBluetoothVolumeColor)
        prioritizesNetworkErrors = values.decode(.prioritizesNetworkErrors, default: prioritizesNetworkErrors)
        bluetoothSymbolScale = values.decode(.bluetoothSymbolScale, default: bluetoothSymbolScale)
        refreshInterval = values.decode(.refreshInterval, default: refreshInterval)
        leftClick = values.decode(.leftClick, default: leftClick)
        sectionOrder = values.decode(.sectionOrder, default: sectionOrder)
        enabledSections = values.decode(.enabledSections, default: enabledSections)
        scrollAdjustsVolume = values.decode(.scrollAdjustsVolume, default: scrollAdjustsVolume)
        scrollScope = values.decode(.scrollScope, default: scrollScope)
        scrollDirection = values.decode(.scrollDirection, default: scrollDirection)
        naturalScrolling = values.decode(.naturalScrolling, default: naturalScrolling)
        outputDeviceLimit = values.decode(.outputDeviceLimit, default: outputDeviceLimit)
        alwaysShowsAllOutputDevices = values.decode(
            .alwaysShowsAllOutputDevices,
            default: alwaysShowsAllOutputDevices
        )
        outputDeviceOrder = values.decode(.outputDeviceOrder, default: outputDeviceOrder)
        self = normalized()
    }
}

private extension KeyedDecodingContainer {
    func decode<Value: Decodable>(_ key: Key, default fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }
}
