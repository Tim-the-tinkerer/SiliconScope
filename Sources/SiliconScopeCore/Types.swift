import Foundation

public enum CoreKind: String, Sendable, Equatable {
    case efficiency
    case performance
}

public enum MemoryPressure: String, Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case urgent
    case critical
    case unknown

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Warning"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }

    /// Vertical position on the pressure history chart. Unknown sits at the bottom.
    public var chartLevel: Double {
        switch self {
        case .unknown: return 0
        case .normal: return 1
        case .warning: return 2
        case .urgent: return 3
        case .critical: return 4
        }
    }
}

public struct HardwareProfile: Equatable, Sendable {
    public var chipName: String
    public var modelIdentifier: String
    public var memoryBytes: UInt64
    public var eCoreCount: Int
    public var pCoreCount: Int
    public var eCoreLabel: String
    public var pCoreLabel: String
    /// `hw.perflevel` name for the lower cluster, such as Efficiency or Performance.
    public var eClusterName: String
    /// `hw.perflevel` name for the fastest cluster, such as Performance or Super.
    public var pClusterName: String
    public var gpuCoreCount: Int
    public var eCoreFrequenciesMHz: [UInt32]
    public var pCoreFrequenciesMHz: [UInt32]
    public var gpuFrequenciesMHz: [UInt32]
    public var anePeakWatts: Double
    public var isAppleSilicon: Bool

    public var cpuCoreCount: Int { eCoreCount + pCoreCount }

    public init(
        chipName: String,
        modelIdentifier: String,
        memoryBytes: UInt64,
        eCoreCount: Int,
        pCoreCount: Int,
        eCoreLabel: String,
        pCoreLabel: String,
        eClusterName: String = "Efficiency",
        pClusterName: String = "Performance",
        gpuCoreCount: Int,
        eCoreFrequenciesMHz: [UInt32],
        pCoreFrequenciesMHz: [UInt32],
        gpuFrequenciesMHz: [UInt32],
        anePeakWatts: Double,
        isAppleSilicon: Bool
    ) {
        self.chipName = chipName
        self.modelIdentifier = modelIdentifier
        self.memoryBytes = memoryBytes
        self.eCoreCount = eCoreCount
        self.pCoreCount = pCoreCount
        self.eCoreLabel = eCoreLabel
        self.pCoreLabel = pCoreLabel
        self.eClusterName = eClusterName
        self.pClusterName = pClusterName
        self.gpuCoreCount = gpuCoreCount
        self.eCoreFrequenciesMHz = eCoreFrequenciesMHz
        self.pCoreFrequenciesMHz = pCoreFrequenciesMHz
        self.gpuFrequenciesMHz = gpuFrequenciesMHz
        self.anePeakWatts = anePeakWatts
        self.isAppleSilicon = isAppleSilicon
    }

    public static let unknown = HardwareProfile(
        chipName: "Unknown",
        modelIdentifier: "Unknown",
        memoryBytes: 0,
        eCoreCount: 0,
        pCoreCount: 0,
        eCoreLabel: "E",
        pCoreLabel: "P",
        eClusterName: "Efficiency",
        pClusterName: "Performance",
        gpuCoreCount: 0,
        eCoreFrequenciesMHz: [],
        pCoreFrequenciesMHz: [],
        gpuFrequenciesMHz: [],
        anePeakWatts: 8,
        isAppleSilicon: false
    )
}

public struct CoreSample: Equatable, Sendable, Identifiable {
    public var kind: CoreKind
    public var dieID: Int
    public var coreID: Int
    public var frequencyMHz: UInt32
    public var activeRatio: Double
    public var scaledRatio: Double

    public var id: String { "\(kind.rawValue)-\(dieID)-\(coreID)" }

    public var shortLabel: String {
        let prefix = kind == .efficiency ? "E" : "P"
        return "\(prefix)\(coreID)"
    }

    public init(
        kind: CoreKind,
        dieID: Int,
        coreID: Int,
        frequencyMHz: UInt32,
        activeRatio: Double,
        scaledRatio: Double
    ) {
        self.kind = kind
        self.dieID = dieID
        self.coreID = coreID
        self.frequencyMHz = frequencyMHz
        self.activeRatio = activeRatio
        self.scaledRatio = scaledRatio
    }
}

