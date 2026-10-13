import Foundation
import Testing
@testable import MacVitalsCore

@Suite("Delivery")
struct DeliveryTests {
    @Test func signatureMatchesKnownVector() {
        // Verify independently: printf '1700000000.{"a":1}' | openssl dgst -sha256 -hmac 'topsecret'
        let signature = RequestSignature.sign(body: Data(#"{"a":1}"#.utf8), timestamp: 1_700_000_000, secret: "topsecret")
        #expect(signature == "sha256=" + Self.opensslReference)
    }

    // Computed with the openssl command above.
    static let opensslReference = "6a939b0c71853d606167625a15168ee9188c6a511c773ef4f42d307f3849e50f"

    @Test func verifyAcceptsValidAndRejectsTamperedOrStale() {
        let body = Data("hello".utf8)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let sig = RequestSignature.sign(body: body, timestamp: 1_700_000_000, secret: "s")
        #expect(RequestSignature.verify(body: body, timestamp: 1_700_000_000, signature: sig, secret: "s", now: now))
        #expect(!RequestSignature.verify(body: Data("hellO".utf8), timestamp: 1_700_000_000, signature: sig, secret: "s", now: now))
        #expect(!RequestSignature.verify(body: body, timestamp: 1_700_000_000, signature: sig, secret: "other", now: now))
        #expect(!RequestSignature.verify(body: body, timestamp: 1_700_000_000, signature: sig, secret: "s",
                                         now: now.addingTimeInterval(3600)))
    }

    @Test func webhookRequestCarriesSignatureAndCustomHeaders() throws {
        let sink = WebhookSink(config: .init(url: "https://example.com/hook", secret: "k", headers: ["X-Api-Key": "abc"]))
        let body = Data("{}".utf8)
        let request = try sink.makeRequest(body: body, now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "abc")
        #expect(request.value(forHTTPHeaderField: RequestSignature.timestampHeader) == "1700000000")
        #expect(request.value(forHTTPHeaderField: RequestSignature.signatureHeader)
                == RequestSignature.sign(body: body, timestamp: 1_700_000_000, secret: "k"))
    }

    @Test func signatureCanTravelInTheQueryForAppsScript() throws {
        let sink = WebhookSink(config: .init(url: "https://script.google.com/macros/s/ID/exec?a=1", secret: "k", signatureInQuery: true))
        let body = Data("{}".utf8)
        let request = try sink.makeRequest(body: body, now: Date(timeIntervalSince1970: 1_700_000_000))
        let items = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "a" }?.value == "1")
        #expect(items.first { $0.name == "mv_ts" }?.value == "1700000000")
        #expect(items.first { $0.name == "mv_sig" }?.value == RequestSignature.sign(body: body, timestamp: 1_700_000_000, secret: "k"))
    }

    @Test func webhookWithoutSecretIsUnsigned() throws {
        let request = try WebhookSink(config: .init(url: "https://example.com/hook")).makeRequest(body: Data())
        #expect(request.value(forHTTPHeaderField: RequestSignature.signatureHeader) == nil)
    }

    @Test func outboxReplacesSameReportAndKeepsOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(Data("v1".utf8), sink: "webhook", fileName: "a.html")
        try outbox.enqueue(Data("x".utf8), sink: "webhook", fileName: "b.html")
        try outbox.enqueue(Data("v2".utf8), sink: "webhook", fileName: "a.html")
        let pending = outbox.pending(for: "webhook")
        #expect(pending.count == 2)
        #expect(outbox.pending(for: "file").isEmpty)
        let a = try #require(pending.first { $0.lastPathComponent.contains("a.html") })
        #expect(try String(contentsOf: a, encoding: .utf8) == "v2")
    }

    @Test func failedDeliveryIsQueuedAndFlushedLater() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FlakySink()
        let dispatcher = Dispatcher(sinks: [sink], outbox: Outbox(directory: dir))
        let state = SessionState(startDate: Date(), endDate: nil)
        let report = ReportBuilder.build(ReportInput(kind: .initial, config: Config(), state: state, machine: DemoData.machine, samples: [], events: []))

        sink.online = false
        #expect(await dispatcher.deliver(report) == false)
        #expect(dispatcher.outbox.pending(for: "flaky").count == 1)

        sink.online = true
        await dispatcher.flush()
        #expect(dispatcher.outbox.pending(for: "flaky").isEmpty)
        #expect(sink.received == [report.fileName])
    }
}

final class FlakySink: ReportSink, @unchecked Sendable {
    var online = true
    var received: [String] = []
    var name: String { "flaky" }
    struct Offline: Error {}

    func deliver(_ payload: ReportPayload, body: Data) async throws {
        guard online else { throw Offline() }
        received.append(payload.fileName)
    }
}

@Suite("Configuration")
struct ConfigTests {
    @Test func defaultsApplyForMissingKeys() throws {
        let config = try ConfigLoader.decode(["monitoringDays": 3])
        #expect(config.monitoringDays == 3)
        #expect(config.sampleIntervalSeconds == 300)
        #expect(config.webhook == nil)
    }

    @Test func managedPreferencesOverrideConfigFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = dir.appendingPathComponent("config.json")
        let plist = dir.appendingPathComponent("managed.plist")
        try Data(#"{"monitoringDays": 3, "organizationName": "File"}"#.utf8).write(to: json)
        try PropertyListSerialization.data(fromPropertyList: ["organizationName": "MDM", "PayloadUUID": "ignored"], format: .xml, options: 0).write(to: plist)
        let config = try ConfigLoader.load(configFile: json, managedPreferences: plist)
        #expect(config.monitoringDays == 3)
        #expect(config.organizationName == "MDM")
    }

    @Test func insecureWebhookIsRejected() {
        #expect(throws: Config.ValidationError.self) {
            try ConfigLoader.decode(["webhook": ["url": "http://example.com/hook"]])
        }
    }

    @Test func redactionHidesSecretsAndQueryTokens() throws {
        let config = try ConfigLoader.decode(["webhook": ["url": "https://flow.example.com/invoke?api-version=1&sig=SECRET", "secret": "SECRET"]])
        let printed = String(decoding: try JSONEncoder().encode(config.redacted), as: UTF8.self)
        #expect(!printed.contains("SECRET"))
        #expect(printed.contains("flow.example.com"))
    }
}
