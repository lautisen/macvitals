import Foundation
import Testing
@testable import MacVitalsCore

@Suite("Collector parsing")
struct CollectorParsingTests {
    @Test func psOutputIsParsedAndGroupedByName() {
        let output = """
          12.5  204800 Google Chrome Helper (Renderer)
           3.0  102400 Google Chrome Helper (Renderer)
           0.0    1024 launchd
          bogus line
          55.1 3145728 WindowServer
        """
        let processes = ProcessCollector.parse(output).sorted { $0.name < $1.name }
        #expect(processes.count == 3)
        let chrome = processes[0]
        #expect(chrome.name == "Google Chrome Helper (Renderer)")
        #expect(chrome.cpuPercent == 15.5)
        #expect(chrome.residentBytes == (204_800 + 102_400) * 1024)
        #expect(chrome.count == 2)
    }

    @Test func topProcessesIsUnionOfCPUAndMemoryLeaders() {
        let processes = [
            ProcessSnapshot(name: "cpuHog", cpuPercent: 300, residentBytes: 10),
            ProcessSnapshot(name: "memHog", cpuPercent: 0, residentBytes: 9_000_000_000),
            ProcessSnapshot(name: "idle", cpuPercent: 0.1, residentBytes: 20),
        ]
        let top = ProcessCollector.topProcesses(processes, count: 1).map(\.name)
        #expect(top == ["cpuHog", "memHog"])
    }

    @Test func appleSiliconBatteryUsesRawCapacityForHealth() throws {
        // Captured shape of `ioreg -rn AppleSmartBattery` on an M-series MacBook.
        let registry: [String: Any] = [
            "CurrentCapacity": 64, "MaxCapacity": 100, "DesignCapacity": 6075,
            "AppleRawMaxCapacity": 5103, "NominalChargeCapacity": 5225, "CycleCount": 412,
            "Temperature": 3071, "IsCharging": true, "ExternalConnected": true,
        ]
        let battery = try #require(BatteryCollector.parse(registry))
        #expect(battery.chargePercent == 64)
        #expect(battery.cycleCount == 412)
        #expect(abs(battery.healthPercent! - 86.0) < 0.1)  // Nominal 5225 / design 6075
        #expect(battery.temperatureCelsius == 30.71)
        #expect(battery.isCharging && battery.onExternalPower)
    }

    @Test func nestedBatteryDataLayoutIsSupported() throws {
        let registry: [String: Any] = [
            "CurrentCapacity": 35, "MaxCapacity": 100, "CycleCount": 201,
            "BatteryData": ["DesignCapacity": 8579, "NominalChargeCapacity": 8003, "AppleRawMaxCapacity": 7759],
        ]
        let battery = try #require(BatteryCollector.parse(registry))
        #expect(battery.chargePercent == 35)
        #expect(abs(battery.healthPercent! - 93.29) < 0.01)
    }

    @Test func intelBatteryReportsCapacityInMilliampHours() throws {
        let registry: [String: Any] = ["CurrentCapacity": 2500, "MaxCapacity": 5000, "DesignCapacity": 6000]
        let battery = try #require(BatteryCollector.parse(registry))
        #expect(battery.chargePercent == 50)
        #expect(abs(battery.healthPercent! - 83.33) < 0.01)
        #expect(!battery.onExternalPower)
    }

    @Test func desktopWithoutBatteryReturnsNil() {
        #expect(BatteryCollector.parse([:]) == nil)
    }

    @Test(arguments: [
        (CPUTicks(user: 0, system: 0, idle: 0, nice: 0), CPUTicks(user: 30, system: 20, idle: 50, nice: 0), 50.0),
        (CPUTicks(user: 100, system: 100, idle: 100, nice: 0), CPUTicks(user: 100, system: 100, idle: 200, nice: 0), 0.0),
        (CPUTicks(user: 0, system: 0, idle: 0, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0), 0.0),
    ])
    func cpuUsageFromTickDeltas(old: CPUTicks, new: CPUTicks, expected: Double) {
        #expect(CPUTicks.usagePercent(from: old, to: new) == expected)
    }

    @Test func cpuTickCounterWrapAroundIsHandled() {
        let old = CPUTicks(user: UInt64(UInt32.max) - 9, system: 0, idle: 0, nice: 0)
        let new = CPUTicks(user: 10, system: 0, idle: 20, nice: 0)
        #expect(CPUTicks.usagePercent(from: old, to: new) == 50)
    }

    @Test func memoryPressureLevelsMapFromSysctl() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
    }
}