public struct MemorySample: Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedFilesBytes: UInt64
    public var freeBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var compressorBytes: UInt64
    public var pressure: MemoryPressure

    public var usedRatio: Double {
        MetricMath.ratio(Double(usedBytes), Double(totalBytes))
    }

    public var swapRatio: Double {
        MetricMath.ratio(Double(swapUsedBytes), Double(swapTotalBytes))
    }

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        appBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        cachedFilesBytes: UInt64,
        freeBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        compressorBytes: UInt64,
        pressure: MemoryPressure
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.compressorBytes = compressorBytes
        self.pressure = pressure
    }

    public static let empty = MemorySample(
        totalBytes: 0,
        usedBytes: 0,
        appBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedFilesBytes: 0,
        freeBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        compressorBytes: 0,
        pressure: .unknown
    )
}

public enum ProcessRanking: Equatable, Sendable {
    case cpu
    case name
    case pid
    case memory
    case threads

    /// CPU keeps the busiest `limit` processes. Every other column keeps the full list so the table is not rebuilt from CPU rank on the next sample.
    public func select(_ rows: [ProcessSample], limit: Int) -> [ProcessSample] {
        switch self {
        case .cpu:
            let ranked = rows.sorted { lhs, rhs in
                if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.pid < rhs.pid
            }
            return Array(ranked.prefix(max(1, limit)))
        case .name, .pid, .memory, .threads:
            return rows
        }
    }
}

public enum TemperatureGroup: String, Sendable, Equatable, CaseIterable {
    case cpu
    case gpu
    case other

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .other: return "Other"
        }
    }

    public static func group(forSensorName name: String) -> TemperatureGroup {
        if name.contains("pACC") || name.contains("eACC") || name.hasPrefix("CPU") {
            return .cpu
        }
        if name.contains("GPU") || name.contains("AGX") {
            return .gpu
        }
        return .other
    }
}

public enum NetworkKind: String, Sendable, Equatable {
    case wifi
    case ethernet
    case vpn
    case bridge
    case other

    public var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn: return "VPN"
        case .bridge: return "Bridge"
        case .other: return "Other"
        }
    }

    /// Wi-Fi and Ethernet are the transport. A VPN is listed on its own and is not part of this flag: the same bytes usually also appear on the physical link.
    public var countsTowardTotal: Bool {
        switch self {
        case .wifi, .ethernet: return true
        case .vpn, .bridge, .other: return false
        }
    }
}

public extension Array where Element == NetworkInterfaceSample {
    /// Download and upload for the global total. Running Wi-Fi and Ethernet always count. A VPN counts only when none of those links are up, so a tunnel is not added on top of the packets already counted on the physical interface.
    func networkTotals() -> (downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        let physicalUp = contains { $0.isUp && ($0.kind == .wifi || $0.kind == .ethernet) }
        let counted = filter { interface in
            guard interface.isUp else { return false }
            switch interface.kind {
            case .wifi, .ethernet: return true
            case .vpn: return !physicalUp
            case .bridge, .other: return false
            }
        }
        return (
            counted.reduce(0) { $0 + $1.downloadBytesPerSecond },
            counted.reduce(0) { $0 + $1.uploadBytesPerSecond }
        )
    }
}

public struct NetworkInterfaceSample: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var displayName: String
    public var kind: NetworkKind
    public var isUp: Bool
    public var addresses: [String]
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public init(
        id: String,
        name: String,
        displayName: String,
        kind: NetworkKind,
        isUp: Bool,
        addresses: [String],
        downloadBytesPerSecond: Double,
        uploadBytesPerSecond: Double
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.isUp = isUp
        self.addresses = addresses
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}

