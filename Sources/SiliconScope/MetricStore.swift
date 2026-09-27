import Combine
import Foundation
import SiliconScopeCore

final class MetricStore: ObservableObject {
    @Published private(set) var hardware = HardwareProfile.unknown
    @Published private(set) var latest = Snapshot()
    @Published private(set) var history: [Snapshot] = []
    @Published private(set) var hasSample = false
    @Published var paused = false
    @Published var page: SidebarPage = .overview {
        didSet { lock.withLock { wantProcesses = page == .processes } }
    }
    @Published var showMenuBar: Bool {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: Prefs.showMenuBar) }
    }
    @Published var openWindowOnLaunch: Bool {
        didSet { UserDefaults.standard.set(openWindowOnLaunch, forKey: Prefs.openWindowOnLaunch) }
    }
    @Published var interval: TimeInterval = 1 {
        didSet {
            lock.withLock { requestedInterval = interval }
            UserDefaults.standard.set(interval, forKey: Prefs.interval)
        }
    }

    static let allowedIntervals: [TimeInterval] = [0.5, 1.0, 2.0]

    private enum Prefs {
        static let showMenuBar = "showMenuBar"
        static let openWindowOnLaunch = "openWindowOnLaunch"
        static let interval = "sampleInterval"
    }

    let historyWindow: TimeInterval = 180

    private let queue = DispatchQueue(label: "com.siliconscope.sampler", qos: .userInitiated)
    private let lock = NSLock()
    private var requestedInterval: TimeInterval = 1
    private var wantProcesses = false
    private var requestedRanking: ProcessRanking = .cpu
    private var searchActive = false
    private var stopFlag = false
    private var pauseFlag = false
    private var started = false
    private var buffer = HistoryBuffer(window: 180)

    init() {
        if UserDefaults.standard.object(forKey: Prefs.showMenuBar) == nil {
            showMenuBar = true
        } else {
            showMenuBar = UserDefaults.standard.bool(forKey: Prefs.showMenuBar)
        }
        if UserDefaults.standard.object(forKey: Prefs.openWindowOnLaunch) == nil {
            openWindowOnLaunch = true
        } else {
            openWindowOnLaunch = UserDefaults.standard.bool(forKey: Prefs.openWindowOnLaunch)
        }
        let storedInterval = UserDefaults.standard.double(forKey: Prefs.interval)
        if Self.allowedIntervals.contains(storedInterval) {
            interval = storedInterval
            requestedInterval = storedInterval
        }
    }

    func start() {
        guard !started else { return }
        started = true
        queue.async { [weak self] in
            guard let self else { return }
            let sampler = SystemSampler()
            self.performOnMain { self.hardware = sampler.hardware }
            while true {
                if self.lock.withLock({ self.stopFlag }) { break }
                if self.lock.withLock({ self.pauseFlag }) {
                    Thread.sleep(forTimeInterval: 0.2)
                    continue
                }
                let (interval, wantProcesses, ranking, searching) = self.lock.withLock {
                    (self.requestedInterval, self.wantProcesses, self.requestedRanking, self.searchActive)
                }
                let snapshot = sampler.sample(
                    SampleRequest(
                        interval: interval,
                        processLimit: searching ? 10_000 : 20,
                        includeProcesses: wantProcesses,
                        processRanking: ranking
                    )
                )
                // Common modes keep consuming while an NSMenu is tracking (default mode is paused).
                self.performOnMain { self.consume(snapshot) }
            }
        }
    }

    func stop() {
        lock.withLock { stopFlag = true }
    }

    func togglePaused() {
        paused.toggle()
        lock.withLock { pauseFlag = paused }
    }

    func setProcessRanking(_ ranking: ProcessRanking) {
        lock.withLock { requestedRanking = ranking }
    }

    func setProcessSearch(_ query: String) {
        let active = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lock.withLock { searchActive = active }
    }

    private func performOnMain(_ body: @escaping () -> Void) {
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue as CFString, body)
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func consume(_ snapshot: Snapshot) {
        latest = snapshot
        var archived = snapshot
        archived.processes = []
        archived.sensors = []
        archived.networkInterfaces = []
        archived.drives = []
        // Per-core bars read the latest snapshot. The charts use the cluster ratios.
        archived.cores = []
        buffer.append(archived)
        history = buffer.snapshots
        hasSample = true
    }

    func aneActivity(in snapshot: Snapshot? = nil) -> Double {
        MetricMath.aneActivity(
            powerWatts: (snapshot ?? latest).anePowerWatts,
            peakWatts: hardware.anePeakWatts
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
