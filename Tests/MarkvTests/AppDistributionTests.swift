import Foundation
import Testing
@testable import Markv

private final class CountingKeyStore: AIAPIKeyStoring {
    var reads = 0
    var writes = 0
    func loadAPIKey() throws -> String { reads += 1; return "existing-key" }
    func saveAPIKey(_ value: String) throws { writes += 1 }
}

private actor CountingAIService: AICompleting {
    var calls = 0
    func complete(configuration: AIConfiguration, messages: [AIChatMessage]) async throws -> String {
        calls += 1
        return "Unexpected AI response"
    }
}

private actor CountingUpdateService: UpdateChecking {
    var calls = 0
    func latestRelease() async throws -> AppRelease {
        calls += 1
        throw UpdateCheckError.invalidResponse
    }
}

@Test func distributionCapabilitiesMatchBuildChannel() {
    #if MARKV_APP_STORE
    #expect(!AppDistribution.supportsAI)
    #expect(!AppDistribution.supportsGitHubUpdates)
    #else
    #expect(AppDistribution.supportsAI)
    #expect(AppDistribution.supportsGitHubUpdates)
    #endif
    #expect(AppDistribution.privacyPolicyURL.scheme == "https")
}

@Test(.enabled(if: !AppDistribution.supportsAI)) @MainActor
func storeEditionCannotRestoreOrEnableAIOrContactUpdateService() async {
    let suiteName = "MarkvStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(true, forKey: "markv.aiEnabled")
    let keys = CountingKeyStore()
    let ai = CountingAIService()
    let updates = CountingUpdateService()
    let model = AppModel(defaults: defaults, restoreLastFolder: false,
                         aiKeyStore: keys, aiService: ai, updateService: updates)
    #expect(!model.aiEnabled)
    #expect(model.aiAPIKey.isEmpty)
    #expect(keys.reads == 0)
    model.aiEnabled = true
    model.aiAPIKey = "must-not-be-stored"
    model.beginAISelectionEdit(.improve)
    model.handleAIEditorEvent(.slash)
    model.aiPromptContext = .insertion
    model.aiInstruction = "Must not be sent"
    model.submitAIPrompt()
    model.retryAIRevision()
    await model.checkForUpdatesAutomatically()
    await model.checkForUpdates()
    #expect(!model.aiEnabled)
    #expect(keys.writes == 0)
    #expect(await ai.calls == 0)
    #expect(await updates.calls == 0)
    #expect(model.updateStatus == .idle)
    #expect(defaults.bool(forKey: "markv.aiEnabled"))
}
