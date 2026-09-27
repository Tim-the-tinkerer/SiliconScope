import Foundation

public enum TemperatureName {
    /// A readable label for an HID product string such as `pACC MTR Temp Sensor4`.
    public static func title(for raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Sensor" }
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
    public static func cpuClusterAverage(_ sensors: [TemperatureSensor]) -> Double? {
        let performance = average(sensors, prefix: "pacc")
        let efficiency = average(sensors, prefix: "eacc")
        switch (performance, efficiency) {
        case let (performance?, efficiency?):
            return (performance + efficiency) / 2
        case let (performance?, nil):
            return performance
        case let (nil, efficiency?):
            return efficiency
        default:
            return nil
        }
    }

    private static func average(_ sensors: [TemperatureSensor], prefix: String) -> Double? {
        let values = sensors.filter { $0.name.lowercased().hasPrefix(prefix) }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The shared name for every numbered sensor of one kind. `PMU tdie8` and `PMU2 tdie1` are both “Power manager die”.
    public static func family(for raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "Sensor" }
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
