import AppKit
import Darwin

/// LaunchServices does not always supply launchDate (notably for Finder).
/// The kernel start time gives these processes the same PID-reuse protection.
struct WindowProcessIdentity: Equatable, Sendable {
    private enum Birth: Equatable, Sendable {
        case launchDate(Date)
        case kernel(WindowProcessStartTime)
    }

    let pid: Int32
    private let birth: Birth

    init?(application: NSRunningApplication) {
        guard !application.isTerminated else { return nil }
        self.init(pid: application.processIdentifier, launchDate: application.launchDate) {
            WindowProcessStartTime.read(pid: application.processIdentifier)
        }
        guard !application.isTerminated else { return nil }
    }

    init?(pid: Int32, launchDate: Date?, kernelStartTime: () -> WindowProcessStartTime?) {
        guard pid > 0 else { return nil }
        self.pid = pid
        if let launchDate {
            birth = .launchDate(launchDate)
        } else if let start = kernelStartTime() {
            birth = .kernel(start)
        } else {
            return nil
        }
    }

    func isCurrent() -> Bool {
        guard let application = NSRunningApplication(processIdentifier: pid),
              !application.isTerminated, !application.isHidden else { return false }
        return matches(launchDate: application.launchDate) { WindowProcessStartTime.read(pid: pid) }
    }

    /// Keep checking the original source even if LaunchServices later fills its date.
    func matches(launchDate: Date?, kernelStartTime: () -> WindowProcessStartTime?) -> Bool {
        switch birth {
        case let .launchDate(expected): launchDate == expected
        case let .kernel(expected): kernelStartTime() == expected
        }
    }
}

struct WindowProcessStartTime: Equatable, Sendable {
    let seconds: UInt64
    let microseconds: UInt64

    init?(seconds: UInt64, microseconds: UInt64) {
        guard seconds > 0, microseconds < 1_000_000 else { return nil }
        self.seconds = seconds
        self.microseconds = microseconds
    }

    static func read(pid: Int32) -> Self? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid) else { return nil }
        return Self(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }
}
