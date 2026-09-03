import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol MarkdownFileAssociationManaging {
    func isDefaultApplication() -> Bool
    func setAsDefaultApplication() async throws
}

@MainActor
final class MarkdownFileAssociationManager: MarkdownFileAssociationManaging {
    static let markdownType = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )

    private let applicationURL: URL
    private let workspace: NSWorkspace

    init(
        applicationURL: URL = Bundle.main.bundleURL,
        workspace: NSWorkspace = .shared
    ) {
        self.applicationURL = applicationURL
        self.workspace = workspace
    }

    func isDefaultApplication() -> Bool {
        guard let handlerURL = workspace.urlForApplication(toOpen: Self.markdownType) else {
            return false
        }
        return normalized(handlerURL) == normalized(applicationURL)
    }

    func setAsDefaultApplication() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.setDefaultApplication(
                at: applicationURL,
                toOpen: Self.markdownType
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func normalized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
