import Darwin
import Foundation

enum Sysctl {
    static func integer<T: FixedWidthInteger>(_ name: String, as type: T.Type = Int.self) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// For C structs such as `xsw_usage` or `timeval`.
    static func value<T>(_ name: String, initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let status = withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        return status == 0 ? value : nil
    }
}
