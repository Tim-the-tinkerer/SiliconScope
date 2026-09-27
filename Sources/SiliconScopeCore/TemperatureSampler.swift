import CoreFoundation
import Darwin
import Foundation

enum TemperatureSampler {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef?, CFDictionary?) -> Int32
    private typealias CopyServices = @convention(c) (CFTypeRef?) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef?, CFString?) -> Unmanaged<CFString>?
    private typealias CopyEvent = @convention(c) (CFTypeRef?, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias EventFloat = @convention(c) (CFTypeRef?, Int64) -> Double

    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW | RTLD_LOCAL)
    private static let create: ClientCreate? = symbol("IOHIDEventSystemClientCreate")
    private static let setMatching: SetMatching? = symbol("IOHIDEventSystemClientSetMatching")
    private static let copyServices: CopyServices? = symbol("IOHIDEventSystemClientCopyServices")
    private static let copyProperty: CopyProperty? = symbol("IOHIDServiceClientCopyProperty")
    private static let copyEvent: CopyEvent? = symbol("IOHIDServiceClientCopyEvent")
    private static let eventFloat: EventFloat? = symbol("IOHIDEventGetFloatValue")

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
        guard let copyServices, let copyProperty, let copyEvent, let eventFloat,
              let client = clientOrCreate()
        else { return Report(cpu: nil, gpu: nil, sensors: []) }

        guard let services = copyServices(client)?.takeRetainedValue() else {
            return Report(cpu: nil, gpu: nil, sensors: [])
        }

        var sensors: [TemperatureSensor] = []
        var usedNames: [String: Int] = [:]
        let count = CFArrayGetCount(services)
        for index in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as CFTypeRef
            let product: String
            if let unmanaged = copyProperty(service, "Product" as CFString) {
                product = unmanaged.takeRetainedValue() as String
            } else {
                product = ""
            }
            guard let event = copyEvent(service, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let value = eventFloat(event, temperatureEvent << 16)
            guard value > 0, value <= 150 else { continue }
            let base = product.isEmpty ? "Sensor \(index + 1)" : product
            let seen = (usedNames[base] ?? 0) + 1
            usedNames[base] = seen
            let name = seen == 1 ? base : "\(base) \(seen)"
            sensors.append(TemperatureSensor(
                id: name,
                name: name,
                celsius: value,
                group: TemperatureGroup.group(forSensorName: base)
            ))
        }
        let cpuValues = sensors.filter { $0.group == .cpu }.map(\.celsius)
        let gpuValues = sensors.filter { $0.group == .gpu }.map(\.celsius)
        return Report(cpu: average(cpuValues), gpu: average(gpuValues), sensors: sensors)
    }

    private static func clientOrCreate() -> CFTypeRef? {
        if let client { return client }
        guard let create, let setMatching, let made = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching: [CFString: Int32] = [
            "PrimaryUsagePage" as CFString: appleVendorPage,
            "PrimaryUsage" as CFString: temperatureUsage,
        ]
        _ = setMatching(made, matching as CFDictionary)
        client = made
        return made
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
