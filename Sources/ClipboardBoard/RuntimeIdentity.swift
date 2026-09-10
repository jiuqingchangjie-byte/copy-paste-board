import AppKit
import ApplicationServices
import CryptoKit

/// Snapshot taken by the running executable itself, before acceptance begins.
/// It contains no clipboard data. A rebuilt bundle cannot update this snapshot.
enum RuntimeIdentity {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    static let buildID = Bundle.main.object(forInfoDictionaryKey: "ClipboardBoardBuildID") as? String ?? "unpackaged"

    static func write() {
        guard let executable = Bundle.main.executableURL,
              let bytes = try? Data(contentsOf: executable, options: .mappedIfSafe) else { return }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let record: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "applicationPath": Bundle.main.bundleURL.path,
            "version": version, "buildID": buildID, "executableSHA256": digest,
            "accessibilityAtLaunch": AXIsProcessTrusted(),
            "eventPostingAtLaunch": CGPreflightPostEventAccess()
        ]
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardBoard-runtime-\(ProcessInfo.processInfo.processIdentifier).json")
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
