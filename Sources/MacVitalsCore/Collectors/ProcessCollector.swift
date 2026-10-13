import Foundation

public enum ProcessCollector {
    /// Runs `ps` once and returns the heaviest process groups by CPU and by memory.
    static func snapshot(top: Int) -> [ProcessSnapshot] {
        guard let output = try? Shell.run("/bin/ps", ["-Axco", "pcpu=,rss=,comm="]) else { return [] }
        return topProcesses(parse(output), count: top)
    }

    /// Parses `ps -o pcpu=,rss=,comm=` output. Names may contain spaces, so only the first two
    /// columns are split. Processes sharing a name are merged.
    public static func parse(_ output: String) -> [ProcessSnapshot] {
        var byName: [String: ProcessSnapshot] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let cpu = Double(fields[0]), let rssKB = UInt64(fields[1]) else { continue }
            let name = fields[2].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            if var existing = byName[name] {
                existing.cpuPercent += cpu
                existing.residentBytes += rssKB * 1024
                existing.count += 1
                byName[name] = existing
            } else {
                byName[name] = ProcessSnapshot(name: name, cpuPercent: cpu, residentBytes: rssKB * 1024)
            }
        }
        return Array(byName.values)
    }

    /// Union of the top `count` by CPU and the top `count` by memory, so a process that is heavy on either shows up.
    public static func topProcesses(_ processes: [ProcessSnapshot], count: Int) -> [ProcessSnapshot] {
        let byCPU = processes.sorted { ($0.cpuPercent, $0.name) > ($1.cpuPercent, $1.name) }.prefix(count)
        let byMemory = processes.sorted { ($0.residentBytes, $0.name) > ($1.residentBytes, $1.name) }.prefix(count)
        var seen = Set<String>()
        return (byCPU + byMemory).filter { seen.insert($0.name).inserted }
    }
}
