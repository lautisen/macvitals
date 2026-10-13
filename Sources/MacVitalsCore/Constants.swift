import Foundation

/// Identifiers and on-disk locations shared by the daemon, the agent, the CLI and the installer scripts.
/// If you fork the project, change the identifiers here and in `scripts/build.sh`.
public enum MacVitals {
    public static let version = "0.1.0"

    public static let bundleIdentifier = "io.github.macvitals"
    public static let daemonLabel = "io.github.macvitals.daemon"
    public static let agentLabel = "io.github.macvitals.agent"
    public static let packageIdentifier = "io.github.macvitals.pkg"
}

public struct Paths: Sendable {
    public var supportDirectory: URL

    public init(supportDirectory: URL = URL(fileURLWithPath: "/Library/Application Support/MacVitals", isDirectory: true)) {
        self.supportDirectory = supportDirectory
    }

    /// `MACVITALS_HOME` relocates everything for development: the daemon then runs without root,
    /// never touches system locations and never uninstalls anything.
    public static let system: Paths = {
        if let home = developmentHome { return Paths(supportDirectory: URL(fileURLWithPath: home, isDirectory: true)) }
        return Paths()
    }()

    public static var developmentHome: String? {
        guard let home = ProcessInfo.processInfo.environment["MACVITALS_HOME"], !home.isEmpty else { return nil }
        return (home as NSString).expandingTildeInPath
    }

    public static var isDevelopment: Bool { developmentHome != nil }

    /// Root-only (0600). The only file that may contain secrets.
    public var configFile: URL { supportDirectory.appendingPathComponent("config.json") }
    /// Configuration profiles pushed by an MDM land here and override `config.json`.
    public static let managedPreferences = URL(fileURLWithPath: "/Library/Managed Preferences/\(MacVitals.bundleIdentifier).plist")

    public var dataDirectory: URL { supportDirectory.appendingPathComponent("data", isDirectory: true) }
    public var samplesFile: URL { dataDirectory.appendingPathComponent("samples.jsonl") }
    public var stateFile: URL { dataDirectory.appendingPathComponent("state.json") }
    public var outboxDirectory: URL { dataDirectory.appendingPathComponent("outbox", isDirectory: true) }

    /// World-readable summary for the menu bar agent, which runs as the logged-in user and cannot read the config.
    public var publicStatusFile: URL { supportDirectory.appendingPathComponent("status.json") }
    /// World-readable copy of the latest report, so the monitored user can see exactly what is collected.
    public var latestReportFile: URL { supportDirectory.appendingPathComponent("latest.html") }

    public static let logFile = URL(fileURLWithPath: "/Library/Logs/MacVitals.log")
    public static let daemonPlist = URL(fileURLWithPath: "/Library/LaunchDaemons/\(MacVitals.daemonLabel).plist")
    public static let agentPlist = URL(fileURLWithPath: "/Library/LaunchAgents/\(MacVitals.agentLabel).plist")
    public static let cliSymlink = URL(fileURLWithPath: "/usr/local/bin/macvitals")
}
