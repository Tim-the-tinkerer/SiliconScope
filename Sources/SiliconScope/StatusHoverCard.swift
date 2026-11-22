import AppKit
import SiliconScopeCore

/// Hover detail for the menu-bar extra.
///
/// This is an app-owned panel, not an `NSStatusBarButton` tooltip. On macOS 27,
/// rewriting `toolTip` on a timer leaves the system tooltip window up, and each
/// new string moves that window to the pointer until the app quits.
@MainActor
final class StatusHoverCard {
    private let panel: NSPanel
    private let label: NSTextField
    private var shownText: String?

    init() {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .left
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 560
        label.translatesAutoresizingMaskIntoConstraints = false
        self.label = label

        let effect = NSVisualEffectView()
        effect.material = .toolTip
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.masksToBounds = true
        effect.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: effect.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -6),
        ])

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effect
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.setAccessibilityElement(false)
        self.panel = panel
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    func show(text: String, itemFrame: CGRect, visibleFrame: CGRect) {
        var cardSize = panel.frame.size
        if shownText != text {
            label.stringValue = text
            shownText = text
            let font = label.font ?? NSFont.systemFont(ofSize: 12)
            let textSize = (text as NSString).boundingRect(
                with: NSSize(width: 560, height: 800),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            )
            let size = NSSize(width: ceil(textSize.width) + 20, height: ceil(textSize.height) + 12)
            guard size.width > 1, size.height > 1 else { return }
            panel.setContentSize(size)
            cardSize = size
        }
        let next = StatusHoverPlacement.frame(
            cardSize: cardSize,
            itemFrame: itemFrame,
            visibleFrame: visibleFrame
        )
        if !panel.isVisible || !Self.sameFrame(panel.frame, next) {
            panel.setFrame(next, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }
}
