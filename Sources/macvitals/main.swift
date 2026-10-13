import Foundation
import MacVitalsCore

let usage = """
MacVitals \(MacVitals.version): privacy-respecting performance monitoring for Macs.

Usage: macvitals <command> [options]

Commands:
  status                    Show the monitoring session and delivery state
  sample                    Take one live measurement and print it as JSON
  report [-o FILE] [--open] Build a report from the data collected so far (sudo)
  demo-report [-o FILE] [--open] [--days N]
                            Build a report from realistic synthetic data (no install needed)
  send-test                 Deliver a test report to every configured destination (sudo)
  config                    Print the effective configuration (secrets masked) and validate it
  uninstall [--purge]       Remove MacVitals; reports are kept unless --purge (sudo)
  version                   Print the version

Internal (started by launchd):
  daemon                    Collector, runs as root
  agent                     Menu bar notice, runs as the logged-in user

Development: set MACVITALS_HOME=/some/folder to run the daemon without root, reading
config.json from and writing all data into that folder.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()

func option(_ names: String...) -> String? {
    guard let index = arguments.firstIndex(where: names.contains), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func flag(_ name: String) -> Bool { arguments.contains(name) }

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("macvitals: \(message)\n".utf8))
    exit(code)
}

func requireRoot(_ what: String) {
    if getuid() != 0 && !Paths.isDevelopment { fail("\(what) needs administrator rights; run it with sudo") }
}

func loadConfig() -> Config {
    do { return try ConfigLoader.load() } catch { fail("invalid configuration: \(error)") }
}

/// Runs async work from top-level code and exits with its status.
func runAsync(_ body: @escaping () async -> Int32) -> Never {
    Task { exit(await body()) }
    dispatchMain()
}

func writeReport(_ html: String, defaultName: String) {
    let path = option("-o", "--output") ?? FileManager.default.currentDirectoryPath + "/" + defaultName
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    do { try Data(html.utf8).write(to: url, options: .atomic) } catch { fail("could not write \(url.path): \(error)") }
    print("Report written to \(url.path)")
    if flag("--open") { _ = try? Shell.run("/usr/bin/open", [url.path]) }
}

switch command {
case "daemon":
    requireRoot("daemon mode")
    let config = loadConfig()
    runAsync {
        await Daemon(config: config).run()
        return 0
    }

case "agent":
    Agent.run()

case "status":
    let paths = Paths.system
    guard let status = JSONFile.read(PublicStatus.self, from: paths.publicStatusFile) else {
        fail("MacVitals is not running on this Mac (no \(paths.publicStatusFile.path))")
    }
    let dates = DateFormatter()
    dates.dateStyle = .medium
    dates.timeStyle = .short
    print("MacVitals \(status.version)")
    print("State:        \(status.active ? "monitoring" : "finished")")
    print("Organization: \(status.organizationName)")
    print("Started:      \(dates.string(from: status.startDate))")
    print("Ends:         \(status.endDate.map { dates.string(from: $0) } ?? "no end date")")
    print("Last report:  \(status.lastReportDate.map { dates.string(from: $0) } ?? "none yet")")
    if getuid() == 0 {
        let samples = SampleStore(file: paths.samplesFile).load()
        let queued = Outbox(directory: paths.outboxDirectory).pending(for: "webhook").count
            + Outbox(directory: paths.outboxDirectory).pending(for: "file").count
        let state = JSONFile.read(SessionState.self, from: paths.stateFile)
        print("Samples:      \(samples.count)")
        print("Reports:      \(state?.reportsGenerated ?? 0) generated; \(queued) waiting for retry")
    } else {
        print("(run with sudo for sample and delivery counts)")
    }

case "sample":
    var config = Config()
    config.topProcessCount = 5
    let collector = SampleCollector(config: config)
    Thread.sleep(forTimeInterval: 1)  // CPU usage is a delta between two readings
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try! encoder.encode(collector.collect()), as: UTF8.self))

case "report":
    requireRoot("reading collected data")
    let paths = Paths.system
    let config = loadConfig()
    guard let state = JSONFile.read(SessionState.self, from: paths.stateFile) else { fail("no monitoring session found") }
    let report = ReportBuilder.build(ReportInput(kind: .partial, config: config, state: state, machine: SystemInfo.machine(),
                                                 samples: SampleStore(file: paths.samplesFile).load(),
                                                 events: SystemInfo.panics(since: state.startDate)))
    writeReport(report.html, defaultName: report.fileName)

case "demo-report":
    let days = Int(option("--days") ?? "7") ?? 7
    var config = Config()
    config.organizationName = "Example Corp IT"
    config.supportContact = "helpdesk@example.com"
    let end = Date()
    var state = SessionState(startDate: end.addingTimeInterval(-Double(days) * 86_400), endDate: end)
    state.lastReportDate = end
    let samples = DemoData.samples(days: days, interval: TimeInterval(config.sampleIntervalSeconds), end: end)
    let events = [SystemEvent(date: samples[samples.count / 2].timestamp, kind: "Kernel panic", detail: "panic-full-demo.panic")]
    let report = ReportBuilder.build(ReportInput(kind: .final, config: config, state: state, machine: DemoData.machine,
                                                 samples: samples, events: events, generatedAt: end))
    writeReport(report.html, defaultName: "MacVitals-demo.html")

case "send-test":
    requireRoot("send-test")
    let config = loadConfig()
    let paths = Paths.system
    runAsync {
        let state = JSONFile.read(SessionState.self, from: paths.stateFile) ?? SessionState.new(config: config)
        var input = ReportInput(kind: .test, config: config, state: state, machine: SystemInfo.machine(),
                                samples: SampleStore(file: paths.samplesFile).load(), events: [])
        if input.samples.count < 2 {
            let collector = SampleCollector(config: config)
            try? await Task.sleep(for: .seconds(1))
            input.samples = [collector.collect(at: Date().addingTimeInterval(-60)), collector.collect()]
        }
        var report = ReportBuilder.build(input)
        report.fileName = "MacVitals-test_" + report.fileName
        let ok = await Dispatcher.make(config: config, paths: paths).deliver(report)
        print(ok ? "Test report delivered to: \(["file"] + (config.webhook == nil ? [] : ["webhook"]))" : "Delivery failed; see messages above.")
        return ok ? 0 : 1
    }

case "config":
    let paths = Paths.system
    let config = loadConfig()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try! encoder.encode(config.redacted), as: UTF8.self))
    if let warning = ConfigLoader.permissionWarning(for: paths.configFile) { print("WARNING: \(warning)") }
    print("Configuration is valid.")

case "uninstall":
    if Paths.isDevelopment { fail("uninstall is disabled while MACVITALS_HOME is set") }
    requireRoot("uninstall")
    do { try Uninstaller.run(purge: flag("--purge")) } catch { fail("uninstall failed: \(error)") }
    print("MacVitals removed\(flag("--purge") ? " (including reports)" : "; reports were kept").")

case "version", "--version", "-v":
    print(MacVitals.version)

case "help", "--help", "-h":
    print(usage)

default:
    fail("unknown command '\(command)'\n\n\(usage)", code: 64)
}
