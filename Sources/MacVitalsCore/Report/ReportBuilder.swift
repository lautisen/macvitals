import Foundation

public enum ReportKind: String, Codable, Sendable {
    /// Sent right after install; proves delivery works before any data exists.
    case initial
    /// Hourly refresh while the session runs.
    case partial
    /// End of session.
    case final
    /// `macvitals send-test` / `demo-report`.
    case test

    var badge: String {
        switch self {
        case .initial: return "Initial"
        case .partial: return "Live · updated periodically"
        case .final: return "Final"
        case .test: return "Test"
        }
    }
}

public struct ReportInput: Sendable {
    public var kind: ReportKind
    public var config: Config
    public var state: SessionState
    public var machine: MachineInfo
    public var samples: [Sample]
    public var events: [SystemEvent]
    public var generatedAt: Date
    public var timeZone: TimeZone

    public init(kind: ReportKind, config: Config, state: SessionState, machine: MachineInfo, samples: [Sample],
                events: [SystemEvent], generatedAt: Date = Date(), timeZone: TimeZone = .current) {
        self.kind = kind
        self.config = config
        self.state = state
        self.machine = machine
        self.samples = samples
        self.events = events
        self.generatedAt = generatedAt
        self.timeZone = timeZone
    }
}

public struct RenderedReport: Sendable {
    public var fileName: String
    public var html: String
    public var kind: ReportKind
    public var summary: Summary
    public var insights: [Insight]
    public var machine: MachineInfo
    public var periodStart: Date
    public var periodEnd: Date?
    public var generatedAt: Date
}

public enum ReportBuilder {
    public static func build(_ input: ReportInput) -> RenderedReport {
        let interval = TimeInterval(input.config.sampleIntervalSeconds)
        let summary = Summary(samples: input.samples, sampleInterval: interval)
        let insights = InsightEngine.analyze(samples: input.samples, events: input.events, sampleInterval: interval)
        let html = render(input, summary: summary, insights: insights)
        return RenderedReport(fileName: input.state.reportFileName(machine: input.machine), html: html, kind: input.kind,
                              summary: summary, insights: insights, machine: input.machine,
                              periodStart: input.state.startDate, periodEnd: input.state.endDate, generatedAt: input.generatedAt)
    }

