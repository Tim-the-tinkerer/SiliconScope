import Darwin
import Foundation

enum MemorySampler {
    static func sample(totalBytes: UInt64) -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            let swapInfo = swap()
            return MemorySample(
                totalBytes: totalBytes,
                usedBytes: 0,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedFilesBytes: 0,
                freeBytes: 0,
                swapUsedBytes: swapInfo.used,
                swapTotalBytes: swapInfo.total,
                compressorBytes: 0,
                pressure: pressure()
            )
        }

        let page = UInt64(sysconf(_SC_PAGESIZE))
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let wired = UInt64(stats.wire_count)
        let compressor = UInt64(stats.compressor_page_count)
        let free = UInt64(stats.free_count)
        let external = UInt64(stats.external_page_count)

        let breakdown = MetricMath.memoryUsedBytes(
            pageSize: page,
            internalPages: internalPages,
            purgeablePages: purgeable,
            wiredPages: wired,
            compressorPages: compressor
        )
        let swapInfo = swap()
        let cached = MetricMath.cachedFileBytes(pageSize: page, externalPages: external, purgeablePages: purgeable)
        // speculative_count is already included in free_count. Adding it again inflates Free.
        let freeBytes = free * page

        return MemorySample(
            totalBytes: totalBytes,
            usedBytes: min(breakdown.used, totalBytes),
            appBytes: breakdown.app,
            wiredBytes: wired * page,
            compressedBytes: compressor * page,
            cachedFilesBytes: cached,
            freeBytes: freeBytes,
            swapUsedBytes: swapInfo.used,
            swapTotalBytes: swapInfo.total,
            compressorBytes: compressor * page,
            pressure: pressure()
        )
    }

    private static func swap() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    private static func pressure() -> MemoryPressure {
        if let level = Sysctl.i32("kern.memorystatus_vm_pressure_level") {
            return MetricMath.pressure(fromLevel: level)
        }
        return .unknown
    }
}
