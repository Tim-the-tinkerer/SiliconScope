import SiliconScopeCore
import XCTest

final class NetworkTests: XCTestCase {
    func testVPNIsLeftOutOfTheTotalWhileAPhysicalLinkIsUp() {
        let interfaces = [
            link("en0", .wifi, up: true, down: 100, upRate: 40),
            link("utun0", .vpn, up: true, down: 100, upRate: 40),
        ]
        let totals = interfaces.networkTotals()
        XCTAssertEqual(totals.downloadBytesPerSecond, 100)
        XCTAssertEqual(totals.uploadBytesPerSecond, 40)
    }

    func testVPNCountsWhenNoPhysicalLinkIsUp() {
        let interfaces = [
            link("en0", .wifi, up: false, down: 0, upRate: 0),
            link("utun0", .vpn, up: true, down: 80, upRate: 20),
        ]
        let totals = interfaces.networkTotals()
        XCTAssertEqual(totals.downloadBytesPerSecond, 80)
        XCTAssertEqual(totals.uploadBytesPerSecond, 20)
    }

    func testBridgeIsNeverAddedToTheTotal() {
        let interfaces = [
            link("bridge0", .bridge, up: true, down: 500, upRate: 500),
        ]
        XCTAssertEqual(interfaces.networkTotals().downloadBytesPerSecond, 0)
    }

    private func link(
        _ name: String,
        _ kind: NetworkKind,
        up: Bool,
        down: Double,
        upRate: Double
    ) -> NetworkInterfaceSample {
        NetworkInterfaceSample(
            id: name,
            name: name,
            displayName: name,
            kind: kind,
            isUp: up,
            addresses: [],
            downloadBytesPerSecond: down,
            uploadBytesPerSecond: upRate
        )
    }
}