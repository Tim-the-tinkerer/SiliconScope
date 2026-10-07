import CoreFoundation
import Foundation

final class IOReportSampler {
    private let hardware: HardwareProfile
    /// Create-rule object. Held for the life of the sampler so ARC, not a raw pointer, owns it.
    private let subscription: CFTypeRef
    private let channels: CFMutableDictionary
    private var previous: (sample: CFDictionary, time: Date)?

    private var subscriptionPointer: IOReportSubscriptionRef {
        UnsafeRawPointer(Unmanaged.passUnretained(subscription).toOpaque())
    }

    init?(hardware: HardwareProfile) {
        guard hardware.isAppleSilicon, IOReport.isAvailable,
              let copyAll = IOReport.copyAllChannels,
              let createSub = IOReport.createSubscription
        else { return nil }

        guard let all = copyAll(0, 0)?.takeRetainedValue() else { return nil }
        guard let selected = Self.filteredChannels(from: all) else { return nil }
        var unused: CFMutableDictionary?
        guard let sub = createSub(nil, selected, &unused, 0, nil)?.takeRetainedValue() else { return nil }
        _ = unused

        self.hardware = hardware
        self.subscription = sub
        self.channels = selected

        if let createSamples = IOReport.createSamples,
           let first = createSamples(Unmanaged.passUnretained(sub).toOpaque(), selected, nil)?.takeRetainedValue() {
            previous = (Self.copyDictionary(first), Date().addingTimeInterval(-0.001))
        }
    }

    func sample(interval: TimeInterval) -> IOReportReading? {
        guard let createSamples = IOReport.createSamples,
              let createDelta = IOReport.createSamplesDelta
        else { return nil }

        let previousSample: (CFDictionary, Date)
        if let existing = previous {
            previousSample = existing
        } else {
            guard let first = createSamples(subscriptionPointer, channels, nil)?.takeRetainedValue() else { return nil }
            previousSample = (Self.copyDictionary(first), Date())
        }

        let wait = interval - Date().timeIntervalSince(previousSample.1)
        if wait > 0.005 {
            Thread.sleep(forTimeInterval: wait)
        }

        guard let next = createSamples(subscriptionPointer, channels, nil)?.takeRetainedValue() else { return nil }
        let now = Date()
        let nextCopy = Self.copyDictionary(next)
        guard let delta = createDelta(previousSample.0, nextCopy, nil)?.takeRetainedValue() else { return nil }
        previous = (nextCopy, now)

        let elapsed = max(now.timeIntervalSince(previousSample.1), 0.001)
        return Self.parse(delta: delta, elapsed: elapsed, hardware: hardware)
    }

