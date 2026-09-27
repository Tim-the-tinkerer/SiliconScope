import AppKit
import Combine
import SiliconScopeCore
import SwiftUI

@main
struct MainEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--help") || args.contains("-h") {
            print(
                """
                Silicon Scope — Apple Silicon CPU, GPU, memory, and Neural Engine monitor

                Usage:
                  SiliconScope              Launch the app
                  SiliconScope --sample     Take one sample and print it
                  SiliconScope --self-test  Validate formatters and metric math
                  SiliconScope --help
                """
            )
            exit(0)
        }

        if args.contains("--self-test") {
            if let error = SelfTest.run() {
                fputs("SELF-TEST FAILED: \(error)\n", stderr)
                exit(1)
            }
            print("SELF-TEST OK")
            exit(0)
        }

        if args.contains("--sample") {
            let sampler = SystemSampler()
            let snapshot = sampler.sample(SampleRequest(interval: 1, processLimit: 8, includeProcesses: true, forceTemperature: true))
            print(SampleText.render(hardware: sampler.hardware, snapshot: snapshot))
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate.shared
        app.delegate = delegate
        // Hide the Dock icon whenever the menu bar extra is on.
        app.setActivationPolicy(delegate.store.showMenuBar ? .accessory : .regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let shared = AppDelegate()

    let store = MetricStore()
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var statusItem: StatusItemController?
    private var cancellables = Set<AnyCancellable>()

    private let minSize = NSSize(width: 980, height: 640)
    private let defaultSize = NSSize(width: 1180, height: 760)

    private override init() { super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        let extra = StatusItemController(store: store)
        extra.onOpenWindow = { [weak self] in self?.showMainWindow() }
        extra.onOpenSettings = { [weak self] in self?.showSettings() }
        extra.start()
        statusItem = extra
        store.$showMenuBar
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.menuBarVisibilityChanged(visible)
            }
            .store(in: &cancellables)
        applyActivationPolicy()
        buildMainMenu()
        if store.openWindowOnLaunch || !store.showMenuBar {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItem?.stop()
        store.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !store.showMenuBar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() } else { window?.makeKeyAndOrderFront(nil) }
        return true
    }

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = ContentView()
            .environmentObject(store)
            .frame(minWidth: minSize.width, minHeight: minSize.height)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: defaultSize)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Silicon Scope"
        window.contentView = hosting
        window.setContentSize(defaultSize)
        window.contentMinSize = minSize
        window.tabbingMode = .disallowed
        window.isRestorable = true
        window.setFrameAutosaveName("SiliconScope.Main")
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc func showSettings(_ sender: Any? = nil) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = SettingsView()
            .environmentObject(store)

        let hosting = NSHostingView(rootView: root)
        let size = NSSize(width: 460, height: 520)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = hosting
        window.setContentSize(size)
        window.contentMinSize = NSSize(width: 420, height: 400)
        window.tabbingMode = .disallowed
        window.isRestorable = true
        window.setFrameAutosaveName("SiliconScope.Settings")
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }

    @objc func showAbout(_ sender: Any? = nil) {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingView(rootView: AboutView())
        let size = NSSize(width: 460, height: 460)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Silicon Scope"
        window.contentView = hosting
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.aboutWindow = window
    }

    @objc private func showPage(_ sender: NSMenuItem) {
        let pages = SidebarPage.allCases
        guard pages.indices.contains(sender.tag) else { return }
        store.page = pages[sender.tag]
    }

    @objc private func togglePause(_ sender: Any?) {
        store.togglePaused()
    }

    @objc private func toggleMenuBar(_ sender: Any?) {
        store.showMenuBar.toggle()
    }

    private func menuBarVisibilityChanged(_ visible: Bool) {
        applyActivationPolicy()
        if !visible {
            showMainWindow()
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(store.showMenuBar ? .accessory : .regular)
        if !store.showMenuBar {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func showWindowMenu(_ sender: Any?) {
        showMainWindow()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMenuBar(_:)) {
            menuItem.state = store.showMenuBar ? .on : .off
        }
        if menuItem.action == #selector(togglePause(_:)) {
            menuItem.title = store.paused ? "Resume Sampling" : "Pause Sampling"
        }
        return true
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let aboutItem = appMenu.addItem(withTitle: "About Silicon Scope", action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Silicon Scope", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Silicon Scope", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        for (index, page) in SidebarPage.allCases.enumerated() {
            let item = viewMenu.addItem(
                withTitle: page.title,
                action: #selector(showPage(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            item.tag = index
        }
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Pause Sampling", action: #selector(togglePause(_:)), keyEquivalent: "p")
        let menuBarItem = viewMenu.addItem(
            withTitle: "Show Menu Bar Extra",
            action: #selector(toggleMenuBar(_:)),
            keyEquivalent: "b"
        )
        menuBarItem.toolTip = "Live CPU, GPU, temperatures, memory, and Neural Engine in the menu bar. When on, Silicon Scope stays out of the Dock."

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Silicon Scope", action: #selector(showWindowMenu(_:)), keyEquivalent: "0")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}

enum SelfTest {
    static func run() -> String? {
        if MetricMath.watts(energy: 1_000_000, unit: "uJ", duration: 0.2505).map({ abs($0 - 3.992016) < 0.0001 }) != true {
            return "watts conversion"
        }
        if MetricFormat.percent(0.5) != "50.0%" { return "percent format" }
        if MetricMath.typicalANEPeakWatts(chipName: "Apple M1 Ultra") != 16 { return "ANE peak" }
        if MetricMath.dvfsMegahertz(raw: 2_064_000_000) != 2064 { return "dvfs hz" }
        if MetricMath.dvfsMegahertz(raw: 4_512_000) != 4512 { return "dvfs khz" }
        if MetricMath.clusterLetter(forPerfLevelName: "Super") != "S" { return "cluster letter" }
        if MetricMath.preferredWatts([0, 4]) != 4 { return "idle power rail" }
        if MetricMath.pressure(fromLevel: 1) != .normal { return "pressure" }
        var buffer = HistoryBuffer(window: 180)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<400 {
            buffer.append(Snapshot(timestamp: start.addingTimeInterval(Double(index) * 0.5)))
        }
        let span = buffer.snapshots.last!.timestamp.timeIntervalSince(buffer.snapshots.first!.timestamp)
        if span > 180.01 { return "history window" }
        if TelemetryMode.classify(
            isAppleSilicon: true,
            hasIOReport: false,
            cpuResidency: true,
            gpuResidency: false,
            cpuEnergy: false,
            gpuEnergy: false,
            aneEnergy: false
        ) != .cpuFallback {
            return "telemetry mode"
        }
        return nil
    }
}
