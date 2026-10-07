import Foundation

public enum TemperatureName {
    public enum Role: Equatable, Sendable {
        case cpu
        case gpu
        case other
    }

    /// A readable label for an HID product string such as `pACC MTR Temp Sensor4`, or an SMC key such as `Tg05`.
    public static func title(for raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Sensor" }
        if let kind = smcKind(cleaned) { return kind.title }
        if let channel = storageChannel(in: cleaned) {
            return "Storage channel \(channel)"
        }
        let (stem, number) = splitTrailingNumber(cleaned)
        let base = knownTitle(for: stem) ?? tidy(stem)
        guard let number else { return base }
        return "\(base) \(number)"
    }

    /// Mean of the performance-cluster average and the efficiency-cluster average.
    /// Each cluster is averaged on its own first, so extra performance diodes do not outweigh the efficiency cluster.
    /// HID `pACC` / `eACC` diodes win. Chips that do not publish them (M4 Pro, M2 Pro) use the SMC `Tp` and `Te` keys.
    /// With neither, the power-manager die sensors are the only CPU reading the machine exposes.
    public static func cpuClusterAverage(_ sensors: [TemperatureSensor]) -> Double? {
        let performance = average(sensors, prefix: "pacc") ?? averageSMC(sensors, second: "p")
        let efficiency = average(sensors, prefix: "eacc") ?? averageSMC(sensors, second: "e")
        switch (performance, efficiency) {
        case let (performance?, efficiency?):
            return (performance + efficiency) / 2
        case let (performance?, nil):
            return performance
        case let (nil, efficiency?):
            return efficiency
        default:
            return averageContaining(sensors, fragment: "tdie")
        }
    }

    /// HID GPU diodes when the chip publishes them. Otherwise the SMC `Tg` keys, then a `PMU TP…g` probe.
    public static func gpuAverage(_ sensors: [TemperatureSensor]) -> Double? {
        let diodes = sensors.filter { isHIDGPUDiode($0.name) }.map(\.celsius)
        if let value = mean(diodes) { return value }
        let smc = sensors.filter { smcKind($0.name) == .gpu }.map(\.celsius)
        if let value = mean(smc) { return value }
        return mean(sensors.filter { isGPUProbe($0.name) }.map(\.celsius))
    }

