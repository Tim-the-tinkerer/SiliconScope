// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiliconScope",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SiliconScope", targets: ["SiliconScope"]),
        .library(name: "SiliconScopeCore", targets: ["SiliconScopeCore"]),
    ],
    targets: [
        .target(
            name: "SiliconScopeCore",
            path: "Sources/SiliconScopeCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .executableTarget(
            name: "SiliconScope",
            dependencies: ["SiliconScopeCore"],
            path: "Sources/SiliconScope",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "SiliconScopeCoreTests",
            dependencies: ["SiliconScopeCore"],
            path: "Tests/SiliconScopeCoreTests"
        ),
    ]
)
