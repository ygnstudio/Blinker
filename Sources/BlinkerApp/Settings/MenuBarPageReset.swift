import Foundation

extension MenuBarConfiguration {
    /// Each sidebar page resets only the preferences it edits.
    func resetting(_ page: MenuBarSettingsPage) -> Self {
        let defaults = Self()
        var value = self
        switch page {
        case .icon:
            value.placement = defaults.placement
            value.dockBackground = defaults.dockBackground
            value.iconSize = defaults.iconSize
            value.stroke = defaults.stroke
            value.leftClick = defaults.leftClick
            value.refreshInterval = defaults.refreshInterval
            value.replacesNetworkWithBluetooth = defaults.replacesNetworkWithBluetooth
            value.prioritizesNetworkErrors = defaults.prioritizesNetworkErrors
            value.bluetoothSymbolScale = defaults.bluetoothSymbolScale
        case .battery:
            value.showsBatteryPercentage = defaults.showsBatteryPercentage
            value.showsBatteryInCenter = defaults.showsBatteryInCenter
            value.showsChargingIndicator = defaults.showsChargingIndicator
            value.showsPercentageWhenConnected = defaults.showsPercentageWhenConnected
            value.batterySymbolScale = defaults.batterySymbolScale
            value.usesBatteryColors = defaults.usesBatteryColors
            value.batteryCriticalThreshold = defaults.batteryCriticalThreshold
            value.showsChargingEffect = defaults.showsChargingEffect
            value.showsChargingHeartbeat = defaults.showsChargingHeartbeat
            value.showsBatteryDetails = defaults.showsBatteryDetails
        case .network:
            value.resetNetwork(to: defaults)
        case .audio:
            value.resetAudio(to: defaults)
        case .bluetooth:
            value.resetBluetooth(to: defaults)
        case .quickActions:
            value.resetQuickActions(to: defaults)
        case .panel:
            value.sectionOrder = defaults.sectionOrder
            value.enabledSections = defaults.enabledSections
            value.panelDensity = defaults.panelDensity
        case .storage:
            value.showsInternalStorage = defaults.showsInternalStorage
            value.showsExternalVolumes = defaults.showsExternalVolumes
        case .performance:
            value.showsCPULoad = defaults.showsCPULoad
            value.showsMemoryUsage = defaults.showsMemoryUsage
            value.showsSwapUsage = defaults.showsSwapUsage
            value.showsUptime = defaults.showsUptime
        }
        return value
    }

    private mutating func resetBluetooth(to defaults: Self) {
        bluetoothDeviceLimit = defaults.bluetoothDeviceLimit
        alwaysShowsAllBluetoothDevices = defaults.alwaysShowsAllBluetoothDevices
        bluetoothDeviceOrder = defaults.bluetoothDeviceOrder
        hiddenBluetoothDevices = defaults.hiddenBluetoothDevices
        hidesUnpairedBluetoothDevices = defaults.hidesUnpairedBluetoothDevices
        scansNearbyBluetoothDevices = defaults.scansNearbyBluetoothDevices
        showsBluetoothSignalStrength = defaults.showsBluetoothSignalStrength
        enablesBluetoothDeviceControl = defaults.enablesBluetoothDeviceControl
    }

    private mutating func resetNetwork(to defaults: Self) {
        wifiSymbolScale = defaults.wifiSymbolScale
        showsWiFiForWired = defaults.showsWiFiForWired
        showsWiFiForHotspot = defaults.showsWiFiForHotspot
        showsWiFiForTemporary = defaults.showsWiFiForTemporary
        showsWiFiForSharing = defaults.showsWiFiForSharing
        showsVPNStatus = defaults.showsVPNStatus
        showsWiFiName = defaults.showsWiFiName
        showsNetworkActivity = defaults.showsNetworkActivity
        showsLocalIPAddress = defaults.showsLocalIPAddress
        showsPublicIPAddress = defaults.showsPublicIPAddress
    }

    private mutating func resetAudio(to defaults: Self) {
        volumeStyle = defaults.volumeStyle
        usesBluetoothVolumeColor = defaults.usesBluetoothVolumeColor
        showsMutedMicInIcon = defaults.showsMutedMicInIcon
        showsAudioInput = defaults.showsAudioInput
        outputDeviceLimit = defaults.outputDeviceLimit
        alwaysShowsAllOutputDevices = defaults.alwaysShowsAllOutputDevices
        outputDeviceOrder = defaults.outputDeviceOrder
        scrollAdjustsVolume = defaults.scrollAdjustsVolume
        scrollScope = defaults.scrollScope
        scrollDirection = defaults.scrollDirection
        naturalScrolling = defaults.naturalScrolling
    }

    private mutating func resetQuickActions(to defaults: Self) {
        showsQuickActionMicMute = defaults.showsQuickActionMicMute
        showsQuickActionDisplayCleaning = defaults.showsQuickActionDisplayCleaning
        showsQuickActionKeyboardCleaning = defaults.showsQuickActionKeyboardCleaning
        showsQuickActionEmptyTrash = defaults.showsQuickActionEmptyTrash
        showsQuickActionKeepAwake = defaults.showsQuickActionKeepAwake
        showsQuickActionShowDesktop = defaults.showsQuickActionShowDesktop
        showsQuickActionDesktopIcons = defaults.showsQuickActionDesktopIcons
        showsQuickActionHiddenFiles = defaults.showsQuickActionHiddenFiles
        showsQuickActionShowExtensions = defaults.showsQuickActionShowExtensions
        showsQuickActionLowPowerMode = defaults.showsQuickActionLowPowerMode
        showsQuickActionScreenSaver = defaults.showsQuickActionScreenSaver
        showsQuickActionDisplaySleep = defaults.showsQuickActionDisplaySleep
        showsQuickActionLockScreen = defaults.showsQuickActionLockScreen
        showsQuickActionDarkMode = defaults.showsQuickActionDarkMode
        showsQuickActionResolution = defaults.showsQuickActionResolution
        showsQuickActionBluetoothConnect = defaults.showsQuickActionBluetoothConnect
        quickActionAudioDeviceAddress = defaults.quickActionAudioDeviceAddress
        quickActionAudioDeviceName = defaults.quickActionAudioDeviceName
        shortcutSlots = defaults.shortcutSlots
    }
}