    /// True when this SMC key supplies a cluster or GPU temperature the HID diodes do not.
    /// Battery, memory, wireless, and the other letter-guesses stay off the list.
    public static func includesSMCKey(_ name: String, hid: [TemperatureSensor]) -> Bool {
        guard let kind = smcKind(name) else { return false }
        let hasPerformance = hid.contains { $0.name.lowercased().contains("pacc") }
        let hasEfficiency = hid.contains { $0.name.lowercased().contains("eacc") }
        switch kind {
        case .performance: return !hasPerformance
        case .efficiency: return !hasEfficiency
        case .gpu: return !hid.contains(where: { isHIDGPUDiode($0.name) })
        case .cpuDie: return !hasPerformance && !hasEfficiency
        case .soc, .heatsink, .battery, .ambient, .storage, .memory, .wireless, .powerManager:
            return false
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Where a sensor belongs. SMC keys are case-sensitive: `Tp` is a performance core, `TPD` is not.
    public static func role(for name: String) -> Role {
        let lower = name.lowercased()
        if lower.contains("pacc") || lower.contains("eacc") || lower.hasPrefix("cpu") {
            return .cpu
        }
        if lower.contains("gpu") || lower.contains("agx") {
            return .gpu
        }
        if let kind = smcKind(name) {
            switch kind {
            case .performance, .efficiency, .cpuDie: return .cpu
            case .gpu: return .gpu
            default: return .other
            }
        }
        if isGPUProbe(name) { return .gpu }
        return .other
    }

    /// Live thermal range. SMC also publishes `flt` keys that are not temperatures (a few degrees, or a voltage under `TV`).
    public static func acceptsCelsius(_ value: Double) -> Bool {
        value >= 8 && value <= 150
    }

    private static func average(_ sensors: [TemperatureSensor], prefix: String) -> Double? {
        let values = sensors.filter { $0.name.lowercased().hasPrefix(prefix) }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageSMC(_ sensors: [TemperatureSensor], second: Character) -> Double? {
        let values = sensors.filter { sensor in
            guard let kind = smcKind(sensor.name) else { return false }
            return (second == "p" && kind == .performance) || (second == "e" && kind == .efficiency)
        }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageContaining(_ sensors: [TemperatureSensor], fragment: String) -> Double? {
        let values = sensors.filter { $0.name.lowercased().contains(fragment) }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func isGPUProbe(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("pmu tp") && lower.hasSuffix("g")
    }

    private static func isHIDGPUDiode(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("gpu") || lower.contains("agx")
    }

    private enum SMCKind: Equatable {
        case performance
        case efficiency
        case gpu
        case cpuDie
        case soc
        case heatsink
        case battery
        case ambient
        case storage
        case memory
        case wireless
        case powerManager

        var title: String {
            switch self {
            case .performance: return "Performance cluster sensor"
            case .efficiency: return "Efficiency cluster sensor"
            case .gpu: return "GPU sensor"
            case .cpuDie: return "CPU die sensor"
            case .soc: return "SoC sensor"
            case .heatsink: return "Heatsink sensor"
            case .battery: return "Battery"
            case .ambient: return "Ambient sensor"
            case .storage: return "Storage sensor"
            case .memory: return "Memory sensor"
            case .wireless: return "Wireless sensor"
            case .powerManager: return "Power manager sensor"
            }
        }

        var family: String {
            if title.hasSuffix(" sensor") {
                return String(title.dropLast(" sensor".count))
            }
            return title
        }
    }

    /// Four-character SMC keys. The second character's case matters: `Tp1k` is the performance cluster and `TPD0` is a power-manager key. These are not one sensor per core.
    private static func smcKind(_ name: String) -> SMCKind? {
        guard name.count == 4, name.first == "T" else { return nil }
        switch name[name.index(after: name.startIndex)] {
        case "p": return .performance
        case "e": return .efficiency
        case "g": return .gpu
        case "C": return .cpuDie
        case "s": return .soc
        case "H": return .heatsink
        case "B": return .battery
        case "a": return .ambient
        case "N": return .storage
        case "m": return .memory
        case "W": return .wireless
        case "P": return .powerManager
        default: return nil
        }
    }

    /// The shared name for every numbered sensor of one kind. `PMU tdie8` and `PMU2 tdie1` are both “Power manager die”.
    public static func family(for raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Sensor" }
        if let kind = smcKind(cleaned) { return kind.family }
        if storageChannel(in: cleaned) != nil { return "Storage" }
        let (stem, _) = splitTrailingNumber(cleaned)
        let key = stem.lowercased().replacingOccurrences(of: "pmu2", with: "pmu")
        let base = knownTitle(for: key) ?? tidy(stem)
        if base.hasSuffix(" sensor") {
            return String(base.dropLast(" sensor".count))
        }
        return base
    }

    private static func storageChannel(in name: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)nand\s*ch\s*(\d+)"#),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return Int(name[range])
    }

    private static func splitTrailingNumber(_ name: String) -> (String, Int?) {
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:\s*)(\d+)\s*$"#),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let stemRange = Range(match.range(at: 1), in: name),
              let numberRange = Range(match.range(at: 2), in: name),
              let number = Int(name[numberRange])
        else { return (name, nil) }
        return (String(name[stemRange]).trimmingCharacters(in: .whitespaces), number)
    }

    private static func knownTitle(for stem: String) -> String? {
        let key = stem.lowercased()
        if key.hasPrefix("pacc") { return "Performance cluster sensor" }
        if key.hasPrefix("eacc") { return "Efficiency cluster sensor" }
        if key.contains("gpu") || key.contains("agx") { return "GPU sensor" }
        if key.contains("ane") { return "Neural Engine sensor" }
        if key.contains("isp") { return "Image processor sensor" }
        if key.contains("pmgr") { return "SoC die sensor" }
        if key.hasPrefix("soc") { return "SoC sensor" }
        if key == "pmu2 tcal" { return "Package 2" }
        if key == "pmu tcal" { return "Package" }
        if key == "pmu2 tdie" { return "Power manager 2 die" }
        if key == "pmu tdie" { return "Power manager die" }
        if key == "pmu2 tdev" { return "Power manager 2 board" }
        if key == "pmu tdev" { return "Power manager board" }
        if key.contains("tp") { return key.hasPrefix("pmu2") ? "Power manager 2 probe" : "Power manager probe" }
        if key.hasPrefix("pmu2") { return "Power manager 2" }
        if key.hasPrefix("pmu") { return "Power manager" }
        if key.contains("battery") || key.contains("gas gauge") { return "Battery" }
        if key.contains("thunderbolt") || key.contains("tbt") { return "Thunderbolt" }
        if key.contains("wlan") || key.contains("wifi") || key.contains("airport") { return "Wi-Fi" }
        return nil
    }

    private static func tidy(_ stem: String) -> String {
        var text = stem
        for phrase in ["MTR Temp Sensor", "Temp Sensor", "temp"] {
            text = text.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Sensor" : text
    }
}
