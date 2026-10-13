import Foundation
import MacVitalsCore

/// The root LaunchDaemon: samples every few minutes, reports periodically, ends the session.
final class Daemon {
    private let paths: Paths
    private let config: Config
    private var state: SessionState
    private let store: SampleStore
    private let dispatcher: Dispatcher
    private let collector: SampleCollector

    /// How long to keep retrying a failed final report before uninstalling anyway (it stays on disk).
    private let finalDeliveryGrace: TimeInterval = 24 * 3600

    init(config: Config, paths: Paths = Paths.system) {
        self.paths = paths
        self.config = config
        store = SampleStore(file: paths.samplesFile)
        dispatcher = Dispatcher.make(config: config, paths: paths)
        collector = SampleCollector(config: config)

        var state = JSONFile.read(SessionState.self, from: paths.stateFile) ?? SessionState.new(config: config)
        // Config changes (e.g. MDM switching to "unlimited") apply to the running session.
        state.endDate = config.monitoringDays > 0
            ? state.startDate.addingTimeInterval(TimeInterval(config.monitoringDays) * 86_400)
            : nil
        self.state = state
    }

    func run() async {
        Log.info("MacVitals \(MacVitals.version) daemon starting; session \(state.startDate) → \(state.endDate.map { "\($0)" } ?? "no end date")")
        if let warning = ConfigLoader.permissionWarning(for: paths.configFile) { Log.warn(warning) }
        if config.webhook == nil { Log.info("No webhook configured; reports are only written to \(config.reportDirectory)") }

        if state.finished {
            await finishDelivery()
            return
        }
        saveState()

        // First start: prove delivery works right away. Restart/reboot: refresh the report.
        await report(state.lastReportDate == nil ? .initial : .partial)

        let interval = Duration.seconds(config.sampleIntervalSeconds)
        while true {
            // Continuous clock keeps counting while the Mac sleeps, so we sample right after wake.
            try? await Task.sleep(for: interval, clock: .continuous)

            do { try store.append(collector.collect()) } catch { Log.error("Could not store sample: \(error)") }

            let now = Date()
            if let end = state.endDate, now >= end {
                await report(.final)
                state.finished = true
                saveState()
                await finishDelivery()
                return
            }
            if now.timeIntervalSince(state.lastReportDate ?? .distantPast) >= TimeInterval(config.reportIntervalSeconds) {
                await report(.partial)
            } else {
                await dispatcher.flush()
            }
        }
    }

    private func report(_ kind: ReportKind) async {
        let input = ReportInput(kind: kind, config: config, state: state, machine: SystemInfo.machine(),
                                samples: store.load(), events: SystemInfo.panics(since: state.startDate))
        let report = ReportBuilder.build(input)
        writeLatestCopy(report.html)
        await dispatcher.deliver(report)
        state.reportsGenerated += 1
        state.lastReportDate = Date()
        saveState()
    }

    /// After the final report: retry anything still queued, then remove ourselves if configured to.
    private func finishDelivery() async {
        let deadline = (state.lastReportDate ?? Date()).addingTimeInterval(finalDeliveryGrace)
        while !dispatcher.outbox.isEmpty && Date() < deadline {
            await dispatcher.flush()
            if dispatcher.outbox.isEmpty { break }
            try? await Task.sleep(for: .seconds(config.sampleIntervalSeconds), clock: .continuous)
        }
        Log.info("Monitoring session finished.")
        if Paths.isDevelopment {
            Log.info("Development mode (MACVITALS_HOME): skipping self-removal.")
        } else if config.autoUninstall {
            Log.info("Auto-uninstall enabled; removing MacVitals (reports in \(config.reportDirectory) are kept).")
            Uninstaller.scheduleSelfRemoval()
        }
    }

    private func saveState() {
        do {
            try JSONFile.write(state, to: paths.stateFile, mode: 0o600)
            try JSONFile.write(PublicStatus(config: config, state: state), to: paths.publicStatusFile, mode: 0o644)
        } catch {
            Log.error("Could not save state: \(error)")
        }
    }

    /// The monitored user can always open exactly what IT receives.
    private func writeLatestCopy(_ html: String) {
        do {
            try Data(html.utf8).write(to: paths.latestReportFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.latestReportFile.path)
        } catch {
            Log.warn("Could not write latest report copy: \(error)")
        }
    }
}