    private static func filteredChannels(from all: CFMutableDictionary) -> CFMutableDictionary? {
        guard let copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, all) else { return nil }
        let source = (all as NSDictionary)["IOReportChannels"] as? [Any] ?? []
        let selected = NSMutableArray()
        for item in source {
            guard let dict = item as? NSDictionary else { continue }
            let cf = dict as CFDictionary
            let group = IOReport.string(IOReport.channelGroup, cf)
            let subgroup = IOReport.string(IOReport.channelSubGroup, cf)
            let channel = IOReport.string(IOReport.channelName, cf)
            if Self.shouldSubscribe(group: group, subgroup: subgroup, channel: channel) {
                selected.add(dict)
            }
        }
        (copy as NSMutableDictionary)["IOReportChannels"] = selected
        return copy
    }

    private static func copyDictionary(_ dict: CFDictionary) -> CFDictionary {
        if let copy = CFPropertyListCreateDeepCopy(kCFAllocatorDefault, dict, 0) as? NSDictionary {
            return copy as CFDictionary
        }
        return CFDictionaryCreateCopy(kCFAllocatorDefault, dict) ?? dict
    }

    private static func shouldSubscribe(group: String, subgroup: String, channel: String) -> Bool {
        if group == "CPU Stats" && subgroup == "CPU Core Performance States" { return true }
        if group == "GPU Stats" && subgroup == "GPU Performance States" { return true }
        if group == "Energy Model" {
            return channel == "CPU Energy"
                || channel == "GPU Energy"
                || channel == "ECPU"
                || channel == "PCPU"
                || channel.hasPrefix("ANE")
                || channel.hasSuffix("CPU Energy")
        }
        if group == "PMP" && (subgroup == "Energy Counters" || subgroup == "Energy") {
            return channel == "ANE" || channel == "DRAM" || channel == "GPU SRAM"
                || isCPUEnergyChannel(channel)
        }
        return false
    }

    /// Cluster rails on M4 are `EACC0` / `PACC1` / `EACC0 SRAM`, not the older `ECPU` / `PCPU` counters.
    private static func isCPUEnergyChannel(_ channel: String) -> Bool {
        let name = channel.uppercased()
        if name.contains("AGX") || name.contains("GPU") || name.contains("ANE") || name.contains("DRAM") {
            return false
        }
        return name.contains("EACC") || name.contains("PACC") || name.contains("ECPU") || name.contains("PCPU")
    }

    private static func parse(delta: CFDictionary, elapsed: TimeInterval, hardware: HardwareProfile) -> IOReportReading {
        var reading = IOReportReading()
        let items = (delta as NSDictionary)["IOReportChannels"] as? [Any] ?? []
        var eSamples: [(String, UInt32, Double, Double)] = []
        var pSamples: [(String, UInt32, Double, Double)] = []
        var cpuAggregate: Double?
        var cpuParts: Double?
        var cpuPMP: Double?
        var cpuHistograms: [(weighted: Double, events: Double)] = []
        var aneModel: Double?
        var anePMP: Double?
        var gpuLockedToPrimary = false

        for item in items {
            guard let ns = item as? NSDictionary else { continue }
            let dict = ns as CFDictionary
            let group = IOReport.string(IOReport.channelGroup, dict)
            let subgroup = IOReport.string(IOReport.channelSubGroup, dict)
            let channel = IOReport.string(IOReport.channelName, dict)
            let unit = IOReport.string(IOReport.channelUnit, dict)

            if group == "CPU Stats" && subgroup == "CPU Core Performance States" {
                guard let parsed = MetricMath.parseCPUCore(channel) else { continue }
                let freqs = parsed.kind == .performance ? hardware.pCoreFrequenciesMHz : hardware.eCoreFrequenciesMHz
                let metrics = MetricMath.frequencyMetrics(residencies: residencies(dict), frequenciesMHz: freqs)
                let row = (channel, metrics.frequencyMHz, metrics.scaledRatio, metrics.activeRatio)
                if parsed.kind == .performance {
                    pSamples.append(row)
                } else {
                    eSamples.append(row)
                }
                reading.sawCPUResidency = true
            } else if group == "GPU Stats" && subgroup == "GPU Performance States"
                && (channel == "GPUPH" || channel.hasPrefix("GPU")) {
                if gpuLockedToPrimary && channel != "GPUPH" { continue }
                var freqs = hardware.gpuFrequenciesMHz
                if freqs.first == 0 { freqs = Array(freqs.dropFirst()) }
                let metrics = MetricMath.frequencyMetrics(residencies: residencies(dict), frequenciesMHz: freqs)
                reading.gpuFrequencyMHz = metrics.frequencyMHz
                reading.gpuScaledRatio = metrics.scaledRatio
                reading.gpuActiveRatio = metrics.activeRatio
                reading.sawGPUResidency = true
                if channel == "GPUPH" { gpuLockedToPrimary = true }
            } else if group == "Energy Model" {
                guard let watts = energyWatts(dict, unit: unit, elapsed: elapsed) else { continue }
                if channel == "GPU Energy" {
                    reading.gpuPowerWatts += watts
                    reading.sawGPUEnergy = true
                } else if channel.hasSuffix("CPU Energy") {
                    cpuAggregate = (cpuAggregate ?? 0) + watts
                } else if channel == "ECPU" || channel == "PCPU" {
                    cpuParts = (cpuParts ?? 0) + watts
                } else if channel.hasPrefix("ANE") {
                    aneModel = (aneModel ?? 0) + watts
                }
            } else if group == "PMP" && (subgroup == "Energy Counters" || subgroup == "Energy") {
                if isCPUEnergyChannel(channel) {
                    let states = residencies(dict)
                    if let histogram = MetricMath.powerHistogram(states) {
                        cpuHistograms.append(histogram)
                    } else if let watts = energyWatts(dict, unit: unit, elapsed: elapsed) {
                        cpuPMP = (cpuPMP ?? 0) + watts
                    }
                } else if let watts = energyWatts(dict, unit: unit, elapsed: elapsed) {
                    switch channel {
                    case "ANE":
                        anePMP = (anePMP ?? 0) + watts
                    case "DRAM":
                        reading.ramPowerWatts += watts
                        reading.sawDRAM = true
                    case "GPU SRAM":
                        reading.gpuSRAMPowerWatts += watts
                        reading.sawGPUSRAM = true
                    default: break
                    }
                }
            }
        }

        let histogramWatts = MetricMath.normalizedHistogramWatts(cpuHistograms)
        reading.cpuPowerWatts = MetricMath.preferredWatts([cpuAggregate, cpuParts, histogramWatts, cpuPMP])
        reading.sawCPUEnergy = cpuAggregate != nil || cpuParts != nil || histogramWatts != nil || cpuPMP != nil
        reading.anePowerWatts = MetricMath.preferredWatts([aneModel, anePMP])
        reading.sawANEEnergy = aneModel != nil || anePMP != nil
        reading.gpuPowerWatts = max(0, reading.gpuPowerWatts)
        reading.ramPowerWatts = max(0, reading.ramPowerWatts)
        reading.gpuSRAMPowerWatts = max(0, reading.gpuSRAMPowerWatts)
        reading.efficiencyCores = MetricMath.flattenCores(eSamples, kind: .efficiency)
        reading.performanceCores = MetricMath.flattenCores(pSamples, kind: .performance)
        return reading
    }

    private static func residencies(_ item: CFDictionary) -> [(name: String, value: Int64)] {
        guard let countFn = IOReport.stateCount, let residencyFn = IOReport.stateResidency else { return [] }
        let count = countFn(item)
        var rows: [(String, Int64)] = []
        rows.reserveCapacity(Int(count))
        for index in 0..<count {
            let name: String
            if let getter = IOReport.stateName, let unmanaged = getter(item, index) {
                name = unmanaged.takeUnretainedValue() as String
            } else {
                name = "S\(index)"
            }
            rows.append((name, residencyFn(item, index)))
        }
        return rows
    }

    private static func energyWatts(_ item: CFDictionary, unit: String, elapsed: TimeInterval) -> Double? {
        guard let getter = IOReport.simpleInteger else { return nil }
        return MetricMath.watts(energy: Double(getter(item, 0)), unit: unit, duration: elapsed)
    }
}

struct IOReportReading {
    var efficiencyCores: [CoreSample] = []
    var performanceCores: [CoreSample] = []
    var gpuActiveRatio: Double = 0
    var gpuScaledRatio: Double = 0
    var gpuFrequencyMHz: UInt32 = 0
    var cpuPowerWatts: Double = 0
    var gpuPowerWatts: Double = 0
    var anePowerWatts: Double = 0
    var ramPowerWatts: Double = 0
    var gpuSRAMPowerWatts: Double = 0
    var sawCPUResidency: Bool = false
    var sawGPUResidency: Bool = false
    var sawCPUEnergy: Bool = false
    var sawGPUEnergy: Bool = false
    var sawANEEnergy: Bool = false
    var sawDRAM: Bool = false
    var sawGPUSRAM: Bool = false
}
