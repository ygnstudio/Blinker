// BLE battery scanning adapted from Status Trio, Copyright 2026 lingyired.
// Apache-2.0; upstream d1672377a172ee4cb4af53d5054610c407c0d34f.
// See ThirdParty/StatusTrio for license and attribution.
import CoreBluetooth
import Foundation

/// Connection and GATT callbacks, split from the scanner's lifecycle for
/// size. The narrow seams back into private state (`connect`,
/// `cancelPeripheralConnection`, `recordCooldown`, `emitNearby`,
/// `startNextQueuedConnections`) live in the main file.
extension BluetoothLEScanner {
    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard sessions[peripheral.identifier] != nil else { return }
        peripheral.discoverServices([
            BluetoothLEParsing.batteryServiceUUID,
            BluetoothLEParsing.deviceInformationServiceUUID,
        ])
    }

    func centralManager(
        _: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error _: (any Error)?
    ) {
        completeSession(for: peripheral.identifier, succeeded: false)
    }

    func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error _: (any Error)?
    ) {
        let succeeded = sessions[peripheral.identifier]?.batteryLevel != nil
        completeSession(for: peripheral.identifier, succeeded: succeeded)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices _: (any Error)?) {
        let identifier = peripheral.identifier
        guard var session = sessions[identifier] else { return }
        let services = peripheral.services ?? []
        guard services.contains(where: {
            $0.uuid == BluetoothLEParsing.batteryServiceUUID
        }) else {
            completeSession(for: identifier, succeeded: false)
            return
        }
        for service in services {
            if service.uuid == BluetoothLEParsing.batteryServiceUUID {
                session.pendingCharacteristicDiscoveries += 1
                peripheral.discoverCharacteristics([BluetoothLEParsing.batteryLevelUUID],
                                                   for: service)
            } else if service.uuid == BluetoothLEParsing.deviceInformationServiceUUID {
                session.pendingCharacteristicDiscoveries += 1
                peripheral.discoverCharacteristics(
                    [BluetoothLEParsing.modelNumberUUID, BluetoothLEParsing.manufacturerNameUUID],
                    for: service
                )
            }
        }
        sessions[identifier] = session
        finishSessionIfReady(identifier)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error _: (any Error)?
    ) {
        let identifier = peripheral.identifier
        guard var session = sessions[identifier] else { return }
        session.pendingCharacteristicDiscoveries -= 1
        let wanted: Set<CBUUID> = [
            BluetoothLEParsing.batteryLevelUUID,
            BluetoothLEParsing.modelNumberUUID,
            BluetoothLEParsing.manufacturerNameUUID,
        ]
        for characteristic in service.characteristics ?? []
        where wanted.contains(characteristic.uuid) {
            session.pendingReads.insert(characteristic.uuid)
            peripheral.readValue(for: characteristic)
        }
        sessions[identifier] = session
        finishSessionIfReady(identifier)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error _: (any Error)?
    ) {
        let identifier = peripheral.identifier
        guard var session = sessions[identifier] else { return }
        session.pendingReads.remove(characteristic.uuid)
        if let value = characteristic.value {
            switch characteristic.uuid {
            case BluetoothLEParsing.batteryLevelUUID:
                guard let level = BluetoothLEParsing.percentage(value) else {
                    completeSession(for: identifier, succeeded: false)
                    return
                }
                session.batteryLevel = level
            case BluetoothLEParsing.modelNumberUUID:
                session.model = BluetoothLEParsing.deviceInfo(value)
            case BluetoothLEParsing.manufacturerNameUUID:
                session.manufacturer = BluetoothLEParsing.deviceInfo(value)
            default:
                break
            }
        }
        sessions[identifier] = session
        // The model decides whether the row folds onto the paired list, so a
        // level publishes only once the model read has settled — otherwise the
        // row flickers between the nearby list and the paired one.
        if session.batteryLevel != nil,
           !session.pendingReads.contains(BluetoothLEParsing.modelNumberUUID) {
            emitNearby(session)
        }
        finishSessionIfReady(identifier)
    }

    private func finishSessionIfReady(_ identifier: UUID) {
        guard let session = sessions[identifier],
              session.pendingCharacteristicDiscoveries <= 0,
              session.pendingReads.isEmpty else { return }
        completeSession(for: identifier, succeeded: session.batteryLevel != nil)
    }

    func completeSession(for identifier: UUID, succeeded: Bool) {
        guard let session = sessions.removeValue(forKey: identifier) else { return }
        // The session's end is the last chance to publish a level whose model
        // never answered.
        emitNearby(session)
        session.timeoutTask?.cancel()
        session.peripheral.delegate = nil
        cancelPeripheralConnection(session.peripheral)
        candidatePeripherals.removeValue(forKey: identifier)
        candidateNames.removeValue(forKey: identifier)
        recordCooldown(for: identifier, succeeded: succeeded)
        startNextQueuedConnections()
    }
}
