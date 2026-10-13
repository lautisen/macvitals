import Foundation

public enum Stats {
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Linear-interpolated percentile, `p` in 0...100.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(0, min(1, p / 100)) * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down)), high = Int(rank.rounded(.up))
        return sorted[low] + (sorted[high] - sorted[low]) * (rank - Double(low))
    }
}

/// Session-wide aggregates used by both the HTML report and the webhook payload.
public struct Summary: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var cpuAverage: Double?
    public var cpuP95: Double?
    public var memoryAverage: Double?
    public var memoryPeak: Double?
    public var swapPeakBytes: UInt64
    public var diskAvailableMinBytes: UInt64?
    public var diskAvailableMinPercent: Double?
    public var batteryHealth: Double?
    public var batteryCycles: Int?
    public var minutesOnBattery: Double
    public var worstThermalState: ThermalState
    public var worstMemoryPressure: MemoryPressure

    public init(samples: [Sample], sampleInterval: TimeInterval) {
        sampleCount = samples.count
        let cpu = samples.map(\.cpuPercent)
        let memory = samples.map(\.memory.usedPercent)
        cpuAverage = Stats.mean(cpu)
        cpuP95 = Stats.percentile(cpu, 95)
        memoryAverage = Stats.mean(memory)
        memoryPeak = memory.max()
        swapPeakBytes = samples.map(\.memory.swapUsedBytes).max() ?? 0
        let lowestDisk = samples.min { $0.disk.availableBytes < $1.disk.availableBytes }
        diskAvailableMinBytes = lowestDisk?.disk.availableBytes
        diskAvailableMinPercent = lowestDisk?.disk.availablePercent
        let latestBattery = samples.last { $0.battery != nil }?.battery
        batteryHealth = latestBattery?.healthPercent
        batteryCycles = latestBattery?.cycleCount
        minutesOnBattery = Double(samples.filter { $0.battery.map { !$0.onExternalPower } ?? false }.count) * sampleInterval / 60
        worstThermalState = samples.map(\.thermalState).max() ?? .nominal
        worstMemoryPressure = samples.map(\.memory.pressure).max() ?? .normal
    }
}

/// Per-process aggregate across the whole session.
public struct ProcessSummary: Equatable, Sendable {
    public var name: String
    /// Average over *all* samples (absent = 0), so a briefly-busy process ranks below a constantly-busy one.
    public var cpuAverage: Double
    public var cpuPeak: Double
    public var memoryAverageBytes: UInt64
    public var memoryPeakBytes: UInt64
    /// Share of samples in which the process was in the top list.
    public var presence: Double

    public static func aggregate(_ samples: [Sample], limit: Int = 15) -> [ProcessSummary] {
        guard !samples.isEmpty else { return [] }
        var cpu: [String: [Double]] = [:]
        var memory: [String: [UInt64]] = [:]
        for sample in samples {
            for process in sample.processes {
                cpu[process.name, default: []].append(process.cpuPercent)
                memory[process.name, default: []].append(process.residentBytes)
            }
        }
        let n = Double(samples.count)
        return cpu.keys.map { name in
            let c = cpu[name]!, m = memory[name]!
            return ProcessSummary(
                name: name,
                cpuAverage: c.reduce(0, +) / n,
                cpuPeak: c.max() ?? 0,
                memoryAverageBytes: UInt64(Double(m.reduce(0, +)) / Double(m.count)),
                memoryPeakBytes: m.max() ?? 0,
                presence: Double(c.count) / n
            )
        }
        .sorted { ($0.cpuAverage, $0.memoryPeakBytes, $0.name) > ($1.cpuAverage, $1.memoryPeakBytes, $1.name) }
        .prefix(limit)
        .map { $0 }
    }
}
