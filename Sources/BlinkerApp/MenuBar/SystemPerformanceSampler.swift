import Darwin
import Foundation

/// CPU load, memory pressure inputs, swap and uptime from mach `host_*`
/// calls and sysctl — all local, no permission, no I/O beyond the kernel.
enum SystemPerformance {
    struct CPUTicks: Equatable, Sendable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var total: UInt64 {
            user + system + idle + nice
        }
    }

    struct Memory: Equatable, Sendable {
        var usedBytes: Int64
        var totalBytes: Int64
    }

    struct Value: Equatable, Sendable {
        /// 0…1, averaged across cores since the previous read; nil until two
        /// samples exist.
        var cpuUsage: Double?
        var memory: Memory?
        var swapUsedBytes: Int64?
        var uptime: TimeInterval
    }

    /// Per-core tick deltas summed; busy = everything that is not idle.
    /// A core-count change (never on real hardware, but trivially in tests)
    /// or a counter regression yields no reading rather than a spike.
    static func usage(previous: [CPUTicks], current: [CPUTicks]) -> Double? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (before, after) in zip(previous, current) {
            guard after.total > before.total, after.idle >= before.idle else { return nil }
            let delta = after.total - before.total
            total += delta
            busy += delta - (after.idle - before.idle)
        }
        guard total > 0 else { return nil }
        return min(1, Double(busy) / Double(total))
    }

    /// Activity Monitor's approximation: App Memory ≈ active + wired +
    /// compressed pages. Free/inactive/speculative stay available.
    static func usedMemoryBytes(active: UInt64, wired: UInt64, compressed: UInt64,
                                pageSize: UInt64) -> UInt64 {
        (active + wired + compressed) * pageSize
    }

    static func sampleTicks() -> [CPUTicks]? {
        var cpuCount = natural_t(0)
        var info: processor_info_array_t?
        var infoCount = mach_msg_type_number_t(0)
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        guard cpuCount > 0, Int(infoCount) >= Int(cpuCount) * Int(CPU_STATE_MAX) else { return nil }
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for cpu in 0 ..< Int(cpuCount) {
            let load = info.withMemoryRebound(to: processor_cpu_load_info.self,
                                              capacity: Int(cpuCount)) { $0[cpu] }
            ticks.append(CPUTicks(user: UInt64(load.cpu_ticks.0),
                                  system: UInt64(load.cpu_ticks.1),
                                  idle: UInt64(load.cpu_ticks.2),
                                  nice: UInt64(load.cpu_ticks.3)))
        }
        return ticks
    }

    static func memory() -> Memory? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { integers in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, integers, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize = vm_size_t()
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0
        else { return nil }
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0, total > 0
        else { return nil }
        let used = usedMemoryBytes(active: UInt64(stats.active_count),
                                   wired: UInt64(stats.wire_count),
                                   compressed: UInt64(stats.compressor_page_count),
                                   pageSize: UInt64(pageSize))
        return Memory(usedBytes: Int64(min(used, total)), totalBytes: Int64(total))
    }

    static func swapUsed() -> Int64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Int64(usage.xsu_used)
    }

    /// `3d 4h` / `5h 12m` / `7m`; language-neutral units (the same precedent
    /// as the throughput row's `0 B/s`), sub-minute reads as 1m.
    static func formatUptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}

/// Keeps the CPU tick baseline across reads on the reader's serial queue.
/// Sampling always runs (one mach call is negligible), so enabling the rows
/// shows a value after the current interval instead of two.
final class SystemPerformanceSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: [SystemPerformance.CPUTicks]?
    private var lastUsage: Double?

    /// The panel value when `include` is set; the baseline advances either
    /// way so a later toggle-on has a fresh reference immediately.
    func read(include: Bool) -> SystemPerformance.Value? {
        lock.lock()
        defer { lock.unlock() }
        if let ticks = SystemPerformance.sampleTicks() {
            if let previous = previousTicks {
                lastUsage = SystemPerformance.usage(previous: previous, current: ticks)
                    ?? lastUsage
            }
            previousTicks = ticks
        }
        guard include else { return nil }
        return SystemPerformance.Value(cpuUsage: lastUsage,
                                       memory: SystemPerformance.memory(),
                                       swapUsedBytes: SystemPerformance.swapUsed(),
                                       uptime: ProcessInfo.processInfo.systemUptime)
    }
}
