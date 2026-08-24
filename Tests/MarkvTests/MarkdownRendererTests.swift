import Foundation
import Testing
@testable import Markv

@Test func rendersHeadingsAndInlineMarkup() {
    let html = MarkdownRenderer.render("# Hello **Markv**\n\nRead *beautifully*.")
    #expect(html.contains("<h1 id=\"hello-markv\">Hello <strong>Markv</strong></h1>"))
    #expect(html.contains("<p>Read <em>beautifully</em>.</p>"))
}

@Test func escapesRawHTMLAndCode() {
    let html = MarkdownRenderer.render("<script>alert(1)</script>\n\n```swift\nlet value = \"<safe>\"\n```")
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;"))
    #expect(html.contains("<pre><code class=\"language-swift\">"))
    #expect(html.contains("&lt;safe&gt;"))
}

@Test func rendersListsQuotesAndTables() {
    let source = """
    - One
    - Two

    > A useful note

    | Name | Kind |
    | --- | --- |
    | Markv | App |
    """
    let html = MarkdownRenderer.render(source)
    #expect(html.contains("<ul><li>One</li><li>Two</li></ul>"))
    #expect(html.contains("<blockquote><p>A useful note</p></blockquote>"))
    #expect(html.contains("<th>Name</th>"))
    #expect(html.contains("<td>Markv</td>"))
}

@Test func blocksUnsafeLinkSchemes() {
    let html = MarkdownRenderer.render("[Nope](javascript:alert(1)) [Okay](https://example.com)")
    #expect(!html.contains("javascript:"))
    #expect(html.contains("href=\"https://example.com\""))
}

@Test func rendersStableHeadingIDsTasksAndImages() {
    let source = """
    # Hello World
    ## Hello World

    - [ ] Open
    - [x] Done

    ![Diagram](images/diagram.png)
    """
    let html = MarkdownRenderer.render(source)
    #expect(html.contains("<h1 id=\"hello-world\">"))
    #expect(html.contains("<h2 id=\"hello-world-1\">"))
    #expect(html.contains("class=\"task-list\""))
    #expect(html.contains("type=\"checkbox\" checked"))
    #expect(html.contains("src=\"images/diagram.png\""))
}

@Test func normalizesImageSpacesAndUsesRestrictedLocalImageScheme() {
    let baseURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    let html = MarkdownRenderer.render(
        "![](IMG/sample&#x20;image.png)",
        localImageBaseURL: baseURL
    )

    #expect(html.contains("src=\"markv-image:///IMG/sample%20image.png\""))
    #expect(html.contains("data-markv-src=\"IMG/sample%20image.png\""))

    let literalSpace = MarkdownRenderer.render("![](IMG/sample image.png)")
    #expect(literalSpace.contains("src=\"IMG/sample%20image.png\""))
}
