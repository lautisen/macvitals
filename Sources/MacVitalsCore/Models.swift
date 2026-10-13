import Foundation

/// One point-in-time measurement. Stored as one JSON line in `samples.jsonl`.
public struct Sample: Codable, Equatable, Sendable {
    public var timestamp: Date
    /// Whole-machine CPU usage, 0–100.
    public var cpuPercent: Double
    public var loadAverage: Double
    public var memory: MemorySnapshot
    public var disk: DiskSnapshot
    public var battery: BatterySnapshot?
    public var thermalState: ThermalState
    public var processes: [ProcessSnapshot]

    public init(timestamp: Date, cpuPercent: Double, loadAverage: Double, memory: MemorySnapshot,
                disk: DiskSnapshot, battery: BatterySnapshot?, thermalState: ThermalState, processes: [ProcessSnapshot]) {
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.loadAverage = loadAverage
        self.memory = memory
        self.disk = disk
        self.battery = battery
        self.thermalState = thermalState
        self.processes = processes
    }
}

public struct MemorySnapshot: Codable, Equatable, Sendable {
    public var totalBytes: UInt64
    /// "Memory Used" as Activity Monitor defines it: app memory + wired + compressed.
    public var usedBytes: UInt64
    public var compressedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: MemoryPressure

    public init(totalBytes: UInt64, usedBytes: UInt64, compressedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }

    public var usedPercent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
}

public enum MemoryPressure: String, Codable, Sendable, Comparable {
    case normal, warning, critical

    /// Values of the `kern.memorystatus_vm_pressure_level` sysctl.
    public init(sysctlLevel: Int) {
        switch sysctlLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }

    private var rank: Int { [.normal: 0, .warning: 1, .critical: 2][self]! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct DiskSnapshot: Codable, Equatable, Sendable {
    public var totalBytes: UInt64
    public var availableBytes: UInt64

    public init(totalBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
    }

    public var availablePercent: Double { totalBytes == 0 ? 0 : Double(availableBytes) / Double(totalBytes) * 100 }
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public var chargePercent: Double
    public var isCharging: Bool
    public var onExternalPower: Bool
    public var cycleCount: Int?
    /// Full-charge capacity relative to design capacity, 0–100+.
    public var healthPercent: Double?
    public var temperatureCelsius: Double?

    public init(chargePercent: Double, isCharging: Bool, onExternalPower: Bool, cycleCount: Int?,
                healthPercent: Double?, temperatureCelsius: Double?) {
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.onExternalPower = onExternalPower
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
        self.temperatureCelsius = temperatureCelsius
    }
}

public enum ThermalState: String, Codable, Sendable, Comparable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        default: self = .nominal
        }
    }

    private var rank: Int { [.nominal: 0, .fair: 1, .serious: 2, .critical: 3][self]! }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// CPU and memory of every process sharing a name, summed (e.g. all "Google Chrome Helper" processes).
public struct ProcessSnapshot: Codable, Equatable, Sendable {
    public var name: String
    /// `ps` %CPU: 100 = one full core, so values above 100 are possible.
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var count: Int

    public init(name: String, cpuPercent: Double, residentBytes: UInt64, count: Int = 1) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.count = count
    }
}

/// Static facts about the machine, captured when a report is built.
public struct MachineInfo: Codable, Equatable, Sendable {
    public var computerName: String
    public var consoleUser: String?
    public var model: String
    public var chip: String
    public var cpuCores: Int
    public var memoryBytes: UInt64
    public var osVersion: String
    public var bootTime: Date?

    public init(computerName: String, consoleUser: String?, model: String, chip: String, cpuCores: Int,
                memoryBytes: UInt64, osVersion: String, bootTime: Date?) {
        self.computerName = computerName
        self.consoleUser = consoleUser
        self.model = model
        self.chip = chip
        self.cpuCores = cpuCores
        self.memoryBytes = memoryBytes
        self.osVersion = osVersion
        self.bootTime = bootTime
    }
}

/// Kernel panics found in DiagnosticReports during the session.
public struct SystemEvent: Codable, Equatable, Sendable {
    public var date: Date
    public var kind: String
    public var detail: String

    public init(date: Date, kind: String, detail: String) {
        self.date = date
        self.kind = kind
        self.detail = detail
    }
}
