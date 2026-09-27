import Foundation

public enum MetricFormat {
    public static func percent(_ ratio: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", MetricMath.clamp01(ratio) * 100)
    }

    public static func watts(_ value: Double) -> String {
        if value < 0.01 { return String(format: "%.0f mW", value * 1000) }
        if value < 1 { return String(format: "%.0f mW", value * 1000) }
        return String(format: "%.2f W", value)
    }

    public static func milliwatts(_ value: Double) -> String {
        String(format: "%.0f mW", value * 1000)
    }

    public static func megahertz(_ value: UInt32) -> String {
        if value >= 1000 {
            return String(format: "%.2f GHz", Double(value) / 1000)
        }
        return "\(value) MHz"
    }

    public static func bytesPerSecond(_ value: Double) -> String {
        "\(bytes(UInt64(max(0, value.rounded()))))/s"
    }

    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(value)
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        if unit == 0 { return "\(value) B" }
        if size >= 100 { return String(format: "%.0f %@", size, units[unit]) }
        if size >= 10 { return String(format: "%.1f %@", size, units[unit]) }
        return String(format: "%.2f %@", size, units[unit])
    }

    public static func temperature(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(format: "%.1f°C", value)
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    public static func uptime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func load(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    public static func processCPU(_ percent: Double) -> String {
        String(format: "%.1f%%", max(0, percent))
    }

    public static func wholePercent(_ ratio: Double) -> String {
        String(format: "%.0f", MetricMath.clamp01(ratio) * 100)
    }

    /// Estimated activity, marked approximate so it is not read as occupancy: `~37%`
    public static func estimatedPercent(_ ratio: Double, digits: Int = 1) -> String {
        "~\(percent(ratio, digits: digits))"
    }

    /// Menu-bar percent. Pads 0–9 with a figure space so `8%` matches `32%` without
    /// reserving a third digit for the rare `100%`.
    public static func menuBarPercent(_ ratio: Double, estimated: Bool = false) -> String {
        let n = Int((MetricMath.clamp01(ratio) * 100).rounded())
        let body: String
        if n >= 100 {
            body = "100%"
        } else {
            body = String(format: "%2d%%", n).replacingOccurrences(of: " ", with: "\u{2007}")
        }
        return estimated ? "~\(body)" : body
    }

    /// Menu-bar temperature. Two digits, figure-space padded, with a degree sign and no unit letter.
    public static func menuBarTemperature(_ celsius: Double?) -> String {
        guard let celsius, celsius > 0 else { return "—" }
        let n = Int(celsius.rounded())
        if n >= 100 { return "\(n)°" }
        return String(format: "%2d°", max(0, n)).replacingOccurrences(of: " ", with: "\u{2007}")
    }

    /// Hide a numeric reading when the channel itself is unavailable (idle zero stays visible).
    public static func value(_ text: String, quality: MetricQuality) -> String {
        quality == .unavailable ? "—" : text
    }

    public static func historyWindow(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds >= 60 && seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds)s"
    }

    /// Compact menu-bar line. Single spaces between fields; 2-digit figure-space padding.
    public static func menuBarLine(
        cpu: Double,
        gpu: Double,
        memory: Double,
        ane: Double,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil
    ) -> String {
        "CPU \(menuBarPercent(cpu)) \(menuBarTemperature(cpuTemp)) GPU \(menuBarPercent(gpu)) \(menuBarTemperature(gpuTemp)) MEM \(menuBarPercent(memory)) ANE \(menuBarPercent(ane, estimated: true))"
    }

    public static func menuBarTooltip(
        cpu: Double,
        gpu: Double,
        memory: Double,
        ane: Double,
        cpuWatts: Double,
        gpuWatts: Double,
        aneWatts: Double,
        pressure: MemoryPressure = .unknown,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil
    ) -> String {
        """
        Silicon Scope
        CPU (processor)  \(percent(cpu, digits: 0))  \(temperature(cpuTemp))  \(watts(cpuWatts))
        GPU (graphics)  \(percent(gpu, digits: 0))  \(temperature(gpuTemp))  \(watts(gpuWatts))
        Memory  \(percent(memory, digits: 0))  pressure \(pressure.title)
        ANE activity (estimated)  \(estimatedPercent(ane, digits: 0))  \(watts(aneWatts)) measured
        """
    }
}
