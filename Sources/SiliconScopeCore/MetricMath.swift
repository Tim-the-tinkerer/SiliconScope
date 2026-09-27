import Foundation

public enum MetricMath {
    /// Bytes per second between two cumulative counters. A reset (current below previous) reports zero instead of a spike.
    public static func counterRate(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    public static func ratio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0, numerator.isFinite, denominator.isFinite else { return 0 }
        return min(max(numerator / denominator, 0), 1)
    }

    public static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    public static func watts(energy: Double, unit: String, duration: TimeInterval) -> Double? {
        guard duration > 0, energy.isFinite else { return nil }
        let perSecond = energy / duration
        switch unit.trimmingCharacters(in: .whitespaces).lowercased() {
        case "mj": return perSecond / 1_000
        case "uj", "µj": return perSecond / 1_000_000
        case "nj": return perSecond / 1_000_000_000
        case "j": return perSecond
        default: return nil
        }
    }

    /// Estimated ANE activity: measured energy-model watts divided by a typical peak for the chip.
    /// This is an activity indicator, not processor occupancy — Apple does not publish an ANE occupancy counter.
    public static func aneActivity(powerWatts: Double, peakWatts: Double) -> Double {
        ratio(powerWatts, peakWatts)
    }

    public static func frequencyMetrics(
        residencies: [(name: String, value: Int64)],
        frequenciesMHz: [UInt32]
    ) -> (frequencyMHz: UInt32, scaledRatio: Double, activeRatio: Double) {
        guard !residencies.isEmpty, !frequenciesMHz.isEmpty else {
            return (0, 0, 0)
        }

        let offset = residencies.firstIndex { state in
            let name = state.name.uppercased()
            return name != "IDLE" && name != "DOWN" && name != "OFF"
        } ?? residencies.count

        let freqs = Array(frequenciesMHz.prefix(max(0, residencies.count - offset)))
        guard !freqs.isEmpty else { return (0, 0, 0) }

        let active = residencies.dropFirst(offset).prefix(freqs.count).reduce(0.0) { $0 + Double($1.value) }
        let total = residencies.reduce(0.0) { $0 + Double($1.value) }
        let activeRatio = ratio(active, total)

        var weighted = 0.0
        for (index, freq) in freqs.enumerated() {
            let sampleIndex = offset + index
            guard sampleIndex < residencies.count else { break }
            weighted += ratio(Double(residencies[sampleIndex].value), active) * Double(freq)
        }

        let minFreq = Double(freqs.first ?? 0)
        let maxFreq = Double(freqs.last ?? freqs.first ?? 1)
        let average = max(weighted, minFreq)
        let scaled = maxFreq > 0 ? (average * activeRatio) / maxFreq : 0
        return (UInt32(average.rounded()), clamp01(scaled), activeRatio)
    }

    public static func parseCPUCore(_ channel: String) -> (kind: CoreKind, key: String)? {
        if channel.contains("PCPU") {
            return (.performance, channel)
        }
        if channel.contains("ECPU") || channel.contains("MCPU") {
            return (.efficiency, channel)
        }
        return nil
    }

    public static func parseDieID(_ channel: String) -> Int {
        guard channel.hasPrefix("DIE_") else { return 0 }
        let rest = channel.dropFirst(4)
        let digits = rest.prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }

