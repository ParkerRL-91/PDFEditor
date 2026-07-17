// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFStack",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PDFStackKit",
            path: "Sources/PDFStackKit"
        ),
        .executableTarget(
            name: "PDFStack",
            dependencies: ["PDFStackKit"],
            path: "Sources/PDFStack"
        ),
        .executableTarget(
            name: "PDFStackSmokeTests",
            dependencies: ["PDFStackKit"],
            path: "Sources/PDFStackSmokeTests"
        )
    ]
)
