// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Spectra",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Spectra", targets: ["Spectra"]),
        .executable(name: "SpectraDiagnostics", targets: ["SpectraDiagnostics"]),
        .library(name: "SpectraCore", targets: ["SpectraCore"])
    ],
    targets: [
        .target(
            name: "SpectraCore",
            path: "SpectraCore",
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "Spectra",
            dependencies: ["SpectraCore"],
            path: "Spectra",
            exclude: ["CrossPlatform", "Visuals/Metal/Shaders.metal"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .executableTarget(
            name: "SpectraDiagnostics",
            dependencies: ["SpectraCore"],
            path: "Diagnostics/SpectraDiagnostics",
            linkerSettings: [
                .linkedFramework("Metal")
            ]
        ),
        .testTarget(
            name: "SpectraTests",
            dependencies: ["SpectraCore"],
            path: "Tests/SpectraTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
