import Foundation
@testable import RepoPeek
import Testing

struct UpdateDiagnosticsTests {
    @Test
    func `diagnostics include update location and install-origin signals`() {
        let bundleURL = FileManager.default.temporaryDirectory
            .appending(path: "RepoPeekDiagnosticsFixture", directoryHint: .isDirectory)
            .appending(path: "RepoPeek.app", directoryHint: .isDirectory)
        let diagnostics = UpdateDiagnostics(
            bundleURL: bundleURL,
            canCheckForUpdates: true,
            developerIDSigned: true,
            quarantineReader: { _ in true }
        )

        #expect(diagnostics.bundlePath == bundleURL.path)
        #expect(diagnostics.resolvedBundlePath == bundleURL.resolvingSymlinksInPath().path)
        #expect(diagnostics.canCheckForUpdates)
        #expect(diagnostics.developerIDSigned)
        #expect(!diagnostics.homebrewCask)
        #expect(!diagnostics.appTranslocated)
        #expect(diagnostics.quarantinePresent)
        #expect(diagnostics.pasteboardText.contains("RepoPeek update diagnostics"))
        #expect(diagnostics.pasteboardText.contains("bundle_path: \(bundleURL.path)"))
        #expect(diagnostics.pasteboardText.contains("quarantine_present: true"))
    }

    @Test
    func `diagnostics flag homebrew and translocated app paths`() throws {
        let homebrewURL = try #require(URL(
            string: "file:///opt/homebrew/Caskroom/repopeek/0.1.0/RepoPeek.app"
        ))
        let translocatedURL = try #require(URL(
            string: "file:///private/var/folders/xx/AppTranslocation/RepoPeek.app"
        ))

        #expect(UpdateDiagnostics(
            bundleURL: homebrewURL,
            canCheckForUpdates: false,
            developerIDSigned: false
        ).homebrewCask)
        #expect(UpdateDiagnostics(
            bundleURL: translocatedURL,
            canCheckForUpdates: false,
            developerIDSigned: false
        ).appTranslocated)
    }
}
