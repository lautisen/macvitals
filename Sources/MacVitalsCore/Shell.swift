import Foundation

public enum Shell {
    public struct Failure: Error, CustomStringConvertible {
        public var command: String
        public var status: Int32
        public var output: String
        public var description: String { "\(command) exited with \(status): \(output)" }
    }

    /// Runs an executable by absolute path (never through a shell, so arguments are not re-parsed).
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw Failure(command: ([executable] + arguments).joined(separator: " "), status: process.terminationStatus, output: output)
        }
        return output
    }
}

public enum Log {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// launchd redirects stdout to `/Library/Logs/MacVitals.log`.
    public static func info(_ message: String) { emit("INFO", message) }
    public static func warn(_ message: String) { emit("WARN", message) }
    public static func error(_ message: String) { emit("ERROR", message) }

    private static func emit(_ level: String, _ message: String) {
        print("\(formatter.string(from: Date())) [\(level)] \(message)")
        fflush(stdout)
    }
}
