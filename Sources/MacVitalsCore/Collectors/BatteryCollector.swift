import Foundation
import IOKit

public enum BatteryCollector {
    /// Reads the `AppleSmartBattery` registry entry. Returns nil on desktops.
    static func snapshot() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return parse(dictionary)
    }

    /// Pure parser, separated from IOKit so it can be unit-tested with captured registry dumps.
    ///
    /// On Apple silicon `CurrentCapacity`/`MaxCapacity` are already percentages and the real
    /// mAh values live in `AppleRaw*`; on Intel they are mAh. Both cases are handled.
    /// Newer macOS releases moved the capacity details into a nested `BatteryData` dictionary;
    /// it is merged underneath the top-level keys so both layouts work.
    public static func parse(_ registry: [String: Any]) -> BatterySnapshot? {
        var p = (registry["BatteryData"] as? [String: Any]) ?? [:]
        p.merge(registry) { _, topLevel in topLevel }
        func int(_ key: String) -> Int? { (p[key] as? NSNumber)?.intValue }
        func bool(_ key: String) -> Bool { (p[key] as? NSNumber)?.boolValue ?? false }

        guard let current = int("CurrentCapacity"), let max = int("MaxCapacity"), max > 0 else { return nil }
        let charge = Double(current) / Double(max) * 100

        var health: Double?
        if let design = int("DesignCapacity"), design > 0,
           let fullCharge = int("NominalChargeCapacity") ?? int("AppleRawMaxCapacity") ?? (max > 100 ? max : nil) {
            health = Double(fullCharge) / Double(design) * 100
        }

        // Reported in hundredths of a degree Celsius.
        let temperature = int("Temperature").map { Double($0) / 100 }

        return BatterySnapshot(
            chargePercent: min(100, charge),
            isCharging: bool("IsCharging"),
            onExternalPower: bool("ExternalConnected"),
            cycleCount: int("CycleCount"),
            healthPercent: health,
            temperatureCelsius: temperature
        )
    }
}
