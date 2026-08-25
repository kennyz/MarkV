import Foundation

struct AIConfiguration: Equatable {
    let baseURL: String
    let model: String
    let apiKey: String

    func endpointURL() throws -> URL {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIServiceError.modelRequired }
        guard var components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty else {
            throw AIServiceError.invalidBaseURL
        }

        let localHosts = ["localhost", "127.0.0.1", "::1"]
        if scheme == "http", !localHosts.contains(host.lowercased()) {
            throw AIServiceError.insecureAPIKeyTransport
        }

        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") {
            if path.isEmpty || path == "/" {
                path = "/chat/completions"
            } else {
                path += "/chat/completions"
            }
        }
        components.path = path
        guard let endpoint = components.url else { throw AIServiceError.invalidBaseURL }
        return endpoint
    }
}

struct AIChatMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct AIChatCompletionRequest: Codable, Equatable {
    let model: String
    let messages: [AIChatMessage]
    let stream: Bool
}

protocol AICompleting: Sendable {
    func complete(
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) async throws -> String
}

enum AIEditAction: String, CaseIterable, Identifiable {
    case improve
    case proofread
    case shorten
    case lengthen
    case custom

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .improve: "Improve Writing"
        case .proofread: "Fix Spelling & Grammar"
        case .shorten: "Make Shorter"
        case .lengthen: "Make Longer"
        case .custom: "Custom Instruction…"
        }
    }

    var instruction: String {
        switch self {
        case .improve:
            "Improve clarity, flow, and tone while preserving the meaning."
        case .proofread:
            "Fix spelling, grammar, punctuation, and awkward phrasing without changing the meaning."
        case .shorten:
            "Make the text substantially shorter while preserving its essential meaning."
        case .lengthen:
            "Expand the text with useful detail while preserving its intent and tone."
        case .custom:
            ""
        }
    }
}

enum AIRequestContext: Equatable {
    case selection(original: String, instruction: String)
    case insertion(instruction: String)
}

enum AIPromptContext: Equatable {
    case selection(original: String)
    case insertion
}

enum AIRevisionMode: Equatable {
    case selection
    case insertion
}

struct AIRevision: Identifiable, Equatable {
    let id = UUID()
    let mode: AIRevisionMode
    let original: String
    let revised: String
}

enum AIRequestFactory {
    static func messages(for context: AIRequestContext) -> [AIChatMessage] {
        switch context {
        case .selection(let original, let instruction):
            return [
                AIChatMessage(
                    role: "system",
                    content: "You are a careful writing editor. Return only the revised text, with no commentary, labels, or quotation marks. Preserve the original language unless the instruction explicitly requests translation."
                ),
                AIChatMessage(
                    role: "user",
                    content: "Instruction:\n\(instruction)\n\nText:\n\(original)"
                )
            ]
        case .insertion(let instruction):
            return [
                AIChatMessage(
                    role: "system",
                    content: "Generate useful Markdown content for a document. Return only Markdown, without wrapping it in a Markdown code fence or adding commentary."
                ),
                AIChatMessage(role: "user", content: instruction)
            ]
        }
    }

    static func normalizedMarkdown(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return trimmed }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIServiceError: LocalizedError, Equatable {
    case invalidBaseURL
    case modelRequired
    case insecureAPIKeyTransport
    case invalidResponse
    case emptyResponse
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid HTTP or HTTPS AI Base URL."
        case .modelRequired:
            "Enter an AI model name."
        case .insecureAPIKeyTransport:
            "HTTP AI endpoints are allowed only for localhost."
        case .invalidResponse:
            "The AI service returned an invalid response."
        case .emptyResponse:
            "The AI service returned empty content."
        case .server(let status, let message):
            message.isEmpty ? "AI request failed with HTTP \(status)." : message
        }
    }
}

private final class AINoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct AIService: AICompleting {
    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 120
            configuration.waitsForConnectivity = false
            self.session = URLSession(
                configuration: configuration,
                delegate: AINoRedirectDelegate(),
                delegateQueue: nil
            )
        }
    }

    func makeRequest(
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) throws -> URLRequest {
        let endpoint = try configuration.endpointURL()
        let body = AIChatCompletionRequest(
            model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: messages,
            stream: false
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 90
        return request
    }

    func complete(
        configuration: AIConfiguration,
        messages: [AIChatMessage]
    ) async throws -> String {
        let request = try makeRequest(configuration: configuration, messages: messages)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard data.count <= 10 * 1024 * 1024 else {
            throw AIServiceError.invalidResponse
        }
        return try decodeResponse(data: data, statusCode: httpResponse.statusCode)
    }

    func decodeResponse(data: Data, statusCode: Int) throws -> String {
        guard data.count <= 10 * 1024 * 1024 else {
            throw AIServiceError.invalidResponse
        }
        guard (200..<300).contains(statusCode) else {
            let errorResponse = try? JSONDecoder().decode(AIErrorResponse.self, from: data)
            let message = String((errorResponse?.error.message ?? "").prefix(500))
            throw AIServiceError.server(
                status: statusCode,
                message: message
            )
        }

        let completion = try JSONDecoder().decode(AIChatCompletionResponse.self, from: data)
        guard let content = completion.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        guard content.count <= 100_000 else { throw AIServiceError.invalidResponse }
        return content
    }
}

private struct AIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct AIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}
