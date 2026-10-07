import CoreFoundation
import Darwin
import Foundation

enum TemperatureSampler {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef?, CFDictionary?) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef?) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef?, CFString?) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef?, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventFloat = @convention(c) (CFTypeRef?, Int64) -> Double
    private typealias Schedule = @convention(c) (CFTypeRef?, CFRunLoop?, CFString?) -> Void

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL)
    private static let create: ClientCreate? = symbol("IOHIDEventSystemClientCreate")
    private static let setMatching: SetMatching? = symbol("IOHIDEventSystemClientSetMatching")
    private static let copyServices: CopyServices? = symbol("IOHIDEventSystemClientCopyServices")
    private static let copyProperty: CopyProperty? = symbol("IOHIDServiceClientCopyProperty")
    private static let copyEvent: CopyEvent? = symbol("IOHIDServiceClientCopyEvent")
    private static let eventFloat: EventFloat? = symbol("IOHIDEventGetFloatValue")
    private static let schedule: Schedule? = symbol("IOHIDEventSystemClientScheduleWithRunLoop")

    private static let appleVendorPage: Int32 = 0xff00
    private static let temperatureUsage: Int32 = 0x0005
    private static let temperatureEvent: Int64 = 15

    struct Report {
        var cpu: Double?
        var gpu: Double?
        var sensors: [TemperatureSensor]
    }

    private static let minInterval: TimeInterval = 3
    private static var last: (report: Report, at: Date)?
    private static var client: CFTypeRef?
    private static var didSchedule = false
    private static let lock = NSLock()

    static func sample(force: Bool = false) -> Report {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if !force, let last, now.timeIntervalSince(last.at) < minInterval {
            return last.report
        }
        let temps = read()
        last = (temps, now)
        return temps
    }

    private static func read() -> Report {
        let hid = readHID()
        // SMC is the fallback for chips that do not publish the HID cluster and GPU diodes.
        // Listing every other SMC key added unnamed rows (and a "performance core" group) beside the diodes this Mac already has.
        let smc = SMCTemperature.sample().filter { TemperatureName.includesSMCKey($0.name, hid: hid) }
        let sensors = hid + smc
        return Report(
            cpu: TemperatureName.cpuClusterAverage(sensors),
            gpu: TemperatureName.gpuAverage(sensors),
            sensors: sensors
        )
    }

    /// HID diodes (`pACC`, `eACC`, `GPU MTR`) when the chip publishes them. M4 Pro and M2 Pro publish PMU copies instead, often three times, plus a `tcal` constant that is not a live temperature.
    private static func readHID() -> [TemperatureSensor] {
        guard let copyServices, let copyEvent, let eventFloat, let client = clientOrCreate() else { return [] }
        guard let services = copyServices(client)?.takeRetainedValue() else { return [] }

        var valuesByName: [String: [Double]] = [:]
        var order: [String] = []
        let count = CFArrayGetCount(services)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as CFTypeRef
            guard let event = copyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = eventFloat(event, temperatureEvent << 16)
            guard value.isFinite, TemperatureName.acceptsCelsius(value) else { continue }
            let product = stringProperty(service, "Product") ?? ""
            if product.lowercased().contains("tcal") { continue }
            let name = product.isEmpty ? "Sensor \(index + 1)" : product
            if valuesByName[name] == nil { order.append(name) }
            valuesByName[name, default: []].append(value)
        }

        return order.map { name in
            TemperatureSensor(
                id: name,
                name: name,
                celsius: median(valuesByName[name] ?? []),
                group: TemperatureGroup.group(forSensorName: name)
            )
        }
    }

    /// `IOHIDServiceClientCopyProperty` returns a number for usage fields. Forcing that to `String` crashes.
    private static func stringProperty(_ service: CFTypeRef, _ key: String) -> String? {
        guard let copyProperty, let unmanaged = copyProperty(service, key as CFString) else { return nil }
        let value = unmanaged.takeRetainedValue() as AnyObject
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private static func clientOrCreate() -> CFTypeRef? {
        if let client { return client }
        guard let create, let setMatching, let made = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching: [CFString: Int32] = [
            "PrimaryUsagePage" as CFString: appleVendorPage,
            "PrimaryUsage" as CFString: temperatureUsage,
        ]
        _ = setMatching(made, matching as CFDictionary)
        if !didSchedule {
            didSchedule = true
            schedule?(made, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            CFRunLoopRunInMode(.defaultMode, 0.2, false)
        }
        client = made
        return made
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
