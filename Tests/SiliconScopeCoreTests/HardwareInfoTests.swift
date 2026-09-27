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
}
