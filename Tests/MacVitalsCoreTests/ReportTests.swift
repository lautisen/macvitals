import Foundation
import Testing
@testable import MacVitalsCore

@Suite("Report rendering")
struct ReportTests {
    let machine = MachineInfo(computerName: "Test <Mac>", consoleUser: "jane", model: "Mac14,2", chip: "Apple M2",
                              cpuCores: 8, memoryBytes: 8 << 30, osVersion: "macOS 15", bootTime: nil)

    @Test func niceTicksCoverTheMaximum() {
        #expect(LineChart.niceTicks(max: 100, count: 4) == [0, 25, 50, 75, 100])
        #expect(LineChart.niceTicks(max: 61, count: 4) == [0, 20, 40, 60, 80])
        #expect(LineChart.niceTicks(max: 0, count: 4) == [0, 1])
    }

    @Test func downsamplingKeepsTheLimit() {
        let points = (0..<2000).map { (Date(timeIntervalSince1970: Double($0) * 60), Double($0)) }
        let reduced = LineChart.downsample(points, to: 600)
        #expect(reduced.count <= 600)
        #expect(reduced.first?.date == points.first?.0)
    }

    @Test func chartBreaksTheLineAcrossGaps() {
        let base = Date(timeIntervalSince1970: 0)
        let points = [0, 300, 600, 10_000, 10_300].map { (base.addingTimeInterval(Double($0)), 50.0) }
        let chart = LineChart(series: [ChartSeries(name: "CPU", colorIndex: 1, points: points)], unit: "%", yMax: 100, gapThreshold: 750)
        let path = chart.path(points, x: { $0.timeIntervalSince1970 }, y: { $0 })
        #expect(path.filter { $0 == "M" }.count == 2)
    }

    @Test func machineProvidedTextIsEscaped() {
        let state = SessionState(startDate: Date(timeIntervalSince1970: 1_760_000_000), endDate: nil)
        let samples = (0..<12).map { makeSample($0 * 5, processes: [ProcessSnapshot(name: "<script>alert(1)</script>", cpuPercent: 5, residentBytes: 1)]) }
        let report = ReportBuilder.build(ReportInput(kind: .partial, config: Config(), state: state, machine: machine, samples: samples, events: []))
        #expect(report.html.contains("Test &lt;Mac&gt;"))
        #expect(!report.html.contains("<script>alert(1)"))
        #expect(!report.html.contains("Test <Mac>"))
    }

    @Test func initialReportHasNoChartsYet() {
        let state = SessionState(startDate: Date(), endDate: nil)
        let report = ReportBuilder.build(ReportInput(kind: .initial, config: Config(), state: state, machine: machine, samples: [], events: []))
        #expect(report.html.contains("Monitoring is active"))
        #expect(!report.html.contains("<svg class=\"chart line-chart\""))
    }

    @Test func reportIsSelfContained() {
        let samples = DemoData.samples(days: 2)
        let state = SessionState(startDate: samples.first!.timestamp, endDate: samples.last!.timestamp)
        let html = ReportBuilder.build(ReportInput(kind: .final, config: Config(), state: state, machine: DemoData.machine, samples: samples, events: [])).html
        #expect(!html.contains("src=\"http"))
        #expect(!html.contains("href=\"http"))
        #expect(html.contains("data:text/csv;base64,"))
    }

    @Test func reportFileNameIsStableAndSafe() {
        let state = SessionState(startDate: Date(timeIntervalSince1970: 1_760_000_000), endDate: nil)
        #expect(state.reportFileName(machine: machine) == "MacVitals_Test-Mac_jane_20251009-0853.html")
    }

    @Test func demoDataIsDeterministic() {
        let end = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(DemoData.samples(days: 3, end: end) == DemoData.samples(days: 3, end: end))
    }

    @Test func csvHasOneRowPerSample() {
        let samples = (0..<5).map { makeSample($0) }
        #expect(CSV.samples(samples).split(separator: "\n").count == 6)
    }
}
