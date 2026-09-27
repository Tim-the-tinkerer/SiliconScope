import Darwin
import SiliconScopeCore
import XCTest

final class SamplerLeakTests: XCTestCase {
    func testRepeatedSamplesDoNotAccumulate() {
        let sampler = SystemSampler()
        guard sampler.usesIOReport else { return }

        let request = SampleRequest(interval: 0.25, includeProcesses: false)
        _ = sampler.sample(request)
        let before = mallocInUse()
        for _ in 0..<16 {
            _ = sampler.sample(request)
        }
        let growth = mallocInUse() &- before
        XCTAssertLessThan(
            growth,
            1_500_000,
            "malloc size_in_use grew by \(growth) bytes across 16 samples"
        )
    }
}

private func mallocInUse() -> Int {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(malloc_default_zone(), &stats)
    return stats.size_in_use
}
