import Foundation

enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Append-only JSON Lines file. One line per sample keeps writes atomic enough that a crash
/// or power loss costs at most the last line, which `load()` skips.
public struct SampleStore {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func append(_ sample: Sample) throws {
        var line = try JSON.encoder.encode(sample)
        line.append(0x0A)
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func load() -> [Sample] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? JSON.decoder.decode(Sample.self, from: Data($0)) }
    }
}

/// Lifecycle of one monitoring session. Root-only.
public struct SessionState: Codable, Equatable, Sendable {
    public var startDate: Date
    /// nil = runs until uninstalled.
    public var endDate: Date?
    public var lastReportDate: Date?
    public var reportsGenerated: Int = 0
    public var finished: Bool = false

    public init(startDate: Date, endDate: Date?) {
        self.startDate = startDate
        self.endDate = endDate
    }

    public static func new(config: Config, now: Date = Date()) -> SessionState {
        let end = config.monitoringDays > 0 ? now.addingTimeInterval(TimeInterval(config.monitoringDays) * 86_400) : nil
        return SessionState(startDate: now, endDate: end)
    }

    /// Stable for the whole session so each hourly upload replaces the previous one at the destination.
    public func reportFileName(machine: MachineInfo) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let parts = ["MacVitals", machine.computerName, machine.consoleUser ?? "nouser", formatter.string(from: startDate)]
        return parts.map(Self.safeFileComponent).joined(separator: "_") + ".html"
    }

    static func safeFileComponent(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        var out = ""
        for scalar in s.unicodeScalars {
            let c: Character = allowed.contains(scalar) ? Character(scalar) : "-"
            if c == "-" && out.hasSuffix("-") { continue }
            out.append(c)
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// What the unprivileged menu bar agent is allowed to know. World-readable, never contains secrets.
public struct PublicStatus: Codable, Equatable, Sendable {
    public var version: String
    public var organizationName: String
    public var supportContact: String
    public var showNotice: Bool
    public var collectsProcessNames: Bool
    public var startDate: Date
    public var endDate: Date?
    public var lastReportDate: Date?
    public var active: Bool

    public init(config: Config, state: SessionState) {
        version = MacVitals.version
        organizationName = config.organizationName
        supportContact = config.supportContact
        showNotice = config.showNotice
        collectsProcessNames = config.collectProcessNames
        startDate = state.startDate
        endDate = state.endDate
        lastReportDate = state.lastReportDate
        active = !state.finished
    }
}

public enum JSONFile {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSON.decoder.decode(T.self, from: data)
    }

    /// Atomic replace, then the requested permissions.
    public static func write<T: Encodable>(_ value: T, to url: URL, mode: Int = 0o600) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSON.encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
