import Foundation

public struct ChartSeries: Sendable {
    public var name: String
    /// Index into the report palette (`--s1`, `--s2`, …).
    public var colorIndex: Int
    public var points: [(date: Date, value: Double)]

    public init(name: String, colorIndex: Int, points: [(date: Date, value: Double)]) {
        self.name = name
        self.colorIndex = colorIndex
        self.points = points
    }
}

/// Renders a time series as a static, dependency-free SVG. The data needed for the hover
/// tooltip is embedded in `data-chart`, so the report stays a single self-contained file.
public struct LineChart: Sendable {
    public var series: [ChartSeries]
    public var unit: String
    /// Fixed top of the y axis (e.g. 100 for percentages). nil = derived from data.
    public var yMax: Double?
    /// Points further apart than this are not joined (the Mac was asleep or off).
    public var gapThreshold: TimeInterval
    public var maxPointsPerSeries = 600

    public var width = 960.0
    public var height = 240.0
    let margin = (top: 12.0, right: 16.0, bottom: 28.0, left: 48.0)

    public init(series: [ChartSeries], unit: String, yMax: Double? = nil, gapThreshold: TimeInterval) {
        self.series = series
        self.unit = unit
        self.yMax = yMax
        self.gapThreshold = gapThreshold
    }

    public func render(timeZone: TimeZone = .current) -> String {
        let all = series.flatMap(\.points)
        guard let first = all.map(\.date).min(), let last = all.map(\.date).max(), last > first else {
            return #"<p class="empty">Not enough data yet.</p>"#
        }
        let plotW = width - margin.left - margin.right
        let plotH = height - margin.top - margin.bottom
        let t0 = first.timeIntervalSince1970, t1 = last.timeIntervalSince1970
        let ticks = Self.niceTicks(max: yMax ?? (all.map(\.value).max() ?? 1), count: 4)
        let top = yMax ?? ticks.last ?? 1

        func x(_ d: Date) -> Double { margin.left + (d.timeIntervalSince1970 - t0) / (t1 - t0) * plotW }
        func y(_ v: Double) -> Double { margin.top + plotH - min(max(v, 0), top) / top * plotH }

        var svg = #"<svg class="chart line-chart" viewBox="0 0 \#(Int(width)) \#(Int(height))" role="img" aria-label="\#(HTML.escape(series.map(\.name).joined(separator: ", "))) over time""#
        let reduced = series.map { (s: $0, points: Self.downsample($0.points, to: maxPointsPerSeries)) }
        svg += #" data-chart="\#(HTML.escape(tooltipJSON(reduced, t0: t0, t1: t1, plotW: plotW, plotH: plotH, top: top)))">"#

        for tick in ticks {
            let ty = Self.fmt(y(tick))
            svg += #"<line class="grid" x1="\#(Self.fmt(margin.left))" x2="\#(Self.fmt(width - margin.right))" y1="\#(ty)" y2="\#(ty)"/>"#
            svg += #"<text class="axis" x="\#(Self.fmt(margin.left - 8))" y="\#(ty)" text-anchor="end" dominant-baseline="middle">\#(Format.number(tick))</text>"#
        }
        for tick in Self.timeTicks(from: first, to: last, timeZone: timeZone) {
            svg += #"<text class="axis" x="\#(Self.fmt(x(tick.date)))" y="\#(Self.fmt(height - 8))" text-anchor="middle">\#(HTML.escape(tick.label))</text>"#
        }
        for (s, points) in reduced {
            svg += #"<path class="line s\#(s.colorIndex)" d="\#(path(points, x: x, y: y))"/>"#
        }
        svg += #"<line class="cross" x1="0" x2="0" y1="\#(Self.fmt(margin.top))" y2="\#(Self.fmt(margin.top + plotH))" visibility="hidden"/>"#
        for (s, _) in reduced {
            svg += #"<circle class="dot s\#(s.colorIndex)" r="4" visibility="hidden"/>"#
        }
        svg += "</svg>"

        if series.count > 1 {
            svg += #"<div class="legend">"# + series.map { #"<span><i class="key s\#($0.colorIndex)"></i>\#(HTML.escape($0.name))</span>"# }.joined() + "</div>"
        }
        return svg
    }