public struct NetworkSample: Equatable, Sendable {
    public var interfaces: [NetworkInterfaceSample]
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public static let empty = NetworkSample(interfaces: [], downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

public enum DiskKind: String, Sendable, Equatable {
    case internalDrive
    case external
    case network
    case image

    public var title: String {
        switch self {
        case .internalDrive: return "Internal"
        case .external: return "External"
        case .network: return "Network"
        case .image: return "Disk Image"
        }
    }

    /// Capacity cards sum disks plugged into this Mac. Network shares and disk images stay in the list.
    public var countsTowardCapacity: Bool {
        switch self {
        case .internalDrive, .external: return true
        case .network, .image: return false
        }
    }
}

public enum DiskVisibility: Sendable, Equatable {
    case hidden
    case localVolume
    case network
}

public struct DiskVolumeSample: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var mountPoint: String
    public var fileSystem: String
    public var usedBytes: UInt64
    public var readOnly: Bool
    public var encrypted: Bool

    public init(
        id: String,
        name: String,
        mountPoint: String,
        fileSystem: String,
        usedBytes: UInt64,
        readOnly: Bool,
        encrypted: Bool
    ) {
        self.id = id
        self.name = name
        self.mountPoint = mountPoint
        self.fileSystem = fileSystem
        self.usedBytes = usedBytes
        self.readOnly = readOnly
        self.encrypted = encrypted
    }
}

public struct DiskDriveSample: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bsdName: String
    public var kind: DiskKind
    public var protocolName: String
    public var solidState: Bool?
    public var sizeBytes: UInt64
    public var availableBytes: UInt64
    public var volumes: [DiskVolumeSample]

    public var usedBytes: UInt64 {
        guard sizeBytes > availableBytes else { return 0 }
        return sizeBytes - availableBytes
    }

    /// Fullness of a drive that has a mounted volume. An empty drive stays at zero so it does not look full.
    public var usedRatio: Double {
        guard sizeBytes > 0, !volumes.isEmpty else { return 0 }
        return min(1, Double(usedBytes) / Double(sizeBytes))
    }

    public init(
        id: String,
        name: String,
        bsdName: String,
        kind: DiskKind,
        protocolName: String,
        solidState: Bool?,
        sizeBytes: UInt64,
        availableBytes: UInt64,
        volumes: [DiskVolumeSample]
    ) {
        self.id = id
        self.name = name
        self.bsdName = bsdName
        self.kind = kind
        self.protocolName = protocolName
        self.solidState = solidState
        self.sizeBytes = sizeBytes
        self.availableBytes = availableBytes
        self.volumes = volumes
    }
}

public struct DiskSample: Equatable, Sendable {
    public var drives: [DiskDriveSample]

    public static let empty = DiskSample(drives: [])
}

public struct TemperatureSensor: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var celsius: Double
    public var group: TemperatureGroup

    public var title: String { TemperatureName.title(for: name) }

    public init(id: String, name: String, celsius: Double, group: TemperatureGroup) {
        self.id = id
        self.name = name
        self.celsius = celsius
        self.group = group
    }
}

public struct ProcessDetail: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var path: String
    public var parentPID: Int32
    public var parentName: String
    public var userName: String
    public var userID: UInt32
    public var started: Date
    public var status: String
    public var nice: Int32
    public var is64Bit: Bool
    public var cpuPercent: Double?
    public var userTime: TimeInterval
    public var systemTime: TimeInterval
    public var threadCount: Int
    public var runningThreads: Int
    public var priority: Int32
    public var residentBytes: UInt64
    public var virtualBytes: UInt64
    public var openFiles: Int
    public var faults: Int
    public var pageins: Int
    public var copyOnWriteFaults: Int
    public var contextSwitches: Int
    public var unixCalls: Int
    public var machCalls: Int

    public init(
        pid: Int32,
        name: String,
        path: String,
        parentPID: Int32,
        parentName: String,
        userName: String,
        userID: UInt32,
        started: Date,
        status: String,
        nice: Int32,
        is64Bit: Bool,
        cpuPercent: Double?,
        userTime: TimeInterval,
        systemTime: TimeInterval,
        threadCount: Int,
        runningThreads: Int,
        priority: Int32,
        residentBytes: UInt64,
        virtualBytes: UInt64,
        openFiles: Int,
        faults: Int,
        pageins: Int,
        copyOnWriteFaults: Int,
        contextSwitches: Int,
        unixCalls: Int,
        machCalls: Int
    ) {
        self.pid = pid
        self.name = name
        self.path = path
        self.parentPID = parentPID
        self.parentName = parentName
        self.userName = userName
        self.userID = userID
        self.started = started
        self.status = status
        self.nice = nice
        self.is64Bit = is64Bit
        self.cpuPercent = cpuPercent
        self.userTime = userTime
        self.systemTime = systemTime
        self.threadCount = threadCount
        self.runningThreads = runningThreads
        self.priority = priority
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
        self.openFiles = openFiles
        self.faults = faults
        self.pageins = pageins
        self.copyOnWriteFaults = copyOnWriteFaults
        self.contextSwitches = contextSwitches
        self.unixCalls = unixCalls
        self.machCalls = machCalls
    }
}

