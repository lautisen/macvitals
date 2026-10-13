import Foundation

/// Runtime configuration. Resolved in layers, later layers win:
/// built-in defaults → `config.json` (root-only) → MDM managed preferences.
///
/// Nothing secret ships inside the installer package: the webhook URL and signing
/// secret are provided per organisation through MDM or a root-owned config file.
public struct Config: Codable, Equatable, Sendable {
    public var sampleIntervalSeconds: Int = 300
    public var reportIntervalSeconds: Int = 3600
    /// Length of a monitoring session. `0` means "until uninstalled".
    public var monitoringDays: Int = 7
    /// Remove MacVitals automatically once the session ends and the final report is delivered.
    public var autoUninstall: Bool = true

    public var organizationName: String = "IT Support"
    public var supportContact: String = "your IT team"
    /// Show a one-time notice to the logged-in user explaining what is collected.
    public var showNotice: Bool = true

    /// Privacy switch: when false, per-process names are not recorded at all.
    public var collectProcessNames: Bool = true
    public var topProcessCount: Int = 10

    /// Reports are always written here. Kept on uninstall unless `--purge` is used.
    public var reportDirectory: String = Paths.system.supportDirectory.appendingPathComponent("reports").path
    public var webhook: WebhookConfig?

    public init() {}

    public struct WebhookConfig: Codable, Equatable, Sendable {
        public var url: String
        /// When set, every request carries `X-MacVitals-Signature` (HMAC-SHA256) so the receiver can verify it.
        public var secret: String?
        public var headers: [String: String]?
        /// Also send the signature as `mv_ts` / `mv_sig` query parameters, for receivers that cannot
        /// read request headers (Google Apps Script).
        public var signatureInQuery: Bool?

        public init(url: String, secret: String? = nil, headers: [String: String]? = nil, signatureInQuery: Bool? = nil) {
            self.url = url
            self.secret = secret
            self.headers = headers
            self.signatureInQuery = signatureInQuery
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sampleIntervalSeconds, reportIntervalSeconds, monitoringDays, autoUninstall
        case organizationName, supportContact, showNotice
        case collectProcessNames, topProcessCount, reportDirectory, webhook
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        sampleIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .sampleIntervalSeconds) ?? d.sampleIntervalSeconds
        reportIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .reportIntervalSeconds) ?? d.reportIntervalSeconds
        monitoringDays = try c.decodeIfPresent(Int.self, forKey: .monitoringDays) ?? d.monitoringDays
        autoUninstall = try c.decodeIfPresent(Bool.self, forKey: .autoUninstall) ?? d.autoUninstall
        organizationName = try c.decodeIfPresent(String.self, forKey: .organizationName) ?? d.organizationName
        supportContact = try c.decodeIfPresent(String.self, forKey: .supportContact) ?? d.supportContact
        showNotice = try c.decodeIfPresent(Bool.self, forKey: .showNotice) ?? d.showNotice
        collectProcessNames = try c.decodeIfPresent(Bool.self, forKey: .collectProcessNames) ?? d.collectProcessNames
        topProcessCount = try c.decodeIfPresent(Int.self, forKey: .topProcessCount) ?? d.topProcessCount
        reportDirectory = try c.decodeIfPresent(String.self, forKey: .reportDirectory) ?? d.reportDirectory
        webhook = try c.decodeIfPresent(WebhookConfig.self, forKey: .webhook)
    }

    public enum ValidationError: Error, CustomStringConvertible {
        case invalid(String)
        public var description: String {
            switch self { case .invalid(let message): return message }
        }
    }

    public func validate() throws {
        guard sampleIntervalSeconds >= 30 else { throw ValidationError.invalid("sampleIntervalSeconds must be ≥ 30") }
        guard reportIntervalSeconds >= sampleIntervalSeconds else {
            throw ValidationError.invalid("reportIntervalSeconds must be ≥ sampleIntervalSeconds")
        }
        guard monitoringDays >= 0 else { throw ValidationError.invalid("monitoringDays must be ≥ 0") }
        guard (1...50).contains(topProcessCount) else { throw ValidationError.invalid("topProcessCount must be 1…50") }
        if let webhook {
            guard let url = URL(string: webhook.url), let host = url.host else {
                throw ValidationError.invalid("webhook.url is not a valid URL")
            }
            // Plain HTTP only for local development receivers.
            let isLocal = ["localhost", "127.0.0.1", "::1"].contains(host)
            guard url.scheme == "https" || (url.scheme == "http" && isLocal) else {
                throw ValidationError.invalid("webhook.url must be an https:// URL")
            }
        }
    }

    /// Copy safe to print or log: secrets and URL query strings (often bearer tokens, e.g. `sig=`) are masked.
    public var redacted: Config {
        var copy = self
        if var hook = copy.webhook {
            hook.url = Config.maskQuery(hook.url)
            hook.secret = hook.secret.map { _ in "••••••" }
            hook.headers = hook.headers?.mapValues { _ in "••••••" }
            copy.webhook = hook
        }
        return copy
    }

    static func maskQuery(_ url: String) -> String {
        guard let range = url.firstIndex(of: "?") else { return url }
        return String(url[..<range]) + "?••••••"
    }
}

// MARK: - Loading

public enum ConfigLoader {
    /// Merges the layers and decodes the result. Unknown keys are ignored so MDM profiles can carry extra metadata.
    public static func load(configFile: URL = Paths.system.configFile,
                            managedPreferences: URL = Paths.managedPreferences) throws -> Config {
        var merged: [String: Any] = [:]
        if let data = try? Data(contentsOf: configFile) {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Config.ValidationError.invalid("\(configFile.path) must contain a JSON object")
            }
            merged.merge(json) { _, new in new }
        }
        if let data = try? Data(contentsOf: managedPreferences),
           let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            merged.merge(plist) { _, new in new }
        }
        return try decode(merged)
    }

    public static func decode(_ dictionary: [String: Any]) throws -> Config {
        let sanitized = dictionary.filter { JSONSerialization.isValidJSONObject([$0.value]) }
        let data = try JSONSerialization.data(withJSONObject: sanitized)
        let config = try JSONDecoder().decode(Config.self, from: data)
        try config.validate()
        return config
    }

    /// A config file holding a secret must not be readable by other users.
    public static func permissionWarning(for file: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let mode = attributes[.posixPermissions] as? NSNumber else { return nil }
        if mode.intValue & 0o077 != 0 {
            return String(format: "%@ is readable by other users (mode %o); run: sudo chmod 600 '%@'", file.path, mode.intValue, file.path)
        }
        return nil
    }
}
