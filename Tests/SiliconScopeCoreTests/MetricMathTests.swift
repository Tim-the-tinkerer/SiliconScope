import SiliconScopeCore
import XCTest

final class MetricMathTests: XCTestCase {
    func testWattsFromMicrojoulesUsesExactDuration() {
        let watts = MetricMath.watts(energy: 1_000_000, unit: "uJ", duration: 0.2505)
        XCTAssertNotNil(watts)
        XCTAssertEqual(watts!, 3.992016, accuracy: 0.000001)
    }

    func testWattsRejectsUnknownUnit() {
        XCTAssertNil(MetricMath.watts(energy: 10, unit: "W", duration: 1))
    }

    func testFrequencyMetricsSkipIdleAndDown() {
        let result = MetricMath.frequencyMetrics(
            residencies: [
                (name: "DOWN", value: 0),
                (name: "IDLE", value: 500),
                (name: "1000 MHz", value: 100),
                (name: "2000 MHz", value: 400),
            ],
            frequenciesMHz: [1000, 2000]
        )
        XCTAssertEqual(result.frequencyMHz, 1800)
        XCTAssertEqual(result.activeRatio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.scaledRatio, 0.45, accuracy: 0.0001)
    }

    func testANEActivityClamps() {
        XCTAssertEqual(MetricMath.aneActivity(powerWatts: 4, peakWatts: 8), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MetricMath.aneActivity(powerWatts: 20, peakWatts: 8), 1.0, accuracy: 0.0001)
        XCTAssertEqual(MetricMath.aneActivity(powerWatts: 1, peakWatts: 0), 0)
    }

    func testParseCPUCoreChannels() {
        XCTAssertEqual(MetricMath.parseCPUCore("ECPU0")?.kind, .efficiency)
        XCTAssertEqual(MetricMath.parseCPUCore("PCPU3")?.kind, .performance)
        XCTAssertEqual(MetricMath.parseCPUCore("DIE_1_PCPU0")?.kind, .performance)
        XCTAssertEqual(MetricMath.parseCPUCore("MCPU2")?.kind, .efficiency)
        XCTAssertNil(MetricMath.parseCPUCore("GPUPH"))
    }

    func testParseDieAndCoreIDs() {
        XCTAssertEqual(MetricMath.parseDieID("DIE_1_ECPU0"), 1)
        XCTAssertEqual(MetricMath.parseDieID("ECPU7"), 0)
        XCTAssertEqual(MetricMath.parseCoreID("ECPU7"), 7)
        XCTAssertEqual(MetricMath.parseCoreID("DIE_0_PCPU1_CPU3"), 3)
    }

    func testMemoryUsedMatchesActivityMonitorStyle() {
        let page: UInt64 = 16384
        let result = MetricMath.memoryUsedBytes(
            pageSize: page,
            internalPages: 100,
            purgeablePages: 10,
            wiredPages: 20,
            compressorPages: 5
        )
        XCTAssertEqual(result.app, 90 * page)
        XCTAssertEqual(result.used, (90 + 20 + 5) * page)
    }