    public static func parseCoreID(_ channel: String) -> Int {
        if let cpuRange = channel.range(of: "_CPU", options: .backwards) {
            let digits = channel[cpuRange.upperBound...].prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
        for prefix in ["PCPU", "ECPU", "MCPU"] {
            if let range = channel.range(of: prefix) {
                let after = channel[range.upperBound...]
                let digits = after.prefix(while: { $0.isNumber })
                if let value = Int(digits) { return value }
            }
        }
        return 0
    }

    public static func sortKey(forCPUChannel channel: String) -> (Int, Int, Int) {
        let die = parseDieID(channel)
        for prefix in ["PCPU", "ECPU", "MCPU"] {
            guard let range = channel.range(of: prefix) else { continue }
            let suffix = channel[range.upperBound...]
            if let cpu = suffix.range(of: "_CPU") {
                let clusterText = suffix[..<cpu.lowerBound]
                let cluster = clusterText.isEmpty ? 0 : (Int(clusterText) ?? 0)
                let core = Int(suffix[cpu.upperBound...].prefix(while: { $0.isNumber })) ?? 0
                return (die, cluster, core)
            }
            let core = Int(suffix.prefix(while: { $0.isNumber })) ?? 0
            return (die, 0, core)
        }
        return (die, 0, 0)
    }

    public static func flattenCores(
        _ samples: [(channel: String, frequencyMHz: UInt32, scaledRatio: Double, activeRatio: Double)],
        kind: CoreKind
    ) -> [CoreSample] {
        let ordered = samples.sorted { sortKey(forCPUChannel: $0.channel) < sortKey(forCPUChannel: $1.channel) }
        var nextID: [Int: Int] = [:]
        return ordered.map { item in
            let die = parseDieID(item.channel)
            let coreID: Int
            if item.channel.contains("_CPU") {
                let next = nextID[die] ?? 0
                nextID[die] = next + 1
                coreID = next
            } else {
                coreID = parseCoreID(item.channel)
            }
            return CoreSample(
                kind: kind,
                dieID: die,
                coreID: coreID,
                frequencyMHz: item.frequencyMHz,
                activeRatio: item.activeRatio,
                scaledRatio: item.scaledRatio
            )
        }
    }

    public static func aggregateCluster(
        _ cores: [CoreSample],
        expectedCount: Int,
        minimumFrequencyMHz: UInt32
    ) -> (frequencyMHz: UInt32, scaledRatio: Double, activeRatio: Double) {
        let count = Double(max(cores.count, expectedCount, 1))
        let scaled = cores.reduce(0.0) { $0 + $1.scaledRatio } / count
        let active = cores.reduce(0.0) { $0 + $1.activeRatio } / count
        let averageFreq = cores.isEmpty
            ? Double(minimumFrequencyMHz)
            : cores.reduce(0.0) { $0 + Double($1.frequencyMHz) } / Double(cores.count)
        let frequency = UInt32(max(averageFreq, Double(minimumFrequencyMHz)).rounded())
        return (frequency, clamp01(scaled), clamp01(active))
    }

    public static func memoryUsedBytes(
        pageSize: UInt64,
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64
    ) -> (used: UInt64, app: UInt64) {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let app = appPages * pageSize
        let used = app + wiredPages * pageSize + compressorPages * pageSize
        return (used, app)
    }

    /// `kern.memorystatus_vm_pressure_level` on shipping macOS.
    /// A healthy Mac reports 1. The kernel also uses 0 for Normal and 8 for the older critical flag.
    public static func pressure(fromLevel level: Int32) -> MemoryPressure {
        switch level {
        case 0, 1: return .normal
        case 2: return .warning
        case 3: return .urgent
        case 4, 8: return .critical
        default: return .unknown
        }
    }

    /// First rail that actually moved wins. A stuck zero (the aggregate channel on some chips) falls through to the cluster counters. If every present rail is idle, the result stays zero.
    public static func preferredWatts(_ candidates: [Double?]) -> Double {
        var idle = 0.0
        var saw = false
        for value in candidates {
            guard let value, value.isFinite else { continue }
            let watts = max(0, value)
            saw = true
            if watts > 0.01 { return watts }
            idle = watts
        }
        return saw ? idle : 0
    }

    /// Activity Monitor's cached-files bucket: file-backed pages plus purgeable anonymous memory.
    public static func cachedFileBytes(pageSize: UInt64, externalPages: UInt64, purgeablePages: UInt64) -> UInt64 {
        pageSize * (externalPages + purgeablePages)
    }

    /// Letter shown for a `hw.perflevelN.name` value: Efficiency, Performance, or Super.
    public static func clusterLetter(forPerfLevelName name: String) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "efficiency": return "E"
        case "performance": return "P"
        case "super": return "S"
        default:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { return "P" }
            return String(first).uppercased()
        }
    }

    /// One DVFS frequency word. M1–M3 store Hz; M4 and later store kHz. The two ranges do not overlap.
    public static func dvfsMegahertz(raw: UInt32) -> UInt32? {
        guard raw > 0 else { return nil }
        let mhz: UInt32
        if raw >= 100_000_000 {
            mhz = raw / 1_000_000
        } else if raw >= 100_000 {
            mhz = raw / 1_000
        } else {
            mhz = raw
        }
        guard (200...20_000).contains(mhz) else { return nil }
        return mhz
    }

    /// Assumed ANE peak used only to estimate activity (power / peak). Not a measured occupancy ceiling.
    public static func typicalANEPeakWatts(chipName: String) -> Double {
        let name = chipName.uppercased()
        if name.contains("ULTRA") { return 16 }
        if name.contains("M4") && (name.contains("MAX") || name.contains("PRO")) { return 10 }
        if name.contains("M4") { return 8 }
        return 8
    }

    public static func cpuFrequencyScale(chipName: String) -> UInt32 {
        let name = chipName.uppercased()
        if name.contains("M1") || name.contains("M2") || name.contains("M3") || name.contains("A1") {
            return 1_000_000
        }
        return 1_000
    }
}
