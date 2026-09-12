// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardBoard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipboardBoard", targets: ["ClipboardBoard"])],
    targets: [
        .target(name: "ClipboardCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "ClipboardBoard", dependencies: ["ClipboardCore"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardBoardTests", dependencies: ["ClipboardBoard"])
    ]
)
