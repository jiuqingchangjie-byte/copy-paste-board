import Foundation
import Testing
@testable import ClipboardCore

struct PreviewSettingsTests {
    @Test func legacySettingsDefaultToOneSecondAndNewPreferencesRoundTrip() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{\"maxHistoryCount\":25,\"hasLaunched\":true}".utf8))
        #expect(settings.preview == PreviewSettings())
        #expect(settings.preview.hoverDelay == 1 && settings.preview.hoverEnabled)
        var updated = settings
        updated.preview = PreviewSettings(hoverEnabled: false, hoverDelay: 1.7)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(updated)) == updated)
        #expect(updated.maxHistoryCount == 25 && updated.hasLaunched)
    }

    @Test func persistedDelayIsNormalizedAtAllBoundaries() throws {
        for value in [-2.0, 0, 0.2, 1, 5, 50] {
            let normalized = min(max(value, 0.2), 5)
            #expect(PreviewSettings(hoverDelay: value).hoverDelay == normalized)
            let json = Data("{\"hoverDelay\":\(value)}".utf8)
            #expect(try JSONDecoder().decode(PreviewSettings.self, from: json).hoverDelay == normalized)
        }
        #expect(PreviewSettings(hoverDelay: .nan).hoverDelay == 1)
        #expect(PreviewSettings(hoverDelay: .infinity).hoverDelay == 1)
    }
}
