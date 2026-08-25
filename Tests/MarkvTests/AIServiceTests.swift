import Foundation
import Testing
@testable import Markv

private final class MemoryAIKeyStore: AIAPIKeyStoring {
    var value = ""
    func loadAPIKey() throws -> String { value }
    func saveAPIKey(_ value: String) throws { self.value = value }
}

private struct StubAIService: AICompleting {
    let result: String

    func complete(
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) async throws -> String {
        result
    }
}

private struct FailingAIService: AICompleting {
    let error: AIServiceError

    func complete(
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) async throws -> String {
        throw error
    }
}

@Test func aiConfigurationNormalizesOpenAICompatibleEndpoints() throws {
    #expect(try AIConfiguration(
        baseURL: "https://api.openai.com/v1/",
        model: "model-a",
        apiKey: "key"
    ).endpointURL().absoluteString == "https://api.openai.com/v1/chat/completions")

    #expect(try AIConfiguration(
        baseURL: "https://example.com/api/chat/completions",
        model: "model-a",
        apiKey: ""
    ).endpointURL().absoluteString == "https://example.com/api/chat/completions")

    #expect(try AIConfiguration(
        baseURL: "http://localhost:1234/v1",
        model: "local-model",
        apiKey: "local-key"
    ).endpointURL().absoluteString == "http://localhost:1234/v1/chat/completions")

    #expect(throws: AIServiceError.insecureAPIKeyTransport) {
        try AIConfiguration(
            baseURL: "http://example.com/v1",
            model: "model-a",
            apiKey: "secret"
        ).endpointURL()
    }
    #expect(throws: AIServiceError.insecureAPIKeyTransport) {
        try AIConfiguration(
            baseURL: "http://example.com/v1",
            model: "model-a",
            apiKey: ""
        ).endpointURL()
    }
    #expect(throws: AIServiceError.modelRequired) {
        try AIConfiguration(baseURL: "https://example.com/v1", model: "", apiKey: "").endpointURL()
    }
}

@Test func aiRequestUsesChatCompletionsJSONAndOptionalBearerKey() throws {
    let service = AIService()
    let messages = [
        AIChatMessage(role: "system", content: "Return only edited text."),
        AIChatMessage(role: "user", content: "Original")
    ]
    let request = try service.makeRequest(
        configuration: AIConfiguration(
            baseURL: "https://example.com/v1",
            model: "custom-model",
            apiKey: "secret-value"
        ),
        messages: messages
    )

    #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-value")
    let body = try #require(request.httpBody)
    let decoded = try JSONDecoder().decode(AIChatCompletionRequest.self, from: body)
    #expect(decoded.model == "custom-model")
    #expect(decoded.messages == messages)
    #expect(decoded.stream == false)

    let keyless = try service.makeRequest(
        configuration: AIConfiguration(
            baseURL: "http://127.0.0.1:8080/v1",
            model: "local",
            apiKey: ""
        ),
        messages: messages
    )
    #expect(keyless.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func aiServiceDecodesContentAndAPIErrorMessages() throws {
    let service = AIService()
    let success = Data(#"{"choices":[{"message":{"content":"  Revised text  "}}]}"#.utf8)
    #expect(try service.decodeResponse(data: success, statusCode: 200) == "Revised text")

    let failure = Data(#"{"error":{"message":"Model unavailable"}}"#.utf8)
    #expect(throws: AIServiceError.server(status: 503, message: "Model unavailable")) {
        try service.decodeResponse(data: failure, statusCode: 503)
    }
}

@Test @MainActor func aiSettingsPersistWithoutWritingAPIKeyToDefaults() {
    let suiteName = "MarkvAISettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let keyStore = MemoryAIKeyStore()

    let model = AppModel(
        defaults: defaults,
        restoreLastFolder: false,
        aiKeyStore: keyStore,
        aiService: StubAIService(result: "Revised")
    )
    model.aiEnabled = true
    model.aiBaseURL = "https://example.com/v1"
    model.aiModel = "custom-model"
    model.aiAPIKey = "private-key"

    #expect(defaults.bool(forKey: "markv.aiEnabled"))
    #expect(defaults.string(forKey: "markv.aiBaseURL") == "https://example.com/v1")
    #expect(defaults.string(forKey: "markv.aiModel") == "custom-model")
    #expect(defaults.string(forKey: "markv.aiAPIKey") == nil)
    #expect(keyStore.value == "private-key")
}

@Test @MainActor func aiSelectionAndSlashResultsRequireUserApproval() async throws {
    let suiteName = "MarkvAIStateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let model = AppModel(
        defaults: defaults,
        restoreLastFolder: false,
        aiKeyStore: MemoryAIKeyStore(),
        aiService: StubAIService(result: "Revised text")
    )
    model.aiEnabled = true
    model.aiBaseURL = "https://example.com/v1"
    model.aiModel = "model"

    model.beginAISelectionEdit(.improve)
    #expect(model.editorCommand?.action == .captureAISelection)
    model.handleAIEditorEvent(.selection("Original text"))
    try await waitForAI(model)
    #expect(model.aiRevision?.mode == .selection)
    #expect(model.aiRevision?.original == "Original text")
    #expect(model.aiRevision?.revised == "Revised text")
    model.acceptAIRevision()
    #expect(model.editorCommand?.action == .replaceAISelection("Revised text"))

    model.handleAIEditorEvent(.slash)
    #expect(model.aiPromptContext == .insertion)
    model.aiInstruction = "Write an outline"
    model.submitAIPrompt()
    try await waitForAI(model)
    #expect(model.aiRevision?.mode == .insertion)
    model.acceptAIRevision()
    if case .replaceAISlashHTML(let html) = model.editorCommand?.action {
        #expect(html.contains("Revised text"))
    } else {
        Issue.record("Expected slash HTML insertion command")
    }
}

@MainActor
private func waitForAI(_ model: AppModel) async throws {
    for _ in 0..<100 where model.aiIsWorking {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(!model.aiIsWorking)
}

@Test @MainActor func aiErrorsRedactConfiguredAPIKey() async throws {
    let suiteName = "MarkvAIRedactionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let keyStore = MemoryAIKeyStore()
    let model = AppModel(
        defaults: defaults,
        restoreLastFolder: false,
        aiKeyStore: keyStore,
        aiService: FailingAIService(
            error: .server(status: 400, message: "Rejected private-key-value")
        )
    )
    model.aiEnabled = true
    model.aiBaseURL = "https://example.com/v1"
    model.aiModel = "model"
    model.aiAPIKey = "private-key-value"

    model.beginAISelectionEdit(.improve)
    model.handleAIEditorEvent(.selection("Original"))
    try await waitForAI(model)
    #expect(model.errorMessage?.contains("private-key-value") == false)
    #expect(model.errorMessage?.contains("••••") == true)
}
