import Foundation
import Testing
@testable import Markv

private struct StubUpdateService: UpdateChecking {
    let release: AppRelease

    func latestRelease() async throws -> AppRelease { release }
}

private struct FailingUpdateService: UpdateChecking {
    func latestRelease() async throws -> AppRelease {
        throw UpdateCheckError.invalidResponse
    }
}

@Test func semanticVersionsCompareNumericComponents() throws {
    let old = try #require(SemanticVersion("v0.6.0"))
    let new = try #require(SemanticVersion("0.10.0"))
    let equivalent = try #require(SemanticVersion("0.6"))

    #expect(old < new)
    #expect(old == equivalent)
    #expect(SemanticVersion("release-1") == nil)
}

@Test func githubReleaseDecoderAcceptsOnlyVersionedHTTPSGitHubPages() throws {
    let service = GitHubUpdateService()
    let valid = Data(#"{"tag_name":"v0.7.0","html_url":"https://github.com/kennyz/MarkV/releases/tag/v0.7.0"}"#.utf8)
    #expect(try service.decodeRelease(from: valid) == AppRelease(
        version: "v0.7.0",
        pageURL: URL(string: "https://github.com/kennyz/MarkV/releases/tag/v0.7.0")!
    ))

    let invalid = Data(#"{"tag_name":"latest","html_url":"http://example.com/update"}"#.utf8)
    #expect(throws: UpdateCheckError.invalidRelease) {
        try service.decodeRelease(from: invalid)
    }
}

@Test(.enabled(if: AppDistribution.supportsGitHubUpdates)) @MainActor func updateCheckReportsNewerAndCurrentReleases() async {
    let newer = AppModel(
        restoreLastFolder: false,
        updateService: StubUpdateService(release: AppRelease(
            version: "v0.7.0",
            pageURL: URL(string: "https://github.com/kennyz/MarkV/releases/tag/v0.7.0")!
        )),
        appVersion: "0.6.0"
    )
    await newer.checkForUpdates()
    #expect(newer.updateStatus == .available(AppRelease(
        version: "v0.7.0",
        pageURL: URL(string: "https://github.com/kennyz/MarkV/releases/tag/v0.7.0")!
    )))

    let current = AppModel(
        restoreLastFolder: false,
        updateService: StubUpdateService(release: AppRelease(
            version: "v0.6.0",
            pageURL: URL(string: "https://github.com/kennyz/MarkV/releases/tag/v0.6.0")!
        )),
        appVersion: "0.6.0"
    )
    await current.checkForUpdates()
    #expect(current.updateStatus == .upToDate)
}

@Test(.enabled(if: AppDistribution.supportsGitHubUpdates)) @MainActor func updateCheckFailureDoesNotBecomeAnAppAlert() async {
    let model = AppModel(
        restoreLastFolder: false,
        updateService: FailingUpdateService(),
        appVersion: "0.6.0"
    )
    await model.checkForUpdates()
    #expect(model.updateStatus == .failed)
    #expect(model.errorMessage == nil)
}
