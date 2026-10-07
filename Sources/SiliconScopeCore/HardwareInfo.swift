import CoreFoundation
import Darwin
import Foundation
import IOKit

public enum HardwareInfo {
    public static func load() -> HardwareProfile {
        let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown chip"
        let model = Sysctl.string("hw.model") ?? "Unknown"
        let memory = Sysctl.u64("hw.memsize") ?? 0
        let appleSilicon = isAppleSilicon(chipName: chip)
        let topology = cpuTopology()
        let gpuCores = gpuCoreCount()
        let freqs = appleSilicon ? dvfsTables() : DVFSTables()

        return HardwareProfile(
            chipName: chip,
            modelIdentifier: model,
            memoryBytes: memory,
            eCoreCount: topology.eCores,
            pCoreCount: topology.pCores,
            eCoreLabel: topology.eLabel,
            pCoreLabel: topology.pLabel,
            eClusterName: topology.eName,
            pClusterName: topology.pName,
            gpuCoreCount: gpuCores,
            eCoreFrequenciesMHz: freqs.eCPU,
            pCoreFrequenciesMHz: freqs.pCPU,
            gpuFrequenciesMHz: freqs.gpu,
            anePeakWatts: MetricMath.typicalANEPeakWatts(chipName: chip),
            isAppleSilicon: appleSilicon
        )
    }

    public static func isAppleSilicon(chipName: String) -> Bool {
        let name = chipName.uppercased()
        return name.contains("APPLE") || name.contains(" M1") || name.contains(" M2")
            || name.contains(" M3") || name.contains(" M4") || name.contains(" M5")
            || name.hasPrefix("APPLE M")
    }

    private struct Topology {
        var eCores: Int
        var pCores: Int
        var eLabel: String
        var pLabel: String
        var eName: String
        var pName: String
    }

    private struct PerfLevel {
        var cores: Int
        var name: String
        var letter: String
    }

    /// perflevel0 is the fastest cluster. Later levels are slower. A third level's cores stay in the lower bucket so the total is not short a cluster.
    private static func cpuTopology() -> Topology {
        let count = Int(Sysctl.u32("hw.nperflevels") ?? 0)
        let levels: [PerfLevel] = (0..<count).map { index in
            let cores = Int(Sysctl.u32("hw.perflevel\(index).physicalcpu") ?? 0)
            let name = Sysctl.string("hw.perflevel\(index).name")?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = (name?.isEmpty == false) ? name! : (index == 0 ? "Performance" : "Efficiency")
            return PerfLevel(cores: cores, name: resolved, letter: MetricMath.clusterLetter(forPerfLevelName: resolved))
        }
        if levels.count >= 2, let high = levels.first, let low = levels.last {
            let slower = levels.dropFirst()
            let lowName = slower.count == 1 ? low.name : slower.map(\.name).joined(separator: " + ")
            return Topology(
                eCores: slower.reduce(0) { $0 + $1.cores },
                pCores: high.cores,
                eLabel: low.letter,
                pLabel: high.letter,
                eName: lowName,
                pName: high.name
            )
        }
        let total = Int(Sysctl.u32("hw.physicalcpu") ?? Sysctl.u32("hw.ncpu") ?? 0)
        return Topology(eCores: 0, pCores: total, eLabel: "E", pLabel: "P", eName: "Efficiency", pName: "Performance")
    }

    private static func gpuCoreCount() -> Int {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AGXAccelerator") else { return 0 }
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var cores = 0
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as NSDictionary?
            else { continue }
            if let value = dict["gpu-core-count"] as? Int {
                cores = value
            } else if let number = dict["gpu-core-count"] as? NSNumber {
                cores = number.intValue
            }
        }
        return cores
    }

    private struct DVFSTables {
        var eCPU: [UInt32] = []
        var pCPU: [UInt32] = []
        var gpu: [UInt32] = []
    }

    private static func dvfsTables() -> DVFSTables {
        var tables = DVFSTables()
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleARMIODevice") else { return tables }
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return tables }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var nameBuf = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuf) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuf)
            guard name == "pmgr" else { continue }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as NSDictionary?
            else { continue }

            let found = classifyDVFS(dict)
            if !found.eCPU.isEmpty { tables.eCPU = found.eCPU }
            if !found.pCPU.isEmpty { tables.pCPU = found.pCPU }
            if !found.gpu.isEmpty { tables.gpu = found.gpu }
        }
        return tables
    }

    private static func classifyDVFS(_ dict: NSDictionary) -> DVFSTables {
        var ladders: [MetricMath.FrequencyLadder] = []
        for case let key as String in dict.allKeys where key.hasPrefix("voltage-states") {
            let parsed = dvfsLadder(from: dict[key])
            guard !parsed.megahertz.isEmpty else { continue }
            ladders.append(MetricMath.FrequencyLadder(
                key: key,
                megahertz: parsed.megahertz,
                kilohertzEncoded: parsed.kilohertzEncoded
            ))
        }
        let classified = MetricMath.classifyFrequencyLadders(ladders)
        return DVFSTables(eCPU: classified.efficiency, pCPU: classified.performance, gpu: classified.gpu)
    }

    private static func dvfsLadder(from value: Any?) -> (megahertz: [UInt32], kilohertzEncoded: Bool) {
        guard let data = value as? Data, data.count >= 8 else { return ([], false) }
        var freqs: [UInt32] = []
        var kilohertzEncoded = false
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var offset = 0
            while offset + 8 <= bytes.count {
                let rawFreq = UInt32(bytes[offset])
                    | UInt32(bytes[offset + 1]) << 8
                    | UInt32(bytes[offset + 2]) << 16
                    | UInt32(bytes[offset + 3]) << 24
                if (100_000..<100_000_000).contains(rawFreq) {
                    kilohertzEncoded = true
                }
                if let mhz = MetricMath.dvfsMegahertz(raw: rawFreq) {
                    freqs.append(mhz)
                }
                offset += 8
            }
        }
        return (freqs, kilohertzEncoded)
    }
}
