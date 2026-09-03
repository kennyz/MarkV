import Foundation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        value = String(value.split(separator: "-", maxSplits: 1).first ?? "")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        components = parts.map { Int($0) ?? 0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct AppRelease: Equatable, Sendable {
    let version: String
    let pageURL: URL
}

protocol UpdateChecking: Sendable {
    func latestRelease() async throws -> AppRelease
}

enum UpdateCheckError: LocalizedError, Equatable {
    case invalidResponse
    case invalidRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The update service returned an invalid response."
        case .invalidRelease: "The update service returned an invalid release."
        }
    }
}

struct GitHubUpdateService: UpdateChecking {
    static let latestReleaseEndpoint = URL(
        string: "https://api.github.com/repos/kennyz/MarkV/releases/latest"
    )!

    let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MarkV-Update-Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count <= 1_000_000 else {
            throw UpdateCheckError.invalidResponse
        }
        return try decodeRelease(from: data)
    }

    func decodeRelease(from data: Data) throws -> AppRelease {
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        let version = payload.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SemanticVersion(version) != nil,
              let pageURL = URL(string: payload.htmlURL),
              pageURL.scheme == "https",
              pageURL.host?.lowercased() == "github.com" else {
            throw UpdateCheckError.invalidRelease
        }
        return AppRelease(version: version, pageURL: pageURL)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case failed
}

enum AppVersion {
    static func current(bundle: Bundle = .main) -> String {
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        // `swift run` has no application Info.plist, so use the source plist in local development.
        let sourcePlist = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        if let dictionary = NSDictionary(contentsOf: sourcePlist),
           let version = dictionary["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return version
        }
        return "Development"
    }
}
