import Testing
@testable import Markv

@Test @MainActor func editorShellSupportsAISelectionReviewAndSlashInsertion() {
    let shell = MarkdownWebView.documentShell
    #expect(shell.contains("function captureAISelection()"))
    #expect(shell.contains("pendingAISelectionRange = range.cloneRange()"))
    #expect(shell.contains("function requestSlashAI()"))
    #expect(shell.contains("postMessage({type:'slash'})"))
    #expect(shell.contains("command === 'replaceAISelection'"))
    #expect(shell.contains("command === 'insertAfterAISelection'"))
    #expect(shell.contains("command === 'replaceAISlashHTML'"))
    #expect(shell.contains("template.innerHTML = value"))
}

@Test func aiRequestFactoryBuildsReviewAndInsertionPrompts() {
    let selection = AIRequestFactory.messages(for: .selection(
        original: "Original text",
        instruction: "Make it clearer"
    ))
    #expect(selection.count == 2)
    #expect(selection[0].role == "system")
    #expect(selection[1].content.contains("Original text"))
    #expect(selection[1].content.contains("Make it clearer"))

    let insertion = AIRequestFactory.messages(for: .insertion(instruction: "Write an outline"))
    #expect(insertion[0].content.contains("Markdown"))
    #expect(insertion[1].content == "Write an outline")
    #expect(AIRequestFactory.normalizedMarkdown("```markdown\n# Title\n```") == "# Title")
}