public struct ProcessSample: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var threadCount: Int

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64, threadCount: Int) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.threadCount = threadCount
    }
}

public enum MetricQuality: String, Sendable, Equatable, CaseIterable {
    case measured
    case estimated
    case partial
    case unavailable

    public var title: String {
        switch self {
        case .measured: return "Measured"
        case .estimated: return "Estimated"
        case .partial: return "Partial"
        case .unavailable: return "Unavailable"
        }
    }

    public var isAvailable: Bool { self != .unavailable }

    /// Chip / package watts are CPU + GPU + ANE. Measured only when every rail in that sum exists.
    public static func packagePower(cpuEnergy: Bool, gpuEnergy: Bool, aneEnergy: Bool) -> MetricQuality {
        let rails = [cpuEnergy, gpuEnergy, aneEnergy].filter(\.self).count
        switch rails {
        case 3: return .measured
        case 0: return .unavailable
        default: return .partial
        }
    }
}

public enum TelemetryMode: String, Sendable, Equatable, CaseIterable {
    case fullIOReport
    case partialIOReport
    case cpuFallback

    public var title: String {
        switch self {
        case .fullIOReport: return "Full IOReport"
        case .partialIOReport: return "Partial IOReport"
        case .cpuFallback: return "CPU fallback"
        }
    }

    public var detail: String {
        switch self {
        case .fullIOReport:
            return "Cluster residency, GPU states, and energy-model watts from IOReport — no sudo."
        case .partialIOReport:
            return "IOReport is up, but some channels are missing on this chip or macOS version."
        case .cpuFallback:
            return "host_processor_info only. GPU, ANE, and energy are unavailable."
        }
    }

    public static func classify(
        isAppleSilicon: Bool,
        hasIOReport: Bool,
        cpuResidency: Bool,
        gpuResidency: Bool,
        cpuEnergy: Bool,
        gpuEnergy: Bool,
        aneEnergy: Bool
    ) -> TelemetryMode {
        guard hasIOReport else { return .cpuFallback }
        if isAppleSilicon {
            if cpuResidency && gpuResidency && cpuEnergy && gpuEnergy && aneEnergy {
                return .fullIOReport
            }
            return .partialIOReport
        }
        return cpuResidency ? .fullIOReport : .partialIOReport
    }
}

public struct MetricConfidence: Equatable, Sendable {
    public var mode: TelemetryMode
    public var cpu: MetricQuality
    public var gpu: MetricQuality
    public var cpuPower: MetricQuality
    public var gpuPower: MetricQuality
    public var aneWatts: MetricQuality
    public var aneActivity: MetricQuality
    /// CPU + GPU + ANE watts. Partial if some rails are missing and treated as zero.
    public var power: MetricQuality
    public var memory: MetricQuality
    public var temperature: MetricQuality
    public var processes: MetricQuality
    public var dram: MetricQuality
    public var gpuSRAM: MetricQuality

    public init(
        mode: TelemetryMode,
        cpu: MetricQuality,
        gpu: MetricQuality,
        cpuPower: MetricQuality,
        gpuPower: MetricQuality,
        aneWatts: MetricQuality,
        aneActivity: MetricQuality,
        power: MetricQuality,
        memory: MetricQuality,
        temperature: MetricQuality,
        processes: MetricQuality,
        dram: MetricQuality = .unavailable,
        gpuSRAM: MetricQuality = .unavailable
    ) {
        self.mode = mode
        self.cpu = cpu
        self.gpu = gpu
        self.cpuPower = cpuPower
        self.gpuPower = gpuPower
        self.aneWatts = aneWatts
        self.aneActivity = aneActivity
        self.power = power
        self.memory = memory
        self.temperature = temperature
        self.processes = processes
        self.dram = dram
        self.gpuSRAM = gpuSRAM
    }

