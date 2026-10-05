import Darwin
import Foundation

/// Interface byte counters and the machine's own IPv4 address, read from
/// `getifaddrs`. Only physical `en*` interfaces count toward throughput;
/// tunnels, bridges, loopback and link-local wireless (AWDL) are excluded so
/// the numbers describe real upstream traffic.
enum SystemNetworkActivity {
    struct Totals: Equatable, Sendable {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var localIPv4: String?
    }

    /// One point-in-time sample; nil when no eligible interface exists.
    static func sample() -> Totals? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var interfaces: [InterfaceSnapshot] = []
        var sequence: UnsafeMutablePointer<ifaddrs>? = first
        while let current = sequence {
            defer { sequence = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard isEligible(name: name) else { continue }
            let flags = current.pointee.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0 && (flags & UInt32(IFF_RUNNING)) != 0
            guard isUp else { continue }
            let family = current.pointee.ifa_addr?.pointee.sa_family
            if family == sa_family_t(AF_LINK),
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                interfaces.append(InterfaceSnapshot(name: name,
                                                    bytesIn: UInt64(data.pointee.ifi_ibytes),
                                                    bytesOut: UInt64(data.pointee.ifi_obytes),
                                                    ipv4Address: nil))
            } else if family == sa_family_t(AF_INET), let address = current.pointee.ifa_addr {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                                  &host, socklen_t(host.count),
                                  nil, 0, NI_NUMERICHOST) == 0 else { continue }
                interfaces.append(InterfaceSnapshot(name: name, bytesIn: 0, bytesOut: 0,
                                                    ipv4Address: String(cString: host)))
            }
        }
        return totals(interfaces: interfaces)
    }

    /// Aggregation, pure for tests. Counters sum across interfaces; the
    /// address is the first routable one, falling back to any address —
    /// link-local and loopback placeholders never win over a real one.
    struct InterfaceSnapshot: Equatable, Sendable {
        var name: String
        var bytesIn: UInt64
        var bytesOut: UInt64
        var ipv4Address: String?
    }

    static func totals(interfaces: [InterfaceSnapshot]) -> Totals? {
        guard !interfaces.isEmpty else { return nil }
        let bytesIn = interfaces.reduce(UInt64(0)) { $0 + $1.bytesIn }
        let bytesOut = interfaces.reduce(UInt64(0)) { $0 + $1.bytesOut }
        let addresses = interfaces.compactMap(\.ipv4Address)
        let routable = addresses.first { !$0.hasPrefix("169.254.") && !$0.hasPrefix("127.") }
        return Totals(bytesIn: bytesIn, bytesOut: bytesOut,
                      localIPv4: routable ?? addresses.first)
    }

    static func isEligible(name: String) -> Bool {
        name.hasPrefix("en")
    }

    /// Averaged rate in bytes per second. Interface counters are 32-bit on
    /// macOS, so a wrapped or reset counter is recovered once; anything else
    /// anomalous yields no rate rather than a spike.
    static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0.2, elapsed.isFinite else { return nil }
        let delta: UInt64
        if current >= previous {
            delta = current - previous
        } else if previous <= UInt64(UInt32.max) {
            delta = (UInt64(UInt32.max) + 1 - previous) + current
        } else {
            return nil
        }
        return Double(delta) / elapsed
    }

    /// `1.2 MB/s`-style readout; sub-KB rates show bytes, zero shows rest.
    static func formatRate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value > 0 else {
            return String(localized: "0 B/s")
        }
        let units = [(Double(1_000_000_000), "GB/s"), (1_000_000.0, "MB/s"), (1_000.0, "KB/s")]
        for (size, unit) in units where value >= size {
            let scaled = value / size
            let text = scaled >= 100
                ? String(format: "%.0f", scaled)
                : String(format: "%.1f", scaled)
            return "\(text) \(unit)"
        }
        return String(format: "%.0f B/s", value)
    }
}

