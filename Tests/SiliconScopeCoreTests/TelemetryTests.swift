import SiliconScopeCore
import XCTest

final class TelemetryTests: XCTestCase {
    func testFullIOReportOnAppleSilicon() {
        let mode = TelemetryMode.classify(
            isAppleSilicon: true,
            hasIOReport: true,
            cpuResidency: true,
            gpuResidency: true,
            cpuEnergy: true,
            gpuEnergy: true,
            aneEnergy: true
        )
        XCTAssertEqual(mode, .fullIOReport)
    }

    func testMissingANEIsPartial() {
        let mode = TelemetryMode.classify(
            isAppleSilicon: true,
            hasIOReport: true,
            cpuResidency: true,
            gpuResidency: true,
            cpuEnergy: true,
            gpuEnergy: true,
            aneEnergy: false
        )
        XCTAssertEqual(mode, .partialIOReport)
    }

    func testNoIOReportIsCPUFallback() {
        let mode = TelemetryMode.classify(
            isAppleSilicon: true,
            hasIOReport: false,
            cpuResidency: true,
            gpuResidency: false,
            cpuEnergy: false,
            gpuEnergy: false,
            aneEnergy: false
        )
        XCTAssertEqual(mode, .cpuFallback)
    }

    func testConfidenceMarksANEActivityEstimated() {
        let confidence = MetricConfidence.resolve(
            isAppleSilicon: true,
            hasIOReport: true,
            cpuResidency: true,
            gpuResidency: true,
            cpuEnergy: true,
            gpuEnergy: true,
            aneEnergy: true,
            hasTemperature: true,
            didSampleProcesses: false,
            memoryOK: true
        )
        XCTAssertEqual(confidence.mode, .fullIOReport)
        XCTAssertEqual(confidence.aneWatts, .measured)
        XCTAssertEqual(confidence.aneActivity, .estimated)
        XCTAssertEqual(confidence.processes, .unavailable)
        XCTAssertEqual(confidence.cpu, .measured)
        XCTAssertEqual(confidence.gpu, .measured)
        XCTAssertEqual(confidence.cpuPower, .measured)
        XCTAssertEqual(confidence.gpuPower, .measured)
        XCTAssertEqual(confidence.power, .measured)
    }

    func testPackagePowerPartialWhenARailIsMissing() {
        let confidence = MetricConfidence.resolve(
            isAppleSilicon: true,
            hasIOReport: true,
            cpuResidency: true,
            gpuResidency: true,
            cpuEnergy: true,
            gpuEnergy: true,
            aneEnergy: false,
            hasTemperature: true,
            didSampleProcesses: false,
            memoryOK: true
        )
        XCTAssertEqual(confidence.cpuPower, .measured)
        XCTAssertEqual(confidence.gpuPower, .measured)
        XCTAssertEqual(confidence.aneWatts, .unavailable)
        XCTAssertEqual(confidence.power, .partial)
        XCTAssertEqual(confidence.mode, .partialIOReport)
    }

    func testPackagePowerQualityHelper() {
        XCTAssertEqual(MetricQuality.packagePower(cpuEnergy: true, gpuEnergy: true, aneEnergy: true), .measured)
        XCTAssertEqual(MetricQuality.packagePower(cpuEnergy: true, gpuEnergy: true, aneEnergy: false), .partial)
        XCTAssertEqual(MetricQuality.packagePower(cpuEnergy: true, gpuEnergy: false, aneEnergy: false), .partial)
        XCTAssertEqual(MetricQuality.packagePower(cpuEnergy: false, gpuEnergy: false, aneEnergy: false), .unavailable)
    }

    func testEmptyCPUFallbackIsUnavailable() {
        let confidence = MetricConfidence.resolve(
            isAppleSilicon: true,
            hasIOReport: false,
            cpuResidency: false,
            gpuResidency: false,
            cpuEnergy: false,
            gpuEnergy: false,
            aneEnergy: false,
            hasTemperature: false,
            didSampleProcesses: false,
            memoryOK: true
        )
        XCTAssertEqual(confidence.mode, .cpuFallback)
        XCTAssertEqual(confidence.cpu, .unavailable)
        XCTAssertEqual(confidence.dram, .unavailable)
        XCTAssertEqual(confidence.gpuSRAM, .unavailable)
    }

    func testFallbackHidesGPUAndANE() {
        let confidence = MetricConfidence.resolve(
            isAppleSilicon: false,
            hasIOReport: false,
            cpuResidency: true,
            gpuResidency: false,
            cpuEnergy: false,
            gpuEnergy: false,
            aneEnergy: false,
            hasTemperature: false,
            didSampleProcesses: true,
            memoryOK: true
        )
        XCTAssertEqual(confidence.mode, .cpuFallback)
        XCTAssertEqual(confidence.cpu, .measured)
        XCTAssertEqual(confidence.gpu, .unavailable)
        XCTAssertEqual(confidence.aneWatts, .unavailable)
        XCTAssertEqual(confidence.aneActivity, .unavailable)
        XCTAssertEqual(confidence.power, .unavailable)
        XCTAssertEqual(confidence.temperature, .unavailable)
        XCTAssertEqual(confidence.processes, .measured)
    }

    func testHistoryIsTimeWindowNotSampleCount() {
        var buffer = HistoryBuffer(window: 180)
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<400 {
            buffer.append(Snapshot(timestamp: start.addingTimeInterval(Double(index) * 0.5)))
        }
        let first = buffer.snapshots.first!.timestamp
        let last = buffer.snapshots.last!.timestamp
        XCTAssertLessThanOrEqual(last.timeIntervalSince(first), 180.01)
        XCTAssertGreaterThan(buffer.snapshots.count, 300)
        XCTAssertLessThanOrEqual(buffer.snapshots.count, 361)
    }

    func testTwoSecondIntervalStillSpansThreeMinutes() {
        var buffer = HistoryBuffer(window: 180)
        let start = Date(timeIntervalSince1970: 2_000_000)
        for index in 0..<120 {
            buffer.append(Snapshot(timestamp: start.addingTimeInterval(Double(index) * 2)))
        }
        XCTAssertEqual(buffer.snapshots.count, 91)
        let span = buffer.snapshots.last!.timestamp.timeIntervalSince(buffer.snapshots.first!.timestamp)
        XCTAssertEqual(span, 180, accuracy: 0.01)
    }

    func testHistoryDropsSamplesOlderThanWindow() {
        var buffer = HistoryBuffer(window: 10)
        let start = Date(timeIntervalSince1970: 3_000_000)
        buffer.append(Snapshot(timestamp: start))
        buffer.append(Snapshot(timestamp: start.addingTimeInterval(11)))
        XCTAssertEqual(buffer.snapshots.count, 1)
        XCTAssertEqual(buffer.snapshots.first?.timestamp, start.addingTimeInterval(11))
    }
}
