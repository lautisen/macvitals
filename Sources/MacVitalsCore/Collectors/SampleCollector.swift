import Foundation

/// Combines every collector into one `Sample`. Keep a single instance alive: CPU usage is a delta between calls.
public final class SampleCollector {
    private let cpu = CPUCollector()
    private let config: Config

    public init(config: Config) {
        self.config = config
    }

    public func collect(at date: Date = Date()) -> Sample {
        Sample(
            timestamp: date,
            cpuPercent: cpu.usagePercent(),
            loadAverage: CPUCollector.loadAverage(),
            memory: MemoryCollector.snapshot(),
            disk: DiskCollector.snapshot(),
            battery: BatteryCollector.snapshot(),
            thermalState: ThermalState(ProcessInfo.processInfo.thermalState),
            processes: config.collectProcessNames ? ProcessCollector.snapshot(top: config.topProcessCount) : []
        )
    }
}
