import Foundation

enum AppDistribution {
    #if MARKV_APP_STORE
    static let supportsAI = false
    static let supportsGitHubUpdates = false
    #else
    static let supportsAI = true
    static let supportsGitHubUpdates = true
    #endif

    static let privacyPolicyURL = URL(string: "https://github.com/kennyz/MarkV/blob/main/PRIVACY.md")!
}
