import Foundation

public struct GlobalHotkeyBinding: Equatable {
    public let key: String
    public let id: UInt32
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(key: String, id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        self.key = key
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Main-thread owner of registrations, independent of persisted user bindings.
public final class GlobalHotkeyRegistry {
    public enum Failure: Equatable {
        case handler(Int32)
        case registration(Int32)
    }

    public private(set) var failures: [String: Failure] = [:]
    public var onPress: ((UInt32) -> Void)?
    private let driver: any HotkeyRegistrationDriving
    private var desired: [GlobalHotkeyBinding] = []
    private var registered = Set<String>()
    private var active = false
    private var handlerReady = false

    public convenience init(signature: UInt32) {
        self.init(driver: CarbonHotkeyDriver(signature: signature))
    }

    init(driver: any HotkeyRegistrationDriving) {
        self.driver = driver
    }

    /// Unchanged successful registrations stay installed. Pausing or disabling
    /// releases OS resources and failures, while the caller keeps user bindings.
    public func update(_ bindings: [GlobalHotkeyBinding], enabled: Bool, paused: Bool) {
        let byKey = Dictionary(bindings.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for old in desired where byKey[old.key] != old {
            remove(old.key)
        }
        var seen = Set<String>()
        desired = bindings.filter { seen.insert($0.key).inserted }
        active = enabled && !paused
        guard active, !desired.isEmpty else { stop(); return }
        register(desired.filter { !registered.contains($0.key) })
    }

    /// A handler failure affects every binding; retrying any row restores the
    /// handler and all missing registrations. Otherwise only that row retries.
    public func retry(_ key: String) {
        guard active, let binding = desired.first(where: { $0.key == key }) else { return }
        guard !registered.contains(key) else { return }
        register([binding])
    }

    private func register(_ bindings: [GlobalHotkeyBinding]) {
        var pending = bindings
        if !handlerReady {
            let status = driver.installHandler { [weak self] identity in
                guard let self, active,
                      desired.contains(where: { $0.id == identity && self.registered.contains($0.key) })
                else {
                    return
                }
                onPress?(identity)
            }
            guard status == 0 else {
                failures = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, .handler(status)) })
                return
            }
            handlerReady = true
            pending = desired.filter { !registered.contains($0.key) }
        }
        for binding in pending {
            let status = driver.register(binding)
            if status == 0 {
                registered.insert(binding.key)
                failures[binding.key] = nil
            } else {
                failures[binding.key] = .registration(status)
            }
        }
    }

    private func remove(_ key: String) {
        if registered.remove(key) != nil {
            driver.unregister(key)
        }
        failures[key] = nil
    }

    private func stop() {
        for key in registered {
            driver.unregister(key)
        }
        registered = []
        failures = [:]
        if handlerReady {
            driver.removeHandler()
        }
        handlerReady = false
    }

    deinit { stop() }
}

protocol HotkeyRegistrationDriving: AnyObject {
    func installHandler(onPress: @escaping (UInt32) -> Void) -> Int32
    func removeHandler()
    func register(_ binding: GlobalHotkeyBinding) -> Int32
    func unregister(_ key: String)
}
