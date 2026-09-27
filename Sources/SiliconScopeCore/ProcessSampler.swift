import Darwin
import Foundation
#if canImport(Darwin.libproc)
import Darwin.libproc
#endif

final class ProcessSampler {
    private struct Tick {
        var user: UInt64
        var system: UInt64
        var startSec: UInt64
        var startUsec: UInt64
    }

    /// Deltas older than this are treated as a new baseline, not a CPU% sample.
    private static let staleInterval: TimeInterval = 5

    private var previous: [Int32: Tick] = [:]
    private var previousTime = Date.distantPast

    func invalidateBaseline() {
        previous.removeAll()
        previousTime = .distantPast
    }

    func sample(limit: Int = 20, ranking: ProcessRanking = .cpu) -> [ProcessSample] {
        let now = Date()
        let rawElapsed = now.timeIntervalSince(previousTime)
        let haveBaseline = !previous.isEmpty && rawElapsed > 0 && rawElapsed < Self.staleInterval
        let elapsed = max(rawElapsed, 0.001)
        previousTime = now

        var bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        if bytesNeeded <= 0 { return [] }
        var pids = [Int32](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<Int32>.size)
        bytesNeeded = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Int32>.size))
        }
        if bytesNeeded <= 0 { return [] }
        let count = min(pids.count, Int(bytesNeeded) / MemoryLayout<Int32>.size)
        if count <= 0 { return [] }

        var nextTicks: [Int32: Tick] = [:]
        var rows: [ProcessSample] = []
        rows.reserveCapacity(min(limit * 3, count))

        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskallinfo()
            let size = MemoryLayout<proc_taskallinfo>.size
            let got = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, Int32(size))
            }
            guard got == size else { continue }

            let tick = Tick(
                user: info.ptinfo.pti_total_user,
                system: info.ptinfo.pti_total_system,
                startSec: info.pbsd.pbi_start_tvsec,
                startUsec: info.pbsd.pbi_start_tvusec
            )
            nextTicks[pid] = tick

            var cpu = 0.0
            if haveBaseline, let last = previous[pid], last.startSec == tick.startSec, last.startUsec == tick.startUsec {
                // Same process as last sample. A counter that moves backwards is ignored rather than wrapped.
                let userDelta = tick.user >= last.user ? tick.user - last.user : 0
                let systemDelta = tick.system >= last.system ? tick.system - last.system : 0
                let delta = Double(userDelta) + Double(systemDelta)
                // These proc counters are already nanoseconds. Do not scale them by the Mach timebase.
                cpu = (delta / 1_000_000_000) / elapsed * 100
            }

            var nameBuf = [CChar](repeating: 0, count: 256)
            let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"
            guard !name.isEmpty else { continue }

            rows.append(
                ProcessSample(
                    pid: pid,
                    name: name,
                    cpuPercent: max(0, cpu),
                    memoryBytes: UInt64(info.ptinfo.pti_resident_size),
                    threadCount: Int(info.ptinfo.pti_threadnum)
                )
            )
        }

        previous = nextTicks
        return ranking.select(rows, limit: limit)
    }
}
