// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipboardBoard",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ClipboardBoard", targets: ["ClipboardBoard"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "ClipboardCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "ClipboardBoard", dependencies: ["ClipboardCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon"),
                                           .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "ClipboardBoardTests", dependencies: ["ClipboardBoard"])
    ]
)
