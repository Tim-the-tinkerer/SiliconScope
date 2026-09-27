import AppKit
import Combine
import SiliconScopeCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: MetricStore
    private var item: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var menuIsOpen = false
    private var liveTimer: Timer?
    var onOpenWindow: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    init(store: MetricStore) {
        self.store = store
        super.init()
    }

    func start() {
        store.$showMenuBar
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                if visible { self?.install() } else { self?.remove() }
            }
            .store(in: &cancellables)

        store.$latest
            .combineLatest(store.$paused)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func stop() {
        stopLiveTimer()
        remove()
        cancellables.removeAll()
    }

    private func install() {
        guard item == nil else {
            refreshButton()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: Self.minSlotWidth)
        item.autosaveName = "SiliconScope.StatusItem"
        if let button = item.button {
            button.font = Self.statusFont
            button.imagePosition = .noImage
            button.lineBreakMode = .byClipping
            if let cell = button.cell as? NSButtonCell {
                cell.wraps = false
                cell.truncatesLastVisibleLine = true
                cell.lineBreakMode = .byClipping
            }
            button.setAccessibilityTitle("Silicon Scope")
            button.setAccessibilityRole(.button)
            button.setAccessibilityHelp("Processor, graphics, memory, temperatures, and estimated Neural Engine activity. Click for details.")
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        self.item = item
        refreshButton()
    }

    private func remove() {
        stopLiveTimer()
        menuIsOpen = false
        if let item {
            NSStatusBar.system.removeStatusItem(item)
        }
        item = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        startLiveTimer()
        updateLiveItems(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        stopLiveTimer()
    }

    private func startLiveTimer() {
        stopLiveTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    private func stopLiveTimer() {
        liveTimer?.invalidate()
        liveTimer = nil
    }

    private func refresh() {
        refreshButton()
        if menuIsOpen, let menu = item?.menu {
            updateLiveItems(menu)
        }
    }

    private func refreshButton() {
        guard let button = item?.button else { return }
        let snap = store.latest
        let ane = store.aneActivity()
        let cpuTemp = TemperatureName.cpuClusterAverage(snap.sensors)
        button.attributedTitle = attributedLine(
            cpu: snap.cpuActiveRatio,
            gpu: snap.gpuActiveRatio,
            memory: snap.memory.usedRatio,
            ane: ane,
            cpuTemp: cpuTemp,
            gpuTemp: snap.gpuTempC
        )
        button.toolTip = MetricFormat.menuBarTooltip(
            cpu: snap.cpuActiveRatio,
            gpu: snap.gpuActiveRatio,
            memory: snap.memory.usedRatio,
            ane: ane,
            cpuWatts: snap.cpuPowerWatts,
            gpuWatts: snap.gpuPowerWatts,
            aneWatts: snap.anePowerWatts,
            pressure: snap.memory.pressure,
            cpuTemp: cpuTemp,
            gpuTemp: snap.gpuTempC
        )
        button.setAccessibilityValue(button.toolTip ?? "")
        // Don't resize the extra while the menu is tracking — that can dismiss it.
        if !menuIsOpen {
            item?.length = Self.fittedLength(for: button.attributedTitle)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = store.latest
        let ane = store.aneActivity()

        addDisabled(menu, "What the numbers mean")
        menu.addItem(.separator())

        addDisabled(menu, cpuLine(snap), tag: .cpu)
        addDisabled(menu, gpuLine(snap), tag: .gpu)
        addDisabled(menu, memLine(snap), tag: .mem)
        addPressure(menu, snap.memory.pressure)
        addDisabled(menu, aneLine(ane, watts: snap.anePowerWatts), tag: .ane)
        addDisabled(menu, chipPowerLine(watts: snap.packagePowerWatts, quality: snap.confidence.power), tag: .chip)

        menu.addItem(.separator())

        let open = menu.addItem(withTitle: "Open Silicon Scope", action: #selector(openWindow), keyEquivalent: "o")
        open.target = self
        open.isEnabled = true

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        settings.isEnabled = true

        let pause = menu.addItem(
            withTitle: store.paused ? "Resume Sampling" : "Pause Sampling",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pause.tag = Row.pause.rawValue
        pause.target = self
        pause.isEnabled = true

        menu.addItem(.separator())

        let hide = menu.addItem(withTitle: "Hide Menu Bar Extra", action: #selector(hideExtra), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true

        let quit = menu.addItem(withTitle: "Quit Silicon Scope", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = true
    }

    private enum Row: Int {
        case cpu = 101
        case gpu
        case mem
        case pressure
        case ane
        case chip
        case pause
    }

    private func cpuLine(_ snap: Snapshot) -> String {
        let temp = MetricFormat.temperature(TemperatureName.cpuClusterAverage(snap.sensors))
        return "CPU  (processor)     \(MetricFormat.percent(snap.cpuActiveRatio, digits: 0))   \(temp)   \(MetricFormat.watts(snap.cpuPowerWatts))   \(MetricFormat.megahertz(snap.pClusterFrequencyMHz))"
    }

    private func gpuLine(_ snap: Snapshot) -> String {
        "GPU  (graphics)      \(MetricFormat.percent(snap.gpuActiveRatio, digits: 0))   \(MetricFormat.temperature(snap.gpuTempC))   \(MetricFormat.watts(snap.gpuPowerWatts))   \(MetricFormat.megahertz(snap.gpuFrequencyMHz))"
    }

    private func memLine(_ snap: Snapshot) -> String {
        "MEM  (memory)        \(MetricFormat.percent(snap.memory.usedRatio, digits: 0))   \(MetricFormat.bytes(snap.memory.usedBytes)) / \(MetricFormat.bytes(snap.memory.totalBytes))"
    }

    private func aneLine(_ ane: Double, watts: Double) -> String {
        "ANE  (activity, est.) \(MetricFormat.estimatedPercent(ane, digits: 0))   \(MetricFormat.watts(watts)) measured"
    }

    private func pressureTitle(_ pressure: MemoryPressure) -> String {
        "Pressure            \(pressure.title)"
    }

    private func chipPowerLine(watts: Double, quality: MetricQuality) -> String {
        let value = MetricFormat.value(MetricFormat.watts(watts), quality: quality)
        if quality == .measured {
            return "Chip power           \(value)"
        }
        return "Chip power           \(value)  \(quality.title)"
    }

    private func updateLiveItems(_ menu: NSMenu) {
        let snap = store.latest
        let ane = store.aneActivity()
        menu.item(withTag: Row.cpu.rawValue)?.title = cpuLine(snap)
        menu.item(withTag: Row.gpu.rawValue)?.title = gpuLine(snap)
        menu.item(withTag: Row.mem.rawValue)?.title = memLine(snap)
        menu.item(withTag: Row.ane.rawValue)?.title = aneLine(ane, watts: snap.anePowerWatts)
        menu.item(withTag: Row.chip.rawValue)?.title = chipPowerLine(watts: snap.packagePowerWatts, quality: snap.confidence.power)
        menu.item(withTag: Row.pause.rawValue)?.title = store.paused ? "Resume Sampling" : "Pause Sampling"
        if let item = menu.item(withTag: Row.pressure.rawValue) {
            applyPressure(item, snap.memory.pressure)
        }
    }

    private func addDisabled(_ menu: NSMenu, _ title: String, tag: Row? = nil) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let tag {
            item.tag = tag.rawValue
        }
    }

    private func addPressure(_ menu: NSMenu, _ pressure: MemoryPressure) {
        let item = menu.addItem(withTitle: pressureTitle(pressure), action: nil, keyEquivalent: "")
        item.tag = Row.pressure.rawValue
        applyPressure(item, pressure)
    }

    private func applyPressure(_ item: NSMenuItem, _ pressure: MemoryPressure) {
        let title = pressureTitle(pressure)
        item.title = title
        // Stay enabled so Warning / Urgent / Critical color is not washed out.
        item.isEnabled = true
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: pressureColor(pressure),
            ]
        )
    }

    private func pressureColor(_ pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .normal:
            return NSColor(srgbRed: 0.361, green: 0.820, blue: 0.537, alpha: 1)
        case .warning:
            return NSColor(srgbRed: 0.961, green: 0.620, blue: 0.243, alpha: 1)
        case .urgent, .critical:
            return NSColor(srgbRed: 0.961, green: 0.341, blue: 0.357, alpha: 1)
        case .unknown:
            return NSColor.secondaryLabelColor
        }
    }

    @objc private func openWindow() {
        onOpenWindow()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func togglePause() {
        store.togglePaused()
        refresh()
    }

    @objc private func hideExtra() {
        store.showMenuBar = false
    }

    private static let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)

    private static let lineStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        style.alignment = .left
        style.lineSpacing = 0
        style.maximumLineHeight = 14
        style.minimumLineHeight = 14
        return style
    }()

    /// Compact two-digit line. `100%` / `ANE ~100%` can grow up to `maxSlotWidth`.
    private static let minSlotWidth: CGFloat = {
        ceil(makeLine(cpu: 0.99, gpu: 0.99, memory: 0.99, ane: 0.99, cpuTemp: 99, gpuTemp: 99).size().width) + 10
    }()

    private static let maxSlotWidth: CGFloat = {
        ceil(makeLine(cpu: 1, gpu: 1, memory: 1, ane: 1, cpuTemp: 100, gpuTemp: 100).size().width) + 10
    }()

    private static func fittedLength(for title: NSAttributedString) -> CGFloat {
        let width = ceil(title.size().width) + 10
        return min(max(width, minSlotWidth), maxSlotWidth)
    }

    private func attributedLine(
        cpu: Double,
        gpu: Double,
        memory: Double,
        ane: Double,
        cpuTemp: Double?,
        gpuTemp: Double?
    ) -> NSAttributedString {
        Self.makeLine(cpu: cpu, gpu: gpu, memory: memory, ane: ane, cpuTemp: cpuTemp, gpuTemp: gpuTemp)
    }

    private static func makeLine(
        cpu: Double,
        gpu: Double,
        memory: Double,
        ane: Double,
        cpuTemp: Double?,
        gpuTemp: Double?
    ) -> NSAttributedString {
        let font = statusFont
        let result = NSMutableAttributedString()
        func append(_ text: String, _ color: NSColor) {
            if result.length > 0 {
                result.append(NSAttributedString(string: " ", attributes: [
                    .font: font,
                    .paragraphStyle: lineStyle,
                ]))
            }
            result.append(NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: lineStyle,
                    .baselineOffset: 0,
                ]
            ))
        }
        let cpuColor = NSColor(srgbRed: 0.30, green: 0.64, blue: 1.00, alpha: 1)
        let gpuColor = NSColor(srgbRed: 0.24, green: 0.86, blue: 0.59, alpha: 1)
        append("CPU \(MetricFormat.menuBarPercent(cpu)) \(MetricFormat.menuBarTemperature(cpuTemp))", cpuColor)
        append("GPU \(MetricFormat.menuBarPercent(gpu)) \(MetricFormat.menuBarTemperature(gpuTemp))", gpuColor)
        append("MEM \(MetricFormat.menuBarPercent(memory))", NSColor(srgbRed: 0.96, green: 0.76, blue: 0.30, alpha: 1))
        append("ANE \(MetricFormat.menuBarPercent(ane, estimated: true))", NSColor(srgbRed: 0.75, green: 0.52, blue: 0.99, alpha: 1))
        return result
    }
}
