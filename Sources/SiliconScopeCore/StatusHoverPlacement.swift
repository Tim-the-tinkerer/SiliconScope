import CoreGraphics
import Foundation

/// Where the menu-bar hover card goes, and when it is allowed on screen.
///
/// The card is anchored to the status item. The pointer is never an input to
/// `frame`, so a live reading cannot drag the card around the desktop.
public enum StatusHoverPlacement {
    /// How long the pointer must rest on the extra before the card appears.
    public static let showDelay: TimeInterval = 0.5
    /// Space between the bottom of the menu-bar extra and the top of the card.
    public static let gap: CGFloat = 4

    /// A couple of points of slop, so a one-pixel jitter on the menu bar does not dismiss the card.
    public static func contains(_ pointer: CGPoint, itemFrame: CGRect) -> Bool {
        itemFrame.insetBy(dx: -2, dy: -2).contains(pointer)
    }

    public static func shouldShow(
        pointerInside: Bool,
        menuOpen: Bool,
        suppressedUntilExit: Bool,
        hoveredFor: TimeInterval
    ) -> Bool {
        pointerInside && !menuOpen && !suppressedUntilExit && hoveredFor >= showDelay
    }

    /// Place the card just under the menu-bar item and keep it inside that screen's visible area.
    public static func frame(cardSize: CGSize, itemFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let width = cardSize.width
        let height = cardSize.height
        var x = itemFrame.midX - width / 2
        var y = itemFrame.minY - height - gap
        let minX = visibleFrame.minX + gap
        let maxX = visibleFrame.maxX - width - gap
        if maxX >= minX {
            x = min(max(x, minX), maxX)
        }
        let minY = visibleFrame.minY + gap
        if y < minY {
            y = minY
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
