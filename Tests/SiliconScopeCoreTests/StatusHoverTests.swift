import CoreGraphics
import SiliconScopeCore
import XCTest

final class StatusHoverTests: XCTestCase {
    func testCardStaysUnderTheMenuBarItemOnThatScreen() {
        let item = CGRect(x: 2400, y: 1050, width: 180, height: 24)
        let visible = CGRect(x: 1920, y: 0, width: 1920, height: 1050)
        let card = StatusHoverPlacement.frame(
            cardSize: CGSize(width: 280, height: 72),
            itemFrame: item,
            visibleFrame: visible
        )

        XCTAssertEqual(card.width, 280)
        XCTAssertEqual(card.height, 72)
        XCTAssertEqual(card.midX, item.midX)
        XCTAssertEqual(card.maxY, item.minY - StatusHoverPlacement.gap)
        XCTAssertGreaterThanOrEqual(card.minX, visible.minX)
        XCTAssertLessThanOrEqual(card.maxX, visible.maxX)
        XCTAssertGreaterThan(card.minX, 1900)
    }

    func testCardClampsToTheScreenInsteadOfFollowingOff() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 900)
        let left = StatusHoverPlacement.frame(
            cardSize: CGSize(width: 300, height: 80),
            itemFrame: CGRect(x: 2, y: 900, width: 30, height: 24),
            visibleFrame: visible
        )
        XCTAssertEqual(left.minX, StatusHoverPlacement.gap)
        XCTAssertEqual(left.maxY, 900 - StatusHoverPlacement.gap)

        let right = StatusHoverPlacement.frame(
            cardSize: CGSize(width: 300, height: 80),
            itemFrame: CGRect(x: 760, y: 900, width: 40, height: 24),
            visibleFrame: visible
        )
        XCTAssertEqual(right.maxX, visible.maxX - StatusHoverPlacement.gap)

        let low = StatusHoverPlacement.frame(
            cardSize: CGSize(width: 300, height: 80),
            itemFrame: CGRect(x: 200, y: 10, width: 40, height: 24),
            visibleFrame: visible
        )
        XCTAssertEqual(low.minY, StatusHoverPlacement.gap)
    }

    func testPointerHitIsTheExtraNotTheDesktop() {
        let item = CGRect(x: 10, y: 20, width: 30, height: 10)
        XCTAssertTrue(StatusHoverPlacement.contains(CGPoint(x: 25, y: 25), itemFrame: item))
        XCTAssertTrue(StatusHoverPlacement.contains(CGPoint(x: 9, y: 20), itemFrame: item))
        XCTAssertFalse(StatusHoverPlacement.contains(CGPoint(x: 0, y: 20), itemFrame: item))
        XCTAssertFalse(StatusHoverPlacement.contains(CGPoint(x: 400, y: 400), itemFrame: item))
    }

    func testCardShowsOnlyAfterThePointerRestsAndHidesForTheMenu() {
        let delay = StatusHoverPlacement.showDelay
        XCTAssertFalse(StatusHoverPlacement.shouldShow(
            pointerInside: true, menuOpen: false, suppressedUntilExit: false, hoveredFor: delay - 0.05
        ))
        XCTAssertTrue(StatusHoverPlacement.shouldShow(
            pointerInside: true, menuOpen: false, suppressedUntilExit: false, hoveredFor: delay
        ))
        XCTAssertFalse(StatusHoverPlacement.shouldShow(
            pointerInside: false, menuOpen: false, suppressedUntilExit: false, hoveredFor: delay + 2
        ))
        XCTAssertFalse(StatusHoverPlacement.shouldShow(
            pointerInside: true, menuOpen: true, suppressedUntilExit: false, hoveredFor: delay + 2
        ))
        XCTAssertFalse(StatusHoverPlacement.shouldShow(
            pointerInside: true, menuOpen: false, suppressedUntilExit: true, hoveredFor: delay + 2
        ))
    }
}
