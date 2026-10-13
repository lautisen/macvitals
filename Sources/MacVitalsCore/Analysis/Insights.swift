import Foundation

/// A plain-language finding for the technician, e.g. "Battery needs service".
public struct Insight: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable, Comparable {
        case info, warning, critical
        private var rank: Int { [.info: 0, .warning: 1, .critical: 2][self]! }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    public var severity: Severity
    public var title: String
    public var detail: String

    public init(_ severity: Severity, _ title: String, _ detail: String) {
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// Rule-based diagnosis. Thresholds are deliberately conservative: a report full of
/// false alarms gets ignored.
public enum InsightEngine {
    public struct Thresholds: Sendable {
        public var cpuBusyPercent = 90.0
        public var cpuBusyShare = 0.10
        /// A single uninterrupted stretch this long is reported even if it is a small share of the week.
        public var cpuBusyStreak: TimeInterval = 30 * 60
        public var memoryPressureShare = 0.20
        public var swapWarningBytes: UInt64 = 2 << 30
        public var diskWarningPercent = 10.0
        public var diskCriticalPercent = 5.0
        public var batteryServicePercent = 80.0
        public var batteryHotCelsius = 45.0
        public var heavyProcessCPU = 50.0
        public init() {}
    }

    public static func analyze(samples: [Sample], events: [SystemEvent], sampleInterval: TimeInterval,
                               thresholds t: Thresholds = Thresholds()) -> [Insight] {
        guard !samples.isEmpty else { return [] }
        var insights: [Insight] = []
        let n = Double(samples.count)
        func duration(_ count: Int) -> String { Format.duration(Double(count) * sampleInterval) }

        if !events.isEmpty {
            insights.append(Insight(.critical, "\(events.count) kernel panic\(events.count == 1 ? "" : "s")",
                                    "The Mac restarted because of a system crash. Check hardware diagnostics (hold D at startup) and recently installed kernel extensions."))
        }

        let busy = samples.filter { $0.cpuPercent >= t.cpuBusyPercent }.count
        let streak = longestStreak(samples, maxGap: sampleInterval * 2.5) { $0.cpuPercent >= t.cpuBusyPercent }
        if Double(busy) / n >= t.cpuBusyShare || TimeInterval(streak) * sampleInterval >= t.cpuBusyStreak {
            insights.append(Insight(.warning, "CPU saturated for \(duration(busy))",
                                    "CPU was above \(Int(t.cpuBusyPercent)) % in \(Format.percent(Double(busy) / n * 100)) of samples; longest stretch \(duration(streak)). See the process table for the cause."))
        }

        let critical = samples.filter { $0.memory.pressure == .critical }.count
        let pressured = samples.filter { $0.memory.pressure >= .warning }.count
        if critical > 0 {
            insights.append(Insight(.critical, "Critical memory pressure for \(duration(critical))",
                                    "macOS ran out of memory and had to swap heavily or kill apps. More RAM or fewer simultaneous apps would help."))
        } else if Double(pressured) / n >= t.memoryPressureShare {
            insights.append(Insight(.warning, "Frequent memory pressure",
                                    "Memory pressure was elevated in \(Format.percent(Double(pressured) / n * 100)) of samples."))
        }

        if let swap = samples.map(\.memory.swapUsedBytes).max(), swap >= t.swapWarningBytes {
            insights.append(Insight(.warning, "Heavy swap use (peak \(Format.bytes(swap)))",
                                    "The Mac used the disk as memory, which makes it feel slow."))
        }

        if let lowest = samples.map(\.disk.availablePercent).min() {
            if lowest < t.diskCriticalPercent {
                insights.append(Insight(.critical, "Disk almost full (\(Format.percent(lowest)) free)",
                                        "macOS needs free space for updates, swap and caches. Free up space urgently."))
            } else if lowest < t.diskWarningPercent {
                insights.append(Insight(.warning, "Low disk space (\(Format.percent(lowest)) free)",
                                        "Below \(Int(t.diskWarningPercent)) % free space performance and updates can suffer."))
            }
        }

        if let battery = samples.last(where: { $0.battery != nil })?.battery {
            if let health = battery.healthPercent, health < t.batteryServicePercent {
                insights.append(Insight(.warning, "Battery needs service (\(Format.percent(health)) health)",
                                        "Full-charge capacity is below \(Int(t.batteryServicePercent)) % of the original design capacity\(battery.cycleCount.map { " after \($0) cycles" } ?? "")."))
            }
            if let hottest = samples.compactMap({ $0.battery?.temperatureCelsius }).max(), hottest >= t.batteryHotCelsius {
                insights.append(Insight(.warning, "Battery ran hot (\(Format.number(hottest)) °C)",
                                        "Sustained heat ages the battery. Check ventilation and heavy workloads."))
            }
        }

        let hot = samples.filter { $0.thermalState >= .serious }.count
        if hot > 0 {
            insights.append(Insight(.warning, "Thermal throttling for \(duration(hot))",
                                    "macOS slowed the CPU to control temperature."))
        }

        if let top = ProcessSummary.aggregate(samples, limit: 1).first, top.cpuAverage >= t.heavyProcessCPU {
            insights.append(Insight(.info, "\(top.name) is the heaviest process",
                                    "Average \(Format.percent(top.cpuAverage)) CPU over the whole period (100 % = one core)."))
        }

        if insights.allSatisfy({ $0.severity == .info }) {
            insights.insert(Insight(.info, "No problems detected", "CPU, memory, disk, battery and temperature stayed within normal ranges."), at: 0)
        }
        return insights.sorted { $0.severity > $1.severity }
    }

    /// Longest run of consecutive matching samples; a gap (sleep) breaks the run.
    static func longestStreak(_ samples: [Sample], maxGap: TimeInterval, where matches: (Sample) -> Bool) -> Int {
        var best = 0, current = 0
        var previous: Date?
        for sample in samples {
            let contiguous = previous.map { sample.timestamp.timeIntervalSince($0) <= maxGap } ?? false
            current = matches(sample) ? (contiguous ? current + 1 : 1) : 0
            best = max(best, current)
            previous = sample.timestamp
        }
        return best
    }
}

public enum Format {
    public static func percent(_ value: Double) -> String { number(value) + " %" }

    public static func number(_ value: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func bytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(clamping: value))
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        return hours < 48 ? "\(number(hours)) h" : "\(number(hours / 24)) days"
    }
}
