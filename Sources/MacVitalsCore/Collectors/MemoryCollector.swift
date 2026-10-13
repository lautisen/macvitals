import Darwin

enum MemoryCollector {
    static func snapshot() -> MemorySnapshot {
        let total = Sysctl.integer("hw.memsize", as: UInt64.self) ?? 0
        let pressure = MemoryPressure(sysctlLevel: Sysctl.integer("kern.memorystatus_vm_pressure_level") ?? 1)
        let swap = Sysctl.value("vm.swapusage", initial: xsw_usage())?.xsu_used ?? 0

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemorySnapshot(totalBytes: total, usedBytes: 0, compressedBytes: 0, swapUsedBytes: swap, pressure: pressure)
        }

        let page = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let used = min(total, appPages * page + wired + compressed)
        return MemorySnapshot(totalBytes: total, usedBytes: used, compressedBytes: compressed, swapUsedBytes: swap, pressure: pressure)
    }
}