    func testPressureMapping() {
        XCTAssertEqual(MetricMath.pressure(fromLevel: 0), .normal)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 1), .normal)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 2), .warning)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 3), .urgent)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 4), .critical)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 8), .critical)
        XCTAssertEqual(MetricMath.pressure(fromLevel: 9), .unknown)
        XCTAssertEqual(MemoryPressure.unknown.chartLevel, 0)
        XCTAssertEqual(MemoryPressure.normal.chartLevel, 1)
        XCTAssertEqual(MemoryPressure.warning.chartLevel, 2)
        XCTAssertEqual(MemoryPressure.urgent.chartLevel, 3)
        XCTAssertEqual(MemoryPressure.critical.chartLevel, 4)
    }

    func testNameAndMemoryRankingsIgnoreCPU() {
        let rows = [
            ProcessSample(pid: 2, name: "zeta", cpuPercent: 90, memoryBytes: 10, threadCount: 1),
            ProcessSample(pid: 1, name: "alpha", cpuPercent: 1, memoryBytes: 500, threadCount: 1),
            ProcessSample(pid: 3, name: "mid", cpuPercent: 40, memoryBytes: 40, threadCount: 1),
        ]
        XCTAssertEqual(ProcessRanking.cpu.select(rows, limit: 1).map(\.pid), [2])
        XCTAssertEqual(ProcessRanking.name.select(rows, limit: 1).map(\.name).sorted(), ["alpha", "mid", "zeta"])
        XCTAssertEqual(ProcessRanking.memory.select(rows, limit: 1).map(\.pid).sorted(), [1, 2, 3])
    }

    func testPreferredWattsSkipsAStuckZero() {
        XCTAssertEqual(MetricMath.preferredWatts([0.5, 4]), 0.5)
        XCTAssertEqual(MetricMath.preferredWatts([0, 4]), 4)
        XCTAssertEqual(MetricMath.preferredWatts([0, 0]), 0)
        XCTAssertEqual(MetricMath.preferredWatts([nil, 1.5]), 1.5)
        XCTAssertEqual(MetricMath.preferredWatts([nil, nil]), 0)
        XCTAssertEqual(MetricMath.preferredWatts([-2, nil]), 0)
    }

    func testCachedFilesIncludePurgeable() {
        XCTAssertEqual(
            MetricMath.cachedFileBytes(pageSize: 16_384, externalPages: 10, purgeablePages: 3),
            13 * 16_384
        )
    }

    func testTemperatureNames() {
        XCTAssertEqual(TemperatureName.title(for: "pACC MTR Temp Sensor4"), "Performance cluster sensor 4")
        XCTAssertEqual(TemperatureName.title(for: "eACC MTR Temp Sensor0"), "Efficiency cluster sensor 0")
        XCTAssertEqual(TemperatureName.title(for: "GPU MTR Temp Sensor1"), "GPU sensor 1")
        XCTAssertEqual(TemperatureName.title(for: "ANE MTR Temp Sensor1"), "Neural Engine sensor 1")
        XCTAssertEqual(TemperatureName.title(for: "ISP MTR Temp Sensor5"), "Image processor sensor 5")
        XCTAssertEqual(TemperatureName.title(for: "PMGR SOC Die Temp Sensor1"), "SoC die sensor 1")
        XCTAssertEqual(TemperatureName.title(for: "SOC MTR Temp Sensor0"), "SoC sensor 0")
        XCTAssertEqual(TemperatureName.title(for: "NAND CH0 temp"), "Storage channel 0")
        XCTAssertEqual(TemperatureName.title(for: "PMU tcal"), "Package")
        XCTAssertEqual(TemperatureName.title(for: "PMU2 tcal"), "Package 2")
        XCTAssertEqual(TemperatureName.title(for: "PMU tdie8"), "Power manager die 8")
        XCTAssertEqual(TemperatureName.title(for: "PMU2 tdev2"), "Power manager 2 board 2")
        XCTAssertEqual(TemperatureName.title(for: "PMU TP3w"), "Power manager probe")
        XCTAssertEqual(TemperatureName.family(for: "pACC MTR Temp Sensor4"), "Performance cluster")
        XCTAssertEqual(TemperatureName.family(for: "eACC MTR Temp Sensor0"), "Efficiency cluster")
        XCTAssertEqual(TemperatureName.family(for: "GPU MTR Temp Sensor1"), "GPU")
        XCTAssertEqual(TemperatureName.family(for: "PMU tdie8"), "Power manager die")
        XCTAssertEqual(TemperatureName.family(for: "PMU2 tdie1"), "Power manager die")
        XCTAssertEqual(TemperatureName.family(for: "PMU tcal"), "Package")
        XCTAssertEqual(TemperatureName.family(for: "PMU2 tcal"), "Package")
        XCTAssertEqual(TemperatureName.family(for: "NAND CH0 temp"), "Storage")
    }

    func testCounterRateIgnoresAReset() {
        XCTAssertEqual(MetricMath.counterRate(current: 1_500, previous: 500, elapsed: 1), 1_000)
        XCTAssertEqual(MetricMath.counterRate(current: 10, previous: 50, elapsed: 1), 0)
        XCTAssertEqual(MetricMath.counterRate(current: 50, previous: 50, elapsed: 0), 0)
    }

    func testCPUTemperatureAveragesTheTwoClusters() {
        let sensors = [
            TemperatureSensor(id: "p1", name: "pACC MTR Temp Sensor1", celsius: 40, group: .cpu),
            TemperatureSensor(id: "p2", name: "pACC MTR Temp Sensor2", celsius: 50, group: .cpu),
            TemperatureSensor(id: "e1", name: "eACC MTR Temp Sensor0", celsius: 30, group: .cpu),
            TemperatureSensor(id: "g1", name: "GPU MTR Temp Sensor1", celsius: 90, group: .gpu),
        ]
        XCTAssertEqual(TemperatureName.cpuClusterAverage(sensors), 37.5)
    }

    func testTemperatureGroups() {
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "pACC MTR Temp Sensor 1"), .cpu)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "eACC MTR Temp Sensor"), .cpu)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "GPU MTR Temp Sensor"), .gpu)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "AGX Thermal"), .gpu)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "NAND CH0 Temp"), .other)
    }

    func testClusterLetters() {
        XCTAssertEqual(MetricMath.clusterLetter(forPerfLevelName: "Efficiency"), "E")
        XCTAssertEqual(MetricMath.clusterLetter(forPerfLevelName: "Performance"), "P")
        XCTAssertEqual(MetricMath.clusterLetter(forPerfLevelName: "Super"), "S")
        XCTAssertEqual(MetricMath.clusterLetter(forPerfLevelName: "  performance "), "P")
    }

    func testDVFSUnitDecode() {
        XCTAssertEqual(MetricMath.dvfsMegahertz(raw: 600_000_000), 600)
        XCTAssertEqual(MetricMath.dvfsMegahertz(raw: 2_064_000_000), 2064)
        XCTAssertEqual(MetricMath.dvfsMegahertz(raw: 3_204_000_000), 3204)
        XCTAssertEqual(MetricMath.dvfsMegahertz(raw: 1_278_000_000), 1278)
        XCTAssertEqual(MetricMath.dvfsMegahertz(raw: 4_512_000), 4512)
        XCTAssertNil(MetricMath.dvfsMegahertz(raw: 0))
        XCTAssertNil(MetricMath.dvfsMegahertz(raw: 1))
    }

    func testTypicalANEPeak() {
        XCTAssertEqual(MetricMath.typicalANEPeakWatts(chipName: "Apple M1"), 8)
        XCTAssertEqual(MetricMath.typicalANEPeakWatts(chipName: "Apple M1 Ultra"), 16)
        XCTAssertEqual(MetricMath.typicalANEPeakWatts(chipName: "Apple M4 Pro"), 10)
    }

    func testM4FrequencyLaddersIgnoreHertzDomains() {
        let ladders = [
            ladder("voltage-states1-sram", [1020, 1296, 1608, 1920, 2256, 2424, 2592], kilohertz: true),
            ladder("voltage-states5-sram", [1260, 4512], kilohertz: true),
            ladder("voltage-states13-sram", [1260, 4512], kilohertz: true),
            ladder("voltage-states8", [400, 2364], kilohertz: false),
            ladder("voltage-states28", [801, 1602, 2004], kilohertz: false),
            ladder("voltage-states9", [338, 1578], kilohertz: false),
            ladder("voltage-states9-sram", [338, 1578], kilohertz: false),
            ladder("voltage-states29", [1068], kilohertz: false),
        ]
        let classified = MetricMath.classifyFrequencyLadders(ladders)
        XCTAssertEqual(classified.efficiency, [1020, 1296, 1608, 1920, 2256, 2424, 2592])
        XCTAssertEqual(classified.performance, [1260, 4512])
        XCTAssertEqual(classified.gpu, [338, 1578])
    }

    func testM1FrequencyLaddersStayInHertz() {
        let classified = MetricMath.classifyFrequencyLadders([
            ladder("voltage-states1", [600, 2064], kilohertz: false),
            ladder("voltage-states5", [600, 3204], kilohertz: false),
            ladder("voltage-states9", [396, 1278], kilohertz: false),
        ])
        XCTAssertEqual(classified.efficiency, [600, 2064])
        XCTAssertEqual(classified.performance, [600, 3204])
        XCTAssertEqual(classified.gpu, [396, 1278])
    }

    func testM4CoreIndexes() {
        XCTAssertEqual(coreKey("ECPU000"), [0, 0, 0])
        XCTAssertEqual(coreKey("ECPU030"), [0, 0, 3])
        XCTAssertEqual(coreKey("PCPU000"), [0, 0, 0])
        XCTAssertEqual(coreKey("PCPU040"), [0, 0, 4])
        XCTAssertEqual(coreKey("PCPU100"), [0, 1, 0])
        XCTAssertEqual(coreKey("PCPU140"), [0, 1, 4])
        XCTAssertEqual(MetricMath.parseCoreID("PCPU140"), 4)
        XCTAssertEqual(MetricMath.parseCoreID("ECPU7"), 7)
    }

    private func coreKey(_ channel: String) -> [Int] {
        let key = MetricMath.sortKey(forCPUChannel: channel)
        return [key.0, key.1, key.2]
    }

    func testFlattenM4CoresAreSequential() {
        let performance = (0..<5).map { "PCPU1\($0)0" } + (0..<5).map { "PCPU0\($0)0" }
        let pCores = MetricMath.flattenCores(
            performance.map { (channel: $0, frequencyMHz: UInt32(0), scaledRatio: 0, activeRatio: 0) },
            kind: .performance
        )
        XCTAssertEqual(pCores.map(\.coreID), Array(0..<10))
        XCTAssertEqual(pCores.map(\.shortLabel), (0..<10).map { "P\($0)" })

        let efficiency = ["ECPU030", "ECPU000", "ECPU020", "ECPU010"]
        let eCores = MetricMath.flattenCores(
            efficiency.map { (channel: $0, frequencyMHz: UInt32(0), scaledRatio: 0, activeRatio: 0) },
            kind: .efficiency
        )
        XCTAssertEqual(eCores.map(\.coreID), [0, 1, 2, 3])
        XCTAssertEqual(eCores.map(\.shortLabel), ["E0", "E1", "E2", "E3"])
    }

    func testParkedCoreReportsZeroFrequency() {
        let parked = MetricMath.frequencyMetrics(
            residencies: [
                (name: "DOWN", value: 900),
                (name: "IDLE", value: 100),
                (name: "V0", value: 0),
                (name: "V1", value: 0),
            ],
            frequenciesMHz: [1260, 4512]
        )
        XCTAssertEqual(parked.frequencyMHz, 0)
        XCTAssertEqual(parked.activeRatio, 0)
        XCTAssertEqual(parked.scaledRatio, 0)
    }

    func testAggregateClusterIgnoresAPoweredOffCluster() {
        let asleep = (0..<5).map { core in
            CoreSample(kind: .performance, dieID: 0, coreID: core, frequencyMHz: 1260, activeRatio: 0, scaledRatio: 0)
        }
        let awake = (5..<10).map { core in
            CoreSample(kind: .performance, dieID: 0, coreID: core, frequencyMHz: 3200, activeRatio: 0.5, scaledRatio: 0.4)
        }
        let aggregate = MetricMath.aggregateCluster(asleep + awake, expectedCount: 10, minimumFrequencyMHz: 1260)
        XCTAssertEqual(aggregate.frequencyMHz, 3200)
        XCTAssertEqual(aggregate.activeRatio, 0.25, accuracy: 0.0001)

        let idle = CoreSample(kind: .efficiency, dieID: 0, coreID: 0, frequencyMHz: 1020, activeRatio: 0, scaledRatio: 0)
        XCTAssertEqual(MetricMath.aggregateCluster([idle], expectedCount: 4, minimumFrequencyMHz: 1020).frequencyMHz, 0)
        XCTAssertEqual(MetricMath.aggregateCluster([], expectedCount: 4, minimumFrequencyMHz: 1020).frequencyMHz, 1020)
    }

    func testSleepingPowerRailDoesNotReportItsBin() {
        let busy = MetricMath.powerHistogram([
            (name: "0.250W", value: 1750),
            (name: "1W", value: 401),
        ])
        let asleep = MetricMath.powerHistogram([(name: "  2W", value: 28)])
        XCTAssertEqual(busy?.events, 2151)
        XCTAssertEqual(busy?.weighted, 838.5)
        XCTAssertEqual(asleep?.weighted, 56)
        let watts = MetricMath.normalizedHistogramWatts([busy!, asleep!])
        XCTAssertEqual(watts!, 894.5 / 2151, accuracy: 0.0001)
        XCTAssertEqual(MetricMath.wattBin("0.250W"), 0.25)
        XCTAssertEqual(MetricMath.wattBin("  2W"), 2)
        XCTAssertNil(MetricMath.wattBin("DOWN"))
        XCTAssertNil(MetricMath.powerHistogram([(name: "mJ", value: 10)]))
        XCTAssertNil(MetricMath.normalizedHistogramWatts([]))
        XCTAssertEqual(MetricMath.normalizedHistogramWatts([(weighted: 0, events: 0)]), 0)
    }

    func testSMCTemperatureNamesAndAverages() {
        XCTAssertEqual(TemperatureName.title(for: "Tp1x"), "Performance cluster sensor")
        XCTAssertEqual(TemperatureName.title(for: "Te04"), "Efficiency cluster sensor")
        XCTAssertEqual(TemperatureName.title(for: "Tg05"), "GPU sensor")
        XCTAssertEqual(TemperatureName.title(for: "TCMz"), "CPU die sensor")
        XCTAssertEqual(TemperatureName.title(for: "TPD0"), "Power manager sensor")
        XCTAssertEqual(TemperatureName.title(for: "Ts0P"), "SoC sensor")
        XCTAssertEqual(TemperatureName.family(for: "Tp1x"), "Performance cluster")
        XCTAssertEqual(TemperatureName.family(for: "Tg05"), "GPU")
        XCTAssertEqual(TemperatureName.family(for: "TPD0"), "Power manager")
        XCTAssertEqual(TemperatureName.role(for: "Tp1x"), .cpu)
        XCTAssertEqual(TemperatureName.role(for: "Te04"), .cpu)
        XCTAssertEqual(TemperatureName.role(for: "Tg05"), .gpu)
        XCTAssertEqual(TemperatureName.role(for: "TPD0"), .other)
        XCTAssertEqual(TemperatureName.role(for: "TVMD"), .other)
        XCTAssertEqual(TemperatureName.role(for: "PMU TP3g"), .gpu)
        XCTAssertEqual(TemperatureName.role(for: "PMU tdie1"), .other)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "Tp1x"), .cpu)
        XCTAssertEqual(TemperatureGroup.group(forSensorName: "TPD0"), .other)
        XCTAssertFalse(TemperatureName.acceptsCelsius(-4))
        XCTAssertFalse(TemperatureName.acceptsCelsius(2))
        XCTAssertTrue(TemperatureName.acceptsCelsius(8))
        XCTAssertTrue(TemperatureName.acceptsCelsius(150))
        XCTAssertFalse(TemperatureName.acceptsCelsius(151))

        let sensors = [
            TemperatureSensor(id: "p1", name: "Tp1x", celsius: 70, group: .cpu),
            TemperatureSensor(id: "p2", name: "Tp2a", celsius: 50, group: .cpu),
            TemperatureSensor(id: "e1", name: "Te04", celsius: 40, group: .cpu),
            TemperatureSensor(id: "e2", name: "Te05", celsius: 36, group: .cpu),
            TemperatureSensor(id: "g1", name: "Tg01", celsius: 44, group: .gpu),
            TemperatureSensor(id: "g2", name: "Tg02", celsius: 40, group: .gpu),
            TemperatureSensor(id: "d1", name: "PMU tdie1", celsius: 48, group: .other),
            TemperatureSensor(id: "pm", name: "TPD0", celsius: 39, group: .other),
        ]
        XCTAssertEqual(TemperatureName.cpuClusterAverage(sensors), 49)
        XCTAssertEqual(TemperatureName.gpuAverage(sensors), 42)

        let hid = [
            TemperatureSensor(id: "p", name: "pACC MTR Temp Sensor1", celsius: 40, group: .cpu),
            TemperatureSensor(id: "e", name: "eACC MTR Temp Sensor0", celsius: 30, group: .cpu),
            TemperatureSensor(id: "tp", name: "Tp1x", celsius: 90, group: .cpu),
            TemperatureSensor(id: "te", name: "Te04", celsius: 10, group: .cpu),
            TemperatureSensor(id: "gpu", name: "GPU MTR Temp Sensor1", celsius: 33, group: .gpu),
            TemperatureSensor(id: "tg", name: "Tg01", celsius: 44, group: .gpu),
        ]
        XCTAssertEqual(TemperatureName.cpuClusterAverage(hid), 35)
        XCTAssertEqual(TemperatureName.gpuAverage(hid), 33)

        let diodes = [
            TemperatureSensor(id: "p", name: "pACC MTR Temp Sensor1", celsius: 40, group: .cpu),
            TemperatureSensor(id: "e", name: "eACC MTR Temp Sensor0", celsius: 30, group: .cpu),
            TemperatureSensor(id: "gpu", name: "GPU MTR Temp Sensor1", celsius: 33, group: .gpu),
        ]
        XCTAssertFalse(TemperatureName.includesSMCKey("Tp1x", hid: diodes))
        XCTAssertFalse(TemperatureName.includesSMCKey("Te04", hid: diodes))
        XCTAssertFalse(TemperatureName.includesSMCKey("Tg05", hid: diodes))
        XCTAssertFalse(TemperatureName.includesSMCKey("TCMz", hid: diodes))
        XCTAssertFalse(TemperatureName.includesSMCKey("TPD0", hid: diodes))
        XCTAssertFalse(TemperatureName.includesSMCKey("Ts0P", hid: []))
        XCTAssertFalse(TemperatureName.includesSMCKey("TW0P", hid: []))
        XCTAssertTrue(TemperatureName.includesSMCKey("Tp1x", hid: []))
        XCTAssertTrue(TemperatureName.includesSMCKey("Te04", hid: []))
        XCTAssertTrue(TemperatureName.includesSMCKey("Tg05", hid: []))
        XCTAssertTrue(TemperatureName.includesSMCKey("TCMz", hid: []))

        let probes = [
            TemperatureSensor(id: "g", name: "PMU TP3g", celsius: 55, group: .gpu),
            TemperatureSensor(id: "d", name: "PMU tdie1", celsius: 48, group: .other),
            TemperatureSensor(id: "d2", name: "PMU tdie2", celsius: 50, group: .other),
            TemperatureSensor(id: "n", name: "NAND CH0 temp", celsius: 33, group: .other),
        ]
        XCTAssertEqual(TemperatureName.gpuAverage(probes), 55)
        XCTAssertEqual(TemperatureName.cpuClusterAverage(probes), 49)
    }

    private func ladder(_ key: String, _ megahertz: [UInt32], kilohertz: Bool) -> MetricMath.FrequencyLadder {
        MetricMath.FrequencyLadder(key: key, megahertz: megahertz, kilohertzEncoded: kilohertz)
    }

    func testFlattenUltraCores() {
        let cores = MetricMath.flattenCores(
            [
                (channel: "DIE_0_PCPU1_CPU0", frequencyMHz: 2000, scaledRatio: 0.5, activeRatio: 0.75),
                (channel: "DIE_0_PCPU_CPU1", frequencyMHz: 1100, scaledRatio: 0.25, activeRatio: 0.5),
                (channel: "DIE_0_PCPU_CPU0", frequencyMHz: 1000, scaledRatio: 0.2, activeRatio: 0.4),
            ],
            kind: .performance
        )
        XCTAssertEqual(cores.map(\.coreID), [0, 1, 2])
        XCTAssertEqual(cores.map(\.frequencyMHz), [1000, 1100, 2000])
    }
}
