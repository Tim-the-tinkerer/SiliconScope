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
        XCTAssertGreaterThan(detail?.footprintBytes ?? 0, 0)
    }

    func testMissingProcess() {
        XCTAssertNil(ProcessDetails.load(pid: -1))
        XCTAssertNil(ProcessDetails.load(pid: 0))
    }

    func testSpinningThreadReportsAboutOneCore() {
        let before = taskTimes()
        var sink = 0
        let start = Date()
        while Date().timeIntervalSince(start) < 0.35 {
            sink = sink &+ 1
        }
        let after = taskTimes()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(sink, 0)
        let user = after.user >= before.user ? after.user - before.user : 0
        let system = after.system >= before.system ? after.system - before.system : 0
        let percent = MetricMath.processCPUPercent(deltaTicks: user + system, elapsed: elapsed)
        XCTAssertGreaterThan(percent, 50)
        XCTAssertLessThan(percent, 150)
    }

    private func taskTimes() -> (user: UInt64, system: UInt64) {
        var info = proc_taskallinfo()
        let size = Int32(MemoryLayout<proc_taskallinfo>.size)
        let got = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(getpid(), PROC_PIDTASKALLINFO, 0, pointer, size)
        }
        XCTAssertEqual(got, size)
        return (info.ptinfo.pti_total_user, info.ptinfo.pti_total_system)
    }
}
