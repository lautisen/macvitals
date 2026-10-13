import Darwin

/// Cumulative CPU tick counters for the whole machine.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Busy percentage between two readings. Counters are 32-bit in the kernel, so wrap-around is handled.
    public static func usagePercent(from old: CPUTicks, to new: CPUTicks) -> Double {
        func delta(_ a: UInt64, _ b: UInt64) -> UInt64 { b >= a ? b - a : (UInt64(UInt32.max) - a) + b + 1 }
        let busy = delta(old.user, new.user) + delta(old.system, new.system) + delta(old.nice, new.nice)
        let total = busy + delta(old.idle, new.idle)
        guard total > 0 else { return 0 }
        return min(100, Double(busy) / Double(total) * 100)
    }
}

final class CPUCollector {
    private var previous: CPUTicks?

    init() {
        previous = Self.readTicks()
    }

    /// Usage since the previous call (or since `init` the first time).
    func usagePercent() -> Double {
        guard let current = Self.readTicks() else { return 0 }
        defer { previous = current }
        guard let previous else { return 0 }
        return CPUTicks.usagePercent(from: previous, to: current)
    }

    static func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) > 0 ? loads[0] : 0
    }
}
