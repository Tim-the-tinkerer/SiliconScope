import SiliconScopeCore
import XCTest

final class FormattersTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(MetricFormat.percent(0.5), "50.0%")
        XCTAssertEqual(MetricFormat.percent(1.4, digits: 0), "100%")
    }

    func testWatts() {
        XCTAssertEqual(MetricFormat.watts(0.004), "4 mW")
        XCTAssertEqual(MetricFormat.watts(2.5), "2.50 W")
    }

    func testBytes() {
        XCTAssertEqual(MetricFormat.bytes(512), "512 B")
        XCTAssertEqual(MetricFormat.bytes(1024), "1.00 KB")
        XCTAssertEqual(MetricFormat.bytes(16 * 1024 * 1024 * 1024), "16.0 GB")
    }

    func testMegahertz() {
        XCTAssertEqual(MetricFormat.megahertz(600), "600 MHz")
        XCTAssertEqual(MetricFormat.megahertz(3204), "3.20 GHz")
    }

    func testDuration() {
        XCTAssertEqual(MetricFormat.duration(65), "1:05")
        XCTAssertEqual(MetricFormat.duration(3_661), "1:01:01")
    }

    func testUptime() {
        XCTAssertEqual(MetricFormat.uptime(90), "1m")
        XCTAssertEqual(MetricFormat.uptime(3700), "1h 1m")
        XCTAssertEqual(MetricFormat.uptime(90_000), "1d 1h 0m")
    }

    func testTemperatureMissing() {
        XCTAssertEqual(MetricFormat.temperature(nil), "—")
        XCTAssertEqual(MetricFormat.temperature(42.1), "42.1°C")
    }

    func testEstimatedPercent() {
        XCTAssertEqual(MetricFormat.estimatedPercent(0.37, digits: 0), "~37%")
        XCTAssertEqual(MetricFormat.estimatedPercent(0.5), "~50.0%")
    }

    func testUnavailableValue() {
        XCTAssertEqual(MetricFormat.value("12.0%", quality: .measured), "12.0%")
        XCTAssertEqual(MetricFormat.value("12.0%", quality: .unavailable), "—")
        XCTAssertEqual(MetricFormat.historyWindow(180), "3 min")
    }

    func testMenuBarLine() {
        let fig = "\u{2007}"
        XCTAssertEqual(
            MetricFormat.menuBarLine(cpu: 0.423, gpu: 0.081, memory: 0.61, ane: 0, cpuTemp: 36.4, gpuTemp: 30.2),
            "CPU 42% 36° GPU \(fig)8% 30° MEM 61% ANE ~\(fig)0%"
        )
        XCTAssertEqual(
            MetricFormat.menuBarLine(cpu: 1.4, gpu: -1, memory: 0, ane: 0.004, cpuTemp: 8.4, gpuTemp: nil),
            "CPU 100% \(fig)8° GPU \(fig)0% — MEM \(fig)0% ANE ~\(fig)0%"
        )
        XCTAssertEqual(
            MetricFormat.menuBarLine(cpu: 0.4, gpu: 0.1, memory: 0.5, ane: 0.37, cpuTemp: 40, gpuTemp: 31),
            "CPU 40% 40° GPU 10% 31° MEM 50% ANE ~37%"
        )
        XCTAssertEqual(
            MetricFormat.menuBarLine(cpu: 0.08, gpu: 0.08, memory: 0.08, ane: 0.08, cpuTemp: 8, gpuTemp: 8).count,
            MetricFormat.menuBarLine(cpu: 0.99, gpu: 0.99, memory: 0.99, ane: 0.99, cpuTemp: 99, gpuTemp: 99).count
        )
    }
}