    public static let unknown = MetricConfidence(
        mode: .cpuFallback,
        cpu: .unavailable,
        gpu: .unavailable,
        cpuPower: .unavailable,
        gpuPower: .unavailable,
        aneWatts: .unavailable,
        aneActivity: .unavailable,
        power: .unavailable,
        memory: .unavailable,
        temperature: .unavailable,
        processes: .unavailable,
        dram: .unavailable,
        gpuSRAM: .unavailable
    )

    public static func resolve(
        isAppleSilicon: Bool,
        hasIOReport: Bool,
        cpuResidency: Bool,
        gpuResidency: Bool,
        cpuEnergy: Bool,
        gpuEnergy: Bool,
        aneEnergy: Bool,
        hasTemperature: Bool,
        didSampleProcesses: Bool,
        memoryOK: Bool,
        dramEnergy: Bool = false,
        gpuSRAMEnergy: Bool = false
    ) -> MetricConfidence {
        let mode = TelemetryMode.classify(
            isAppleSilicon: isAppleSilicon,
            hasIOReport: hasIOReport,
            cpuResidency: cpuResidency,
            gpuResidency: gpuResidency,
            cpuEnergy: cpuEnergy,
            gpuEnergy: gpuEnergy,
            aneEnergy: aneEnergy
        )
        let cpu: MetricQuality = cpuResidency ? .measured : .unavailable
        let aneWatts: MetricQuality = aneEnergy ? .measured : .unavailable
        return MetricConfidence(
            mode: mode,
            cpu: cpu,
            gpu: gpuResidency ? .measured : .unavailable,
            cpuPower: cpuEnergy ? .measured : .unavailable,
            gpuPower: gpuEnergy ? .measured : .unavailable,
            aneWatts: aneWatts,
            aneActivity: aneEnergy ? .estimated : .unavailable,
            power: .packagePower(cpuEnergy: cpuEnergy, gpuEnergy: gpuEnergy, aneEnergy: aneEnergy),
            memory: memoryOK ? .measured : .unavailable,
            temperature: hasTemperature ? .measured : .unavailable,
            processes: didSampleProcesses ? .measured : .unavailable,
            dram: dramEnergy ? .measured : .unavailable,
            gpuSRAM: gpuSRAMEnergy ? .measured : .unavailable
        )
    }
}

public struct Snapshot: Equatable, Sendable {
    public var timestamp: Date
    public var cpuActiveRatio: Double
    public var cpuScaledRatio: Double
    public var eClusterActiveRatio: Double
    public var eClusterScaledRatio: Double
    public var eClusterFrequencyMHz: UInt32
    public var pClusterActiveRatio: Double
    public var pClusterScaledRatio: Double
    public var pClusterFrequencyMHz: UInt32
    public var cores: [CoreSample]
    public var gpuActiveRatio: Double
    public var gpuScaledRatio: Double
    public var gpuFrequencyMHz: UInt32
    public var cpuPowerWatts: Double
    public var gpuPowerWatts: Double
    public var anePowerWatts: Double
    public var ramPowerWatts: Double
    public var gpuSRAMPowerWatts: Double
    public var systemPowerWatts: Double
    public var memory: MemorySample
    public var cpuTempC: Double?
    public var gpuTempC: Double?
    public var sensors: [TemperatureSensor]
    public var networkDownloadBytesPerSecond: Double
    public var networkUploadBytesPerSecond: Double
    public var networkInterfaces: [NetworkInterfaceSample]
    public var drives: [DiskDriveSample]
    public var loadAverage1: Double
    public var loadAverage5: Double
    public var loadAverage15: Double
    public var uptime: TimeInterval
    public var processes: [ProcessSample]
    public var confidence: MetricConfidence

    public var hasIOReport: Bool { confidence.mode != .cpuFallback }

    public var packagePowerWatts: Double {
        cpuPowerWatts + gpuPowerWatts + anePowerWatts
    }

