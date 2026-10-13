import Foundation
import Testing
@testable import MacVitalsCore

func makeSample(_ minute: Int, cpu: Double = 10, memoryPercent: Double = 50, pressure: MemoryPressure = .normal,
                diskFreePercent: Double = 50, swap: UInt64 = 0, thermal: ThermalState = .nominal,
                battery: BatterySnapshot? = nil, processes: [ProcessSnapshot] = []) -> Sample {
    let total: UInt64 = 16 << 30
    let disk: UInt64 = 500_000_000_000
    return Sample(
        timestamp: Date(timeIntervalSince1970: 1_760_000_000 + Double(minute) * 60),
        cpuPercent: cpu, loadAverage: 1,
        memory: MemorySnapshot(totalBytes: total, usedBytes: UInt64(memoryPercent / 100 * Double(total)),
                               compressedBytes: 0, swapUsedBytes: swap, pressure: pressure),
        disk: DiskSnapshot(totalBytes: disk, availableBytes: UInt64(diskFreePercent / 100 * Double(disk))),
        battery: battery, thermalState: thermal, processes: processes
    )
}

@Suite("Statistics and insights")
struct AnalysisTests {
    @Test func percentileInterpolates() {
        #expect(Stats.percentile([1, 2, 3, 4, 5], 50) == 3)
        #expect(Stats.percentile([0, 10], 95) == 9.5)
        #expect(Stats.percentile([], 50) == nil)
        #expect(Stats.mean([2, 4]) == 3)
    }

    @Test func healthyMacReportsNoProblems() {
        let samples = (0..<100).map { makeSample($0 * 5) }
        let insights = InsightEngine.analyze(samples: samples, events: [], sampleInterval: 300)
        #expect(insights.map(\.title) == ["No problems detected"])
    }

    @Test func shortContinuousCPUSpikeIsDetectedEvenIfRare() {
        // 1 000 calm samples and one 40-minute stretch at 98 %: under the 10 % share, over the 30 min streak.
        var samples = (0..<1000).map { makeSample($0 * 5) }
        for i in 500..<508 { samples[i].cpuPercent = 98 }
        let insights = InsightEngine.analyze(samples: samples, events: [], sampleInterval: 300)
        #expect(insights.contains { $0.title.hasPrefix("CPU saturated") })
    }

    @Test func isolatedCPUSpikesAreNotReported() {
        var samples = (0..<1000).map { makeSample($0 * 5) }
        for i in stride(from: 0, to: 1000, by: 50) { samples[i].cpuPercent = 99 }
        let insights = InsightEngine.analyze(samples: samples, events: [], sampleInterval: 300)
        #expect(!insights.contains { $0.title.hasPrefix("CPU saturated") })
    }

    @Test func sleepGapBreaksAStreak() {
        let samples = [0, 5, 10, 300, 305, 310].map { makeSample($0, cpu: 99) }
        #expect(InsightEngine.longestStreak(samples, maxGap: 750) { $0.cpuPercent > 90 } == 3)
    }

    @Test func criticalFindingsComeFirst() {
        let battery = BatterySnapshot(chargePercent: 50, isCharging: false, onExternalPower: false,
                                      cycleCount: 900, healthPercent: 71, temperatureCelsius: 30)
        let samples = (0..<20).map { makeSample($0 * 5, diskFreePercent: 3, battery: battery) }
        let insights = InsightEngine.analyze(samples: samples, events: [], sampleInterval: 300)
        #expect(insights.first?.severity == .critical)
        #expect(insights.contains { $0.title.hasPrefix("Disk almost full") })
        #expect(insights.contains { $0.title.hasPrefix("Battery needs service") })
    }

    @Test func kernelPanicIsCritical() {
        let samples = (0..<10).map { makeSample($0 * 5) }
        let events = [SystemEvent(date: samples[3].timestamp, kind: "Kernel panic", detail: "x.panic")]
        let insights = InsightEngine.analyze(samples: samples, events: events, sampleInterval: 300)
        #expect(insights.first?.title == "1 kernel panic")
    }

    @Test func processSummaryAveragesOverAllSamples() {
        let busy = ProcessSnapshot(name: "busy", cpuPercent: 100, residentBytes: 100)
        let samples = [makeSample(0, processes: [busy]), makeSample(5, processes: []), makeSample(10, processes: [busy]), makeSample(15)]
        let summary = try! #require(ProcessSummary.aggregate(samples).first)
        #expect(summary.cpuAverage == 50)  // present in 2 of 4 samples
        #expect(summary.presence == 0.5)
    }

    @Test func summaryComputesTimeOnBattery() {
        let unplugged = BatterySnapshot(chargePercent: 80, isCharging: false, onExternalPower: false,
                                        cycleCount: nil, healthPercent: nil, temperatureCelsius: nil)
        let samples = [makeSample(0, battery: unplugged), makeSample(5, battery: unplugged), makeSample(10)]
        #expect(Summary(samples: samples, sampleInterval: 300).minutesOnBattery == 10)
    }
}
