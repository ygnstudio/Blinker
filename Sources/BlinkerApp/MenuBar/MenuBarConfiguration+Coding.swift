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
        case showsMutedMicInIcon
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
        case showsVPNStatus
        case showsWiFiName
        case showsAudioInput
        case bluetoothDeviceLimit
        case alwaysShowsAllBluetoothDevices
        case bluetoothDeviceOrder
        case hiddenBluetoothDevices
        case hidesUnpairedBluetoothDevices
        case scansNearbyBluetoothDevices
        case showsBatteryDetails
        case showsNetworkActivity
        case showsLocalIPAddress
        case showsPublicIPAddress
        case showsBluetoothSignalStrength
        case enablesBluetoothDeviceControl
        case panelDensity
        case showsQuickActionMicMute
        case showsQuickActionDisplayCleaning
        case showsQuickActionKeyboardCleaning
        case showsQuickActionEmptyTrash
        case showsQuickActionKeepAwake
        case showsQuickActionDesktopIcons
        case showsQuickActionHiddenFiles
        case showsQuickActionScreenSaver
        case showsQuickActionDisplaySleep
        case showsQuickActionLockScreen
        case showsQuickActionBluetoothConnect
        case quickActionAudioDeviceAddress
        case quickActionAudioDeviceName
        case shortcutSlots
        case showsInternalStorage
        case showsExternalVolumes
        case showsCPULoad
        case showsMemoryUsage
        case showsSwapUsage
        case showsUptime
    }

    /// New settings retain defaults when reading an older saved configuration.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        decodeAppearance(from: values)
        decodeInteraction(from: values)
        decodeBluetooth(from: values)
        decodeQuickActions(from: values)
        // A save written before the bluetooth section existed carries no trace
        // of it in sectionOrder; enable the section for those users exactly
        // once. Saves written afterwards always list it, enabled or not.
        if !sectionOrder.contains(.bluetooth) {
            enabledSections.insert(.bluetooth)
        }
        // Same one-time enable for the quick actions page. Saves written
        // before it existed carry none of its keys; newer saves always do.
        // (The section used to ride along in sectionOrder; normalized()
        // strips it now that quick actions is a page of its own.)
        if !values.contains(.showsQuickActionMicMute) {
            enabledSections.insert(.quickActions)
        }
        // Same one-time enable for storage and performance: saves written
        // before they existed carry none of their keys; newer saves always do.
        if !values.contains(.showsCPULoad) {
            enabledSections.formUnion([.storage, .performance])
        }
        self = normalized()
    }

    private mutating func decodeAppearance(from values: KeyedDecodingContainer<CodingKeys>) {
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
        showsMutedMicInIcon = values.decode(.showsMutedMicInIcon, default: showsMutedMicInIcon)
        replacesNetworkWithBluetooth = values.decode(
            .replacesNetworkWithBluetooth,
            default: replacesNetworkWithBluetooth
        )
        usesBluetoothVolumeColor = values.decode(.usesBluetoothVolumeColor, default: usesBluetoothVolumeColor)
        prioritizesNetworkErrors = values.decode(.prioritizesNetworkErrors, default: prioritizesNetworkErrors)
        bluetoothSymbolScale = values.decode(.bluetoothSymbolScale, default: bluetoothSymbolScale)
        refreshInterval = values.decode(.refreshInterval, default: refreshInterval)
        showsVPNStatus = values.decode(.showsVPNStatus, default: showsVPNStatus)
        showsWiFiName = values.decode(.showsWiFiName, default: showsWiFiName)
        showsAudioInput = values.decode(.showsAudioInput, default: showsAudioInput)
        showsBatteryDetails = values.decode(.showsBatteryDetails, default: showsBatteryDetails)
        showsNetworkActivity = values.decode(.showsNetworkActivity, default: showsNetworkActivity)
        showsLocalIPAddress = values.decode(.showsLocalIPAddress, default: showsLocalIPAddress)
        showsPublicIPAddress = values.decode(.showsPublicIPAddress, default: showsPublicIPAddress)
    }

    private mutating func decodeInteraction(from values: KeyedDecodingContainer<CodingKeys>) {
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
    }

    private mutating func decodeBluetooth(from values: KeyedDecodingContainer<CodingKeys>) {
        bluetoothDeviceLimit = values.decode(.bluetoothDeviceLimit, default: bluetoothDeviceLimit)
        alwaysShowsAllBluetoothDevices = values.decode(
            .alwaysShowsAllBluetoothDevices,
            default: alwaysShowsAllBluetoothDevices
        )
        bluetoothDeviceOrder = values.decode(.bluetoothDeviceOrder, default: bluetoothDeviceOrder)
        hiddenBluetoothDevices = values.decode(.hiddenBluetoothDevices, default: hiddenBluetoothDevices)
        hidesUnpairedBluetoothDevices = values.decode(
            .hidesUnpairedBluetoothDevices,
            default: hidesUnpairedBluetoothDevices
        )
        scansNearbyBluetoothDevices = values.decode(
            .scansNearbyBluetoothDevices,
            default: scansNearbyBluetoothDevices
        )
        showsBluetoothSignalStrength = values.decode(
            .showsBluetoothSignalStrength,
            default: showsBluetoothSignalStrength
        )
        enablesBluetoothDeviceControl = values.decode(
            .enablesBluetoothDeviceControl,
            default: enablesBluetoothDeviceControl
        )
        panelDensity = values.decode(.panelDensity, default: panelDensity)
        showsQuickActionMicMute = values.decode(.showsQuickActionMicMute, default: showsQuickActionMicMute)
        showsQuickActionDisplayCleaning = values.decode(
            .showsQuickActionDisplayCleaning,
            default: showsQuickActionDisplayCleaning
        )
        showsQuickActionKeyboardCleaning = values.decode(
            .showsQuickActionKeyboardCleaning,
            default: showsQuickActionKeyboardCleaning
        )
        showsQuickActionEmptyTrash = values.decode(
            .showsQuickActionEmptyTrash,
            default: showsQuickActionEmptyTrash
        )
        shortcutSlots = values.decode(.shortcutSlots, default: shortcutSlots)
        showsInternalStorage = values.decode(.showsInternalStorage, default: showsInternalStorage)
        showsExternalVolumes = values.decode(.showsExternalVolumes, default: showsExternalVolumes)
        showsCPULoad = values.decode(.showsCPULoad, default: showsCPULoad)
        showsMemoryUsage = values.decode(.showsMemoryUsage, default: showsMemoryUsage)
        showsSwapUsage = values.decode(.showsSwapUsage, default: showsSwapUsage)
        showsUptime = values.decode(.showsUptime, default: showsUptime)
    }

    /// Quick action row toggles and the Bluetooth connect target. Every key
    /// keeps its built-in default when absent, so saves written before a row
    /// existed simply adopt the default for it.
    private mutating func decodeQuickActions(from values: KeyedDecodingContainer<CodingKeys>) {
        showsQuickActionKeepAwake = values.decode(
            .showsQuickActionKeepAwake,
            default: showsQuickActionKeepAwake
        )
        showsQuickActionDesktopIcons = values.decode(
            .showsQuickActionDesktopIcons,
            default: showsQuickActionDesktopIcons
        )
        showsQuickActionHiddenFiles = values.decode(
            .showsQuickActionHiddenFiles,
            default: showsQuickActionHiddenFiles
        )
        showsQuickActionScreenSaver = values.decode(
            .showsQuickActionScreenSaver,
            default: showsQuickActionScreenSaver
        )
        showsQuickActionDisplaySleep = values.decode(
            .showsQuickActionDisplaySleep,
            default: showsQuickActionDisplaySleep
        )
        showsQuickActionLockScreen = values.decode(
            .showsQuickActionLockScreen,
            default: showsQuickActionLockScreen
        )
        showsQuickActionBluetoothConnect = values.decode(
            .showsQuickActionBluetoothConnect,
            default: showsQuickActionBluetoothConnect
        )
        quickActionAudioDeviceAddress = values.decode(
            .quickActionAudioDeviceAddress,
            default: quickActionAudioDeviceAddress
        )
        quickActionAudioDeviceName = values.decode(
            .quickActionAudioDeviceName,
            default: quickActionAudioDeviceName
        )
    }
}

private extension KeyedDecodingContainer {
    func decode<Value: Decodable>(_ key: Key, default fallback: Value) -> Value {
        (try? decodeIfPresent(Value.self, forKey: key)) ?? fallback
    }
}
