import Darwin
import SiliconScopeCore
import XCTest

final class ProcessDetailTests: XCTestCase {
    func testCurrentProcessDetail() {
        let detail = ProcessDetails.load(pid: getpid(), cpuPercent: 1.25)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.pid, getpid())
        XCTAssertEqual(detail?.cpuPercent, 1.25)
        XCTAssertFalse(detail?.name.isEmpty ?? true)
        XCTAssertFalse(detail?.path.isEmpty ?? true)
        XCTAssertGreaterThan(detail?.threadCount ?? 0, 0)
        XCTAssertGreaterThan(detail?.residentBytes ?? 0, 0)
    }

    func testMissingProcess() {
        XCTAssertNil(ProcessDetails.load(pid: -1))
        XCTAssertNil(ProcessDetails.load(pid: 0))
    }
}
