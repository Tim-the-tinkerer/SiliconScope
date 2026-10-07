import Foundation

public struct SampleRequest: Equatable, Sendable {
    public var interval: TimeInterval
    public var processLimit: Int
    /// Process enumeration is expensive; the app only asks for it on the Processes page.
    public var includeProcesses: Bool
    /// Which column chooses the rows. Name and memory keep the whole list.
    public var processRanking: ProcessRanking
    /// Thermal discovery is throttled internally; force a read for one-shot CLI samples.
    public var forceTemperature: Bool

    public init(
        interval: TimeInterval = 1,
        processLimit: Int = 18,
        includeProcesses: Bool = true,
        processRanking: ProcessRanking = .cpu,
        forceTemperature: Bool = false
    ) {
        self.interval = max(0.25, interval)
        self.processLimit = max(5, processLimit)
        self.includeProcesses = includeProcesses
        self.processRanking = processRanking
        self.forceTemperature = forceTemperature
    }
}

public final class SystemSampler {
    public let hardware: HardwareProfile
    private let ioReport: IOReportSampler?
    private let processes = ProcessSampler()
    private let network = NetworkSampler()
    private let disks = DiskMonitor()
    private let cpuFallback = CPUUsageSampler()

    public init(hardware: HardwareProfile = HardwareInfo.load()) {
        self.hardware = hardware
        self.ioReport = IOReportSampler(hardware: hardware)
    }

    public var usesIOReport: Bool { ioReport != nil }

    public func sample(_ request: SampleRequest = SampleRequest()) -> Snapshot {
        // This runs on a thread that loops until quit. Without a pool, autoreleased
        // IOReport and Foundation objects from every sample stay alive for the whole run.
        autoreleasepool { sampleBody(request) }
    }

    private func sampleBody(_ request: SampleRequest) -> Snapshot {
        let loads = Sysctl.loadAverage()
        let processRows = request.includeProcesses
            ? processes.sample(limit: request.processLimit, ranking: request.processRanking)
            : []
        if !request.includeProcesses {
            processes.invalidateBaseline()
        }
        var snapshot = Snapshot(
            timestamp: Date(),
            memory: MemorySampler.sample(totalBytes: hardware.memoryBytes),
            loadAverage1: loads.0,
            loadAverage5: loads.1,
            loadAverage15: loads.2,
            uptime: Sysctl.uptime(),
            processes: processRows
        )

        var cpuResidency = false
        var gpuResidency = false
        var cpuEnergy = false
        var gpuEnergy = false
        var aneEnergy = false
        var dramEnergy = false
        var gpuSRAMEnergy = false
        let usedIOReport: Bool

        if let reading = ioReport?.sample(interval: request.interval) {
            apply(reading, to: &snapshot)
            cpuResidency = reading.sawCPUResidency
            gpuResidency = reading.sawGPUResidency
            cpuEnergy = reading.sawCPUEnergy
            gpuEnergy = reading.sawGPUEnergy
            aneEnergy = reading.sawANEEnergy
            dramEnergy = reading.sawDRAM
            gpuSRAMEnergy = reading.sawGPUSRAM
            usedIOReport = true
        } else {
            Thread.sleep(forTimeInterval: request.interval)
            let cores = cpuFallback.sample(hardware: hardware)
            apply(cores: cores, to: &snapshot)
            cpuResidency = !cores.isEmpty
            usedIOReport = false
        }

        let temps = TemperatureSampler.sample(force: request.forceTemperature)
        snapshot.cpuTempC = temps.cpu
        snapshot.gpuTempC = temps.gpu
        snapshot.sensors = temps.sensors
        let traffic = network.sample()
        snapshot.networkDownloadBytesPerSecond = traffic.downloadBytesPerSecond
        snapshot.networkUploadBytesPerSecond = traffic.uploadBytesPerSecond
        snapshot.networkInterfaces = traffic.interfaces
        snapshot.drives = disks.currentDrives()
        snapshot.timestamp = Date()
        snapshot.confidence = MetricConfidence.resolve(
            isAppleSilicon: hardware.isAppleSilicon,
            hasIOReport: usedIOReport,
            cpuResidency: cpuResidency,
            gpuResidency: gpuResidency,
            cpuEnergy: cpuEnergy,
            gpuEnergy: gpuEnergy,
            aneEnergy: aneEnergy,
            hasTemperature: temps.cpu != nil || temps.gpu != nil || !temps.sensors.isEmpty,
            didSampleProcesses: request.includeProcesses,
            memoryOK: snapshot.memory.totalBytes > 0,
            dramEnergy: dramEnergy,
            gpuSRAMEnergy: gpuSRAMEnergy
        )
        return snapshot
    }

