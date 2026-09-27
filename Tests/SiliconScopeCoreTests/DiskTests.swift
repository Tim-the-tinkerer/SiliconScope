import SiliconScopeCore
import XCTest

final class DiskTests: XCTestCase {
    func testRegistryNamesDropTheVolumeIndex() {
        XCTAssertEqual(DiskSampler.cleanRegistryName("Macintosh HD - Data@5"), "Macintosh HD - Data")
        XCTAssertEqual(DiskSampler.cleanRegistryName("APPLE SSD AP1024Q Media"), "APPLE SSD AP1024Q")
        XCTAssertEqual(DiskSampler.cleanRegistryName("com.apple.os.update-ABC@1"), "com.apple.os.update-ABC")
    }

    func testVolumeTitlePrefersTheRealVolumeName() {
        XCTAssertEqual(
            DiskSampler.volumeTitle(
                registryName: "Macintosh HD - Data@5",
                mountedName: "Macintosh HD",
                mountPoint: "/System/Volumes/Data"
            ),
            "Macintosh HD - Data"
        )
        XCTAssertEqual(
            DiskSampler.volumeTitle(
                registryName: "com.apple.os.update-ABCDEF@1",
                mountedName: "Macintosh HD",
                mountPoint: "/"
            ),
            "Macintosh HD"
        )
    }

    func testVisibilitySkipsSystemSnapshotsAndCryptex() {
        XCTAssertEqual(DiskSampler.visibility(mountPoint: "/", source: "/dev/disk3s1s1", fileSystem: "apfs"), .localVolume)
        XCTAssertEqual(
            DiskSampler.visibility(mountPoint: "/System/Volumes/Data", source: "/dev/disk3s5", fileSystem: "apfs"),
            .localVolume
        )
        XCTAssertEqual(
            DiskSampler.visibility(mountPoint: "/System/Volumes/Preboot", source: "/dev/disk3s2", fileSystem: "apfs"),
            .hidden
        )
        XCTAssertEqual(
            DiskSampler.visibility(mountPoint: "/Volumes/Recovery", source: "/dev/disk3s3", fileSystem: "apfs"),
            .hidden
        )
        XCTAssertEqual(
            DiskSampler.visibility(
                mountPoint: "/Volumes/.timemachine/ABC/2026.backup",
                source: "com.apple.TimeMachine.2026.backup@/dev/disk7s2",
                fileSystem: "apfs"
            ),
            .hidden
        )
        XCTAssertEqual(
            DiskSampler.visibility(
                mountPoint: "/private/var/run/com.apple.security.cryptexd/mnt/toolchain",
                source: "/dev/disk5s1",
                fileSystem: "apfs"
            ),
            .hidden
        )
        XCTAssertEqual(
            DiskSampler.visibility(mountPoint: "/Volumes/Tim", source: "//Tim@nas/Tim", fileSystem: "smbfs"),
            .network
        )
        XCTAssertEqual(DiskSampler.visibility(mountPoint: "/dev", source: "devfs", fileSystem: "devfs"), .hidden)
    }

    func testConnectedDrivesIncludeTheStartupDisk() {
        let sample = DiskSampler.sample()
        let startup = sample.drives.filter { $0.kind == .internalDrive }
        guard !startup.isEmpty else { return }
        XCTAssertGreaterThan(startup[0].sizeBytes, 1_000_000_000)
        let mounts = startup.flatMap(\.volumes).map(\.mountPoint)
        XCTAssertTrue(mounts.contains("/"))
        XCTAssertTrue(mounts.contains("/System/Volumes/Data"))
        XCTAssertFalse(mounts.contains { $0.contains("Preboot") || $0.contains("cryptex") || $0 == "/Volumes/Recovery" })
        let root = startup.flatMap(\.volumes).first { $0.mountPoint == "/" }
        XCTAssertNotNil(root)
        XCTAssertFalse(root?.name.contains("com.apple") ?? true)
        let data = startup.flatMap(\.volumes).first { $0.mountPoint == "/System/Volumes/Data" }
        XCTAssertFalse(data?.name.isEmpty ?? true)
        XCTAssertFalse(data?.name.contains("com.apple") ?? true)
        XCTAssertGreaterThan(data?.usedBytes ?? 0, 0)
        XCTAssertGreaterThan(startup[0].availableBytes, 0)
        XCTAssertLessThan(startup[0].availableBytes, startup[0].sizeBytes)
    }

