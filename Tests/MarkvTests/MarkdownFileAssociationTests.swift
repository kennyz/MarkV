import Foundation
import Testing
@testable import Markv

@MainActor
private final class StubMarkdownFileAssociation: MarkdownFileAssociationManaging {
    var isDefault = false

    func isDefaultApplication() -> Bool { isDefault }

    func setAsDefaultApplication() async throws {
        isDefault = true
    }
}

@Test @MainActor func modelCanSetAndRefreshMarkdownDefaultApplication() async {
    let association = StubMarkdownFileAssociation()
    let model = AppModel(
        restoreLastFolder: false,
        markdownFileAssociation: association
    )

    model.refreshMarkdownFileAssociation()
    #expect(!model.isDefaultMarkdownApplication)

    await model.setAsDefaultMarkdownApplication()
    #expect(model.isDefaultMarkdownApplication)
    #expect(!model.isChangingMarkdownAssociation)
    #expect(model.errorMessage == nil)
}
