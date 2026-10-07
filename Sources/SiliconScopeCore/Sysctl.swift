import Darwin
import Foundation

enum Sysctl {
    static func string(_ name: String) -> String? {
        name.withCString { cName -> String? in
            var size = 0
            guard sysctlbyname(cName, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buffer = [CChar](repeating: 0, count: size)
            guard sysctlbyname(cName, &buffer, &size, nil, 0) == 0 else { return nil }
            return String(cString: buffer)
        }
    }

    static func u32(_ name: String) -> UInt32? {
        value(name)
    }

    static func u64(_ name: String) -> UInt64? {
        value(name)
    }

    static func i32(_ name: String) -> Int32? {
        value(name)
    }

    static func value<T>(_ name: String) -> T? {
        name.withCString { cName -> T? in
            let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { value.deallocate() }
            memset(value, 0, MemoryLayout<T>.size)
            var size = MemoryLayout<T>.size
            guard sysctlbyname(cName, value, &size, nil, 0) == 0 else { return nil }
            return value.pointee
        }
    }

    static func loadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return (0, 0, 0) }
        return (loads[0], loads[1], loads[2])
    }

    static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0 else { return 0 }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
        return Date().timeIntervalSince(bootDate)
    }
}