    func testDiskMonitorKeepsFreeSpaceWithoutLosingTheStartupDisk() {
        let monitor = DiskMonitor()
        let first = monitor.currentDrives()
        let second = monitor.currentDrives()
        let startup = second.first { $0.kind == .internalDrive }
        XCTAssertEqual(first.first { $0.kind == .internalDrive }?.bsdName, startup?.bsdName)
        XCTAssertGreaterThan(startup?.availableBytes ?? 0, 0)
        XCTAssertLessThan(startup?.availableBytes ?? 0, startup?.sizeBytes ?? 0)
        XCTAssertTrue(startup?.volumes.contains { $0.mountPoint == "/" } ?? false)
    }

    func testSMARTAttributesUsePlainNames() {
        let raw: [String: UInt64] = [
            "TEMPERATURE": 306,
            "AVAILABLE_SPARE": 100,
            "AVAILABLE_SPARE_THRESHOLD": 99,
            "PERCENTAGE_USED": 1,
            "POWER_ON_HOURS_0": 1990,
            "POWER_ON_HOURS_1": 0,
            "POWER_CYCLES_0": 540,
            "DATA_UNITS_READ_0": 97_198_397,
            "DATA_UNITS_WRITTEN_0": 56_260_256,
            "MEDIA_ERRORS_0": 0,
            "CRITICAL_WARNING": 0,
            "VENDOR_EXTRA": 7,
        ]
        let rows = DiskSmart.attributes(from: raw)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(byID["TEMPERATURE"]?.title, "Temperature")
        XCTAssertEqual(byID["TEMPERATURE"]?.value, "32.9°C")
        XCTAssertEqual(byID["PERCENTAGE_USED"]?.value, "1%")
        XCTAssertEqual(byID["POWER_ON_HOURS"]?.value, "1,990 hours")
        XCTAssertEqual(byID["DATA_UNITS_READ"]?.value, MetricFormat.bytes(97_198_397 * DiskSmart.nvmeDataUnitBytes))
        XCTAssertEqual(byID["CRITICAL_WARNING"]?.value, "None")
        XCTAssertEqual(byID["VENDOR_EXTRA"]?.title, "Vendor Extra")
        XCTAssertEqual(byID["VENDOR_EXTRA"]?.value, "7")
        XCTAssertNil(rows.first { $0.id.hasSuffix("_0") || $0.id.hasSuffix("_1") })
        XCTAssertEqual(DiskSmart.partitionMapTitle("GUID_partition_scheme"), "GUID")
    }

    func testStartupDiskReportsSMARTWhenTheDriveHasIt() {
        let startup = DiskSampler.sample().drives.first { $0.kind == .internalDrive }
        guard let bsd = startup?.bsdName, !bsd.isEmpty else { return }
        let detail = DiskDetails.load(bsdName: bsd, maximumAge: 0)
        XCTAssertTrue(detail.reported)
        XCTAssertGreaterThan(detail.blockSize, 0)
        guard !detail.smartStatus.isEmpty else { return }
        if detail.attributes.contains(where: { $0.id == "TEMPERATURE" }) {
            XCTAssertTrue(detail.attributes.contains { $0.id == "PERCENTAGE_USED" })
            XCTAssertGreaterThan(detail.bytesRead, 0)
            XCTAssertFalse(detail.serialNumber.isEmpty)
        }
    }
}