/// Keeps the counter baseline across reads on the reader's serial queue.
/// Sampling always runs — one `getifaddrs` walk is negligible — so toggling
/// the rows shows a value after the current interval instead of two.
final class NetworkThroughputSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTotals: SystemNetworkActivity.Totals?
    private var previousAt: Date?
    /// Last computed average, republished when a burst read is too close to
    /// the previous one to form a rate; the row must not flicker on events.
    private var lastActivity: MenuBarSystemSnapshot.NetworkActivity?

    struct Reading: Equatable, Sendable {
        var activity: MenuBarSystemSnapshot.NetworkActivity?
        var localIPv4: String?
    }

    func read(includeActivity: Bool, includeAddress: Bool) -> Reading {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard let totals = SystemNetworkActivity.sample() else {
            previousTotals = nil
            previousAt = nil
            lastActivity = nil
            return Reading(activity: nil, localIPv4: nil)
        }
        var activity: MenuBarSystemSnapshot.NetworkActivity?
        if includeActivity {
            if let previousTotals, let previousAt {
                let elapsed = now.timeIntervalSince(previousAt)
                if let download = SystemNetworkActivity.rate(previous: previousTotals.bytesIn,
                                                             current: totals.bytesIn, elapsed: elapsed),
                   let upload = SystemNetworkActivity.rate(previous: previousTotals.bytesOut,
                                                           current: totals.bytesOut, elapsed: elapsed) {
                    lastActivity = MenuBarSystemSnapshot.NetworkActivity(
                        downBytesPerSecond: download, upBytesPerSecond: upload)
                }
            }
            activity = lastActivity
        }
        previousTotals = totals
        previousAt = now
        return Reading(activity: activity,
                       localIPv4: includeAddress ? totals.localIPv4 : nil)
    }
}

/// External address lookup, the panel's only outbound request and opt-in.
/// The fetch is asynchronous with a TTL cache; a failure backs off briefly
/// so a dead endpoint cannot spin the refresh loop.
final class PublicIPProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var fetchedAt: Date?
    private var retryNotBefore: Date?
    private var inFlight = false
    private let ttl: TimeInterval
    private let backoff: TimeInterval
    private let endpoint: URL
    private let session: URLSession

    init(endpoint: URL = URL(string: "https://api.ipify.org")!,
         ttl: TimeInterval = 600, backoff: TimeInterval = 60, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.ttl = ttl
        self.backoff = backoff
        self.session = session
    }

    /// The cached address while fresh; nil when never fetched or expired.
    func cachedValue(now: Date = Date()) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl else { return nil }
        return value
    }

    /// Starts a fetch when the cache is stale; `onChange` fires once when a
    /// new value lands so the monitor can republish. Never blocks the caller.
    func refreshIfNeeded(now: Date = Date(), onChange: @escaping @Sendable () -> Void) {
        lock.lock()
        if inFlight {
            lock.unlock()
            return
        }
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < ttl {
            lock.unlock()
            return
        }
        if let retryNotBefore, now < retryNotBefore {
            lock.unlock()
            return
        }
        inFlight = true
        lock.unlock()
        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let parsed = (response as? HTTPURLResponse).flatMap { $0.statusCode == 200 ? data : nil }
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(Self.sanitized(_:))
            lock.lock()
            inFlight = false
            if let parsed {
                let changed = parsed != value
                value = parsed
                fetchedAt = Date()
                retryNotBefore = nil
                lock.unlock()
                if changed { onChange() }
            } else {
                retryNotBefore = Date().addingTimeInterval(backoff)
                lock.unlock()
            }
        }.resume()
    }

    /// Accepts exactly one dotted-quad IPv4 or a textual IPv6 address; the
    /// endpoint answers with a bare address and anything else (markup,
    /// whitespace runs, oversized payloads) is treated as a failure.
    static func sanitized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 45,
              trimmed.contains(where: \.isNumber),
              trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":"
                  || ("a" ... "f").contains($0.lowercased()) }),
              trimmed.contains(".") || trimmed.contains(":")
        else { return nil }
        return trimmed
    }
}