    static func render(_ input: ReportInput, summary: Summary, insights: [Insight]) -> String {
        let e = HTML.escape
        let m = input.machine
        let dates = DateFormatter()
        dates.locale = Locale(identifier: "en_US_POSIX")
        dates.timeZone = input.timeZone
        dates.dateFormat = "MMM d, yyyy 'at' HH:mm"
        let hasData = input.samples.count >= 2

        var h = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(e(m.computerName)) · MacVitals</title>
        <style>\(ReportAssets.css)</style>
        </head>
        <body>
        <main class="report">
        <header class="top">
          <div class="eyebrow">MacVitals performance report · \(e(input.config.organizationName))</div>
          <h1>\(e(m.computerName))<span class="badge">\(e(input.kind.badge))</span></h1>
          <div class="meta">
            <span>User: \(e(m.consoleUser ?? "nobody logged in"))</span>
            <span>\(e(m.model)) · \(e(m.chip)) · \(m.cpuCores) cores · \(Format.bytes(m.memoryBytes)) RAM</span>
            <span>\(e(m.osVersion))</span>
          </div>
          <div class="meta">
            <span>Period: \(dates.string(from: input.state.startDate)) → \(input.state.endDate.map { dates.string(from: $0) } ?? "until removed")</span>
            <span>Samples: \(summary.sampleCount) (every \(Format.duration(TimeInterval(input.config.sampleIntervalSeconds))))</span>
          </div>
        </header>
        """

        if !hasData {
            h += """
            <section class="card"><h2>Monitoring is active</h2>
            <p class="note">This first report confirms that the Mac can deliver reports. Charts and findings appear from the next update.</p></section>
            """
        } else {
            h += tiles(summary)
            h += insightsSection(insights)
            h += charts(input)
            h += processTable(input.samples)
            h += eventsTable(input.events, dates: dates)
        }

        h += """
        <footer>
          <span>Generated \(dates.string(from: input.generatedAt)) by MacVitals \(MacVitals.version). Questions: \(e(input.config.supportContact)).</span>
          <span>Collected: CPU, memory, disk, battery and temperature metrics\(input.config.collectProcessNames ? ", and the names of the busiest processes" : ""). Never collected: file contents, keystrokes, screenshots, browsing history.</span>
          \(hasData ? #"<span><a download="\#(e(input.state.reportFileName(machine: m).replacingOccurrences(of: ".html", with: ".csv")))" href="data:text/csv;base64,\#(Data(CSV.samples(input.samples).utf8).base64EncodedString())">Download raw data (CSV)</a></span>"# : "")
        </footer>
        </main>
        <div id="tip" role="tooltip"></div>
        <script>\(ReportAssets.js)</script>
        </body>
        </html>
        """
        return h
    }

    // MARK: - Sections

    static func tiles(_ s: Summary) -> String {
        func tile(_ label: String, _ value: String, _ sub: String) -> String {
            #"<div class="tile"><div class="label">\#(label)</div><div class="value">\#(value)</div><div class="sub">\#(sub)</div></div>"#
        }
        var items = [
            tile("CPU average", s.cpuAverage.map(Format.percent) ?? "–", "95th percentile " + (s.cpuP95.map(Format.percent) ?? "–")),
            tile("Memory used", s.memoryAverage.map(Format.percent) ?? "–", "peak " + (s.memoryPeak.map(Format.percent) ?? "–")),
            tile("Swap peak", Format.bytes(s.swapPeakBytes), "pressure peak: \(s.worstMemoryPressure.rawValue)"),
            tile("Lowest free disk", s.diskAvailableMinBytes.map(Format.bytes) ?? "–", (s.diskAvailableMinPercent.map(Format.percent) ?? "–") + " of capacity"),
        ]
        if let health = s.batteryHealth {
            items.append(tile("Battery health", Format.percent(health), s.batteryCycles.map { "\($0) cycles" } ?? ""))
            items.append(tile("Time on battery", Format.duration(s.minutesOnBattery * 60), "worst thermal state: \(s.worstThermalState.rawValue)"))
        }
        return #"<section class="tiles" aria-label="Summary">\#(items.joined())</section>"#
    }

    static func insightsSection(_ insights: [Insight]) -> String {
        let items = insights.map { i -> String in
            let ok = i.severity == .info && i.title == "No problems detected"
            let (cls, glyph, label) = ok ? ("ok", "✓", "OK") : {
                switch i.severity {
                case .critical: return ("critical", "!", "Critical")
                case .warning: return ("warning", "!", "Warning")
                case .info: return ("info", "i", "Info")
                }
            }()
            return #"<li><span class="icon \#(cls)" aria-hidden="true">\#(glyph)</span><div><strong>\#(HTML.escape(i.title))<span class="sev">\#(label)</span></strong><span>\#(HTML.escape(i.detail))</span></div></li>"#
        }
        return #"<section class="card"><h2>Findings</h2><ul class="insights">\#(items.joined())</ul></section>"#
    }

    static func charts(_ input: ReportInput) -> String {
        let s = input.samples
        let gap = TimeInterval(input.config.sampleIntervalSeconds) * 2.5
        func card(_ title: String, _ now: String, _ chart: LineChart) -> String {
            #"<section class="card"><div class="chart-head"><h2>\#(title)</h2><span class="now">\#(now)</span></div>\#(chart.render(timeZone: input.timeZone))</section>"#
        }
        let last = s.last!
        var cards = [
            card("CPU usage", "now " + Format.percent(last.cpuPercent),
                 LineChart(series: [ChartSeries(name: "CPU", colorIndex: 1, points: s.map { ($0.timestamp, $0.cpuPercent) })],
                           unit: "%", yMax: 100, gapThreshold: gap)),
            card("Memory used", "now " + Format.percent(last.memory.usedPercent),
                 LineChart(series: [ChartSeries(name: "Memory", colorIndex: 1, points: s.map { ($0.timestamp, $0.memory.usedPercent) })],
                           unit: "%", yMax: 100, gapThreshold: gap)),
            card("Free disk space", "now " + Format.bytes(last.disk.availableBytes),
                 LineChart(series: [ChartSeries(name: "Free", colorIndex: 1, points: s.map { ($0.timestamp, Double($0.disk.availableBytes) / 1e9) })],
                           unit: "GB", gapThreshold: gap)),
        ]
        let battery = s.compactMap { sample in sample.battery.map { (sample.timestamp, $0.chargePercent) } }
        if !battery.isEmpty {
            cards.append(card("Battery charge", last.battery.map { "now " + Format.percent($0.chargePercent) + ($0.onExternalPower ? " · on power" : " · on battery") } ?? "",
                              LineChart(series: [ChartSeries(name: "Charge", colorIndex: 1, points: battery)], unit: "%", yMax: 100, gapThreshold: gap)))
        }
        return #"<div class="charts">\#(cards.joined())</div>"#
    }

    static func processTable(_ samples: [Sample]) -> String {
        let rows = ProcessSummary.aggregate(samples)
        guard !rows.isEmpty else { return "" }
        let body = rows.map { p in
            "<tr><td>\(HTML.escape(p.name))</td><td class=\"num\">\(Format.percent(p.cpuAverage))</td><td class=\"num\">\(Format.percent(p.cpuPeak))</td>"
                + "<td class=\"num\">\(Format.bytes(p.memoryAverageBytes))</td><td class=\"num\">\(Format.bytes(p.memoryPeakBytes))</td><td class=\"num\">\(Format.percent(p.presence * 100))</td></tr>"
        }.joined()
        return """
        <section class="card"><h2>Heaviest processes</h2>
        <div class="table-wrap"><table>
        <thead><tr><th>Process</th><th class="num">CPU avg</th><th class="num">CPU peak</th><th class="num">RAM avg</th><th class="num">RAM peak</th><th class="num">Seen in</th></tr></thead>
        <tbody>\(body)</tbody></table></div>
        <p class="note">Processes with the same name are added together. CPU: 100 % = one full core. "Seen in" = share of samples where the process was among the heaviest.</p>
        </section>
        """
    }

    static func eventsTable(_ events: [SystemEvent], dates: DateFormatter) -> String {
        guard !events.isEmpty else { return "" }
        let rows = events.map { "<tr><td>\(dates.string(from: $0.date))</td><td>\(HTML.escape($0.kind))</td><td>\(HTML.escape($0.detail))</td></tr>" }.joined()
        return #"<section class="card"><h2>System events</h2><div class="table-wrap"><table><thead><tr><th>When</th><th>Event</th><th>Report file</th></tr></thead><tbody>\#(rows)</tbody></table></div></section>"#
    }
}

public enum CSV {
    public static func samples(_ samples: [Sample]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["timestamp,cpu_percent,load_1m,memory_used_percent,memory_pressure,swap_used_bytes,disk_available_bytes,battery_percent,on_external_power,thermal_state"]
        for s in samples {
            lines.append([
                iso.string(from: s.timestamp), LineChart.fmt(s.cpuPercent), LineChart.fmt(s.loadAverage),
                LineChart.fmt(s.memory.usedPercent), s.memory.pressure.rawValue, String(s.memory.swapUsedBytes),
                String(s.disk.availableBytes), s.battery.map { LineChart.fmt($0.chargePercent) } ?? "",
                s.battery.map { String($0.onExternalPower) } ?? "", s.thermalState.rawValue,
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
