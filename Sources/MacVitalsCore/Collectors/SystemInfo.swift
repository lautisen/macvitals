import Foundation
import SystemConfiguration

public enum SystemInfo {
    public static func machine() -> MachineInfo {
        let boot = Sysctl.value("kern.boottime", initial: timeval()).map {
            Date(timeIntervalSince1970: TimeInterval($0.tv_sec) + TimeInterval($0.tv_usec) / 1_000_000)
        }
        return MachineInfo(
            computerName: computerName(),
            consoleUser: consoleUser(),
            model: Sysctl.string("hw.model") ?? "Mac",
            chip: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU",
            cpuCores: Sysctl.integer("hw.ncpu") ?? ProcessInfo.processInfo.processorCount,
            memoryBytes: Sysctl.integer("hw.memsize", as: UInt64.self) ?? 0,
            osVersion: "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
            bootTime: boot
        )
    }

    public static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName
    }

    /// The user logged in at the physical console, or nil at the login window.
    public static func consoleUser() -> String? {
        guard let name = SCDynamicStoreCopyConsoleUser(nil, nil, nil) as String?,
              !["", "loginwindow", "root"].contains(name) else { return nil }
        return name
    }

    /// Kernel panics are the one crash class worth surfacing to IT: they mean the whole Mac went down.
    public static func panics(since start: Date,
                              directories: [String] = ["/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports/Retired"]) -> [SystemEvent] {
        let fm = FileManager.default
        var events: [SystemEvent] = []
        for directory in directories {
            guard let files = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            for file in files where file.hasSuffix(".panic") || file.hasPrefix("panic-full") {
                let path = (directory as NSString).appendingPathComponent(file)
                guard let date = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date, date >= start else { continue }
                events.append(SystemEvent(date: date, kind: "Kernel panic", detail: file))
            }
        }
        return events.sorted { $0.date < $1.date }
    }
}