    private func apply(_ reading: IOReportReading, to snapshot: inout Snapshot) {
        let eAgg = MetricMath.aggregateCluster(
            reading.efficiencyCores,
            expectedCount: hardware.eCoreCount,
            minimumFrequencyMHz: hardware.eCoreFrequenciesMHz.first ?? 0
        )
        let pAgg = MetricMath.aggregateCluster(
            reading.performanceCores,
            expectedCount: hardware.pCoreCount,
            minimumFrequencyMHz: hardware.pCoreFrequenciesMHz.first ?? 0
        )
        let cores = reading.efficiencyCores + reading.performanceCores
        let total = Double(max(cores.count, hardware.cpuCoreCount, 1))
        snapshot.cores = cores
        snapshot.eClusterFrequencyMHz = eAgg.frequencyMHz
        snapshot.eClusterScaledRatio = eAgg.scaledRatio
        snapshot.eClusterActiveRatio = eAgg.activeRatio
        snapshot.pClusterFrequencyMHz = pAgg.frequencyMHz
        snapshot.pClusterScaledRatio = pAgg.scaledRatio
        snapshot.pClusterActiveRatio = pAgg.activeRatio
        snapshot.cpuScaledRatio = MetricMath.clamp01(
            (reading.efficiencyCores.reduce(0) { $0 + $1.scaledRatio }
                + reading.performanceCores.reduce(0) { $0 + $1.scaledRatio }) / total
        )
        snapshot.cpuActiveRatio = MetricMath.clamp01(
            (reading.efficiencyCores.reduce(0) { $0 + $1.activeRatio }
                + reading.performanceCores.reduce(0) { $0 + $1.activeRatio }) / total
        )
        snapshot.gpuActiveRatio = reading.gpuActiveRatio
        snapshot.gpuScaledRatio = reading.gpuScaledRatio
        snapshot.gpuFrequencyMHz = reading.gpuFrequencyMHz
        snapshot.cpuPowerWatts = reading.cpuPowerWatts
        snapshot.gpuPowerWatts = reading.gpuPowerWatts
        snapshot.anePowerWatts = reading.anePowerWatts
        snapshot.ramPowerWatts = reading.ramPowerWatts
        snapshot.gpuSRAMPowerWatts = reading.gpuSRAMPowerWatts
        snapshot.systemPowerWatts = max(
            reading.cpuPowerWatts + reading.gpuPowerWatts + reading.anePowerWatts,
            0
        )
    }

    private func apply(cores: [CoreSample], to snapshot: inout Snapshot) {
        snapshot.cores = cores
        let eCores = cores.filter { $0.kind == .efficiency }
        let pCores = cores.filter { $0.kind == .performance }
        let eAgg = MetricMath.aggregateCluster(eCores, expectedCount: hardware.eCoreCount, minimumFrequencyMHz: 0)
        let pAgg = MetricMath.aggregateCluster(pCores, expectedCount: hardware.pCoreCount, minimumFrequencyMHz: 0)
        snapshot.eClusterActiveRatio = eAgg.activeRatio
        snapshot.eClusterScaledRatio = eAgg.scaledRatio
        snapshot.pClusterActiveRatio = pAgg.activeRatio
        snapshot.pClusterScaledRatio = pAgg.scaledRatio
        snapshot.cpuActiveRatio = MetricMath.aggregateCluster(
            cores,
            expectedCount: hardware.cpuCoreCount,
            minimumFrequencyMHz: 0
        ).activeRatio
        snapshot.cpuScaledRatio = snapshot.cpuActiveRatio
    }
}

public enum SampleText {
    public static func render(hardware: HardwareProfile, snapshot: Snapshot) -> String {
        var lines: [String] = []
        lines.append("Silicon Scope")
        lines.append("\(hardware.chipName)  \(hardware.modelIdentifier)  \(MetricFormat.bytes(hardware.memoryBytes))")
        lines.append(
            "CPU  \(MetricFormat.percent(snapshot.cpuActiveRatio))  E \(MetricFormat.percent(snapshot.eClusterActiveRatio)) @ \(MetricFormat.megahertz(snapshot.eClusterFrequencyMHz))  P \(MetricFormat.percent(snapshot.pClusterActiveRatio)) @ \(MetricFormat.megahertz(snapshot.pClusterFrequencyMHz))"
        )
        lines.append(
            "GPU  \(MetricFormat.percent(snapshot.gpuActiveRatio))  \(MetricFormat.megahertz(snapshot.gpuFrequencyMHz))  \(MetricFormat.watts(snapshot.gpuPowerWatts))"
        )
        lines.append(
            "ANE  \(MetricFormat.watts(snapshot.anePowerWatts)) measured  activity \(MetricFormat.estimatedPercent(MetricMath.aneActivity(powerWatts: snapshot.anePowerWatts, peakWatts: hardware.anePeakWatts))) of \(MetricFormat.watts(hardware.anePeakWatts)) typical peak"
        )
        lines.append(
            "MEM  \(MetricFormat.bytes(snapshot.memory.usedBytes)) / \(MetricFormat.bytes(snapshot.memory.totalBytes))  \(snapshot.memory.pressure.title)"
        )
        lines.append(
            "TEMP CPU \(MetricFormat.temperature(snapshot.cpuTempC))  GPU \(MetricFormat.temperature(snapshot.gpuTempC))"
        )
        lines.append(
            "NET  down \(MetricFormat.bytesPerSecond(snapshot.networkDownloadBytesPerSecond))  up \(MetricFormat.bytesPerSecond(snapshot.networkUploadBytesPerSecond))"
        )
        let physical = snapshot.drives.filter(\.kind.countsTowardCapacity)
        let capacity = physical.reduce(UInt64(0)) { $0 + $1.sizeBytes }
        let free = physical.reduce(UInt64(0)) { $0 + $1.availableBytes }
        lines.append(
            "DISK  \(snapshot.drives.count) drives  \(MetricFormat.bytes(capacity))  free \(MetricFormat.bytes(free))"
        )
        lines.append(
            "PWR  package \(MetricFormat.watts(snapshot.packagePowerWatts))  CPU \(MetricFormat.watts(snapshot.cpuPowerWatts))  GPU \(MetricFormat.watts(snapshot.gpuPowerWatts))  ANE \(MetricFormat.watts(snapshot.anePowerWatts))"
        )
        lines.append(
            "TEL  \(snapshot.confidence.mode.title)  CPU \(snapshot.confidence.cpu.title)  GPU \(snapshot.confidence.gpu.title)  ANE W \(snapshot.confidence.aneWatts.title)  ANE % \(snapshot.confidence.aneActivity.title)  chip \(snapshot.confidence.power.title)"
        )
        return lines.joined(separator: "\n")
    }
}
