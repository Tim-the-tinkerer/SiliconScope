import Darwin
import Foundation

final class CPUUsageSampler {
    private var previous: [host_cpu_load_info] = []

    func sample(hardware: HardwareProfile) -> [CoreSample] {
        var processorCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &infoArray,
            &infoCount
        )
        guard kr == KERN_SUCCESS, let infoArray, processorCount > 0 else { return [] }
        defer {
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), size)
        }

        let stride = MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        var current: [host_cpu_load_info] = []
        current.reserveCapacity(Int(processorCount))
        for index in 0..<Int(processorCount) {
            let base = infoArray.advanced(by: index * stride)
            current.append(base.withMemoryRebound(to: host_cpu_load_info.self, capacity: 1) { $0.pointee })
        }

        var cores: [CoreSample] = []
        let previous = self.previous
        self.previous = current
        guard previous.count == current.count else { return [] }

        let eCount = hardware.eCoreCount
        for (index, now) in current.enumerated() {
            let last = previous[index]
            let user = Double(now.cpu_ticks.0 &- last.cpu_ticks.0)
            let system = Double(now.cpu_ticks.1 &- last.cpu_ticks.1)
            let idle = Double(now.cpu_ticks.2 &- last.cpu_ticks.2)
            let nice = Double(now.cpu_ticks.3 &- last.cpu_ticks.3)
            let total = user + system + idle + nice
            let active = MetricMath.ratio(user + system + nice, total)
            let kind: CoreKind = index < eCount ? .efficiency : .performance
            let coreID = kind == .efficiency ? index : index - eCount
            cores.append(
                CoreSample(
                    kind: kind,
                    dieID: 0,
                    coreID: coreID,
                    frequencyMHz: 0,
                    activeRatio: active,
                    scaledRatio: active
                )
            )
        }
        return cores
    }
}
