import Testing
@testable import Markv

@Test func editorCentersWithinTheVisibleAreaWhenOutlineToggles() {
    #expect(MarkvDocumentLayout.defaultOutlineWidth == 220)
    #expect(MarkvDocumentLayout.clampedOutlineWidth(80) == MarkvDocumentLayout.minimumOutlineWidth)
    #expect(MarkvDocumentLayout.clampedOutlineWidth(500) == MarkvDocumentLayout.maximumOutlineWidth)
    #expect(MarkvDocumentLayout.editorTrailingInset(outlineVisible: false, outlineWidth: 260) == 0)
    let expectedInset = MarkvDocumentLayout.clampedOutlineWidth(260) + (MarkvDocumentLayout.outlineEdgeInset * 2)
    let actualInset = MarkvDocumentLayout.editorTrailingInset(outlineVisible: true, outlineWidth: 260)
    #expect(abs(actualInset - expectedInset) < 0.001)
}