    public var efficiencyCores: [CoreSample] {
        cores.filter { $0.kind == .efficiency }
    }

    public var performanceCores: [CoreSample] {
        cores.filter { $0.kind == .performance }
    }

    public init(
        timestamp: Date = Date(),
        cpuActiveRatio: Double = 0,
        cpuScaledRatio: Double = 0,
        eClusterActiveRatio: Double = 0,
        eClusterScaledRatio: Double = 0,
        eClusterFrequencyMHz: UInt32 = 0,
        pClusterActiveRatio: Double = 0,
        pClusterScaledRatio: Double = 0,
        pClusterFrequencyMHz: UInt32 = 0,
        cores: [CoreSample] = [],
        gpuActiveRatio: Double = 0,
        gpuScaledRatio: Double = 0,
        gpuFrequencyMHz: UInt32 = 0,
        cpuPowerWatts: Double = 0,
        gpuPowerWatts: Double = 0,
        anePowerWatts: Double = 0,
        ramPowerWatts: Double = 0,
        gpuSRAMPowerWatts: Double = 0,
        systemPowerWatts: Double = 0,
        memory: MemorySample = .empty,
        cpuTempC: Double? = nil,
        gpuTempC: Double? = nil,
        sensors: [TemperatureSensor] = [],
        networkDownloadBytesPerSecond: Double = 0,
        networkUploadBytesPerSecond: Double = 0,
        networkInterfaces: [NetworkInterfaceSample] = [],
        drives: [DiskDriveSample] = [],
        loadAverage1: Double = 0,
        loadAverage5: Double = 0,
        loadAverage15: Double = 0,
        uptime: TimeInterval = 0,
        processes: [ProcessSample] = [],
        confidence: MetricConfidence = .unknown
    ) {
        self.timestamp = timestamp
        self.cpuActiveRatio = cpuActiveRatio
        self.cpuScaledRatio = cpuScaledRatio
        self.eClusterActiveRatio = eClusterActiveRatio
        self.eClusterScaledRatio = eClusterScaledRatio
        self.eClusterFrequencyMHz = eClusterFrequencyMHz
        self.pClusterActiveRatio = pClusterActiveRatio
        self.pClusterScaledRatio = pClusterScaledRatio
        self.pClusterFrequencyMHz = pClusterFrequencyMHz
        self.cores = cores
        self.gpuActiveRatio = gpuActiveRatio
        self.gpuScaledRatio = gpuScaledRatio
        self.gpuFrequencyMHz = gpuFrequencyMHz
        self.cpuPowerWatts = cpuPowerWatts
        self.gpuPowerWatts = gpuPowerWatts
        self.anePowerWatts = anePowerWatts
        self.ramPowerWatts = ramPowerWatts
        self.gpuSRAMPowerWatts = gpuSRAMPowerWatts
        self.systemPowerWatts = systemPowerWatts
        self.memory = memory
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
        self.sensors = sensors
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.networkInterfaces = networkInterfaces
        self.drives = drives
        self.loadAverage1 = loadAverage1
        self.loadAverage5 = loadAverage5
        self.loadAverage15 = loadAverage15
        self.uptime = uptime
        self.processes = processes
        self.confidence = confidence
    }
}

public struct HistoryBuffer: Equatable, Sendable {
    public var snapshots: [Snapshot]
    /// Visible history duration. Changing the sample interval does not change this window.
    public var window: TimeInterval
    /// Hard cap so a very small interval cannot grow without bound.
    public var sampleCap: Int

    public init(window: TimeInterval = 180, sampleCap: Int = 800) {
        self.snapshots = []
        self.window = max(10, window)
        self.sampleCap = max(32, sampleCap)
    }

    public mutating func append(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
        trim(now: snapshot.timestamp)
    }

    public mutating func trim(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        if let firstKeep = snapshots.firstIndex(where: { $0.timestamp >= cutoff }) {
            if firstKeep > 0 {
                snapshots.removeFirst(firstKeep)
            }
        } else {
            snapshots.removeAll()
        }
        if snapshots.count > sampleCap {
            snapshots.removeFirst(snapshots.count - sampleCap)
        }
    }
}
