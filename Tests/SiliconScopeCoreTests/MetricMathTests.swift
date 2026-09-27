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
