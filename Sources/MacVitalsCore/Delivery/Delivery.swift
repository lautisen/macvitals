import CryptoKit
import Foundation

/// JSON body POSTed to the webhook. Versioned so receivers can evolve independently.
public struct ReportPayload: Codable, Equatable, Sendable {
    public var schema = 1
    public var kind: ReportKind
    public var fileName: String
    public var computerName: String
    public var user: String?
    public var generatedAt: Date
    public var periodStart: Date
    public var periodEnd: Date?
    public var summary: Summary
    public var insights: [Insight]
    public var contentType = "text/html"
    public var contentBase64: String

    public init(_ report: RenderedReport) {
        kind = report.kind
        fileName = report.fileName
        computerName = report.machine.computerName
        user = report.machine.consoleUser
        generatedAt = report.generatedAt
        periodStart = report.periodStart
        periodEnd = report.periodEnd
        summary = report.summary
        insights = report.insights
        contentBase64 = Data(report.html.utf8).base64EncodedString()
    }
}

/// Stripe-style request signing: `HMAC-SHA256(secret, "<timestamp>.<body>")`.
/// Including the timestamp lets receivers reject replays older than a few minutes.
public enum RequestSignature {
    public static let timestampHeader = "X-MacVitals-Timestamp"
    public static let signatureHeader = "X-MacVitals-Signature"

    public static func sign(body: Data, timestamp: Int, secret: String) -> String {
        var message = Data("\(timestamp).".utf8)
        message.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: Data(secret.utf8)))
        return "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Reference verifier (receivers in other languages should mirror this).
    public static func verify(body: Data, timestamp: Int, signature: String, secret: String,
                              now: Date = Date(), tolerance: TimeInterval = 300) -> Bool {
        guard abs(now.timeIntervalSince1970 - TimeInterval(timestamp)) <= tolerance else { return false }
        let expected = Array(sign(body: body, timestamp: timestamp, secret: secret).utf8)
        let given = Array(signature.utf8)
        guard expected.count == given.count else { return false }
        return zip(expected, given).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0  // constant time
    }
}

public protocol ReportSink {
    var name: String { get }
    func deliver(_ payload: ReportPayload, body: Data) async throws
}

/// Always enabled: writes the HTML report to a local folder (root:admin, 0640).
public struct FileSink: ReportSink {
    public var directory: URL
    public var name: String { "file" }

    public init(directory: URL) {
        self.directory = directory
    }

    public func deliver(_ payload: ReportPayload, body: Data) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o750])
        let url = directory.appendingPathComponent(payload.fileName)
        guard let html = Data(base64Encoded: payload.contentBase64) else { return }
        try html.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        if getuid() == 0 {
            try? fm.setAttributes([.groupOwnerAccountName: "admin"], ofItemAtPath: directory.path)
            try? fm.setAttributes([.groupOwnerAccountName: "admin"], ofItemAtPath: url.path)
        }
    }
}

/// POSTs the JSON payload to any HTTPS endpoint: Google Apps Script (Drive), Power Automate (SharePoint/OneDrive),
/// n8n, Make, Zapier, a cloud function, your own API…
public struct WebhookSink: ReportSink {
    public var config: Config.WebhookConfig
    public var session: URLSession
    public var name: String { "webhook" }

    public struct HTTPError: Error, CustomStringConvertible {
        public var status: Int
        public var body: String
        public var description: String { "HTTP \(status): \(body.prefix(200))" }
    }

    public init(config: Config.WebhookConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func makeRequest(body: Data, now: Date = Date()) throws -> URLRequest {
        guard var url = URL(string: config.url) else { throw Config.ValidationError.invalid("invalid webhook URL") }
        let timestamp = Int(now.timeIntervalSince1970)
        let signature = config.secret.flatMap { $0.isEmpty ? nil : RequestSignature.sign(body: body, timestamp: timestamp, secret: $0) }
        if let signature, config.signatureInQuery == true {
            url.append(queryItems: [URLQueryItem(name: "mv_ts", value: String(timestamp)), URLQueryItem(name: "mv_sig", value: signature)])
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MacVitals/\(MacVitals.version)", forHTTPHeaderField: "User-Agent")
        for (key, value) in config.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let signature {
            request.setValue(String(timestamp), forHTTPHeaderField: RequestSignature.timestampHeader)
            request.setValue(signature, forHTTPHeaderField: RequestSignature.signatureHeader)
        }
        return request
    }

    public func deliver(_ payload: ReportPayload, body: Data) async throws {
        let (data, response) = try await session.data(for: try makeRequest(body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw HTTPError(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }
}

/// Persists undelivered payloads so reports survive offline periods, VPN drops and reboots.
/// Keyed by file name: a newer version of the same report replaces the queued one.
public struct Outbox {
    public var directory: URL
    public var limit = 20

    public init(directory: URL) {
        self.directory = directory
    }

    public func enqueue(_ body: Data, sink: String, fileName: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("\(sink)--\(fileName).json")
        try body.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        trim()
    }

    public func pending(for sink: String) -> [URL] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("\(sink)--") && $0.pathExtension == "json" }
            .sorted { modified($0) < modified($1) }
    }

    public var isEmpty: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty
    }

    private func trim() {
        let all = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { modified($0) < modified($1) }
        for url in all.dropLast(limit) { try? FileManager.default.removeItem(at: url) }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Fans a report out to every sink; failures go to the outbox and are retried on the next tick.
public struct Dispatcher {
    public var sinks: [ReportSink]
    public var outbox: Outbox

    public init(sinks: [ReportSink], outbox: Outbox) {
        self.sinks = sinks
        self.outbox = outbox
    }

    public static func make(config: Config, paths: Paths) -> Dispatcher {
        var sinks: [ReportSink] = [FileSink(directory: URL(fileURLWithPath: config.reportDirectory, isDirectory: true))]
        if let hook = config.webhook { sinks.append(WebhookSink(config: hook)) }
        return Dispatcher(sinks: sinks, outbox: Outbox(directory: paths.outboxDirectory))
    }

    /// Returns true when every sink accepted the report.
    @discardableResult
    public func deliver(_ report: RenderedReport) async -> Bool {
        let payload = ReportPayload(report)
        guard let body = try? JSON.encoder.encode(payload) else { return false }
        var allDelivered = true
        for sink in sinks {
            do {
                try await sink.deliver(payload, body: body)
                // A fresh copy supersedes anything still queued for this file.
                try? FileManager.default.removeItem(at: outbox.directory.appendingPathComponent("\(sink.name)--\(payload.fileName).json"))
                Log.info("Report delivered via \(sink.name): \(payload.fileName) (\(payload.kind.rawValue))")
            } catch {
                allDelivered = false
                Log.warn("Delivery via \(sink.name) failed, queued for retry: \(Self.describe(error))")
                try? outbox.enqueue(body, sink: sink.name, fileName: payload.fileName)
            }
        }
        return allDelivered
    }

    static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError { return "network error \(urlError.code.rawValue): \(urlError.localizedDescription)" }
        return String(describing: error)
    }

    /// Retries queued payloads, oldest first. Stops at the first failure per sink (still offline).
    public func flush() async {
        for sink in sinks {
            for url in outbox.pending(for: sink.name) {
                guard let body = try? Data(contentsOf: url),
                      let payload = try? JSON.decoder.decode(ReportPayload.self, from: body) else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }
                do {
                    try await sink.deliver(payload, body: body)
                    try? FileManager.default.removeItem(at: url)
                    Log.info("Queued report delivered via \(sink.name): \(payload.fileName)")
                } catch {
                    break
                }
            }
        }
    }
}
