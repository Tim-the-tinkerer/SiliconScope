import Darwin
import Foundation

public enum ProcessDetails {
    /// One process, read on demand. Returns nil when the pid has already exited.
    public static func load(pid: Int32, cpuPercent: Double? = nil) -> ProcessDetail? {
        guard pid > 0 else { return nil }
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, pointer, size)
        }
        guard got == size else { return nil }

        let bsd = info.pbsd
        let task = info.ptinfo
        let parent = Int32(bsd.pbi_ppid)
        return ProcessDetail(
            pid: pid,
            name: processName(pid) ?? decodeCString(bsd.pbi_comm),
            path: executablePath(pid),
            parentPID: parent,
            parentName: parent > 0 ? (processName(parent) ?? "") : "",
            userName: userName(uid: bsd.pbi_uid),
            userID: UInt32(bsd.pbi_uid),
            started: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000),
            status: statusTitle(bsd.pbi_status),
            nice: bsd.pbi_nice,
            is64Bit: (bsd.pbi_flags & UInt32(PROC_FLAG_LP64)) != 0,
            cpuPercent: cpuPercent,
            userTime: TimeInterval(task.pti_total_user) / 1_000_000_000,
            systemTime: TimeInterval(task.pti_total_system) / 1_000_000_000,
            threadCount: Int(task.pti_threadnum),
            runningThreads: Int(task.pti_numrunning),
            priority: task.pti_priority,
            residentBytes: task.pti_resident_size,
            virtualBytes: task.pti_virtual_size,
            openFiles: Int(bsd.pbi_nfiles),
            faults: Int(task.pti_faults),
            pageins: Int(task.pti_pageins),
            copyOnWriteFaults: Int(task.pti_cow_faults),
            contextSwitches: Int(task.pti_csw),
            unixCalls: Int(task.pti_syscalls_unix),
            machCalls: Int(task.pti_syscalls_mach)
        )
    }

    private static func executablePath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func processName(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, size)
        }
        guard got == size else { return nil }
        let registered = decodeCString(info.pbi_name)
        if registered != "—" { return registered }
        let command = decodeCString(info.pbi_comm)
        return command == "—" ? nil : command
    }

    private static func userName(uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let raw = entry.pointee.pw_name else { return "uid \(uid)" }
        let name = String(cString: raw)
        return name.isEmpty ? "uid \(uid)" : name
    }

    private static func statusTitle(_ status: UInt32) -> String {
        switch status {
        case 1: return "Idle"
        case 2: return "Running"
        case 3: return "Sleeping"
        case 4: return "Stopped"
        case 5: return "Zombie"
        default: return "Unknown"
        }
    }

    private static func decodeCString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
            let text = String(decoding: bytes[..<end], as: UTF8.self)
            return text.isEmpty ? "—" : text
        }
    }
}
