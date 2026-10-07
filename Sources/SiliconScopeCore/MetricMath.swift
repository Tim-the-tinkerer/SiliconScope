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
        // A core parked in DOWN/IDLE has no clock. Reporting the bottom DVFS step made a powered-off M4 cluster look busy at its minimum megahertz.
        guard active > 0 else { return (0, 0, activeRatio) }

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
        sortKey(forCPUChannel: channel).2
    }

    /// Die, cluster, then core. M4 names a core `PCPU100`: cluster 1, core 0, with a trailing zero. Older names are `PCPU1` or `DIE_0_PCPU1_CPU3`.
    public static func sortKey(forCPUChannel channel: String) -> (Int, Int, Int) {
        let die = parseDieID(channel)
        let body: Substring
        if channel.hasPrefix("DIE_"), let split = channel.dropFirst(4).firstIndex(of: "_") {
            body = channel[channel.index(after: split)...]
        } else {
            body = Substring(channel)
        }
        for prefix in ["PCPU", "ECPU", "MCPU", "SCPU"] {
            guard let range = body.range(of: prefix) else { continue }
            let suffix = body[range.upperBound...]
            if let cpu = suffix.range(of: "_CPU") {
                let clusterText = suffix[..<cpu.lowerBound]
                let cluster = clusterText.isEmpty ? 0 : (Int(clusterText) ?? 0)
                let core = Int(suffix[cpu.upperBound...].prefix(while: { $0.isNumber })) ?? 0
                return (die, cluster, core)
            }
            let digits = suffix.prefix(while: { $0.isNumber })
            if digits.count == 3, digits.last == "0" {
                let chars = Array(digits)
                let cluster = chars[0].wholeNumberValue ?? 0
                let core = chars[1].wholeNumberValue ?? 0
                return (die, cluster, core)
            }
            return (die, 0, Int(digits) ?? 0)
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
            let coreID = nextID[die] ?? 0
            nextID[die] = coreID + 1
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
        let weight = cores.reduce(0.0) { $0 + $1.activeRatio }
        let averageFreq: Double
        if cores.isEmpty {
            averageFreq = Double(minimumFrequencyMHz)
        } else if weight > 0 {
            // M4 Pro keeps one performance cluster powered off. An unweighted mean treats that cluster's floor clock as real work.
            averageFreq = cores.reduce(0.0) { $0 + Double($1.frequencyMHz) * $1.activeRatio } / weight
        } else {
            averageFreq = 0
        }
        return (UInt32(averageFreq.rounded()), clamp01(scaled), clamp01(active))
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

    /// One `voltage-states*` ladder from the power manager, already decoded to MHz.
    public struct FrequencyLadder: Equatable, Sendable {
        public var key: String
        public var megahertz: [UInt32]
        /// M4 and later store CPU clusters in kilohertz. M1–M3 store hertz, and so do the non-CPU domains that sit beside the M4 tables.
        public var kilohertzEncoded: Bool

        public init(key: String, megahertz: [UInt32], kilohertzEncoded: Bool) {
            self.key = key
            self.megahertz = megahertz
            self.kilohertzEncoded = kilohertzEncoded
        }
    }

    /// The slowest CPU ladder is the efficiency cluster and the fastest is the performance cluster.
    /// When any kilohertz ladder reaches a CPU clock, those are the clusters: an M4 Pro also publishes hertz tables that peak near 2 GHz and are not CPU cores.
    /// Chips with only hertz tables (M1–M3) keep every ladder that peaks at 2 GHz or more.
    public static func classifyFrequencyLadders(
        _ ladders: [FrequencyLadder]
    ) -> (efficiency: [UInt32], performance: [UInt32], gpu: [UInt32]) {
        let cpuClock: UInt32 = 2_000
        let cpuCandidates = ladders.filter { ($0.megahertz.max() ?? 0) >= cpuClock }
        let kilohertz = cpuCandidates.filter(\.kilohertzEncoded)
        let cpuSource = kilohertz.isEmpty ? cpuCandidates : kilohertz
        let unique = uniqueFrequencyLadders(cpuSource.map(\.megahertz))
        let efficiency: [UInt32]
        let performance: [UInt32]
        if let slowest = unique.first, let fastest = unique.last {
            if unique.count == 1 {
                efficiency = []
                performance = fastest
            } else {
                efficiency = slowest
                performance = fastest
            }
        } else {
            efficiency = []
            performance = []
        }
        return (efficiency, performance, gpuFrequencyLadder(ladders))
    }

    /// A PMP energy histogram bin such as `0.250W` or `  2W`.
    public static func wattBin(_ name: String) -> Double? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let unit = trimmed.last, unit == "W" || unit == "w" else { return nil }
        let number = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
        guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Weighted watt-seconds and the sample count for one power rail. Nil when the channel is not a watt histogram.
    public static func powerHistogram(
        _ residencies: [(name: String, value: Int64)]
    ) -> (weighted: Double, events: Double)? {
        var weighted = 0.0
        var events = 0.0
        var labeled = false
        for state in residencies {
            guard let watts = wattBin(state.name) else { continue }
            labeled = true
            let count = Double(max(0, state.value))
            weighted += watts * count
            events += count
        }
        guard labeled else { return nil }
        return (weighted, events)
    }

    /// Sum of rail averages. A sleeping M4 cluster records only a few bins, so each rail is scaled to the busiest rail's sample count and the gap counts as zero watts.
    public static func normalizedHistogramWatts(_ rails: [(weighted: Double, events: Double)]) -> Double? {
        let active = rails.filter { $0.events > 0 }
        guard !active.isEmpty else { return rails.isEmpty ? nil : 0 }
        let span = active.map(\.events).max() ?? 0
        guard span > 0 else { return 0 }
        return active.reduce(0.0) { $0 + ($1.weighted / span) }
    }

    private static func uniqueFrequencyLadders(_ ladders: [[UInt32]]) -> [[UInt32]] {
        var seen = Set<[UInt32]>()
        var result: [[UInt32]] = []
        for ladder in ladders where seen.insert(ladder).inserted {
            result.append(ladder)
        }
        return result.sorted { ($0.max() ?? 0) < ($1.max() ?? 0) }
    }

    private static func gpuFrequencyLadder(_ ladders: [FrequencyLadder]) -> [UInt32] {
        if let sram = ladders.first(where: { $0.key == "voltage-states9-sram" && !$0.megahertz.isEmpty }) {
            return sram.megahertz
        }
        if let plain = ladders.first(where: { $0.key == "voltage-states9" && !$0.megahertz.isEmpty }) {
            return plain.megahertz
        }
        return ladders
            .filter { !$0.megahertz.isEmpty && ($0.megahertz.max() ?? 0) < 2_000 }
            .max(by: { ($0.megahertz.max() ?? 0) < ($1.megahertz.max() ?? 0) })?
            .megahertz ?? []
    }
}
