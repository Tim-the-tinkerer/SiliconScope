import SiliconScopeCore
import XCTest

final class HardwareInfoTests: XCTestCase {
    func testAppleSiliconDetection() {
        XCTAssertTrue(HardwareInfo.isAppleSilicon(chipName: "Apple M1"))
        XCTAssertTrue(HardwareInfo.isAppleSilicon(chipName: "Apple M4 Max"))
        XCTAssertFalse(HardwareInfo.isAppleSilicon(chipName: "Intel(R) Core(TM) i7"))
    }

    func testLoadReturnsThisMachine() {
        let profile = HardwareInfo.load()
        XCTAssertFalse(profile.chipName.isEmpty)
        XCTAssertGreaterThan(profile.memoryBytes, 0)
        XCTAssertGreaterThan(profile.cpuCoreCount, 0)
        XCTAssertFalse(profile.pClusterName.isEmpty)
        XCTAssertFalse(profile.eClusterName.isEmpty)
    }

    func testM1DVFSAndClusterNames() {
        let profile = HardwareInfo.load()
        guard profile.chipName.contains("M1") else { return }
        XCTAssertEqual(profile.eCoreLabel, "E")
        XCTAssertEqual(profile.pCoreLabel, "P")
        XCTAssertEqual(profile.eClusterName, "Efficiency")
        XCTAssertEqual(profile.pClusterName, "Performance")
        XCTAssertEqual(profile.eCoreFrequenciesMHz.last, 2064)
        XCTAssertEqual(profile.pCoreFrequenciesMHz.last, 3204)
        XCTAssertEqual(profile.gpuFrequenciesMHz.last, 1278)
        XCTAssertEqual(profile.eCoreFrequenciesMHz.first, 600)
        XCTAssertEqual(profile.pCoreFrequenciesMHz.first, 600)
    }

    func testM4ProLiveClustersPowerAndTemperature() {
        let hardware = HardwareInfo.load()
        guard hardware.chipName.contains("M4 Pro") else { return }
        XCTAssertEqual(hardware.eCoreCount, 4)
        XCTAssertEqual(hardware.pCoreCount, 10)
        XCTAssertEqual(hardware.eCoreFrequenciesMHz.count, 7)
        XCTAssertEqual(hardware.eCoreFrequenciesMHz.first, 1020)
        XCTAssertEqual(hardware.eCoreFrequenciesMHz.last, 2592)
        XCTAssertEqual(hardware.pCoreFrequenciesMHz.count, 19)
        XCTAssertEqual(hardware.pCoreFrequenciesMHz.first, 1260)
        XCTAssertEqual(hardware.pCoreFrequenciesMHz.last, 4512)
        XCTAssertEqual(hardware.gpuFrequenciesMHz.first, 338)
        XCTAssertEqual(hardware.gpuFrequenciesMHz.last, 1578)
        XCTAssertFalse(hardware.gpuFrequenciesMHz.contains(0))

        let snapshot = SystemSampler(hardware: hardware).sample(
            SampleRequest(interval: 0.4, processLimit: 5, includeProcesses: false, forceTemperature: true)
        )
        let efficiency = snapshot.cores.filter { $0.kind == .efficiency }
        let performance = snapshot.cores.filter { $0.kind == .performance }
        XCTAssertEqual(efficiency.map(\.coreID), Array(0..<4))
        XCTAssertEqual(performance.map(\.coreID), Array(0..<10))
        XCTAssertEqual(efficiency.map(\.shortLabel), ["E0", "E1", "E2", "E3"])
        XCTAssertEqual(performance.map(\.shortLabel), (0..<10).map { "P\($0)" })
        if snapshot.eClusterFrequencyMHz > 0 {
            XCTAssertGreaterThanOrEqual(snapshot.eClusterFrequencyMHz, 1020)
            XCTAssertLessThanOrEqual(snapshot.eClusterFrequencyMHz, 2592)
        }
        if snapshot.pClusterFrequencyMHz > 0 {
            XCTAssertGreaterThanOrEqual(snapshot.pClusterFrequencyMHz, 1260)
            XCTAssertLessThanOrEqual(snapshot.pClusterFrequencyMHz, 4512)
        }
        XCTAssertGreaterThan(snapshot.cpuPowerWatts, 0.05)

        let names = snapshot.sensors.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains { $0.count == 4 && $0.hasPrefix("Tp") })
        XCTAssertTrue(names.contains { $0.count == 4 && $0.hasPrefix("Te") })
        XCTAssertTrue(names.contains { $0.count == 4 && $0.hasPrefix("Tg") })
        XCTAssertFalse(names.contains { $0.lowercased().contains("tcal") })
        XCTAssertNotNil(snapshot.cpuTempC)
        XCTAssertNotNil(snapshot.gpuTempC)
        if let cpu = snapshot.cpuTempC {
            XCTAssertGreaterThan(cpu, 20)
            XCTAssertLessThan(cpu, 110)
        }
        if let gpu = snapshot.gpuTempC {
            XCTAssertGreaterThan(gpu, 20)
            XCTAssertLessThan(gpu, 110)
        }
    }
}
