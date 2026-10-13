import Foundation

/// Realistic synthetic week of data, for `macvitals demo-report`, screenshots and tests.
/// Deterministic: the same seed always produces the same report.
public enum DemoData {
    public struct Seeded: RandomNumberGenerator {
        private var state: UInt64
        public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        public mutating func next() -> UInt64 {  // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    public static let machine = MachineInfo(
        computerName: "Design-MBP-14", consoleUser: "alex", model: "Mac15,6", chip: "Apple M3 Pro",
        cpuCores: 11, memoryBytes: 18 << 30, osVersion: "macOS Version 15.6 (Build 24G84)", bootTime: nil
    )

    public static func samples(days: Int = 7, interval: TimeInterval = 300, end: Date = Date(), seed: UInt64 = 42,
                               timeZone: TimeZone = .current) -> [Sample] {
        var rng = Seeded(seed: seed)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let total: UInt64 = 494_384_795_648
        var available: Double = 61e9
        var charge = 100.0
        var samples: [Sample] = []

        // The incident the report should catch: a runaway indexer on the last full weekday.
        var incidentDay = calendar.startOfDay(for: end.addingTimeInterval(-86_400))
        while calendar.isDateInWeekend(incidentDay) { incidentDay = calendar.date(byAdding: .day, value: -1, to: incidentDay)! }

        var t = start
        while t <= end {
            defer { t = t.addingTimeInterval(interval) }
            let hour = calendar.component(.hour, from: t)
            let weekday = calendar.component(.weekday, from: t)
            let weekend = weekday == 1 || weekday == 7
            // Lid closed overnight and most of the weekend: no samples (gaps in the charts).
            if hour < 8 || hour >= 20 || (weekend && !(10...12).contains(hour)) { continue }

            let working = (9...18).contains(hour)
            let videoCall = (hour == 11 || hour == 16) && !weekend
            let runaway = calendar.isDate(t, inSameDayAs: incidentDay) && (13...15).contains(hour)
            var cpu = Double.random(in: 4...14, using: &rng)
            if working { cpu += Double.random(in: 6...22, using: &rng) }
            if videoCall { cpu += Double.random(in: 20...35, using: &rng) }
            if runaway { cpu = Double.random(in: 88...99, using: &rng) }

            var memory = 58 + (working ? 14 : 0) + Double.random(in: -4...6, using: &rng) + (runaway ? 18 : 0)
            memory = min(memory, 97)
            let pressure: MemoryPressure = memory > 92 ? .critical : memory > 84 ? .warning : .normal
            let swap = UInt64(max(0, memory - 75) * 0.22e9)

            available = max(18e9, available - Double.random(in: 0...45e6, using: &rng))
            let onPower = !(13...16).contains(hour) || weekend
            if onPower { charge = min(100, charge + 4) } else { charge = max(12, charge - Double.random(in: 1.2...2.4, using: &rng)) }

            var processes = [
                ProcessSnapshot(name: "WindowServer", cpuPercent: cpu * 0.25, residentBytes: 610_000_000),
                ProcessSnapshot(name: "Google Chrome Helper (Renderer)", cpuPercent: working ? cpu * 0.9 : 3, residentBytes: 2_900_000_000, count: 14),
                ProcessSnapshot(name: "Slack Helper", cpuPercent: Double.random(in: 1...6, using: &rng), residentBytes: 780_000_000, count: 4),
                ProcessSnapshot(name: "Figma", cpuPercent: working ? Double.random(in: 5...30, using: &rng) : 0.5, residentBytes: 1_650_000_000),
                ProcessSnapshot(name: "kernel_task", cpuPercent: Double.random(in: 2...8, using: &rng), residentBytes: 450_000_000),
            ]
            if videoCall { processes.append(ProcessSnapshot(name: "zoom.us", cpuPercent: Double.random(in: 60...110, using: &rng), residentBytes: 520_000_000)) }
            if runaway { processes.append(ProcessSnapshot(name: "mds_stores", cpuPercent: Double.random(in: 380...540, using: &rng), residentBytes: 1_200_000_000)) }

            samples.append(Sample(
                timestamp: t,
                cpuPercent: min(cpu, 100),
                loadAverage: cpu / 100 * 11,
                memory: MemorySnapshot(totalBytes: 18 << 30, usedBytes: UInt64(memory / 100 * Double(18 << 30)),
                                       compressedBytes: UInt64(max(0, memory - 60) * 40e6), swapUsedBytes: swap, pressure: pressure),
                disk: DiskSnapshot(totalBytes: total, availableBytes: UInt64(available)),
                battery: BatterySnapshot(chargePercent: charge, isCharging: onPower && charge < 100, onExternalPower: onPower,
                                         cycleCount: 612, healthPercent: 78.4, temperatureCelsius: 30 + cpu / 6),
                thermalState: runaway && cpu > 95 ? .serious : .nominal,
                processes: processes
            ))
        }
        return samples
    }
}
