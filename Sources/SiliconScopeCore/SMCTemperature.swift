import Foundation
import IOKit

/// Apple SMC temperature keys. M4 Pro and M2 Pro do not publish `pACC` / `eACC` / `GPU MTR` HID diodes; the live core and GPU temperatures are these keys.
enum SMCTemperature {
    private static let commandReadBytes: UInt8 = 5
    private static let commandReadIndex: UInt8 = 8
    private static let commandReadInfo: UInt8 = 9
    private static let recordSize = 80
    private static let keyOffset = 0
    private static let infoSizeOffset = 28
    private static let infoTypeOffset = 32
    private static let data8Offset = 42
    private static let data32Offset = 44
    private static let bytesOffset = 48

    private static var connection: io_connect_t = 0
    private static var opened = false
    private static var cachedKeys: [Key]?

    private struct Key {
        var code: UInt32
        var size: UInt32
        var type: UInt32
    }

    static func sample() -> [TemperatureSensor] {
        guard connect() else { return [] }
        if cachedKeys == nil {
            cachedKeys = discover()
        }
        guard let cachedKeys else { return [] }
        var sensors: [TemperatureSensor] = []
        sensors.reserveCapacity(cachedKeys.count)
        for entry in cachedKeys {
            guard let celsius = readCelsius(entry), TemperatureName.acceptsCelsius(celsius) else { continue }
            let name = string(for: entry.code)
            sensors.append(TemperatureSensor(
                id: "smc-\(name)",
                name: name,
                celsius: celsius,
                group: TemperatureGroup.group(forSensorName: name)
            ))
        }
        return sensors
    }

    private static func connect() -> Bool {
        if opened { return connection != 0 }
        opened = true
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleSMC"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return false }
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var openedConnection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &openedConnection) == KERN_SUCCESS else { return false }
        connection = openedConnection
        return true
    }

    private static func discover() -> [Key] {
        let limit = keyCount()
        var found: [Key] = []
        for index in 0..<limit {
            var input = blank()
            write(commandReadIndex, into: &input, at: data8Offset)
            write(UInt32(index), into: &input, at: data32Offset)
            guard call(&input) else { continue }
            let code = readUInt32(input, at: keyOffset)
            guard code != 0 else { continue }
            let name = string(for: code)
            guard name.first == "T", !name.hasPrefix("TV") else { continue }
            guard let info = keyInfo(code) else { continue }
            let type = string(for: info.type)
            guard type == "flt " || type == "sp78" else { continue }
            found.append(Key(code: code, size: info.size, type: info.type))
        }
        return found
    }

    private static func keyCount() -> Int {
        guard let info = keyInfo(code("#KEY")), info.size >= 4, let bytes = readBytes(code("#KEY"), size: info.size) else {
            return 2048
        }
        let count = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        guard (1...8192).contains(count) else { return 2048 }
        return count
    }

    private static func readCelsius(_ entry: Key) -> Double? {
        guard let bytes = readBytes(entry.code, size: entry.size) else { return nil }
        let type = string(for: entry.type)
        if type == "flt ", bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        }
        if type == "sp78", bytes.count >= 2 {
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        }
        return nil
    }

    private static func keyInfo(_ code: UInt32) -> (size: UInt32, type: UInt32)? {
        var input = blank()
        write(code, into: &input, at: keyOffset)
        write(commandReadInfo, into: &input, at: data8Offset)
        guard call(&input) else { return nil }
        let size = readUInt32(input, at: infoSizeOffset)
        guard size > 0, size <= 32 else { return nil }
        return (size, readUInt32(input, at: infoTypeOffset))
    }

    private static func readBytes(_ code: UInt32, size: UInt32) -> [UInt8]? {
        var input = blank()
        write(code, into: &input, at: keyOffset)
        write(size, into: &input, at: infoSizeOffset)
        write(commandReadBytes, into: &input, at: data8Offset)
        guard call(&input) else { return nil }
        let start = bytesOffset
        let end = start + Int(size)
        guard end <= input.count else { return nil }
        return Array(input[start..<end])
    }

    private static func call(_ input: inout [UInt8]) -> Bool {
        var output = blank()
        var outSize = output.count
        let result = input.withUnsafeBytes { inRaw in
            output.withUnsafeMutableBytes { outRaw in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inRaw.baseAddress,
                    inRaw.count,
                    outRaw.baseAddress,
                    &outSize
                )
            }
        }
        guard result == KERN_SUCCESS else { return false }
        input = output
        return true
    }

    private static func blank() -> [UInt8] {
        Array(repeating: 0, count: recordSize)
    }

    private static func code(_ text: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in text.utf8.prefix(4) {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }

    private static func string(for value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }

    private static func write(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xff)
        bytes[offset + 1] = UInt8((value >> 8) & 0xff)
        bytes[offset + 2] = UInt8((value >> 16) & 0xff)
        bytes[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private static func write(_ value: UInt8, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = value
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
