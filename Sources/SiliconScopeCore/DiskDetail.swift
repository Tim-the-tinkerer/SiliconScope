import Darwin
import Foundation
import IOKit

public struct DiskSmartAttribute: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var value: String

    public init(id: String, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

public struct DiskDetail: Equatable, Sendable {
    public var bsdName: String
    public var reported: Bool
    public var serialNumber: String
    public var revision: String
    public var blockSize: UInt64
    public var partitionMap: String
    public var smartStatus: String
    public var attributes: [DiskSmartAttribute]
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
    public var readOperations: UInt64
    public var writeOperations: UInt64
    public var readErrors: UInt64
    public var writeErrors: UInt64
    public var readRetries: UInt64
    public var writeRetries: UInt64
    public var hasActivity: Bool

    public static let empty = DiskDetail(
        bsdName: "",
        reported: false,
        serialNumber: "",
        revision: "",
        blockSize: 0,
        partitionMap: "",
        smartStatus: "",
        attributes: [],
        bytesRead: 0,
        bytesWritten: 0,
        readOperations: 0,
        writeOperations: 0,
        readErrors: 0,
        writeErrors: 0,
        readRetries: 0,
        writeRetries: 0,
        hasActivity: false
    )
}

public enum DiskSmart {
    /// NVMe data units are 1,000 blocks of 512 bytes, regardless of the drive's formatted block size.
    public static let nvmeDataUnitBytes: UInt64 = 512_000

    public static func attributes(from raw: [String: UInt64]) -> [DiskSmartAttribute] {
        var used = Set<String>()
        var rows: [DiskSmartAttribute] = []
        for field in fields {
            guard let pair = wideValue(raw, base: field.key, used: &used) else { continue }
            guard let value = field.format(pair.low, pair.high) else { continue }
            rows.append(DiskSmartAttribute(id: field.key, title: field.title, value: value))
        }
        let leftovers = raw.keys.filter { key in
            !used.contains(key) && !key.hasSuffix("_1")
        }.sorted()
        for key in leftovers {
            guard let pair = wideValue(raw, base: key.hasSuffix("_0") ? String(key.dropLast(2)) : key, used: &used) else { continue }
            let title = plainTitle(key.hasSuffix("_0") ? String(key.dropLast(2)) : key)
            rows.append(DiskSmartAttribute(id: key, title: title, value: grouped(pair.low, pair.high)))
        }
        return rows
    }

    public static func partitionMapTitle(_ content: String) -> String {
        switch content {
        case "GUID_partition_scheme": return "GUID"
        case "FDisk_partition_scheme": return "MBR"
        case "Apple_partition_scheme": return "Apple"
        case "": return ""
        default:
            if content.localizedCaseInsensitiveContains("APFS") { return "APFS" }
            return content.replacingOccurrences(of: "_", with: " ")
        }
    }

    private struct Field {
        var key: String
        var title: String
        var format: (UInt64, UInt64) -> String?
    }

    private static let fields: [Field] = [
        Field(key: "TEMPERATURE", title: "Temperature") { low, _ in
            guard low > 0 else { return nil }
            let celsius = low > 200 ? Double(low) - 273.15 : Double(low)
            guard celsius > 0, celsius < 150 else { return nil }
            return String(format: "%.1f°C", celsius)
        },
        Field(key: "PERCENTAGE_USED", title: "Life used") { low, _ in "\(low)%" },
        Field(key: "AVAILABLE_SPARE", title: "Available spare") { low, _ in "\(low)%" },
        Field(key: "AVAILABLE_SPARE_THRESHOLD", title: "Spare threshold") { low, _ in "\(low)%" },
        Field(key: "POWER_ON_HOURS", title: "Power on") { low, high in "\(grouped(low, high)) hours" },
        Field(key: "POWER_CYCLES", title: "Power cycles") { low, high in grouped(low, high) },
        Field(key: "UNSAFE_SHUTDOWNS", title: "Unsafe shutdowns") { low, high in grouped(low, high) },
        Field(key: "DATA_UNITS_READ", title: "Data read") { low, high in dataUnits(low, high) },
        Field(key: "DATA_UNITS_WRITTEN", title: "Data written") { low, high in dataUnits(low, high) },
        Field(key: "HOST_READ_COMMANDS", title: "Read commands") { low, high in grouped(low, high) },
        Field(key: "HOST_WRITE_COMMANDS", title: "Write commands") { low, high in grouped(low, high) },
        Field(key: "MEDIA_ERRORS", title: "Media errors") { low, high in grouped(low, high) },
        Field(key: "NUM_ERROR_INFO_LOG_ENTRIES", title: "Error log entries") { low, high in grouped(low, high) },
        Field(key: "CONTROLLER_BUSY_TIME", title: "Controller busy") { low, high in
            let minutes = low
            guard high == 0 else { return "\(grouped(low, high)) min" }
            if minutes < 60 { return "\(grouped(minutes)) min" }
            return "\(grouped(minutes / 60)) h \(minutes % 60) min"
        },
        Field(key: "CRITICAL_WARNING", title: "Critical warning") { low, _ in
            if low == 0 { return "None" }
            var parts: [String] = []
            if low & 0x01 != 0 { parts.append("Spare") }
            if low & 0x02 != 0 { parts.append("Temperature") }
            if low & 0x04 != 0 { parts.append("Reliability") }
            if low & 0x08 != 0 { parts.append("Read-only") }
            if low & 0x10 != 0 { parts.append("Backup failed") }
            if parts.isEmpty { return "0x\(String(low, radix: 16))" }
            return parts.joined(separator: ", ")
        },
    ]

    private static func wideValue(_ raw: [String: UInt64], base: String, used: inout Set<String>) -> (low: UInt64, high: UInt64)? {
        if used.contains(base) || used.contains(base + "_0") { return nil }
        if let low = raw[base] {
            used.insert(base)
            return (low, 0)
        }
        guard let low = raw[base + "_0"] else { return nil }
        used.insert(base + "_0")
        used.insert(base + "_1")
        return (low, raw[base + "_1"] ?? 0)
    }

    private static func dataUnits(_ low: UInt64, _ high: UInt64) -> String {
        if high == 0, low <= UInt64.max / nvmeDataUnitBytes {
            return MetricFormat.bytes(low * nvmeDataUnitBytes)
        }
        return "\(grouped(low, high)) units"
    }

    private static func grouped(_ low: UInt64, _ high: UInt64) -> String {
        guard high == 0 else { return "\(grouped(high)) × 2⁶⁴ + \(grouped(low))" }
        return grouped(low)
    }

    private static func grouped(_ value: UInt64) -> String {
        let digits = String(value)
        var parts: [String] = []
        var index = digits.endIndex
        while index > digits.startIndex {
            let start = digits.index(index, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            parts.append(String(digits[start..<index]))
            index = start
        }
        return parts.reversed().joined(separator: ",")
    }

    private static func plainTitle(_ key: String) -> String {
        key.lowercased()
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

public enum DiskDetails {
    public static func load(bsdName: String, maximumAge: TimeInterval = 5) -> DiskDetail {
        let now = Date()
        if maximumAge > 0, let cached = cache.read(bsdName, now: now, maximumAge: maximumAge) {
            return cached
        }
        let detail = read(bsdName: bsdName)
        if detail.reported {
            cache.store(detail, at: now)
        }
        return detail
    }

    private static func read(bsdName: String) -> DiskDetail {
        guard bsdName.range(of: #"^disk[0-9]+(s[0-9]+)*$"#, options: .regularExpression) != nil else {
            return DiskDetail.empty
        }
        let plist = diskutilInfo(bsdName)
        let registry = registryInfo(bsdName: bsdName)
        let smart = integerMap(plist?["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"])
        let status = plist?["SMARTStatus"] as? String ?? ""
        let block = (plist?["DeviceBlockSize"] as? NSNumber)?.uint64Value ?? registry.blockSize
        let map = DiskSmart.partitionMapTitle(plist?["Content"] as? String ?? "")
        let reported = plist != nil || registry.found
        return DiskDetail(
            bsdName: bsdName,
            reported: reported,
            serialNumber: registry.serialNumber,
            revision: registry.revision,
            blockSize: block,
            partitionMap: map,
            smartStatus: status,
            attributes: DiskSmart.attributes(from: smart),
            bytesRead: registry.bytesRead,
            bytesWritten: registry.bytesWritten,
            readOperations: registry.readOperations,
            writeOperations: registry.writeOperations,
            readErrors: registry.readErrors,
            writeErrors: registry.writeErrors,
            readRetries: registry.readRetries,
            writeRetries: registry.writeRetries,
            hasActivity: registry.hasActivity
        )
    }

    private static func diskutilInfo(_ bsdName: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", bsdName]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private struct RegistryInfo {
        var found = false
        var serialNumber = ""
        var revision = ""
        var blockSize: UInt64 = 0
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        var readOperations: UInt64 = 0
        var writeOperations: UInt64 = 0
        var readErrors: UInt64 = 0
        var writeErrors: UInt64 = 0
        var readRetries: UInt64 = 0
        var writeRetries: UInt64 = 0
        var hasActivity = false
    }

    private static func registryInfo(bsdName: String) -> RegistryInfo {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOMedia"),
              IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return RegistryInfo() }
        defer { IOObjectRelease(iterator) }

        var info = RegistryInfo()
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let current = entry
            entry = IOIteratorNext(iterator)
            let properties = copyProperties(current)
            let name = properties?["BSD Name"] as? String
            guard name == bsdName else {
                IOObjectRelease(current)
                continue
            }
            info.found = true
            info.blockSize = integer(properties?["Physical Block Size"])
            if info.blockSize == 0 { info.blockSize = integer(properties?["Preferred Block Size"]) }
            absorb(current, into: &info)
            IOObjectRelease(current)
            break
        }
        return info
    }

    private static func absorb(_ entry: io_registry_entry_t, into info: inout RegistryInfo) {
        var cursor = entry
        IOObjectRetain(cursor)
        defer { IOObjectRelease(cursor) }
        var steps = 0
        while steps < 12 {
            steps += 1
            let name = objectClass(cursor)
            if let properties = copyProperties(cursor) {
                if let device = properties["Device Characteristics"] as? NSDictionary {
                    if info.serialNumber.isEmpty, let serial = device["Serial Number"] as? String {
                        info.serialNumber = serial.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if info.revision.isEmpty, let revision = device["Product Revision Level"] as? String {
                        let trimmed = revision.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty, trimmed != "0" { info.revision = trimmed }
                    }
                }
                if name == "IOBlockStorageDriver", let statistics = properties["Statistics"] as? NSDictionary, !info.hasActivity {
                    info.bytesRead = integer(statistics["Bytes (Read)"])
                    info.bytesWritten = integer(statistics["Bytes (Write)"])
                    info.readOperations = integer(statistics["Operations (Read)"])
                    info.writeOperations = integer(statistics["Operations (Write)"])
                    info.readErrors = integer(statistics["Errors (Read)"])
                    info.writeErrors = integer(statistics["Errors (Write)"])
                    info.readRetries = integer(statistics["Retries (Read)"])
                    info.writeRetries = integer(statistics["Retries (Write)"])
                    info.hasActivity = true
                }
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(cursor, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(cursor)
            cursor = parent
        }
    }

    private static func copyProperties(_ entry: io_registry_entry_t) -> NSDictionary? {
        var raw: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return raw?.takeRetainedValue()
    }

    private static func objectClass(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return "" }
        return String(cString: name)
    }

    private static func integerMap(_ value: Any?) -> [String: UInt64] {
        guard let dictionary = value as? [String: Any] else {
            guard let object = value as? NSDictionary else { return [:] }
            var result: [String: UInt64] = [:]
            for (key, raw) in object {
                guard let name = key as? String else { continue }
                let number = integer(raw)
                if number > 0 || raw is NSNumber { result[name] = number }
            }
            return result
        }
        var result: [String: UInt64] = [:]
        for (key, raw) in dictionary {
            result[key] = integer(raw)
        }
        return result
    }

    private static func integer(_ value: Any?) -> UInt64 {
        if let number = value as? NSNumber { return number.uint64Value }
        if let number = value as? UInt64 { return number }
        if let number = value as? Int { return number >= 0 ? UInt64(number) : 0 }
        return 0
    }

    private static let cache = DetailCache()

    private final class DetailCache: @unchecked Sendable {
        private var entries: [String: (at: Date, detail: DiskDetail)] = [:]
        private let lock = NSLock()

        func read(_ name: String, now: Date, maximumAge: TimeInterval) -> DiskDetail? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[name], now.timeIntervalSince(entry.at) < maximumAge else { return nil }
            return entry.detail
        }

        func store(_ detail: DiskDetail, at date: Date) {
            lock.lock()
            entries[detail.bsdName] = (date, detail)
            lock.unlock()
        }
    }
}