    func path(_ points: [(date: Date, value: Double)], x: (Date) -> Double, y: (Double) -> Double) -> String {
        var d = ""
        var previous: Date?
        for p in points {
            let joined = previous.map { p.date.timeIntervalSince($0) <= gapThreshold } ?? false
            d += (joined ? "L" : "M") + Self.fmt(x(p.date)) + " " + Self.fmt(y(p.value))
            previous = p.date
        }
        return d
    }

    private func tooltipJSON(_ reduced: [(s: ChartSeries, points: [(date: Date, value: Double)])],
                             t0: Double, t1: Double, plotW: Double, plotH: Double, top: Double) -> String {
        let seriesJSON = reduced.map { item in
            let pts = item.points.map { "[\(Int($0.date.timeIntervalSince1970 * 1000)),\(Self.fmt($0.value))]" }.joined(separator: ",")
            return #"{"n":\#(Self.jsonString(item.s.name)),"c":\#(item.s.colorIndex),"p":[\#(pts)]}"#
        }.joined(separator: ",")
        return #"{"w":\#(Int(width)),"ml":\#(margin.left),"mt":\#(margin.top),"pw":\#(plotW),"ph":\#(plotH),"t0":\#(Int(t0 * 1000)),"t1":\#(Int(t1 * 1000)),"top":\#(top),"gap":\#(Int(gapThreshold * 1000)),"u":\#(Self.jsonString(unit)),"s":[\#(seriesJSON)]}"#
    }

    // MARK: - Helpers (internal for tests)

    /// Bucket-averages a series down to at most `limit` points, preserving gaps.
    static func downsample(_ points: [(date: Date, value: Double)], to limit: Int) -> [(date: Date, value: Double)] {
        guard points.count > limit, limit > 0 else { return points }
        let bucket = Int((Double(points.count) / Double(limit)).rounded(.up))
        return stride(from: 0, to: points.count, by: bucket).map { start in
            let slice = points[start..<min(start + bucket, points.count)]
            return (slice.first!.date, slice.map(\.value).reduce(0, +) / Double(slice.count))
        }
    }

    /// 0 plus `count` evenly spaced "nice" values (1, 2, 2.5, 5 × 10ⁿ) covering `max`.
    static func niceTicks(max: Double, count: Int) -> [Double] {
        guard max > 0 else { return [0, 1] }
        let raw = max / Double(count)
        let magnitude = pow(10, floor(log10(raw)))
        let step = [1, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? raw
        let n = Int((max / step).rounded(.up))
        return (0...n).map { Double($0) * step }
    }

    static func timeTicks(from start: Date, to end: Date, timeZone: TimeZone) -> [(date: Date, label: String)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let span = end.timeIntervalSince(start)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        let stepHours: Int
        if span > 36 * 3600 {
            stepHours = 24 * max(1, Int((span / 86_400 / 8).rounded(.up)))
            formatter.dateFormat = "EEE d"
        } else {
            stepHours = [1, 2, 3, 6, 12].first { span / Double($0 * 3600) <= 8 } ?? 12
            formatter.dateFormat = "HH:mm"
        }
        guard var tick = calendar.dateInterval(of: stepHours >= 24 ? .day : .hour, for: start)?.start else { return [] }
        if stepHours >= 24 { tick = calendar.date(byAdding: .day, value: 1, to: tick)! }
        var ticks: [(Date, String)] = []
        while tick <= end {
            if tick >= start, stepHours >= 24 || calendar.component(.hour, from: tick) % stepHours == 0 {
                ticks.append((tick, formatter.string(from: tick)))
            }
            tick = calendar.date(byAdding: .hour, value: stepHours >= 24 ? stepHours : 1, to: tick)!
        }
        return ticks
    }

    static func fmt(_ v: Double) -> String {
        let rounded = (v * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    static func jsonString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let array = data.map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
