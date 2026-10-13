import Foundation
import MacVitalsCore

enum Uninstaller {
    /// Shell script so it can outlive the daemon that launches it (the daemon plist sets
    /// `AbandonProcessGroup`). Every path is a compile-time constant, quoted.
    static func script(purge: Bool, delaySeconds: Int) -> String {
        let support = Paths.system.supportDirectory.path
        let keepReports = purge ? "" : "! -name reports"
        return """
        sleep \(delaySeconds)
        for uid in $(/bin/ps -axo uid=,comm= | /usr/bin/awk '/loginwindow$/ {print $1}' | /usr/bin/sort -u); do
            /bin/launchctl bootout "gui/$uid/\(MacVitals.agentLabel)" 2>/dev/null
        done
        /bin/launchctl bootout 'system/\(MacVitals.daemonLabel)' 2>/dev/null
        /bin/rm -f '\(Paths.daemonPlist.path)' '\(Paths.agentPlist.path)' '\(Paths.cliSymlink.path)' '\(Paths.logFile.path)'
        if [ -d '\(support)' ]; then
            /usr/bin/find '\(support)' -mindepth 1 -maxdepth 1 \(keepReports) -exec /bin/rm -rf {} +
            /bin/rmdir '\(support)' 2>/dev/null
        fi
        /usr/sbin/pkgutil --forget '\(MacVitals.packageIdentifier)' >/dev/null 2>&1
        exit 0
        """
    }

    /// Interactive `sudo macvitals uninstall`.
    static func run(purge: Bool) throws {
        try Shell.run("/bin/sh", ["-c", script(purge: purge, delaySeconds: 0)])
    }

    /// Called by the daemon itself at the end of a session.
    static func scheduleSelfRemoval() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script(purge: false, delaySeconds: 3)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { Log.error("Could not start self-removal: \(error)") }
    }
}
